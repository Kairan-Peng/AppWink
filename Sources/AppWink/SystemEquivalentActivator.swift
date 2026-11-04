import AppKit
import Foundation

enum SystemEquivalentActivationResult: Equatable {
    case activated
    case failed
}

struct SystemEquivalentActivationDiagnostics: Equatable {
    let applicationURL: URL
    let didSucceed: Bool
    let runningApplicationBundleIdentifier: String?
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
}

final class SystemEquivalentActivator {
    typealias OpenApplication = (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) -> Void
    typealias ScheduleAfter = @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void
    typealias DiagnosticsRecorder = @Sendable (SystemEquivalentActivationDiagnostics) -> Void

    private let openApplication: OpenApplication
    private let scheduleAfter: ScheduleAfter
    private let diagnosticsRecorder: DiagnosticsRecorder
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder
    private let settleDelay: TimeInterval

    init(
        openApplication: @escaping OpenApplication = defaultSystemEquivalentOpenApplication,
        scheduleAfter: @escaping ScheduleAfter = defaultSystemEquivalentScheduleAfter,
        diagnosticsRecorder: @escaping DiagnosticsRecorder = { _ in },
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared,
        settleDelay: TimeInterval = 0.15
    ) {
        self.openApplication = openApplication
        self.scheduleAfter = scheduleAfter
        self.diagnosticsRecorder = diagnosticsRecorder
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
        self.settleDelay = settleDelay
    }

    func activate(
        applicationURL: URL,
        completion: @escaping @Sendable (SystemEquivalentActivationResult) -> Void
    ) {
        let performanceIntervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .hotkey,
            name: systemEquivalentActivatePerformanceDiagnosticsName
        )
        let deliveryGate = DeliveryGate()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        openApplication(applicationURL, configuration) { [
            scheduleAfter,
            diagnosticsRecorder,
            performanceDiagnosticsRecorder,
            performanceIntervalToken,
            settleDelay,
            applicationURL,
            completion,
            deliveryGate,
        ] runningApplication, error in
            guard deliveryGate.beginDelivery() else {
                return
            }

            let nsError = error as NSError?
            let result: SystemEquivalentActivationResult = error == nil ? .activated : .failed
            let diagnostics = SystemEquivalentActivationDiagnostics(
                applicationURL: applicationURL,
                didSucceed: error == nil,
                runningApplicationBundleIdentifier: runningApplication?.bundleIdentifier,
                errorDomain: nsError?.domain,
                errorCode: nsError?.code,
                errorDescription: error?.localizedDescription
            )
            let performanceMetadata = systemEquivalentActivatePerformanceDiagnosticsMetadata(
                result: result,
                runningApplicationBundleIdentifier: runningApplication?.bundleIdentifier,
                error: nsError
            )

            scheduleAfter(settleDelay) {
                deliveryGate.deliver(
                    diagnostics: diagnostics,
                    diagnosticsRecorder: diagnosticsRecorder,
                    performanceDiagnosticsRecorder: performanceDiagnosticsRecorder,
                    performanceIntervalToken: performanceIntervalToken,
                    performanceMetadata: performanceMetadata,
                    completion: completion,
                    result: result
                )
            }
        }
    }
}

private final class DeliveryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasStartedDelivery = false
    private var hasDelivered = false

    func beginDelivery() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !hasStartedDelivery else {
            return false
        }

        hasStartedDelivery = true
        return true
    }

    func deliver(
        diagnostics: SystemEquivalentActivationDiagnostics,
        diagnosticsRecorder: @escaping @Sendable (SystemEquivalentActivationDiagnostics) -> Void,
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder,
        performanceIntervalToken: PerformanceDiagnosticsIntervalToken?,
        performanceMetadata: [String: String],
        completion: @escaping @Sendable (SystemEquivalentActivationResult) -> Void,
        result: SystemEquivalentActivationResult
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard !hasDelivered else {
            return
        }

        hasDelivered = true
        diagnosticsRecorder(diagnostics)
        if performanceDiagnosticsRecorder.endInterval(performanceIntervalToken, metadata: performanceMetadata) {
            performanceDiagnosticsRecorder.recordEvent(
                category: .hotkey,
                name: systemEquivalentActivatePerformanceDiagnosticsName,
                metadata: performanceMetadata
            )
        }
        completion(result)
    }
}

private let systemEquivalentActivatePerformanceDiagnosticsName = "systemEquivalentActivate"

private func systemEquivalentActivatePerformanceDiagnosticsMetadata(
    result: SystemEquivalentActivationResult,
    runningApplicationBundleIdentifier: String?,
    error: NSError?
) -> [String: String] {
    var metadata = [
        "result": result.performanceDiagnosticsValue,
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

private extension SystemEquivalentActivationResult {
    var performanceDiagnosticsValue: String {
        switch self {
        case .activated:
            return "activated"
        case .failed:
            return "failed"
        }
    }
}

private func defaultSystemEquivalentOpenApplication(
    _ applicationURL: URL,
    _ configuration: NSWorkspace.OpenConfiguration,
    _ completion: @escaping @Sendable (NSRunningApplication?, Error?) -> Void
) {
    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration, completionHandler: completion)
}

private func defaultSystemEquivalentScheduleAfter(_ interval: TimeInterval, _ action: @escaping @Sendable () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
        action()
    }
}
