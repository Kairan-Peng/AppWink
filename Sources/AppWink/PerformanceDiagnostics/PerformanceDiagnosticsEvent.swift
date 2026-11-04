import Foundation

enum PerformanceDiagnosticsCategory: String, Codable, Sendable {
    case configuration
    case eventListener
    case hotkey
    case overlay
    case registration
    case report
    case resource
    case systemQuery
    case uiTransition
}

enum PerformanceDiagnosticsRound: String, Codable, Sendable {
    case core
    case idleAndStress
    case optionalFeatures
}

struct PerformanceDiagnosticsDurationSample: Codable, Equatable, Sendable {
    let category: PerformanceDiagnosticsCategory
    let name: String
    let startNanoseconds: UInt64
    let endNanoseconds: UInt64
    let durationNanoseconds: UInt64
    let metadata: [String: String]
}

struct PerformanceDiagnosticsEvent: Codable, Equatable, Sendable {
    let category: PerformanceDiagnosticsCategory
    let name: String
    let timestampNanoseconds: UInt64
    let metadata: [String: String]
}

struct PerformanceDiagnosticsIntervalToken: Codable, Equatable, Sendable {
    let category: PerformanceDiagnosticsCategory
    let name: String
    let startNanoseconds: UInt64
    let metadata: [String: String]
    let sessionGeneration: UInt64
}

struct PerformanceDiagnosticsSnapshot: Codable, Equatable, Sendable {
    let isSampling: Bool
    let round: PerformanceDiagnosticsRound?
    let startedAt: Date?
    let stoppedAt: Date?
    let notes: String
    let rawEvents: [PerformanceDiagnosticsEvent]
    let counters: [String: Int]
    let durationSamples: [String: [PerformanceDiagnosticsDurationSample]]
    let droppedRawEventCount: Int
    let totalEventCount: Int
    let errorCount: Int
}
