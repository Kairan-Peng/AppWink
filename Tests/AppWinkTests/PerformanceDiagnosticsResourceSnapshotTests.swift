import XCTest
@testable import AppWinkRuntime

final class PerformanceDiagnosticsResourceSnapshotTests: XCTestCase {
    private struct FixedResourceSampler: PerformanceDiagnosticsResourceSampling {
        let snapshot: PerformanceDiagnosticsResourceSnapshot

        func sample() -> PerformanceDiagnosticsResourceSnapshot {
            snapshot
        }
    }

    func testResourceSamplerCanBeInjectedForDeterministicSamples() {
        let expected = PerformanceDiagnosticsResourceSnapshot(
            residentMemoryBytes: 123_456,
            cpuTimeSeconds: 7.5,
            threadCount: 9,
            processIdentifier: 101,
            timestamp: Date(timeIntervalSince1970: 500)
        )

        let sampler: any PerformanceDiagnosticsResourceSampling = FixedResourceSampler(snapshot: expected)

        XCTAssertEqual(sampler.sample(), expected)
    }

    func testSystemResourceSamplerReturnsCurrentProcessSnapshot() {
        let sampler = SystemPerformanceDiagnosticsResourceSampler(
            clock: ManualPerformanceDiagnosticsClock(nowDate: Date(timeIntervalSince1970: 700))
        )

        let snapshot = sampler.sample()

        XCTAssertEqual(snapshot.processIdentifier, ProcessInfo.processInfo.processIdentifier)
        XCTAssertGreaterThan(snapshot.residentMemoryBytes, 0)
        XCTAssertGreaterThan(snapshot.threadCount, 0)
        XCTAssertGreaterThanOrEqual(snapshot.cpuTimeSeconds, 0)
        XCTAssertEqual(snapshot.timestamp, Date(timeIntervalSince1970: 700))
    }

    func testCPUTimeCombinesTerminatedAndLiveThreadTime() {
        let cpuTimeSeconds = SystemPerformanceDiagnosticsResourceSampler.cpuTimeSeconds(
            terminatedThreadCPUTimeSeconds: 1.25,
            liveThreadCPUTimeSeconds: 2.5
        )

        XCTAssertEqual(cpuTimeSeconds, 3.75)
    }

    func testResourceSummaryUsesChronologicalSamplesForExtremaAndDeltas() {
        let report = PerformanceDiagnosticsReport(
            snapshot: emptySnapshot(),
            resourceSnapshots: [
                resourceSample(timestamp: 200, memory: 150, cpu: 2.5, threads: 5),
                resourceSample(timestamp: 100, memory: 100, cpu: 1.25, threads: 4),
                resourceSample(timestamp: 300, memory: 120, cpu: 3.75, threads: 7),
            ]
        )

        XCTAssertEqual(report.resourceSnapshots.map(\.timestamp), [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 300),
        ])
        XCTAssertEqual(report.resourceSummary.sampleCount, 3)
        XCTAssertEqual(report.resourceSummary.minimumResidentMemoryBytes, 100)
        XCTAssertEqual(report.resourceSummary.maximumResidentMemoryBytes, 150)
        XCTAssertEqual(report.resourceSummary.residentMemoryDeltaBytes, 20)
        XCTAssertEqual(report.resourceSummary.minimumCPUTimeSeconds, 1.25)
        XCTAssertEqual(report.resourceSummary.maximumCPUTimeSeconds, 3.75)
        XCTAssertEqual(report.resourceSummary.cpuTimeDeltaSeconds, 2.5)
        XCTAssertEqual(report.resourceSummary.minimumThreadCount, 4)
        XCTAssertEqual(report.resourceSummary.maximumThreadCount, 7)
        XCTAssertEqual(report.resourceSummary.threadCountDelta, 3)
        XCTAssertEqual(report.resourceSummary.firstSampleAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(report.resourceSummary.lastSampleAt, Date(timeIntervalSince1970: 300))
    }

    func testResourceSummaryMemoryDeltaSaturatesAtInt64Bounds() {
        let positiveReport = PerformanceDiagnosticsReport(
            snapshot: emptySnapshot(),
            resourceSnapshots: [
                resourceSample(timestamp: 100, memory: 0, cpu: 1, threads: 4),
                resourceSample(timestamp: 200, memory: UInt64.max, cpu: 2, threads: 5),
            ]
        )
        XCTAssertEqual(positiveReport.resourceSummary.residentMemoryDeltaBytes, Int64.max)

        let negativeReport = PerformanceDiagnosticsReport(
            snapshot: emptySnapshot(),
            resourceSnapshots: [
                resourceSample(timestamp: 100, memory: UInt64.max, cpu: 1, threads: 4),
                resourceSample(timestamp: 200, memory: 0, cpu: 2, threads: 5),
            ]
        )
        XCTAssertEqual(negativeReport.resourceSummary.residentMemoryDeltaBytes, Int64.min)
    }

    private func emptySnapshot() -> PerformanceDiagnosticsSnapshot {
        PerformanceDiagnosticsSnapshot(
            isSampling: false,
            round: nil,
            startedAt: nil,
            stoppedAt: nil,
            notes: "",
            rawEvents: [],
            counters: [:],
            durationSamples: [:],
            droppedRawEventCount: 0,
            totalEventCount: 0,
            errorCount: 0
        )
    }

    private func resourceSample(
        timestamp: TimeInterval,
        memory: UInt64,
        cpu: Double,
        threads: Int
    ) -> PerformanceDiagnosticsResourceSnapshot {
        PerformanceDiagnosticsResourceSnapshot(
            residentMemoryBytes: memory,
            cpuTimeSeconds: cpu,
            threadCount: threads,
            processIdentifier: 42,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}
