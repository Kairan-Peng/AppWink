import AppKit
import Foundation
@testable import AppWinkRuntime

private struct SystemEquivalentActivatorSnapshot {
    let openCount: Int
    let activatesValues: [Bool]
    let scheduledIntervals: [TimeInterval]
    let diagnostics: [SystemEquivalentActivationDiagnostics]
    let completionResults: [SystemEquivalentActivationResult]
    let events: [String]
    let scheduledActionCount: Int
}

private extension SystemEquivalentActivationResult {
    var eventDescription: String {
        switch self {
        case .activated:
            return "activated"
        case .failed:
            return "failed"
        }
    }
}

private let systemEquivalentActivateDiagnosticsKey = "hotkey.systemEquivalentActivate"
private let systemEquivalentActivateDiagnosticsName = "systemEquivalentActivate"

private func expectedPerformanceMetadata(
    result: SystemEquivalentActivationResult,
    runningApplicationBundleIdentifier: String? = nil,
    error: NSError? = nil
) -> [String: String] {
    var metadata = [
        "result": result.eventDescription,
    ]

    if let runningApplicationBundleIdentifier {
        metadata["runningApplicationBundleIdentifier"] = runningApplicationBundleIdentifier
    }

    if let error {
        metadata["errorDomain"] = error.domain
        metadata["errorCode"] = String(error.code)
    }

    return metadata
}

private func metadataIncludesApplicationURLPath(_ metadata: [String: String], applicationURL: URL) -> Bool {
    let forbiddenValues = [
        applicationURL.path,
        applicationURL.absoluteString,
    ]

    return metadata.values.contains { value in
        forbiddenValues.contains(value)
    }
}

private final class SystemEquivalentActivatorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var openCount = 0
    private var activatesValues: [Bool] = []
    private var scheduledIntervals: [TimeInterval] = []
    private var scheduledActions: [@Sendable () -> Void] = []
    private var diagnostics: [SystemEquivalentActivationDiagnostics] = []
    private var completionResults: [SystemEquivalentActivationResult] = []
    private var events: [String] = []

    func recordOpen(activates: Bool) {
        lock.lock()
        openCount += 1
        activatesValues.append(activates)
        lock.unlock()
    }

    func recordSchedule(interval: TimeInterval, action: @escaping @Sendable () -> Void) {
        lock.lock()
        scheduledIntervals.append(interval)
        scheduledActions.append(action)
        lock.unlock()
    }

    func recordDiagnostics(_ diagnostic: SystemEquivalentActivationDiagnostics) {
        lock.lock()
        diagnostics.append(diagnostic)
        events.append("diagnostics")
        lock.unlock()
    }

    func recordCompletion(_ result: SystemEquivalentActivationResult) {
        lock.lock()
        completionResults.append(result)
        events.append("completion:\(result.eventDescription)")
        lock.unlock()
    }

    func snapshot() -> SystemEquivalentActivatorSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return SystemEquivalentActivatorSnapshot(
            openCount: openCount,
            activatesValues: activatesValues,
            scheduledIntervals: scheduledIntervals,
            diagnostics: diagnostics,
            completionResults: completionResults,
            events: events,
            scheduledActionCount: scheduledActions.count
        )
    }

    func scheduledAction(at index: Int) -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        guard scheduledActions.indices.contains(index) else {
            return nil
        }

        return scheduledActions[index]
    }
}

import XCTest

