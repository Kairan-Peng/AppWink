import AppKit
import AppWinkCore

@MainActor
enum PreparedApplicationToggleExecutionTiming {
    case immediate
    case nextRunLoop
}

@MainActor
struct PreparedApplicationToggle {
    let executionTiming: PreparedApplicationToggleExecutionTiming
    let execute: (@escaping @MainActor (Result<ApplicationToggleResult, ApplicationToggleError>) -> Void) -> Void
}

@MainActor
protocol ApplicationToggleServicing {
    func prepareToggle(
        application: ManagedApplication,
        frontmostProcessIdentifier: pid_t?,
        invocationSource: ToggleInvocationSource
    ) -> PreparedApplicationToggle

    func toggle(
        application: ManagedApplication,
        frontmostProcessIdentifier: pid_t?,
        invocationSource: ToggleInvocationSource,
        completion: @escaping @MainActor (Result<ApplicationToggleResult, ApplicationToggleError>) -> Void
    )
}

extension ApplicationToggleServicing {
    func toggle(
        application: ManagedApplication,
        frontmostProcessIdentifier: pid_t?,
        invocationSource: ToggleInvocationSource = .manual,
        completion: @escaping @MainActor (Result<ApplicationToggleResult, ApplicationToggleError>) -> Void
    ) {
        let preparedToggle = prepareToggle(
            application: application,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            invocationSource: invocationSource
        )
        preparedToggle.execute(completion)
    }
}
