import AppKit
import AppWinkCore
import Foundation

struct ResolvedFileSystemActionResult: Sendable {
    let refreshedItem: ManagedFileSystemItem?
}

enum FileSystemOpenServiceError: Error, Equatable, LocalizedError, Sendable {
    case targetUnavailable(String)
    case openingApplicationUnavailable(String)
    case systemDefaultOpenFailed

    var errorDescription: String? {
        switch self {
        case .targetUnavailable(let displayName):
            return "Target unavailable: \(displayName)"
        case .openingApplicationUnavailable(let displayName):
            return "Opening application unavailable: \(displayName)"
        case .systemDefaultOpenFailed:
            return "The system default application could not open the target."
        }
    }
}

protocol WorkspaceOpening: Sendable {
    func openDefault(_ targetURL: URL) async throws

    func open(
        _ targetURL: URL,
        withApplicationAt applicationURL: URL
    ) async throws
}

protocol FileSystemOpenServicing: Sendable {
    func openWithSystemDefault(
        _ item: ManagedFileSystemItem
    ) async throws -> ResolvedFileSystemActionResult

    func open(
        _ item: ManagedFileSystemItem,
        with application: ManagedApplication
    ) async throws -> ResolvedFileSystemActionResult
}

struct NSWorkspaceOpening: WorkspaceOpening {
    typealias OpenDefault = @Sendable (URL) -> Bool
    typealias OpenSelected = @Sendable (
        [URL],
        URL,
        NSWorkspace.OpenConfiguration,
        @escaping @Sendable (NSRunningApplication?, Error?) -> Void
    ) -> Void

    private let openDefaultURL: OpenDefault
    private let openSelectedURLs: OpenSelected

    init(
        openDefault: @escaping OpenDefault = { NSWorkspace.shared.open($0) },
        openSelected: @escaping OpenSelected = {
            targetURLs,
            applicationURL,
            configuration,
            completion in
            NSWorkspace.shared.open(
                targetURLs,
                withApplicationAt: applicationURL,
                configuration: configuration,
                completionHandler: completion
            )
        }
    ) {
        openDefaultURL = openDefault
        openSelectedURLs = openSelected
    }

    func openDefault(_ targetURL: URL) async throws {
        guard openDefaultURL(targetURL) else {
            throw FileSystemOpenServiceError.systemDefaultOpenFailed
        }
    }

    func open(
        _ targetURL: URL,
        withApplicationAt applicationURL: URL
    ) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            openSelectedURLs(
                [targetURL],
                applicationURL,
                configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

struct FileSystemOpenService: FileSystemOpenServicing {
    typealias StartAccessingSecurityScopedResource = @Sendable (URL) -> Bool
    typealias StopAccessingSecurityScopedResource = @Sendable (URL) -> Void
    typealias FileExistsAtPath = @Sendable (String) -> Bool

    private let workspace: any WorkspaceOpening
    private let startAccessingSecurityScopedResource: StartAccessingSecurityScopedResource
    private let stopAccessingSecurityScopedResource: StopAccessingSecurityScopedResource
    private let fileExistsAtPath: FileExistsAtPath

    init(
        workspace: any WorkspaceOpening = NSWorkspaceOpening(),
        startAccessingSecurityScopedResource: @escaping StartAccessingSecurityScopedResource = {
            $0.startAccessingSecurityScopedResource()
        },
        stopAccessingSecurityScopedResource: @escaping StopAccessingSecurityScopedResource = {
            $0.stopAccessingSecurityScopedResource()
        },
        fileExistsAtPath: @escaping FileExistsAtPath = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) {
        self.workspace = workspace
        self.startAccessingSecurityScopedResource = startAccessingSecurityScopedResource
        self.stopAccessingSecurityScopedResource = stopAccessingSecurityScopedResource
        self.fileExistsAtPath = fileExistsAtPath
    }

    func openWithSystemDefault(
        _ item: ManagedFileSystemItem
    ) async throws -> ResolvedFileSystemActionResult {
        guard let resolution = item.resolve() else {
            throw FileSystemOpenServiceError.targetUnavailable(item.displayName)
        }

        return try await performOpen(item: item, resolution: resolution) {
            try await workspace.openDefault($0)
        }
    }

    func open(
        _ item: ManagedFileSystemItem,
        with application: ManagedApplication
    ) async throws -> ResolvedFileSystemActionResult {
        guard let resolution = item.resolve() else {
            throw FileSystemOpenServiceError.targetUnavailable(item.displayName)
        }
        guard let applicationURL = application.resolvedURL() else {
            throw FileSystemOpenServiceError.openingApplicationUnavailable(
                application.displayName
            )
        }

        return try await performOpen(item: item, resolution: resolution) {
            try await workspace.open($0, withApplicationAt: applicationURL)
        }
    }

    private func performOpen(
        item: ManagedFileSystemItem,
        resolution: ManagedFileSystemItem.Resolution,
        operation: @Sendable (URL) async throws -> Void
    ) async throws -> ResolvedFileSystemActionResult {
        let targetURL = resolution.url
        let didStartAccess = startAccessingSecurityScopedResource(targetURL)
        defer {
            if didStartAccess {
                stopAccessingSecurityScopedResource(targetURL)
            }
        }
        guard fileExistsAtPath(targetURL.path) else {
            throw FileSystemOpenServiceError.targetUnavailable(
                item.displayName
            )
        }

        let refreshedItem = try item.refreshingBookmarkIfNeeded(for: resolution)
        try await operation(targetURL)
        return ResolvedFileSystemActionResult(refreshedItem: refreshedItem)
    }
}
