import Foundation

final class PerformanceDiagnosticsRecorder: @unchecked Sendable {
    static let defaultRawEventLimit = 10_000
    static let shared = PerformanceDiagnosticsRecorder()

    private static let unsafeMetadataKeyFragments: Set<String> = [
        "applicationpath",
        "bundlepath",
        "clipboard",
        "documentname",
        "documenttitle",
        "fullpath",
        "homedirectory",
        "hostname",
        "inputtext",
        "license",
        "licensekey",
        "path",
        "typedtext",
        "userinput",
        "username",
        "windowname",
        "windowtitle",
    ]

    private let clock: any PerformanceDiagnosticsClock
    private let rawEventLimit: Int
    private let lock = NSLock()

    private var isSampling = false
    private var sessionGeneration: UInt64 = 0
    private var round: PerformanceDiagnosticsRound?
    private var startedAt: Date?
    private var stoppedAt: Date?
    private var notes = ""
    private var rawEvents: [PerformanceDiagnosticsEvent] = []
    private var counters: [String: Int] = [:]
    private var durationSamples: [String: [PerformanceDiagnosticsDurationSample]] = [:]
    private var droppedRawEventCount = 0
    private var totalEventCount = 0
    private var errorCount = 0

    init(
        clock: any PerformanceDiagnosticsClock = SystemPerformanceDiagnosticsClock(),
        rawEventLimit: Int = PerformanceDiagnosticsRecorder.defaultRawEventLimit
    ) {
        self.clock = clock
        self.rawEventLimit = max(0, rawEventLimit)
    }

    func startSampling(round: PerformanceDiagnosticsRound) {
        lock.lock()
        defer { lock.unlock() }

        sessionGeneration &+= 1
        resetSessionState()
        self.round = round
        startedAt = clock.nowDate
        stoppedAt = nil
        isSampling = true
    }

    func stopSampling() {
        lock.lock()
        defer { lock.unlock() }

        isSampling = false
        stoppedAt = clock.nowDate
    }

    func clearSession() {
        lock.lock()
        defer { lock.unlock() }

        sessionGeneration &+= 1
        resetSessionState()
    }

    func updateNotes(_ notes: String) {
        lock.lock()
        defer { lock.unlock() }

        self.notes = notes
    }

    func incrementErrorCount() {
        lock.lock()
        defer { lock.unlock() }

        guard isSampling else {
            return
        }

        errorCount += 1
    }

    func recordEvent(
        category: PerformanceDiagnosticsCategory,
        name: String,
        metadata: [String: String] = [:]
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard isSampling else {
            return
        }

        let timestampNanoseconds = clock.nowNanoseconds
        let sanitizedMetadata = sanitizeMetadata(metadata)

        recordEventLocked(
            category: category,
            name: name,
            timestampNanoseconds: timestampNanoseconds,
            metadata: sanitizedMetadata
        )
    }

    /// Records low-frequency diagnostics UI lifecycle events before sampling starts.
    /// Runtime instrumentation should use `recordEvent` to preserve the inactive fast path.
    func recordSessionEvent(
        category: PerformanceDiagnosticsCategory,
        name: String,
        metadata: [String: String] = [:]
    ) {
        lock.lock()
        defer { lock.unlock() }

        let timestampNanoseconds = clock.nowNanoseconds
        let sanitizedMetadata = sanitizeMetadata(metadata)

        recordEventLocked(
            category: category,
            name: name,
            timestampNanoseconds: timestampNanoseconds,
            metadata: sanitizedMetadata
        )
    }

    func measure<T>(
        category: PerformanceDiagnosticsCategory,
        name: String,
        metadata: [String: String] = [:],
        _ work: () throws -> T
    ) rethrows -> T {
        guard let activeGeneration = activeSessionGeneration() else {
            return try work()
        }

        let startNanoseconds = clock.nowNanoseconds
        let sanitizedMetadata = sanitizeMetadata(metadata)

        do {
            let result = try work()
            recordMeasurementIfSampling(
                category: category,
                name: name,
                startNanoseconds: startNanoseconds,
                endNanoseconds: clock.nowNanoseconds,
                metadata: sanitizedMetadata,
                didThrow: false,
                sessionGeneration: activeGeneration
            )
            return result
        } catch {
            recordMeasurementIfSampling(
                category: category,
                name: name,
                startNanoseconds: startNanoseconds,
                endNanoseconds: clock.nowNanoseconds,
                metadata: sanitizedMetadata,
                didThrow: true,
                sessionGeneration: activeGeneration
            )
            throw error
        }
    }