private func XCTAssertSystemEquivalentActivatePerformanceDiagnostics(
    _ snapshot: PerformanceDiagnosticsSnapshot,
    expectedMetadata: [String: String],
    expectedDurationNanoseconds: UInt64,
    applicationURL: URL,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(snapshot.counters[systemEquivalentActivateDiagnosticsKey], 1, file: file, line: line)

    let events = snapshot.rawEvents.filter {
        $0.category == .hotkey && $0.name == systemEquivalentActivateDiagnosticsName
    }
    XCTAssertEqual(events.count, 1, file: file, line: line)
    guard let event = events.first else {
        return
    }

    XCTAssertEqual(event.metadata, expectedMetadata, file: file, line: line)
    XCTAssertFalse(
        metadataIncludesApplicationURLPath(event.metadata, applicationURL: applicationURL),
        file: file,
        line: line
    )

    let samples = snapshot.durationSamples[systemEquivalentActivateDiagnosticsKey] ?? []
    XCTAssertEqual(samples.count, 1, file: file, line: line)
    guard let sample = samples.first else {
        return
    }

    XCTAssertEqual(sample.category, .hotkey, file: file, line: line)
    XCTAssertEqual(sample.name, systemEquivalentActivateDiagnosticsName, file: file, line: line)
    XCTAssertEqual(sample.startNanoseconds, 0, file: file, line: line)
    XCTAssertEqual(sample.endNanoseconds, expectedDurationNanoseconds, file: file, line: line)
    XCTAssertEqual(sample.durationNanoseconds, expectedDurationNanoseconds, file: file, line: line)
    XCTAssertEqual(sample.metadata, expectedMetadata, file: file, line: line)
    XCTAssertFalse(
        metadataIncludesApplicationURLPath(sample.metadata, applicationURL: applicationURL),
        file: file,
        line: line
    )
}

final class SystemEquivalentActivatorTests: XCTestCase {
    func testActivateOpensOnceSettlesOnceRecordsOnce() {
        let applicationURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let expectedDelay: TimeInterval = 0.42
        let expectedDurationNanoseconds: UInt64 = 123_000_000
        let recorder = SystemEquivalentActivatorRecorder()
        let performanceClock = ManualPerformanceDiagnosticsClock()
        let performanceDiagnosticsRecorder = PerformanceDiagnosticsRecorder(clock: performanceClock)
        performanceDiagnosticsRecorder.startSampling(round: .core)
        let runningApplication = NSRunningApplication.current

        let activator = SystemEquivalentActivator(
            openApplication: { url, configuration, completion in
                XCTAssertEqual(url, applicationURL)
                recorder.recordOpen(activates: configuration.activates)
                completion(runningApplication, nil)
                completion(runningApplication, nil)
            },
            scheduleAfter: { interval, action in
                recorder.recordSchedule(interval: interval, action: action)
            },
            diagnosticsRecorder: { diagnostic in
                recorder.recordDiagnostics(diagnostic)
            },
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder,
            settleDelay: expectedDelay
        )

        activator.activate(applicationURL: applicationURL) { result in
            recorder.recordCompletion(result)
        }

        let initialSnapshot = recorder.snapshot()
        XCTAssertEqual(initialSnapshot.openCount, 1)
        XCTAssertEqual(initialSnapshot.activatesValues, [true])
        XCTAssertEqual(initialSnapshot.scheduledIntervals, [expectedDelay])
        XCTAssertTrue(initialSnapshot.diagnostics.isEmpty)
        XCTAssertTrue(initialSnapshot.completionResults.isEmpty)
        XCTAssertTrue(initialSnapshot.events.isEmpty)
        XCTAssertEqual(initialSnapshot.scheduledActionCount, 1)
        XCTAssertNil(performanceDiagnosticsRecorder.snapshot().counters[systemEquivalentActivateDiagnosticsKey])

        let scheduledAction = recorder.scheduledAction(at: 0)
        XCTAssertNotNil(scheduledAction)
        performanceClock.advance(nanoseconds: expectedDurationNanoseconds)
        scheduledAction?()

        let finalSnapshot = recorder.snapshot()
        XCTAssertEqual(finalSnapshot.diagnostics.count, 1)
        XCTAssertEqual(finalSnapshot.diagnostics[0].applicationURL, applicationURL)
        XCTAssertEqual(finalSnapshot.diagnostics[0].didSucceed, true)
        XCTAssertEqual(finalSnapshot.diagnostics[0].runningApplicationBundleIdentifier, runningApplication.bundleIdentifier)
        XCTAssertEqual(finalSnapshot.diagnostics[0].errorDomain, nil)
        XCTAssertEqual(finalSnapshot.diagnostics[0].errorCode, nil)
        XCTAssertEqual(finalSnapshot.diagnostics[0].errorDescription, nil)
        XCTAssertEqual(finalSnapshot.completionResults, [.activated])
        XCTAssertEqual(finalSnapshot.events, ["diagnostics", "completion:activated"])
        XCTAssertSystemEquivalentActivatePerformanceDiagnostics(
            performanceDiagnosticsRecorder.snapshot(),
            expectedMetadata: expectedPerformanceMetadata(
                result: .activated,
                runningApplicationBundleIdentifier: runningApplication.bundleIdentifier
            ),
            expectedDurationNanoseconds: expectedDurationNanoseconds,
            applicationURL: applicationURL
        )
    }

