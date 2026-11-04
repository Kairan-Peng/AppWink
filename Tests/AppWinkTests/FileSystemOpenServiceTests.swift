import AppKit
import AppWinkCore
import Foundation
import os
import XCTest

@testable import AppWinkRuntime

final class FileSystemOpenServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        defer {
            temporaryDirectory = nil
        }
        if let temporaryDirectory,
           FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testSystemDefaultOpensOnEveryInvocation() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let item = makeItem(for: targetURL)
        let workspace = WorkspaceSpy()
        let scope = SecurityScopeRecorder(startReturns: false)
        let service = makeService(workspace: workspace, scope: scope)

        _ = try await service.openWithSystemDefault(item)
        _ = try await service.openWithSystemDefault(item)

        let snapshot = await workspace.snapshot()
        XCTAssertEqual(snapshot.defaultOpenURLs, [targetURL, targetURL])
        XCTAssertTrue(snapshot.selectedOpenCalls.isEmpty)
    }

    func testFolderUsesSystemDefaultWorkspaceOpenRequest() async throws {
        let folderURL = try makeDirectory(named: "Project")
        let workspace = WorkspaceSpy()
        let scope = SecurityScopeRecorder(startReturns: false)
        let service = makeService(workspace: workspace, scope: scope)

        _ = try await service.openWithSystemDefault(makeItem(for: folderURL))

        let snapshot = await workspace.snapshot()
        XCTAssertEqual(snapshot.defaultOpenURLs, [folderURL])
        XCTAssertTrue(snapshot.selectedOpenCalls.isEmpty)
    }

    func testSelectedApplicationOpensOnEveryInvocation() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let applicationURL = try makeApplicationDirectory(named: "Preview.app")
        let item = makeItem(for: targetURL)
        let application = makeApplication(for: applicationURL)
        let workspace = WorkspaceSpy()
        let scope = SecurityScopeRecorder(startReturns: false)
        let service = makeService(workspace: workspace, scope: scope)

        _ = try await service.open(item, with: application)
        _ = try await service.open(item, with: application)

        let snapshot = await workspace.snapshot()
        XCTAssertEqual(
            snapshot.selectedOpenCalls,
            [
                SelectedOpenCall(targetURL: targetURL, applicationURL: applicationURL),
                SelectedOpenCall(targetURL: targetURL, applicationURL: applicationURL),
            ]
        )
        XCTAssertTrue(snapshot.defaultOpenURLs.isEmpty)
    }

    func testSelectedApplicationFailureDoesNotFallbackToSystemDefault() async {
        do {
            let targetURL = try makeFile(named: "Document.txt")
            let applicationURL = try makeApplicationDirectory(named: "Preview.app")
            let workspace = WorkspaceSpy(selectedError: .rejected)
            let scope = SecurityScopeRecorder(startReturns: false)
            let service = makeService(workspace: workspace, scope: scope)

            do {
                _ = try await service.open(
                    makeItem(for: targetURL),
                    with: makeApplication(for: applicationURL)
                )
                XCTFail("Expected selected application failure")
            } catch {
                XCTAssertEqual(error as? TestOpenError, .rejected)
            }

            let snapshot = await workspace.snapshot()
            XCTAssertEqual(snapshot.selectedOpenCalls.count, 1)
            XCTAssertTrue(snapshot.defaultOpenURLs.isEmpty)
        } catch {
            XCTFail("Unexpected fixture failure: \(error)")
        }
    }

    func testUnresolvedTargetReturnsErrorWithoutCallingWorkspaceOrStartingScope() async {
        let workspace = WorkspaceSpy()
        let scope = SecurityScopeRecorder(startReturns: true)
        let service = makeService(workspace: workspace, scope: scope)
        let item = ManagedFileSystemItem(
            displayName: "Missing",
            fallbackPath: temporaryDirectory.appendingPathComponent("Missing.txt").path,
            bookmarkData: Data("invalid bookmark".utf8)
        )

        do {
            _ = try await service.openWithSystemDefault(item)
            XCTFail("Expected unavailable target")
        } catch {
            XCTAssertEqual(
                error as? FileSystemOpenServiceError,
                .targetUnavailable("Missing")
            )
        }

        let workspaceSnapshot = await workspace.snapshot()
        XCTAssertTrue(workspaceSnapshot.defaultOpenURLs.isEmpty)
        XCTAssertTrue(workspaceSnapshot.selectedOpenCalls.isEmpty)
        XCTAssertEqual(scope.snapshot().startCallCount, 0)
    }

    func testUnresolvedApplicationReturnsErrorBeforeStartingScope() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let workspace = WorkspaceSpy()
        let scope = SecurityScopeRecorder(startReturns: true)
        let service = makeService(workspace: workspace, scope: scope)
        let application = ManagedApplication(
            displayName: "Missing Handler",
            bundleIdentifier: "com.example.missing",
            fallbackPath: temporaryDirectory.appendingPathComponent("Missing.app").path,
            bookmarkData: Data("invalid bookmark".utf8)
        )

        do {
            _ = try await service.open(makeItem(for: targetURL), with: application)
            XCTFail("Expected unavailable opening application")
        } catch {
            XCTAssertEqual(
                error as? FileSystemOpenServiceError,
                .openingApplicationUnavailable("Missing Handler")
            )
        }

        let workspaceSnapshot = await workspace.snapshot()
        XCTAssertTrue(workspaceSnapshot.defaultOpenURLs.isEmpty)
        XCTAssertTrue(workspaceSnapshot.selectedOpenCalls.isEmpty)
        XCTAssertEqual(scope.snapshot().startCallCount, 0)
    }

    func testSuccessfulScopeStartIsBalancedOnceAfterSuccessfulOpen() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let scope = SecurityScopeRecorder(startReturns: true)
        let workspace = WorkspaceSpy(scopeIsActive: scope.isActive)
        let service = makeService(workspace: workspace, scope: scope)

        _ = try await service.openWithSystemDefault(makeItem(for: targetURL))

        let scopeSnapshot = scope.snapshot()
        let workspaceSnapshot = await workspace.snapshot()
        XCTAssertEqual(scopeSnapshot.startURLs, [targetURL])
        XCTAssertEqual(scopeSnapshot.stopURLs, [targetURL])
        XCTAssertFalse(scopeSnapshot.isActive)
        XCTAssertEqual(workspaceSnapshot.scopeActivityAtOpen, [true])
    }

    func testSuccessfulScopeStartIsBalancedOnceAfterFailedOpen() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let applicationURL = try makeApplicationDirectory(named: "Preview.app")
        let scope = SecurityScopeRecorder(startReturns: true)
        let workspace = WorkspaceSpy(
            selectedError: .rejected,
            scopeIsActive: scope.isActive
        )
        let service = makeService(workspace: workspace, scope: scope)

        do {
            _ = try await service.open(
                makeItem(for: targetURL),
                with: makeApplication(for: applicationURL)
            )
            XCTFail("Expected selected application failure")
        } catch {
            XCTAssertEqual(error as? TestOpenError, .rejected)
        }

        let scopeSnapshot = scope.snapshot()
        let workspaceSnapshot = await workspace.snapshot()
        XCTAssertEqual(scopeSnapshot.startURLs, [targetURL])
        XCTAssertEqual(scopeSnapshot.stopURLs, [targetURL])
        XCTAssertFalse(scopeSnapshot.isActive)
        XCTAssertEqual(workspaceSnapshot.scopeActivityAtOpen, [true])
    }

    func testScopeRemainsActiveWhileWorkspaceOpenIsSuspended() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let scope = SecurityScopeRecorder(startReturns: true)
        let workspace = SuspendingWorkspace()
        let service = makeService(workspace: workspace, scope: scope)
        let item = makeItem(for: targetURL)
        let operation = Task {
            try await service.openWithSystemDefault(item)
        }

        await workspace.waitUntilEntered()

        let suspendedSnapshot = scope.snapshot()
        XCTAssertEqual(suspendedSnapshot.startURLs, [targetURL])
        XCTAssertTrue(suspendedSnapshot.stopURLs.isEmpty)
        XCTAssertTrue(suspendedSnapshot.isActive)

        await workspace.complete(with: .success(()))
        _ = try await operation.value

        let completedSnapshot = scope.snapshot()
        XCTAssertEqual(completedSnapshot.stopURLs, [targetURL])
        XCTAssertFalse(completedSnapshot.isActive)
    }

    func testScopeRemainsActiveUntilSuspendedWorkspaceFailureCompletes() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let scope = SecurityScopeRecorder(startReturns: true)
        let workspace = SuspendingWorkspace()
        let service = makeService(workspace: workspace, scope: scope)
        let item = makeItem(for: targetURL)
        let operation = Task {
            try await service.openWithSystemDefault(item)
        }

        await workspace.waitUntilEntered()

        let suspendedSnapshot = scope.snapshot()
        XCTAssertEqual(suspendedSnapshot.startURLs, [targetURL])
        XCTAssertTrue(suspendedSnapshot.stopURLs.isEmpty)
        XCTAssertTrue(suspendedSnapshot.isActive)

        await workspace.complete(with: .failure(.rejected))
        do {
            _ = try await operation.value
            XCTFail("Expected suspended workspace failure")
        } catch {
            XCTAssertEqual(error as? TestOpenError, .rejected)
        }

        let completedSnapshot = scope.snapshot()
        XCTAssertEqual(completedSnapshot.stopURLs, [targetURL])
        XCTAssertFalse(completedSnapshot.isActive)
    }

    func testFailedScopeStartDoesNotStopAndStillOpens() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let scope = SecurityScopeRecorder(startReturns: false)
        let workspace = WorkspaceSpy(scopeIsActive: scope.isActive)
        let service = makeService(workspace: workspace, scope: scope)

        _ = try await service.openWithSystemDefault(makeItem(for: targetURL))

        let scopeSnapshot = scope.snapshot()
        let workspaceSnapshot = await workspace.snapshot()
        XCTAssertEqual(scopeSnapshot.startURLs, [targetURL])
        XCTAssertTrue(scopeSnapshot.stopURLs.isEmpty)
        XCTAssertFalse(scopeSnapshot.isActive)
        XCTAssertEqual(workspaceSnapshot.defaultOpenURLs, [targetURL])
        XCTAssertEqual(workspaceSnapshot.scopeActivityAtOpen, [false])
    }

    func testPostResolutionMissingTargetBalancesSuccessfulScopeBeforeReturningUnavailable() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let item = makeItem(for: targetURL)
        let scope = SecurityScopeRecorder(startReturns: true)
        let workspace = WorkspaceSpy()
        let service = FileSystemOpenService(
            workspace: workspace,
            startAccessingSecurityScopedResource: scope.start,
            stopAccessingSecurityScopedResource: scope.stop,
            fileExistsAtPath: { _ in false }
        )

        do {
            _ = try await service.openWithSystemDefault(item)
            XCTFail("Expected unavailable target")
        } catch {
            XCTAssertEqual(
                error as? FileSystemOpenServiceError,
                .targetUnavailable(item.displayName)
            )
        }

        let scopeSnapshot = scope.snapshot()
        let workspaceSnapshot = await workspace.snapshot()
        XCTAssertEqual(scopeSnapshot.startURLs, [targetURL])
        XCTAssertEqual(scopeSnapshot.stopURLs, [targetURL])
        XCTAssertFalse(scopeSnapshot.isActive)
        XCTAssertTrue(workspaceSnapshot.defaultOpenURLs.isEmpty)
    }

    func testPostResolutionMissingTargetDoesNotStopWhenScopeStartFails() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let item = makeItem(for: targetURL)
        let scope = SecurityScopeRecorder(startReturns: false)
        let workspace = WorkspaceSpy()
        let service = FileSystemOpenService(
            workspace: workspace,
            startAccessingSecurityScopedResource: scope.start,
            stopAccessingSecurityScopedResource: scope.stop,
            fileExistsAtPath: { _ in false }
        )

        do {
            _ = try await service.openWithSystemDefault(item)
            XCTFail("Expected unavailable target")
        } catch {
            XCTAssertEqual(
                error as? FileSystemOpenServiceError,
                .targetUnavailable(item.displayName)
            )
        }

        let scopeSnapshot = scope.snapshot()
        let workspaceSnapshot = await workspace.snapshot()
        XCTAssertEqual(scopeSnapshot.startURLs, [targetURL])
        XCTAssertTrue(scopeSnapshot.stopURLs.isEmpty)
        XCTAssertFalse(scopeSnapshot.isActive)
        XCTAssertTrue(workspaceSnapshot.defaultOpenURLs.isEmpty)
    }

    func testStaleBookmarkRefreshIsReturnedWithoutExtendingScopeLifetime() async throws {
        let originalURL = try makeFile(named: "Before.txt")
        let item = try ManagedFileSystemItem(url: originalURL)
        let renamedURL = temporaryDirectory.appendingPathComponent("After.txt")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        XCTAssertTrue(try XCTUnwrap(item.resolve()).bookmarkIsStale)
        let scope = SecurityScopeRecorder(startReturns: true)
        let workspace = WorkspaceSpy(scopeIsActive: scope.isActive)
        let service = makeService(workspace: workspace, scope: scope)

        let result = try await service.openWithSystemDefault(item)

        let refreshedItem = try XCTUnwrap(result.refreshedItem)
        let workspaceSnapshot = await workspace.snapshot()
        XCTAssertEqual(
            URL(fileURLWithPath: refreshedItem.fallbackPath)
                .standardizedFileURL
                .resolvingSymlinksInPath(),
            renamedURL.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            refreshedItem.resolve()?.url
                .standardizedFileURL
                .resolvingSymlinksInPath(),
            renamedURL.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            workspaceSnapshot.defaultOpenURLs.map {
                $0.standardizedFileURL.resolvingSymlinksInPath()
            },
            [renamedURL.standardizedFileURL.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(workspaceSnapshot.scopeActivityAtOpen, [true])
        XCTAssertFalse(scope.snapshot().isActive)
    }

    func testFreshBookmarkReturnsNoRefreshedItem() async throws {
        let targetURL = try makeFile(named: "Document.txt")
        let workspace = WorkspaceSpy()
        let scope = SecurityScopeRecorder(startReturns: false)
        let service = makeService(workspace: workspace, scope: scope)

        let result = try await service.openWithSystemDefault(makeItem(for: targetURL))

        XCTAssertNil(result.refreshedItem)
    }

    func testLiveWorkspaceSelectedOpenActivatesChosenApplication() async throws {
        let targetURL = URL(fileURLWithPath: "/tmp/Document.txt")
        let applicationURL = URL(fileURLWithPath: "/Applications/Preview.app")
        let recorder = LiveWorkspaceRecorder()
        let workspace = NSWorkspaceOpening(
            openDefault: { _ in true },
            openSelected: recorder.openSelected
        )

        try await workspace.open(targetURL, withApplicationAt: applicationURL)

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.targetURLs, [[targetURL]])
        XCTAssertEqual(snapshot.applicationURLs, [applicationURL])
        XCTAssertEqual(snapshot.activatesValues, [true])
    }

    func testLiveWorkspaceSelectedOpenPropagatesCompletionError() async {
        let workspace = NSWorkspaceOpening(
            openDefault: { _ in true },
            openSelected: { _, _, _, completion in
                completion(nil, TestOpenError.rejected)
            }
        )

        do {
            try await workspace.open(
                URL(fileURLWithPath: "/tmp/Document.txt"),
                withApplicationAt: URL(fileURLWithPath: "/Applications/Preview.app")
            )
            XCTFail("Expected selected workspace failure")
        } catch {
            XCTAssertEqual(error as? TestOpenError, .rejected)
        }
    }

    func testLiveWorkspaceDefaultFalseMapsToExplicitError() async {
        let workspace = NSWorkspaceOpening(
            openDefault: { _ in false },
            openSelected: { _, _, _, completion in completion(nil, nil) }
        )

        do {
            try await workspace.openDefault(URL(fileURLWithPath: "/tmp/Document.txt"))
            XCTFail("Expected system default failure")
        } catch {
            XCTAssertEqual(
                error as? FileSystemOpenServiceError,
                .systemDefaultOpenFailed
            )
        }
    }

    private func makeService(
        workspace: any WorkspaceOpening,
        scope: SecurityScopeRecorder
    ) -> FileSystemOpenService {
        FileSystemOpenService(
            workspace: workspace,
            startAccessingSecurityScopedResource: scope.start,
            stopAccessingSecurityScopedResource: scope.stop
        )
    }

    private func makeFile(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try Data("value".utf8).write(to: url)
        return url
    }

    private func makeDirectory(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeApplicationDirectory(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeItem(for url: URL) -> ManagedFileSystemItem {
        ManagedFileSystemItem(
            displayName: url.lastPathComponent,
            fallbackPath: url.path,
            bookmarkData: Data("invalid bookmark".utf8)
        )
    }

    private func makeApplication(for url: URL) -> ManagedApplication {
        ManagedApplication(
            displayName: url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: "com.example.preview",
            fallbackPath: url.path,
            bookmarkData: Data("invalid bookmark".utf8)
        )
    }
}

private actor SuspendingWorkspace: WorkspaceOpening {
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

    func openDefault(_ targetURL: URL) async throws {
        try await suspendOpen()
    }

    func open(
        _ targetURL: URL,
        withApplicationAt applicationURL: URL
    ) async throws {
        try await suspendOpen()
    }

    func waitUntilEntered() async {
        guard openContinuation == nil else {
            return
        }

        await withCheckedContinuation {
            enteredWaiters.append($0)
        }
    }

    func complete(with result: Result<Void, TestOpenError>) {
        guard let openContinuation else {
            XCTFail("Workspace open has not entered")
            return
        }
        self.openContinuation = nil

        switch result {
        case .success:
            openContinuation.resume()
        case .failure(let error):
            openContinuation.resume(throwing: error)
        }
    }

    private func suspendOpen() async throws {
        try await withCheckedThrowingContinuation {
            openContinuation = $0
            let waiters = enteredWaiters
            enteredWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

private enum TestOpenError: Error, Equatable, Sendable {
    case rejected
}

private struct SelectedOpenCall: Equatable, Sendable {
    let targetURL: URL
    let applicationURL: URL
}

private struct WorkspaceSnapshot: Sendable {
    let defaultOpenURLs: [URL]
    let selectedOpenCalls: [SelectedOpenCall]
    let scopeActivityAtOpen: [Bool]
}

private actor WorkspaceSpy: WorkspaceOpening {
    private var defaultOpenURLs: [URL] = []
    private var selectedOpenCalls: [SelectedOpenCall] = []
    private var scopeActivityAtOpen: [Bool] = []
    private let defaultError: TestOpenError?
    private let selectedError: TestOpenError?
    private let scopeIsActive: @Sendable () -> Bool

    init(
        defaultError: TestOpenError? = nil,
        selectedError: TestOpenError? = nil,
        scopeIsActive: @escaping @Sendable () -> Bool = { false }
    ) {
        self.defaultError = defaultError
        self.selectedError = selectedError
        self.scopeIsActive = scopeIsActive
    }

    func openDefault(_ targetURL: URL) async throws {
        defaultOpenURLs.append(targetURL)
        scopeActivityAtOpen.append(scopeIsActive())
        if let defaultError {
            throw defaultError
        }
    }

    func open(
        _ targetURL: URL,
        withApplicationAt applicationURL: URL
    ) async throws {
        selectedOpenCalls.append(
            SelectedOpenCall(
                targetURL: targetURL,
                applicationURL: applicationURL
            )
        )
        scopeActivityAtOpen.append(scopeIsActive())
        if let selectedError {
            throw selectedError
        }
    }

    func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            defaultOpenURLs: defaultOpenURLs,
            selectedOpenCalls: selectedOpenCalls,
            scopeActivityAtOpen: scopeActivityAtOpen
        )
    }
}

private final class SecurityScopeRecorder: Sendable {
    private struct State: Sendable {
        var startURLs: [URL] = []
        var stopURLs: [URL] = []
        var activeAccessCount = 0
    }

    private let startReturns: Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(startReturns: Bool) {
        self.startReturns = startReturns
    }

    func start(_ url: URL) -> Bool {
        state.withLock {
            $0.startURLs.append(url)
            if startReturns {
                $0.activeAccessCount += 1
            }
        }
        return startReturns
    }

    func stop(_ url: URL) {
        state.withLock {
            $0.stopURLs.append(url)
            $0.activeAccessCount -= 1
        }
    }

    func isActive() -> Bool {
        state.withLock { $0.activeAccessCount > 0 }
    }

    func snapshot() -> SecurityScopeSnapshot {
        state.withLock {
            SecurityScopeSnapshot(
                startURLs: $0.startURLs,
                stopURLs: $0.stopURLs,
                isActive: $0.activeAccessCount > 0
            )
        }
    }
}

private struct SecurityScopeSnapshot: Sendable {
    let startURLs: [URL]
    let stopURLs: [URL]
    let isActive: Bool

    var startCallCount: Int {
        startURLs.count
    }
}

private final class LiveWorkspaceRecorder: Sendable {
    private struct State: Sendable {
        var targetURLs: [[URL]] = []
        var applicationURLs: [URL] = []
        var activatesValues: [Bool] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func openSelected(
        _ targetURLs: [URL],
        _ applicationURL: URL,
        _ configuration: NSWorkspace.OpenConfiguration,
        _ completion: @escaping @Sendable (NSRunningApplication?, Error?) -> Void
    ) {
        let activates = configuration.activates
        state.withLock {
            $0.targetURLs.append(targetURLs)
            $0.applicationURLs.append(applicationURL)
            $0.activatesValues.append(activates)
        }
        completion(nil, nil)
    }

    func snapshot() -> LiveWorkspaceSnapshot {
        state.withLock {
            LiveWorkspaceSnapshot(
                targetURLs: $0.targetURLs,
                applicationURLs: $0.applicationURLs,
                activatesValues: $0.activatesValues
            )
        }
    }
}

private struct LiveWorkspaceSnapshot: Sendable {
    let targetURLs: [[URL]]
    let applicationURLs: [URL]
    let activatesValues: [Bool]
}
