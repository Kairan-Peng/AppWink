import Foundation

struct PerformanceDiagnosticsReportExport: Equatable, Sendable {
    let markdown: String
    let jsonData: Data
}

enum PerformanceDiagnosticsReportExportWriteError: Error, Equatable {
    case destinationIsDirectory(URL)
}

struct PerformanceDiagnosticsReportExporter: Sendable {
    func report(
        for snapshot: PerformanceDiagnosticsSnapshot,
        resourceSnapshots: [PerformanceDiagnosticsResourceSnapshot]
    ) -> PerformanceDiagnosticsReport {
        PerformanceDiagnosticsReport(
            snapshot: snapshot,
            resourceSnapshots: resourceSnapshots
        )
    }

    func makeReport(
        snapshot: PerformanceDiagnosticsSnapshot,
        resourceSnapshot: PerformanceDiagnosticsResourceSnapshot
    ) throws -> PerformanceDiagnosticsReportExport {
        try makeReport(snapshot: snapshot, resourceSnapshots: [resourceSnapshot])
    }

    func makeReport(
        snapshot: PerformanceDiagnosticsSnapshot,
        resourceSnapshots: [PerformanceDiagnosticsResourceSnapshot]
    ) throws -> PerformanceDiagnosticsReportExport {
        let report = report(for: snapshot, resourceSnapshots: resourceSnapshots)

        return PerformanceDiagnosticsReportExport(
            markdown: markdown(for: report),
            jsonData: try Self.jsonEncoder.encode(report)
        )
    }

    func data(
        for snapshot: PerformanceDiagnosticsSnapshot,
        resourceSnapshots: [PerformanceDiagnosticsResourceSnapshot]
    ) throws -> Data {
        try Self.jsonEncoder.encode(report(for: snapshot, resourceSnapshots: resourceSnapshots))
    }

    func write(
        snapshot: PerformanceDiagnosticsSnapshot,
        resourceSnapshots: [PerformanceDiagnosticsResourceSnapshot],
        to url: URL
    ) throws -> Data {
        let data = try data(for: snapshot, resourceSnapshots: resourceSnapshots)
        try data.write(to: url, options: [.atomic])
        return data
    }

    func write(_ export: PerformanceDiagnosticsReportExport, markdownURL: URL) throws {
        let directoryURL = markdownURL.deletingLastPathComponent()
        let jsonURL = markdownURL
            .deletingPathExtension()
            .appendingPathExtension("json")
        let fileManager = FileManager.default
        let uniqueID = UUID().uuidString
        let markdownTempURL = directoryURL
            .appendingPathComponent(".\(markdownURL.lastPathComponent).\(uniqueID).tmp", isDirectory: false)
        let jsonTempURL = directoryURL
            .appendingPathComponent(".\(jsonURL.lastPathComponent).\(uniqueID).tmp", isDirectory: false)
        let markdownBackupURL = directoryURL
            .appendingPathComponent(".\(markdownURL.lastPathComponent).\(uniqueID).backup", isDirectory: false)
        let jsonBackupURL = directoryURL
            .appendingPathComponent(".\(jsonURL.lastPathComponent).\(uniqueID).backup", isDirectory: false)

        var markdownWasPublished = false
        var jsonWasPublished = false
        var markdownWasBackedUp = false
        var jsonWasBackedUp = false
        var didFinish = false

        defer {
            try? fileManager.removeItem(at: markdownTempURL)
            try? fileManager.removeItem(at: jsonTempURL)

            if didFinish {
                try? fileManager.removeItem(at: markdownBackupURL)
                try? fileManager.removeItem(at: jsonBackupURL)
            } else {
                if markdownWasPublished {
                    try? fileManager.removeItem(at: markdownURL)
                }
                if jsonWasPublished {
                    try? fileManager.removeItem(at: jsonURL)
                }
                if markdownWasBackedUp {
                    try? fileManager.moveItem(at: markdownBackupURL, to: markdownURL)
                }
                if jsonWasBackedUp {
                    try? fileManager.moveItem(at: jsonBackupURL, to: jsonURL)
                }
            }
        }

        try validateWritableFileDestination(markdownURL)
        try validateWritableFileDestination(jsonURL)

        try export.markdown.write(to: markdownTempURL, atomically: true, encoding: .utf8)
        try export.jsonData.write(to: jsonTempURL, options: [.atomic])

        if fileManager.fileExists(atPath: markdownURL.path) {
            try fileManager.moveItem(at: markdownURL, to: markdownBackupURL)
            markdownWasBackedUp = true
        }
        if fileManager.fileExists(atPath: jsonURL.path) {
            try fileManager.moveItem(at: jsonURL, to: jsonBackupURL)
            jsonWasBackedUp = true
        }

        try fileManager.moveItem(at: markdownTempURL, to: markdownURL)
        markdownWasPublished = true
        try fileManager.moveItem(at: jsonTempURL, to: jsonURL)
        jsonWasPublished = true
        didFinish = true
    }

