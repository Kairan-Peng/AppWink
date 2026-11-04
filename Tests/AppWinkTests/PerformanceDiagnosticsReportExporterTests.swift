import XCTest
@testable import AppWinkRuntime

final class PerformanceDiagnosticsReportExporterTests: XCTestCase {
    func testReportSortsCountersAndDurationMetricsAndCalculatesPercentiles() throws {
        let clock = ManualPerformanceDiagnosticsClock(nowDate: Date(timeIntervalSince1970: 1_000))
        let recorder = PerformanceDiagnosticsRecorder(clock: clock)
        recorder.startSampling(round: .core)
        recorder.updateNotes("Round notes")
        recorder.recordEvent(category: .overlay, name: "shown")
        recorder.recordEvent(category: .hotkey, name: "pressed")
        recordDuration(recorder, clock: clock, key: (.systemQuery, "spaceIDs"), nanoseconds: 5)
        recordDuration(recorder, clock: clock, key: (.systemQuery, "spaceIDs"), nanoseconds: 1)
        recordDuration(recorder, clock: clock, key: (.registration, "refresh"), nanoseconds: 30)
        recordDuration(recorder, clock: clock, key: (.systemQuery, "spaceIDs"), nanoseconds: 10)
        recordDuration(recorder, clock: clock, key: (.systemQuery, "spaceIDs"), nanoseconds: 2)
        recordDuration(recorder, clock: clock, key: (.systemQuery, "spaceIDs"), nanoseconds: 100)
        recorder.incrementErrorCount()
        clock.advance(nanoseconds: 1_000_000_000)
        recorder.stopSampling()

        let report = PerformanceDiagnosticsReportExporter().report(
            for: recorder.snapshot(),
            resourceSnapshots: []
        )

        XCTAssertEqual(report.overview.round, .core)
        XCTAssertEqual(report.overview.startedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(report.overview.stoppedAt, Date(timeIntervalSince1970: 1_001.000000148))
        XCTAssertEqual(report.overview.notes, "Round notes")
        XCTAssertEqual(report.overview.totalEventCount, 8)
        XCTAssertEqual(report.overview.errorCount, 1)
        XCTAssertEqual(report.eventCounters.map(\.key), [
            "hotkey.pressed",
            "overlay.shown",
            "registration.refresh",
            "systemQuery.spaceIDs",
        ])
        XCTAssertEqual(report.eventCounters.map(\.count), [1, 1, 1, 5])
        XCTAssertEqual(report.durationMetrics.map(\.key), [
            "registration.refresh",
            "systemQuery.spaceIDs",
        ])

        let spaceIDs = try XCTUnwrap(report.durationMetrics.first { $0.key == "systemQuery.spaceIDs" })
        XCTAssertEqual(spaceIDs.count, 5)
        XCTAssertEqual(spaceIDs.minimumDurationNanoseconds, 1)
        XCTAssertEqual(spaceIDs.maximumDurationNanoseconds, 100)
        XCTAssertEqual(spaceIDs.averageDurationNanoseconds, 23.6)
        XCTAssertEqual(spaceIDs.p50DurationNanoseconds, 5)
        XCTAssertEqual(spaceIDs.p95DurationNanoseconds, 100)
    }

    func testJSONExportIsStablePrettyPrintedAndUsesSortedKeys() throws {
        let snapshot = PerformanceDiagnosticsSnapshot(
            isSampling: false,
            round: .optionalFeatures,
            startedAt: Date(timeIntervalSince1970: 10.123),
            stoppedAt: Date(timeIntervalSince1970: 20.987),
            notes: "stable export",
            rawEvents: [
                PerformanceDiagnosticsEvent(
                    category: .hotkey,
                    name: "pressed",
                    timestampNanoseconds: 1,
                    metadata: ["bundleIdentifier": "com.apple.finder"]
                ),
            ],
            counters: ["systemQuery.windowList": 2, "hotkey.pressed": 1],
            durationSamples: [
                "systemQuery.windowList": [
                    Self.durationSample(category: .systemQuery, name: "windowList", durationNanoseconds: 4),
                    Self.durationSample(category: .systemQuery, name: "windowList", durationNanoseconds: 8),
                ],
            ],
            droppedRawEventCount: 3,
            totalEventCount: 6,
            errorCount: 1
        )
        let resources = [
            Self.resourceSample(timestamp: 12.456, memory: 20, cpu: 2, threads: 4),
            Self.resourceSample(timestamp: 11.234, memory: 10, cpu: 1, threads: 3),
        ]
        let exporter = PerformanceDiagnosticsReportExporter()

        let firstData = try exporter.data(for: snapshot, resourceSnapshots: resources)
        let secondData = try exporter.data(for: snapshot, resourceSnapshots: resources)

        XCTAssertEqual(firstData, secondData)

        let json = try XCTUnwrap(String(data: firstData, encoding: .utf8))
        XCTAssertTrue(json.hasPrefix("{\n  \"durationMetrics\""))
        XCTAssertLessThan(try XCTUnwrap(json.range(of: "\"durationMetrics\"")?.lowerBound), try XCTUnwrap(json.range(of: "\"eventCounters\"")?.lowerBound))
        XCTAssertLessThan(try XCTUnwrap(json.range(of: "\"eventCounters\"")?.lowerBound), try XCTUnwrap(json.range(of: "\"overview\"")?.lowerBound))
        XCTAssertTrue(json.contains("\"minimumDurationNanoseconds\""))
        XCTAssertTrue(json.contains("\"resourceSummary\""))
        XCTAssertTrue(json.contains("\"startedAt\" : \"1970-01-01T00:00:10.123Z\""))
        XCTAssertTrue(json.contains("\"stoppedAt\" : \"1970-01-01T00:00:20.987Z\""))
        XCTAssertTrue(json.contains("\"timestamp\" : \"1970-01-01T00:00:12.456Z\""))

        let decoded = try JSONDecoder.iso8601Fractional.decode(PerformanceDiagnosticsReport.self, from: firstData)
        XCTAssertEqual(decoded.overview.totalEventCount, 6)
        XCTAssertEqual(decoded.overview.startedAt, Date(timeIntervalSince1970: 10.123))
        XCTAssertEqual(decoded.overview.stoppedAt, Date(timeIntervalSince1970: 20.987))
        XCTAssertEqual(decoded.eventCounters.map { $0.key }, ["hotkey.pressed", "systemQuery.windowList"])
        XCTAssertEqual(decoded.resourceSnapshots.map { $0.timestamp }, [
            Date(timeIntervalSince1970: 11.234),
            Date(timeIntervalSince1970: 12.456),
        ])
    }

    func testMakeReportProducesUsefulMarkdownWithoutUnsafeMetadataExamples() throws {
        let clock = ManualPerformanceDiagnosticsClock(nowDate: Date(timeIntervalSince1970: 100))
        let recorder = PerformanceDiagnosticsRecorder(clock: clock)
        recorder.startSampling(round: .core)
        recorder.updateNotes("Activity Monitor idle CPU stayed near zero.")
        recorder.recordEvent(
            category: .hotkey,
            name: "decision",
            metadata: [
                "bundleIdentifier": "com.apple.finder",
                "fullPath": "/Users/example/Documents/Secret.app",
                "licenseKey": "APPWINK-SECRET",
            ]
        )
        recordDuration(recorder, clock: clock, key: (.systemQuery, "windowList"), nanoseconds: 8_000_000)
        recorder.incrementErrorCount()
        clock.advance(nanoseconds: 1_000_000_000)
        recorder.stopSampling()

        let export = try PerformanceDiagnosticsReportExporter().makeReport(
            snapshot: recorder.snapshot(),
            resourceSnapshot: Self.resourceSample(timestamp: 101, memory: 40_000_000, cpu: 2, threads: 6)
        )

        XCTAssertTrue(export.markdown.contains("# AppWink Performance Diagnostics"))
        XCTAssertTrue(export.markdown.contains("## Overview"))
        XCTAssertTrue(export.markdown.contains("## Event Counters"))
        XCTAssertTrue(export.markdown.contains("hotkey.decision"))
        XCTAssertTrue(export.markdown.contains("## Duration Metrics"))
        XCTAssertTrue(export.markdown.contains("systemQuery.windowList"))
        XCTAssertTrue(export.markdown.contains("- systemQuery.windowList: count 1, p50 8.000 ms, p95 8.000 ms, max 8.000 ms"))
        XCTAssertTrue(export.markdown.contains("## Resource Summary"))
        XCTAssertTrue(export.markdown.contains("- Resident memory: 40000000 bytes min, 40000000 bytes max, 0 bytes delta"))
        XCTAssertTrue(export.markdown.contains("- CPU time: 2.000 s min, 2.000 s max, 0.000 s delta"))
        XCTAssertTrue(export.markdown.contains("- Threads: 6 min, 6 max, 0 delta"))
        XCTAssertTrue(export.markdown.contains("## Dropped And Error Counts"))
        XCTAssertTrue(export.markdown.contains("Dropped raw events: 0"))
        XCTAssertTrue(export.markdown.contains("Errors: 1"))
        XCTAssertTrue(export.markdown.contains("## Notes"))
        XCTAssertTrue(export.markdown.contains("Activity Monitor idle CPU stayed near zero."))
        XCTAssertFalse(export.markdown.contains("/Users/example"))
        XCTAssertFalse(export.markdown.contains("APPWINK-SECRET"))

        let json = try XCTUnwrap(String(data: export.jsonData, encoding: .utf8))
        XCTAssertFalse(json.contains("/Users/example"))
        XCTAssertFalse(json.contains("APPWINK-SECRET"))
    }

    func testDurationAverageDoesNotOverflowForLargeUInt64Durations() throws {
        let snapshot = PerformanceDiagnosticsSnapshot(
            isSampling: false,
            round: nil,
            startedAt: nil,
            stoppedAt: nil,
            notes: "",
            rawEvents: [],
            counters: [:],
            durationSamples: [
                "systemQuery.large": [
                    Self.durationSample(
                        category: .systemQuery,
                        name: "large",
                        durationNanoseconds: UInt64.max
                    ),
                    Self.durationSample(
                        category: .systemQuery,
                        name: "large",
                        durationNanoseconds: UInt64.max
                    ),
                ],
            ],
            droppedRawEventCount: 0,
            totalEventCount: 0,
            errorCount: 0
        )

        let metric = try XCTUnwrap(
            PerformanceDiagnosticsReport(snapshot: snapshot, resourceSnapshots: [])
                .durationMetrics
                .first
        )

        XCTAssertEqual(metric.count, 2)
        XCTAssertEqual(metric.minimumDurationNanoseconds, UInt64.max)
        XCTAssertEqual(metric.maximumDurationNanoseconds, UInt64.max)
        XCTAssertEqual(metric.averageDurationNanoseconds, Double(UInt64.max))
        XCTAssertEqual(metric.p50DurationNanoseconds, UInt64.max)
        XCTAssertEqual(metric.p95DurationNanoseconds, UInt64.max)
    }

    func testExporterWritesMarkdownAndJSONSidecar() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let markdownURL = directory.appendingPathComponent("appwink-performance.md")
        let jsonURL = directory.appendingPathComponent("appwink-performance.json")
        let export = PerformanceDiagnosticsReportExport(
            markdown: "# Report",
            jsonData: Data(#"{"ok":true}"#.utf8)
        )

        try PerformanceDiagnosticsReportExporter().write(export, markdownURL: markdownURL)

        XCTAssertEqual(try String(contentsOf: markdownURL, encoding: .utf8), "# Report")
        XCTAssertEqual(try Data(contentsOf: jsonURL), Data(#"{"ok":true}"#.utf8))
    }

    func testExporterDoesNotLeaveVisibleMarkdownWhenSidecarDestinationFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let markdownURL = directory.appendingPathComponent("appwink-performance.md")
        let jsonURL = directory.appendingPathComponent("appwink-performance.json", isDirectory: true)
        try FileManager.default.createDirectory(at: jsonURL, withIntermediateDirectories: true)

        let export = PerformanceDiagnosticsReportExport(
            markdown: "# Report",
            jsonData: Data(#"{"ok":true}"#.utf8)
        )

        XCTAssertThrowsError(
            try PerformanceDiagnosticsReportExporter().write(export, markdownURL: markdownURL)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdownURL.path))

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testWriteToURLReturnsAndPersistsSameData() throws {
        let snapshot = PerformanceDiagnosticsSnapshot(
            isSampling: false,
            round: .idleAndStress,
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
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent("diagnostics.json")
        let data = try PerformanceDiagnosticsReportExporter().write(
            snapshot: snapshot,
            resourceSnapshots: [],
            to: url
        )

        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    private func recordDuration(
        _ recorder: PerformanceDiagnosticsRecorder,
        clock: ManualPerformanceDiagnosticsClock,
        key: (PerformanceDiagnosticsCategory, String),
        nanoseconds: UInt64
    ) {
        recorder.measure(category: key.0, name: key.1) {
            clock.advance(nanoseconds: nanoseconds)
        }
    }

    private static func durationSample(
        category: PerformanceDiagnosticsCategory,
        name: String,
        durationNanoseconds: UInt64
    ) -> PerformanceDiagnosticsDurationSample {
        PerformanceDiagnosticsDurationSample(
            category: category,
            name: name,
            startNanoseconds: 0,
            endNanoseconds: durationNanoseconds,
            durationNanoseconds: durationNanoseconds,
            metadata: [:]
        )
    }

    private static func resourceSample(
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

private extension JSONDecoder {
    static var iso8601Fractional: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            guard let date = formatter.date(from: dateString) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected fractional ISO-8601 date."
                )
            }

            return date
        }
        return decoder
    }
}