    func beginInterval(
        category: PerformanceDiagnosticsCategory,
        name: String,
        metadata: [String: String] = [:]
    ) -> PerformanceDiagnosticsIntervalToken? {
        guard let activeGeneration = activeSessionGeneration() else {
            return nil
        }

        let startNanoseconds = clock.nowNanoseconds
        let sanitizedMetadata = sanitizeMetadata(metadata)

        lock.lock()
        defer { lock.unlock() }

        guard isSampling, sessionGeneration == activeGeneration else {
            return nil
        }

        return PerformanceDiagnosticsIntervalToken(
            category: category,
            name: name,
            startNanoseconds: startNanoseconds,
            metadata: sanitizedMetadata,
            sessionGeneration: activeGeneration
        )
    }

    @discardableResult
    func endInterval(
        _ token: PerformanceDiagnosticsIntervalToken?,
        metadata: [String: String] = [:]
    ) -> Bool {
        guard let token else {
            return false
        }

        guard isSessionActive(generation: token.sessionGeneration) else {
            return false
        }

        let endNanoseconds = clock.nowNanoseconds
        let sanitizedMetadata = sanitizeMetadata(metadata)

        lock.lock()
        defer { lock.unlock() }

        guard isSampling, sessionGeneration == token.sessionGeneration else {
            return false
        }

        let mergedMetadata = token.metadata.merging(sanitizedMetadata) { _, new in new }
        recordDurationSampleLocked(
            category: token.category,
            name: token.name,
            startNanoseconds: token.startNanoseconds,
            endNanoseconds: endNanoseconds,
            metadata: mergedMetadata
        )
        return true
    }

    func snapshot() -> PerformanceDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return PerformanceDiagnosticsSnapshot(
            isSampling: isSampling,
            round: round,
            startedAt: startedAt,
            stoppedAt: stoppedAt,
            notes: notes,
            rawEvents: rawEvents,
            counters: counters,
            durationSamples: durationSamples,
            droppedRawEventCount: droppedRawEventCount,
            totalEventCount: totalEventCount,
            errorCount: errorCount
        )
    }

    private func resetSessionState() {
        isSampling = false
        round = nil
        startedAt = nil
        stoppedAt = nil
        notes = ""
        rawEvents = []
        counters = [:]
        durationSamples = [:]
        droppedRawEventCount = 0
        totalEventCount = 0
        errorCount = 0
    }

    private func recordMeasurementIfSampling(
        category: PerformanceDiagnosticsCategory,
        name: String,
        startNanoseconds: UInt64,
        endNanoseconds: UInt64,
        metadata: [String: String],
        didThrow: Bool,
        sessionGeneration measurementGeneration: UInt64
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard isSampling, sessionGeneration == measurementGeneration else {
            return
        }

        if didThrow {
            errorCount += 1
        }

        recordEventLocked(
            category: category,
            name: name,
            timestampNanoseconds: startNanoseconds,
            metadata: metadata
        )
        recordDurationSampleLocked(
            category: category,
            name: name,
            startNanoseconds: startNanoseconds,
            endNanoseconds: endNanoseconds,
            metadata: metadata
        )
    }

    private func recordEventLocked(
        category: PerformanceDiagnosticsCategory,
        name: String,
        timestampNanoseconds: UInt64,
        metadata: [String: String]
    ) {
        totalEventCount += 1
        counters[counterKey(category: category, name: name), default: 0] += 1

        guard rawEvents.count < rawEventLimit else {
            droppedRawEventCount += 1
            return
        }

        rawEvents.append(
            PerformanceDiagnosticsEvent(
                category: category,
                name: name,
                timestampNanoseconds: timestampNanoseconds,
                metadata: metadata
            )
        )
    }

    private func recordDurationSampleLocked(
        category: PerformanceDiagnosticsCategory,
        name: String,
        startNanoseconds: UInt64,
        endNanoseconds: UInt64,
        metadata: [String: String]
    ) {
        let key = counterKey(category: category, name: name)
        let durationNanoseconds = endNanoseconds >= startNanoseconds ? endNanoseconds - startNanoseconds : 0

        durationSamples[key, default: []].append(
            PerformanceDiagnosticsDurationSample(
                category: category,
                name: name,
                startNanoseconds: startNanoseconds,
                endNanoseconds: endNanoseconds,
                durationNanoseconds: durationNanoseconds,
                metadata: metadata
            )
        )
    }

    private func counterKey(category: PerformanceDiagnosticsCategory, name: String) -> String {
        "\(category.rawValue).\(name)"
    }

    private func sanitizeMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.filter { key, _ in
            !Self.isUnsafeMetadataKey(key)
        }
    }

    private func activeSessionGeneration() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }

        guard isSampling else {
            return nil
        }

        return sessionGeneration
    }

    private func isSessionActive(generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return isSampling && sessionGeneration == generation
    }

    private static func isUnsafeMetadataKey(_ key: String) -> Bool {
        let normalizedKey = key.lowercased().filter { character in
            character.isLetter || character.isNumber
        }

        return unsafeMetadataKeyFragments.contains { fragment in
            normalizedKey.contains(fragment)
        }
    }
}
