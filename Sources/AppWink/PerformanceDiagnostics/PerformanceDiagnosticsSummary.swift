import Foundation

struct PerformanceDiagnosticsReport: Codable, Equatable, Sendable {
    let overview: PerformanceDiagnosticsReportOverview
    let eventCounters: [PerformanceDiagnosticsEventCounterSummary]
    let durationMetrics: [PerformanceDiagnosticsDurationMetricSummary]
    let resourceSnapshots: [PerformanceDiagnosticsResourceSnapshot]
    let resourceSummary: PerformanceDiagnosticsResourceSummary
    let rawEvents: [PerformanceDiagnosticsEvent]

    init(
        snapshot: PerformanceDiagnosticsSnapshot,
        resourceSnapshots: [PerformanceDiagnosticsResourceSnapshot]
    ) {
        overview = PerformanceDiagnosticsReportOverview(snapshot: snapshot)
        eventCounters = snapshot.counters
            .map { key, count in
                PerformanceDiagnosticsEventCounterSummary(key: key, count: count)
            }
            .sorted { lhs, rhs in
                lhs.key < rhs.key
            }
        durationMetrics = snapshot.durationSamples
            .map { key, samples in
                PerformanceDiagnosticsDurationMetricSummary(key: key, samples: samples)
            }
            .sorted { lhs, rhs in
                lhs.key < rhs.key
            }
        self.resourceSnapshots = resourceSnapshots.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }

            return lhs.processIdentifier < rhs.processIdentifier
        }
        resourceSummary = PerformanceDiagnosticsResourceSummary(samples: self.resourceSnapshots)
        rawEvents = snapshot.rawEvents
    }
}

struct PerformanceDiagnosticsReportOverview: Codable, Equatable, Sendable {
    let isSampling: Bool
    let round: PerformanceDiagnosticsRound?
    let startedAt: Date?
    let stoppedAt: Date?
    let notes: String
    let totalEventCount: Int
    let droppedRawEventCount: Int
    let errorCount: Int

    init(snapshot: PerformanceDiagnosticsSnapshot) {
        isSampling = snapshot.isSampling
        round = snapshot.round
        startedAt = snapshot.startedAt
        stoppedAt = snapshot.stoppedAt
        notes = snapshot.notes
        totalEventCount = snapshot.totalEventCount
        droppedRawEventCount = snapshot.droppedRawEventCount
        errorCount = snapshot.errorCount
    }
}

struct PerformanceDiagnosticsEventCounterSummary: Codable, Equatable, Sendable {
    let key: String
    let count: Int
}

struct PerformanceDiagnosticsDurationMetricSummary: Codable, Equatable, Sendable {
    let key: String
    let count: Int
    let minimumDurationNanoseconds: UInt64
    let maximumDurationNanoseconds: UInt64
    let averageDurationNanoseconds: Double
    let p50DurationNanoseconds: UInt64
    let p95DurationNanoseconds: UInt64

    init(key: String, samples: [PerformanceDiagnosticsDurationSample]) {
        let durations = samples
            .map(\.durationNanoseconds)
            .sorted()

        self.key = key
        count = durations.count
        minimumDurationNanoseconds = durations.first ?? 0
        maximumDurationNanoseconds = durations.last ?? 0
        averageDurationNanoseconds = durations.isEmpty
            ? 0
            : durations.reduce(0.0) { partialResult, duration in
                partialResult + Double(duration)
            } / Double(durations.count)
        p50DurationNanoseconds = Self.nearestRankPercentile(0.50, in: durations)
        p95DurationNanoseconds = Self.nearestRankPercentile(0.95, in: durations)
    }

    private static func nearestRankPercentile(_ percentile: Double, in sortedDurations: [UInt64]) -> UInt64 {
        guard !sortedDurations.isEmpty else {
            return 0
        }

        let rawIndex = Int(ceil(percentile * Double(sortedDurations.count))) - 1
        let index = min(max(rawIndex, 0), sortedDurations.count - 1)
        return sortedDurations[index]
    }
}

struct PerformanceDiagnosticsResourceSummary: Codable, Equatable, Sendable {
    let sampleCount: Int
    let minimumResidentMemoryBytes: UInt64
    let maximumResidentMemoryBytes: UInt64
    let residentMemoryDeltaBytes: Int64
    let minimumCPUTimeSeconds: Double
    let maximumCPUTimeSeconds: Double
    let cpuTimeDeltaSeconds: Double
    let minimumThreadCount: Int
    let maximumThreadCount: Int
    let threadCountDelta: Int
    let firstSampleAt: Date?
    let lastSampleAt: Date?

    init(samples: [PerformanceDiagnosticsResourceSnapshot]) {
        sampleCount = samples.count
        minimumResidentMemoryBytes = samples.map(\.residentMemoryBytes).min() ?? 0
        maximumResidentMemoryBytes = samples.map(\.residentMemoryBytes).max() ?? 0
        minimumCPUTimeSeconds = samples.map(\.cpuTimeSeconds).min() ?? 0
        maximumCPUTimeSeconds = samples.map(\.cpuTimeSeconds).max() ?? 0
        minimumThreadCount = samples.map(\.threadCount).min() ?? 0
        maximumThreadCount = samples.map(\.threadCount).max() ?? 0
        firstSampleAt = samples.first?.timestamp
        lastSampleAt = samples.last?.timestamp

        if let first = samples.first, let last = samples.last {
            residentMemoryDeltaBytes = Self.signedDelta(
                from: first.residentMemoryBytes,
                to: last.residentMemoryBytes
            )
            cpuTimeDeltaSeconds = last.cpuTimeSeconds - first.cpuTimeSeconds
            threadCountDelta = last.threadCount - first.threadCount
        } else {
            residentMemoryDeltaBytes = 0
            cpuTimeDeltaSeconds = 0
            threadCountDelta = 0
        }
    }

    private static func signedDelta(from firstValue: UInt64, to lastValue: UInt64) -> Int64 {
        if lastValue >= firstValue {
            let magnitude = lastValue - firstValue
            return magnitude > UInt64(Int64.max) ? Int64.max : Int64(magnitude)
        }

        let magnitude = firstValue - lastValue
        let int64MinMagnitude = UInt64(Int64.max) + 1
        return magnitude >= int64MinMagnitude ? Int64.min : -Int64(magnitude)
    }
}
