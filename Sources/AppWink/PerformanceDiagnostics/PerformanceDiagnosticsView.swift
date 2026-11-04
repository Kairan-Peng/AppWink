import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PerformanceDiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedRound: PerformanceDiagnosticsRound = .core
    @State private var notes = ""
    @State private var snapshot: PerformanceDiagnosticsSnapshot?
    @State private var exportStatusText: String?
    @State private var isExporting = false

    private let rounds: [PerformanceDiagnosticsRound] = [
        .core,
        .optionalFeatures,
        .idleAndStress,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.sixteen) {
            header

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.sixteen) {
                    statusGrid
                    roundPicker
                    actionRow
                    exportStatus
                    notesEditor
                    durationSummary
                    resourceSummary
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(SettingsDesignTokens.Space.twentyFour)
        .frame(width: 560, height: 520, alignment: .topLeading)
        .onAppear {
            refreshSnapshot(syncNotes: true)
        }
        .onChange(of: notes) { _, newValue in
            model.updatePerformanceDiagnosticsNotes(newValue)
            refreshSnapshot(syncNotes: false)
        }
    }

    private var currentSnapshot: PerformanceDiagnosticsSnapshot {
        snapshot ?? model.performanceDiagnosticsSnapshot()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.four) {
            Text("Performance Diagnostics")
                .font(.title3.weight(.semibold))

            Text("Hidden internal sampling session")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: SettingsDesignTokens.Space.twenty, verticalSpacing: SettingsDesignTokens.Space.eight) {
            metricRow("Status", currentSnapshot.isSampling ? "Sampling" : "Stopped")
            metricRow("Round", currentSnapshot.round.map(roundTitle) ?? "None")
            metricRow("Started", currentSnapshot.startedAt.map(formatDate) ?? "Not started")
            metricRow("Events", "\(currentSnapshot.totalEventCount)")
            metricRow("Dropped", "\(currentSnapshot.droppedRawEventCount)")
            metricRow("Errors", "\(currentSnapshot.errorCount)")
        }
        .font(.callout)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }

    private var roundPicker: some View {
        Picker("Round", selection: $selectedRound) {
            ForEach(rounds, id: \.self) { round in
                Text(roundTitle(round)).tag(round)
            }
        }
        .pickerStyle(.segmented)
    }

    private var actionRow: some View {
        HStack(spacing: SettingsDesignTokens.Space.eight) {
            Button("Start") {
                model.startPerformanceDiagnosticsSampling(round: selectedRound)
                model.updatePerformanceDiagnosticsNotes(notes)
                refreshSnapshot(syncNotes: true)
            }
            .disabled(currentSnapshot.isSampling)

            Button("Stop") {
                model.updatePerformanceDiagnosticsNotes(notes)
                model.stopPerformanceDiagnosticsSampling()
                refreshSnapshot(syncNotes: true)
            }
            .disabled(!currentSnapshot.isSampling)

            Button("Export") {
                exportReport()
            }
            .disabled(isExporting)

            Button("Clear", role: .destructive) {
                model.updatePerformanceDiagnosticsNotes("")
                model.clearPerformanceDiagnosticsSession()
                notes = ""
                refreshSnapshot(syncNotes: true)
            }
            .disabled(!hasSessionContent)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var exportStatus: some View {
        if let exportStatusText {
            Text(exportStatusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.six) {
            Text("Notes")
                .font(.callout.weight(.semibold))

            TextEditor(text: $notes)
                .font(.callout)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.row, style: .continuous))
        }
    }

    @ViewBuilder
    private var durationSummary: some View {
        if let summary = compactDurationSummary {
            summarySection(title: "Durations", value: summary)
        }
    }

    @ViewBuilder
    private var resourceSummary: some View {
        if let summary = compactResourceSummary {
            summarySection(title: "Resources", value: summary)
        }
    }

    private func summarySection(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.four) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var compactDurationSummary: String? {
        let samplesByKey = currentSnapshot.durationSamples
        let sampleCount = samplesByKey.values.reduce(0) { $0 + $1.count }
        guard sampleCount > 0 else {
            return nil
        }

        let slowest = samplesByKey
            .flatMap { key, samples in samples.map { (key, $0.durationNanoseconds) } }
            .max { lhs, rhs in lhs.1 < rhs.1 }

        guard let slowest else {
            return "\(sampleCount) duration samples"
        }

        return "\(sampleCount) samples; slowest \(slowest.0) \(formatDuration(slowest.1))"
    }

    private var compactResourceSummary: String? {
        guard let event = currentSnapshot.rawEvents.reversed().first(where: { $0.category == .resource }) else {
            return nil
        }

        let metadata = event.metadata
        let memory = metadata["residentMemoryBytes"].flatMap(UInt64.init).map(formatBytes) ?? "n/a"
        let threads = metadata["threadCount"] ?? "n/a"
        let cpu = metadata["cpuTimeSeconds"].flatMap(Double.init).map { Self.posixString(format: "%.2fs", $0) } ?? "n/a"

        return "latest \(event.name): memory \(memory), threads \(threads), CPU \(cpu)"
    }

    private var hasSessionContent: Bool {
        currentSnapshot.totalEventCount > 0
            || currentSnapshot.droppedRawEventCount > 0
            || currentSnapshot.errorCount > 0
            || !notes.isEmpty
            || currentSnapshot.startedAt != nil
    }

    private func refreshSnapshot(syncNotes: Bool) {
        let nextSnapshot = model.performanceDiagnosticsSnapshot()
        snapshot = nextSnapshot

        if syncNotes, notes != nextSnapshot.notes {
            notes = nextSnapshot.notes
        }

        if let round = nextSnapshot.round {
            selectedRound = round
        }
    }

    private func exportReport() {
        model.updatePerformanceDiagnosticsNotes(notes)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "appwink-performance-diagnostics.md"

        guard panel.runModal() == .OK, let markdownURL = panel.url else {
            exportStatusText = "Export canceled."
            refreshSnapshot(syncNotes: false)
            return
        }

        let exportSnapshot = model.performanceDiagnosticsSnapshot()
        isExporting = true
        exportStatusText = "Exporting..."

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                PerformanceDiagnosticsExportTaskResult.export(
                    snapshot: exportSnapshot,
                    markdownURL: markdownURL
                )
            }.value

            await MainActor.run {
                isExporting = false

                switch result {
                case .success:
                    model.recordPerformanceDiagnosticsReportExportSucceeded()
                    exportStatusText = "Exported \(markdownURL.lastPathComponent) and JSON sidecar."
                case .failure(let failure):
                    model.recordPerformanceDiagnosticsReportExportFailed(errorType: failure.errorType)
                    exportStatusText = "Export failed: \(failure.message)"
                }

                refreshSnapshot(syncNotes: false)
            }
        }
    }

    private func roundTitle(_ round: PerformanceDiagnosticsRound) -> String {
        switch round {
        case .core:
            return "Core"
        case .optionalFeatures:
            return "Optional Features"
        case .idleAndStress:
            return "Idle & Stress"
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        "\(bytes) bytes"
    }

    private func formatDuration(_ nanoseconds: UInt64) -> String {
        let milliseconds = Double(nanoseconds) / 1_000_000
        return Self.posixString(format: "%.2f ms", milliseconds)
    }

    private static func posixString(format: String, _ value: Double) -> String {
        String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private struct PerformanceDiagnosticsExportFailure: Sendable {
    let errorType: String
    let message: String
}

private enum PerformanceDiagnosticsExportTaskResult: Sendable {
    case success
    case failure(PerformanceDiagnosticsExportFailure)

    static func export(
        snapshot: PerformanceDiagnosticsSnapshot,
        markdownURL: URL
    ) -> PerformanceDiagnosticsExportTaskResult {
        do {
            let resourceSnapshot = SystemPerformanceDiagnosticsResourceSampler().sample()
            let export = try PerformanceDiagnosticsReportExporter().makeReport(
                snapshot: snapshot,
                resourceSnapshot: resourceSnapshot
            )
            try PerformanceDiagnosticsReportExporter().write(export, markdownURL: markdownURL)
            return .success
        } catch {
            return .failure(
                PerformanceDiagnosticsExportFailure(
                    errorType: String(describing: type(of: error)),
                    message: error.localizedDescription
                )
            )
        }
    }
}