    func testActivateDoesNotRetryOrFallbackOnFailure() {
        let applicationURL = URL(fileURLWithPath: "/Applications/Notes.app")
        let failure = NSError(domain: "SystemEquivalentActivatorTests", code: 17)
        let expectedDurationNanoseconds: UInt64 = 75_000_000
        let recorder = SystemEquivalentActivatorRecorder()
        let performanceClock = ManualPerformanceDiagnosticsClock()
        let performanceDiagnosticsRecorder = PerformanceDiagnosticsRecorder(clock: performanceClock)
        performanceDiagnosticsRecorder.startSampling(round: .core)

        let activator = SystemEquivalentActivator(
            openApplication: { url, configuration, completion in
                XCTAssertEqual(url, applicationURL)
                recorder.recordOpen(activates: configuration.activates)
                completion(nil, failure)
            },
            scheduleAfter: { interval, action in
                recorder.recordSchedule(interval: interval, action: action)
            },
            diagnosticsRecorder: { diagnostic in
                recorder.recordDiagnostics(diagnostic)
            },
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder,
            settleDelay: 0.15
        )

        activator.activate(applicationURL: applicationURL) { result in
            recorder.recordCompletion(result)
        }

        let initialSnapshot = recorder.snapshot()
        XCTAssertEqual(initialSnapshot.openCount, 1)
        XCTAssertEqual(initialSnapshot.activatesValues, [true])
        XCTAssertEqual(initialSnapshot.scheduledIntervals, [0.15])
        XCTAssertTrue(initialSnapshot.diagnostics.isEmpty)
        XCTAssertTrue(initialSnapshot.completionResults.isEmpty)
        XCTAssertTrue(initialSnapshot.events.isEmpty)
        XCTAssertEqual(initialSnapshot.scheduledActionCount, 1)
        XCTAssertNil(performanceDiagnosticsRecorder.snapshot().counters[systemEquivalentActivateDiagnosticsKey])

        let scheduledAction = recorder.scheduledAction(at: 0)
        XCTAssertNotNil(scheduledAction)
        performanceClock.advance(nanoseconds: expectedDurationNanoseconds)
        scheduledAction?()

        let finalSnapshot = recorder.snapshot()
        XCTAssertEqual(finalSnapshot.openCount, 1)
        XCTAssertEqual(finalSnapshot.diagnostics.count, 1)
        XCTAssertEqual(finalSnapshot.diagnostics[0].applicationURL, applicationURL)
        XCTAssertEqual(finalSnapshot.diagnostics[0].didSucceed, false)
        XCTAssertEqual(finalSnapshot.diagnostics[0].runningApplicationBundleIdentifier, nil)
        XCTAssertEqual(finalSnapshot.diagnostics[0].errorDomain, failure.domain)
        XCTAssertEqual(finalSnapshot.diagnostics[0].errorCode, failure.code)
        XCTAssertEqual(finalSnapshot.diagnostics[0].errorDescription, failure.localizedDescription)
        XCTAssertEqual(finalSnapshot.completionResults, [.failed])
        XCTAssertEqual(finalSnapshot.events, ["diagnostics", "completion:failed"])
        XCTAssertSystemEquivalentActivatePerformanceDiagnostics(
            performanceDiagnosticsRecorder.snapshot(),
            expectedMetadata: expectedPerformanceMetadata(result: .failed, error: failure),
            expectedDurationNanoseconds: expectedDurationNanoseconds,
            applicationURL: applicationURL
        )
    }
}
