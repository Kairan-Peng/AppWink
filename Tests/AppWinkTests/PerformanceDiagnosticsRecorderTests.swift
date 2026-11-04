import XCTest
@testable import AppWinkRuntime

final class PerformanceDiagnosticsRecorderTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    private final class CountingPerformanceDiagnosticsClock: PerformanceDiagnosticsClock, @unchecked Sendable {
        private(set) var dateReadCount = 0
        private(set) var nanosecondsReadCount = 0

        var nowDate: Date {
            dateReadCount += 1
            return Date(timeIntervalSince1970: 0)
        }

        var nowNanoseconds: UInt64 {
            nanosecondsReadCount += 1
            return 0
        }
    }

    func testInactiveRecorderDoesNotStoreRawEvents() {
        let clock = ManualPerformanceDiagnosticsClock()
        let recorder = PerformanceDiagnosticsRecorder(clock: clock, rawEventLimit: 10)

        recorder.recordEvent(category: .hotkey, name: "pressed")
        recorder.measure(category: .configuration, name: "save") {}

        let snapshot = recorder.snapshot()
        XCTAssertFalse(snapshot.isSampling)
        XCTAssertEqual(snapshot.rawEvents.count, 0)
        XCTAssertEqual(snapshot.totalEventCount, 0)
    }

    func testSessionEventRecordsBeforeSamplingStarts() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())

        recorder.recordSessionEvent(category: .uiTransition, name: "diagnosticsOpenedFromVersionRow")

        let snapshot = recorder.snapshot()
        XCTAssertFalse(snapshot.isSampling)
        XCTAssertEqual(snapshot.counters["uiTransition.diagnosticsOpenedFromVersionRow"], 1)
        XCTAssertEqual(snapshot.totalEventCount, 1)
        XCTAssertEqual(snapshot.rawEvents.first?.name, "diagnosticsOpenedFromVersionRow")
    }

    func testActiveRecorderStoresEventsCountersAndDurations() {
        let clock = ManualPerformanceDiagnosticsClock()
        let recorder = PerformanceDiagnosticsRecorder(clock: clock, rawEventLimit: 10)

        recorder.startSampling(round: .core)
        recorder.recordEvent(
            category: .hotkey,
            name: "carbonCallback",
            metadata: ["bundleIdentifier": "com.apple.finder"]
        )
        clock.advance(nanoseconds: 2_000_000)
        recorder.measure(category: .systemQuery, name: "currentSpaceID") {
            clock.advance(nanoseconds: 3_000_000)
        }

        let snapshot = recorder.snapshot()
        XCTAssertTrue(snapshot.isSampling)
        XCTAssertEqual(snapshot.round, .core)
        XCTAssertEqual(snapshot.startedAt, Date(timeIntervalSince1970: 0))
        XCTAssertNil(snapshot.stoppedAt)
        XCTAssertEqual(snapshot.totalEventCount, 2)
        XCTAssertEqual(snapshot.rawEvents.count, 2)
        XCTAssertEqual(snapshot.counters["hotkey.carbonCallback"], 1)
        XCTAssertEqual(snapshot.durationSamples["systemQuery.currentSpaceID"]?.count, 1)
        XCTAssertEqual(snapshot.durationSamples["systemQuery.currentSpaceID"]?.first?.durationNanoseconds, 3_000_000)
    }

    func testSessionTimestampsTrackStartAndStop() {
        let clock = ManualPerformanceDiagnosticsClock(nowDate: Date(timeIntervalSince1970: 100), nowNanoseconds: 10)
        let recorder = PerformanceDiagnosticsRecorder(clock: clock)

        recorder.startSampling(round: .core)
        XCTAssertEqual(recorder.snapshot().startedAt, Date(timeIntervalSince1970: 100))
        XCTAssertNil(recorder.snapshot().stoppedAt)

        clock.advance(nanoseconds: 1_500_000_000)
        recorder.stopSampling()

        let snapshot = recorder.snapshot()
        XCTAssertFalse(snapshot.isSampling)
        XCTAssertEqual(snapshot.startedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(snapshot.stoppedAt, Date(timeIntervalSince1970: 101.5))

        recorder.clearSession()
        XCTAssertNil(recorder.snapshot().startedAt)
        XCTAssertNil(recorder.snapshot().stoppedAt)
    }

    func testClearSessionResetsFullSessionState() {
        let clock = ManualPerformanceDiagnosticsClock()
        let recorder = PerformanceDiagnosticsRecorder(clock: clock, rawEventLimit: 1)

        recorder.startSampling(round: .optionalFeatures)
        recorder.updateNotes("diagnostics notes")
        recorder.recordEvent(category: .hotkey, name: "pressed")
        recorder.measure(category: .systemQuery, name: "currentSpaceID") {
            clock.advance(nanoseconds: 2_000_000)
        }
        recorder.incrementErrorCount()

        let populatedSnapshot = recorder.snapshot()
        XCTAssertEqual(populatedSnapshot.round, .optionalFeatures)
        XCTAssertEqual(populatedSnapshot.notes, "diagnostics notes")
        XCTAssertEqual(populatedSnapshot.rawEvents.count, 1)
        XCTAssertEqual(populatedSnapshot.counters["hotkey.pressed"], 1)
        XCTAssertEqual(populatedSnapshot.counters["systemQuery.currentSpaceID"], 1)
        XCTAssertEqual(populatedSnapshot.durationSamples["systemQuery.currentSpaceID"]?.count, 1)
        XCTAssertEqual(populatedSnapshot.droppedRawEventCount, 1)
        XCTAssertEqual(populatedSnapshot.totalEventCount, 2)
        XCTAssertEqual(populatedSnapshot.errorCount, 1)
        XCTAssertNotNil(populatedSnapshot.startedAt)

        recorder.clearSession()

        let snapshot = recorder.snapshot()
        XCTAssertFalse(snapshot.isSampling)
        XCTAssertNil(snapshot.round)
        XCTAssertNil(snapshot.startedAt)
        XCTAssertNil(snapshot.stoppedAt)
        XCTAssertEqual(snapshot.notes, "")
        XCTAssertEqual(snapshot.rawEvents.count, 0)
        XCTAssertEqual(snapshot.counters, [:])
        XCTAssertEqual(snapshot.durationSamples, [:])
        XCTAssertEqual(snapshot.droppedRawEventCount, 0)
        XCTAssertEqual(snapshot.totalEventCount, 0)
        XCTAssertEqual(snapshot.errorCount, 0)
    }

    func testManualClockAdvancesDateWithNanoseconds() {
        let clock = ManualPerformanceDiagnosticsClock(nowDate: Date(timeIntervalSince1970: 200), nowNanoseconds: 50)

        clock.advance(nanoseconds: 2_250_000_000)

        XCTAssertEqual(clock.nowNanoseconds, 2_250_000_050)
        XCTAssertEqual(clock.nowDate, Date(timeIntervalSince1970: 202.25))
    }

    func testRawEventCapDropsRawEventsButKeepsAggregates() {
        let recorder = PerformanceDiagnosticsRecorder(
            clock: ManualPerformanceDiagnosticsClock(),
            rawEventLimit: 2
        )

        recorder.startSampling(round: .optionalFeatures)
        recorder.recordEvent(category: .eventListener, name: "callback")
        recorder.recordEvent(category: .eventListener, name: "callback")
        recorder.recordEvent(category: .eventListener, name: "callback")

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.rawEvents.count, 2)
        XCTAssertEqual(snapshot.droppedRawEventCount, 1)
        XCTAssertEqual(snapshot.totalEventCount, 3)
        XCTAssertEqual(snapshot.counters["eventListener.callback"], 3)
    }

    func testIntervalRecordsDurationAcrossAsyncBoundaries() {
        let clock = ManualPerformanceDiagnosticsClock()
        let recorder = PerformanceDiagnosticsRecorder(clock: clock)
        recorder.startSampling(round: .idleAndStress)

        let token = recorder.beginInterval(
            category: .eventListener,
            name: "mouseWheelTimerActive",
            metadata: ["source": "test"]
        )
        clock.advance(nanoseconds: 9_000_000)
        recorder.endInterval(token, metadata: ["result": "finished"])

        let sample = recorder.snapshot().durationSamples["eventListener.mouseWheelTimerActive"]?.first
        XCTAssertEqual(sample?.durationNanoseconds, 9_000_000)
        XCTAssertEqual(sample?.metadata["source"], "test")
        XCTAssertEqual(sample?.metadata["result"], "finished")
    }

    func testMeasureCompletionDoesNotRecordIntoNewSessionAfterClearAndRestart() {
        let clock = ManualPerformanceDiagnosticsClock()
        let recorder = PerformanceDiagnosticsRecorder(clock: clock)
        recorder.startSampling(round: .core)

        recorder.measure(category: .configuration, name: "save") {
            clock.advance(nanoseconds: 1_000_000)
            recorder.clearSession()
            recorder.startSampling(round: .idleAndStress)
            recorder.updateNotes("new session")
            clock.advance(nanoseconds: 2_000_000)
        }

        let snapshot = recorder.snapshot()
        XCTAssertTrue(snapshot.isSampling)
        XCTAssertEqual(snapshot.round, .idleAndStress)
        XCTAssertEqual(snapshot.notes, "new session")
        XCTAssertEqual(snapshot.totalEventCount, 0)
        XCTAssertEqual(snapshot.rawEvents.count, 0)
        XCTAssertEqual(snapshot.counters, [:])
        XCTAssertEqual(snapshot.durationSamples, [:])
        XCTAssertEqual(snapshot.errorCount, 0)
    }

    func testIntervalTokenDoesNotRecordIntoNewSessionAfterClearAndRestart() {
        let clock = ManualPerformanceDiagnosticsClock()
        let recorder = PerformanceDiagnosticsRecorder(clock: clock)
        recorder.startSampling(round: .core)

        let token = recorder.beginInterval(category: .eventListener, name: "callback")
        clock.advance(nanoseconds: 1_000_000)
        recorder.clearSession()
        recorder.startSampling(round: .optionalFeatures)
        clock.advance(nanoseconds: 2_000_000)
        recorder.endInterval(token, metadata: ["result": "finished"])

        let snapshot = recorder.snapshot()
        XCTAssertTrue(snapshot.isSampling)
        XCTAssertEqual(snapshot.round, .optionalFeatures)
        XCTAssertEqual(snapshot.totalEventCount, 0)
        XCTAssertEqual(snapshot.rawEvents.count, 0)
        XCTAssertEqual(snapshot.counters, [:])
        XCTAssertEqual(snapshot.durationSamples, [:])
    }

    func testInactiveBeginIntervalDoesNotReadClock() {
        let clock = CountingPerformanceDiagnosticsClock()
        let recorder = PerformanceDiagnosticsRecorder(clock: clock)

        let token = recorder.beginInterval(
            category: .eventListener,
            name: "callback",
            metadata: ["filePath": "/Users/example/private.txt"]
        )

        XCTAssertNil(token)
        XCTAssertEqual(clock.dateReadCount, 0)
        XCTAssertEqual(clock.nanosecondsReadCount, 0)
    }

    func testMeasureRethrowsAndIncrementsErrorCount() {
        let clock = ManualPerformanceDiagnosticsClock()
        let recorder = PerformanceDiagnosticsRecorder(clock: clock)
        recorder.startSampling(round: .core)

        XCTAssertThrowsError(
            try recorder.measure(category: .configuration, name: "save") {
                clock.advance(nanoseconds: 4_000_000)
                throw TestError.failed
            }
        )

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.errorCount, 1)
        XCTAssertEqual(snapshot.totalEventCount, 1)
        XCTAssertEqual(snapshot.durationSamples["configuration.save"]?.first?.durationNanoseconds, 4_000_000)
    }

    func testMetadataRedactionDropsUnsafeKeys() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())

        recorder.startSampling(round: .core)
        recorder.recordEvent(
            category: .hotkey,
            name: "decision",
            metadata: [
                "appDisplayName": "Finder",
                "bundleIdentifier": "com.apple.finder",
                "documentPath": "/Users/example/Documents/secret.md",
                "documentTitle": "Secret Document",
                "filePath": "/Users/example/private.txt",
                "fullPath": "/Users/example/Documents/secret.txt",
                "inputText": "private input",
                "licenseKey": "APPWINK-SECRET",
                "licensePayload": "APPWINK-SECRET",
                "result": "allowed",
                "source": "test",
                "typedText": "private typed text",
                "userHomeDirectory": "/Users/example",
                "windowName": "Secret Window",
                "windowTitleText": "Secret Document",
            ]
        )

        let metadata = recorder.snapshot().rawEvents.first?.metadata ?? [:]
        XCTAssertEqual(metadata["appDisplayName"], "Finder")
        XCTAssertEqual(metadata["bundleIdentifier"], "com.apple.finder")
        XCTAssertEqual(metadata["result"], "allowed")
        XCTAssertEqual(metadata["source"], "test")
        XCTAssertNil(metadata["documentPath"])
        XCTAssertNil(metadata["documentTitle"])
        XCTAssertNil(metadata["filePath"])
        XCTAssertNil(metadata["fullPath"])
        XCTAssertNil(metadata["inputText"])
        XCTAssertNil(metadata["licenseKey"])
        XCTAssertNil(metadata["licensePayload"])
        XCTAssertNil(metadata["typedText"])
        XCTAssertNil(metadata["userHomeDirectory"])
        XCTAssertNil(metadata["windowName"])
        XCTAssertNil(metadata["windowTitleText"])
    }

    func testSnapshotCodableRoundTrip() throws {
        let clock = ManualPerformanceDiagnosticsClock(nowDate: Date(timeIntervalSince1970: 300))
        let recorder = PerformanceDiagnosticsRecorder(clock: clock, rawEventLimit: 10)
        recorder.startSampling(round: .optionalFeatures)
        recorder.updateNotes("Focused diagnostics run")
        recorder.recordEvent(category: .overlay, name: "shown", metadata: ["result": "visible"])
        clock.advance(nanoseconds: 5_000_000)
        recorder.measure(category: .resource, name: "sample") {
            clock.advance(nanoseconds: 7_000_000)
        }
        recorder.incrementErrorCount()
        recorder.stopSampling()

        let snapshot = recorder.snapshot()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PerformanceDiagnosticsSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }
}
