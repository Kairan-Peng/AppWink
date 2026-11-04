import AppWinkCore
import Foundation

enum BindingActionResult {
    case application(ApplicationToggleResult)
    case opened(refreshedItem: ManagedFileSystemItem?)
}

struct BindingActionFailure: Equatable, Sendable {
    let domain: String
    let code: Int
    let description: String

    init(_ error: any Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        description = nsError.localizedDescription
    }
}

enum BindingActionError: Error, LocalizedError, Sendable {
    case accessibilityPermissionRequired
    case targetUnavailable
    case selectedHandlerUnavailable
    case applicationFailed(BindingActionFailure)
    case openFailed(BindingActionFailure)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required."
        case .targetUnavailable:
            "The target is unavailable."
        case .selectedHandlerUnavailable:
            "The selected opening application is unavailable."
        case .applicationFailed(let failure), .openFailed(let failure):
            failure.description
        }
    }

    var diagnosticDomain: String {
        switch self {
        case .accessibilityPermissionRequired,
             .targetUnavailable,
             .selectedHandlerUnavailable:
            "AppWink.BindingAction"
        case .applicationFailed(let failure), .openFailed(let failure):
            failure.domain
        }
    }

    var diagnosticCode: Int {
        switch self {
        case .accessibilityPermissionRequired:
            2
        case .targetUnavailable:
            4
        case .selectedHandlerUnavailable:
            5
        case .applicationFailed(let failure), .openFailed(let failure):
            failure.code
        }
    }
}

struct BindingActionAuthorizationContext: Equatable, Sendable {
    let accessibilityGranted: Bool
}

@MainActor
struct PreparedBindingAction {
    let executionTiming: PreparedApplicationToggleExecutionTiming
    let isAccepted: Bool
    let execute: (
        @escaping @MainActor (
            Result<BindingActionResult, BindingActionError>
        ) -> Void
    ) -> Void
}

@MainActor
protocol BindingActionExecuting {
    func prepareAction(
        for binding: HotkeyBinding,
        authorization: BindingActionAuthorizationContext,
        frontmostProcessIdentifier: pid_t?,
        source: ToggleInvocationSource
    ) -> PreparedBindingAction
}

@MainActor
final class BindingActionExecutor: BindingActionExecuting {
    private let applicationToggleService: any ApplicationToggleServicing
    private let fileSystemOpenService: any FileSystemOpenServicing

    init(
        applicationToggleService: any ApplicationToggleServicing =
            ApplicationToggleService(),
        fileSystemOpenService: any FileSystemOpenServicing =
            FileSystemOpenService()
    ) {
        self.applicationToggleService = applicationToggleService
        self.fileSystemOpenService = fileSystemOpenService
    }

    func prepareAction(
        for binding: HotkeyBinding,
        authorization: BindingActionAuthorizationContext,
        frontmostProcessIdentifier: pid_t?,
        source: ToggleInvocationSource
    ) -> PreparedBindingAction {
        if binding.target.requiredPermissions.contains(.accessibility),
           !authorization.accessibilityGranted {
            return rejected(.accessibilityPermissionRequired)
        }
        switch binding.target {
        case .application(let application):
            guard application.resolvedURL() != nil else {
                return rejected(.targetUnavailable)
            }
            return prepareApplication(
                application,
                frontmostProcessIdentifier: frontmostProcessIdentifier,
                source: source
            )
        case .folder(let item, .finderNewTab):
            guard item.resolve() != nil else {
                return rejected(.targetUnavailable)
            }
            return prepareSystemDefaultOpen(item)
        case .folder(let item, .application(let application)),
             .file(let item, .application(let application)):
            guard item.resolve() != nil else {
                return rejected(.targetUnavailable)
            }
            guard application.resolvedURL() != nil else {
                return rejected(.selectedHandlerUnavailable)
            }
            return prepareSelectedApplicationOpen(item, application: application)
        case .file(let item, .systemDefault):
            guard item.resolve() != nil else {
                return rejected(.targetUnavailable)
            }
            return prepareSystemDefaultOpen(item)
        }
    }

    private func rejected(
        _ error: BindingActionError
    ) -> PreparedBindingAction {
        PreparedBindingAction(
            executionTiming: .immediate,
            isAccepted: false
        ) { completion in
            completion(.failure(error))
        }
    }

    private func prepareApplication(
        _ application: ManagedApplication,
        frontmostProcessIdentifier: pid_t?,
        source: ToggleInvocationSource
    ) -> PreparedBindingAction {
        let preparedToggle = applicationToggleService.prepareToggle(
            application: application,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            invocationSource: source
        )
        return PreparedBindingAction(
            executionTiming: preparedToggle.executionTiming,
            isAccepted: true
        ) { completion in
            preparedToggle.execute {
                switch $0 {
                case .success(let result):
                    completion(.success(.application(result)))
                case .failure(let error):
                    completion(
                        .failure(
                            .applicationFailed(BindingActionFailure(error))
                        )
                    )
                }
            }
        }
    }

    private func prepareSystemDefaultOpen(
        _ item: ManagedFileSystemItem
    ) -> PreparedBindingAction {
        let service = fileSystemOpenService
        return PreparedBindingAction(
            executionTiming: .immediate,
            isAccepted: true
        ) { completion in
            Task { @MainActor in
                do {
                    let result = try await service.openWithSystemDefault(item)
                    completion(
                        .success(
                            .opened(refreshedItem: result.refreshedItem)
                        )
                    )
                } catch {
                    completion(
                        .failure(self.fileSystemFailure(error))
                    )
                }
            }
        }
    }

    private func prepareSelectedApplicationOpen(
        _ item: ManagedFileSystemItem,
        application: ManagedApplication
    ) -> PreparedBindingAction {
        let service = fileSystemOpenService
        return PreparedBindingAction(
            executionTiming: .immediate,
            isAccepted: true
        ) { completion in
            Task { @MainActor in
                do {
                    let result = try await service.open(
                        item,
                        with: application
                    )
                    completion(
                        .success(
                            .opened(refreshedItem: result.refreshedItem)
                        )
                    )
                } catch {
                    completion(
                        .failure(self.fileSystemFailure(error))
                    )
                }
            }
        }
    }

    private func fileSystemFailure(
        _ error: any Error
    ) -> BindingActionError {
        switch error as? FileSystemOpenServiceError {
        case .targetUnavailable:
            .targetUnavailable
        case .openingApplicationUnavailable:
            .selectedHandlerUnavailable
        case .systemDefaultOpenFailed, nil:
            .openFailed(BindingActionFailure(error))
        }
    }
}