    private func markdown(for report: PerformanceDiagnosticsReport) -> String {
        var sections: [String] = []

        sections.append(
            """
            # AppWink Performance Diagnostics

            ## Overview

            - Sampling: \(report.overview.isSampling ? "active" : "stopped")
            - Round: \(report.overview.round?.rawValue ?? "none")
            - Started: \(formatDate(report.overview.startedAt))
            - Stopped: \(formatDate(report.overview.stoppedAt))
            - Total events: \(report.overview.totalEventCount)
            """
        )

        sections.append(
            """
            ## Event Counters

            \(eventCounterMarkdown(report.eventCounters))
            """
        )

        sections.append(
            """
            ## Duration Metrics

            \(durationMetricMarkdown(report.durationMetrics))
            """
        )

        sections.append(
            """
            ## Resource Summary

            - Samples: \(report.resourceSummary.sampleCount)
            - Resident memory: \(formatBytes(report.resourceSummary.minimumResidentMemoryBytes)) min, \(formatBytes(report.resourceSummary.maximumResidentMemoryBytes)) max, \(formatSignedBytes(report.resourceSummary.residentMemoryDeltaBytes)) delta
            - CPU time: \(formatSeconds(report.resourceSummary.minimumCPUTimeSeconds)) min, \(formatSeconds(report.resourceSummary.maximumCPUTimeSeconds)) max, \(formatSeconds(report.resourceSummary.cpuTimeDeltaSeconds)) delta
            - Threads: \(report.resourceSummary.minimumThreadCount) min, \(report.resourceSummary.maximumThreadCount) max, \(formatSignedInteger(report.resourceSummary.threadCountDelta)) delta
            - First sample: \(formatDate(report.resourceSummary.firstSampleAt))
            - Last sample: \(formatDate(report.resourceSummary.lastSampleAt))
            """
        )

        sections.append(
            """
            ## Dropped And Error Counts

            - Dropped raw events: \(report.overview.droppedRawEventCount)
            - Errors: \(report.overview.errorCount)
            """
        )

        sections.append(
            """
            ## Notes

            \(notesMarkdown(report.overview.notes))
            """
        )

        return sections.joined(separator: "\n\n") + "\n"
    }

    private func eventCounterMarkdown(_ counters: [PerformanceDiagnosticsEventCounterSummary]) -> String {
        guard !counters.isEmpty else {
            return "No event counters recorded."
        }

        return counters
            .map { "- \($0.key): \($0.count)" }
            .joined(separator: "\n")
    }

    private func durationMetricMarkdown(_ metrics: [PerformanceDiagnosticsDurationMetricSummary]) -> String {
        guard !metrics.isEmpty else {
            return "No duration metrics recorded."
        }

        return metrics
            .map { metric in
                "- \(metric.key): count \(metric.count), p50 \(formatDuration(metric.p50DurationNanoseconds)), p95 \(formatDuration(metric.p95DurationNanoseconds)), max \(formatDuration(metric.maximumDurationNanoseconds))"
            }
            .joined(separator: "\n")
    }

    private func notesMarkdown(_ notes: String) -> String {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty else {
            return "No notes recorded."
        }

        return trimmedNotes
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else {
            return "n/a"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func formatDuration(_ nanoseconds: UInt64) -> String {
        Self.posixString(format: "%.3f ms", Double(nanoseconds) / 1_000_000)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        "\(bytes) bytes"
    }

    private func formatSignedBytes(_ bytes: Int64) -> String {
        let sign = bytes > 0 ? "+" : ""
        return "\(sign)\(bytes) bytes"
    }

    private func formatSeconds(_ seconds: Double) -> String {
        Self.posixString(format: "%.3f s", seconds)
    }

    private func formatSignedInteger(_ value: Int) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value)"
    }

    private func validateWritableFileDestination(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        throw PerformanceDiagnosticsReportExportWriteError.destinationIsDirectory(url)
    }

    private static func posixString(format: String, _ value: Double) -> String {
        String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
