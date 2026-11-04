import AppWinkCore
import Foundation
import XCTest

@testable import AppWinkRuntime

@MainActor
final class BindingActionExecutorTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        defer { temporaryDirectory = nil }
        if let temporaryDirectory,
           FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testApplicationUsesExistingToggleServiceAndTiming() async throws {
        let toggleService = ExecutorToggleServiceSpy()
        toggleService.executionTiming = .nextRunLoop
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(
            toggleService: toggleService,
            fileService: fileService
        )
        let application = try makeApplication(named: "Notes")

        let action = executor.prepareAction(
            for: HotkeyBinding(target: .application(application)),
            authorization: allowedAuthorization,
            frontmostProcessIdentifier: 321,
            source: .hotKey
        )
        let result = await execute(action)
        let fileCalls = await fileService.calls()

        XCTAssertTrue(action.isAccepted)
        guard case .nextRunLoop = action.executionTiming else {
            return XCTFail("Expected application timing")
        }
        XCTAssertEqual(toggleService.calls.count, 1)
        XCTAssertEqual(toggleService.calls.first?.application, application)
        XCTAssertEqual(toggleService.calls.first?.frontmostProcessIdentifier, 321)
        XCTAssertEqual(toggleService.calls.first?.source, .hotKey)
        XCTAssertTrue(fileCalls.isEmpty)
        guard case .success(.application(.hidden("Notes"))) = result else {
            return XCTFail("Expected application toggle result")
        }
    }

    func testDefaultFolderUsesSystemWorkspaceOpen() async throws {
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Project", isDirectory: true)

        let action = executor.prepareAction(
            for: HotkeyBinding(target: .folder(item, .finderNewTab)),
            authorization: allowedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .manual
        )
        let result = await execute(action)
        let fileCalls = await fileService.calls()

        XCTAssertTrue(action.isAccepted)
        guard case .immediate = action.executionTiming else {
            return XCTFail("Expected immediate timing")
        }
        XCTAssertEqual(fileCalls, [.systemDefault(item)])
        guard case .success(.opened(refreshedItem: nil)) = result else {
            return XCTFail("Expected opened result")
        }
    }

    func testSelectedApplicationFolderUsesFileService() async throws {
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Project", isDirectory: true)
        let application = try makeApplication(named: "Editor")

        _ = await execute(executor.prepareAction(
            for: HotkeyBinding(
                target: .folder(item, .application(application))
            ),
            authorization: deniedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .manual
        ))
        let fileCalls = await fileService.calls()

        XCTAssertEqual(fileCalls, [.selected(item, application)])
    }

    func testSystemDefaultFileUsesFileService() async throws {
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Document.txt")

        _ = await execute(executor.prepareAction(
            for: HotkeyBinding(target: .file(item, .systemDefault)),
            authorization: deniedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .hotKey
        ))
        let calls = await fileService.calls()

        XCTAssertEqual(calls, [.systemDefault(item)])
    }

    func testSelectedApplicationFileUsesFileService() async throws {
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Document.txt")
        let application = try makeApplication(named: "Preview")

        _ = await execute(executor.prepareAction(
            for: HotkeyBinding(
                target: .file(item, .application(application))
            ),
            authorization: deniedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .hotKey
        ))
        let calls = await fileService.calls()

        XCTAssertEqual(calls, [.selected(item, application)])
    }

    func testApplicationRequiresAccessibility() async throws {
        let toggleService = ExecutorToggleServiceSpy()
        let executor = makeExecutor(toggleService: toggleService)
        let action = executor.prepareAction(
            for: HotkeyBinding(
                target: .application(try makeApplication(named: "Notes"))
            ),
            authorization: deniedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .hotKey
        )

        let result = await execute(action)

        XCTAssertFalse(action.isAccepted)
        XCTAssertTrue(toggleService.calls.isEmpty)
        guard case .failure(.accessibilityPermissionRequired) = result else {
            return XCTFail("Expected Accessibility failure")
        }
    }

    func testDefaultFolderDoesNotRequireAccessibilityPermission() async throws {
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Project", isDirectory: true)
        let action = executor.prepareAction(
            for: HotkeyBinding(target: .folder(item, .finderNewTab)),
            authorization: BindingActionAuthorizationContext(
                accessibilityGranted: false
            ),
            frontmostProcessIdentifier: nil,
            source: .hotKey
        )

        let result = await execute(action)
        let calls = await fileService.calls()

        XCTAssertTrue(action.isAccepted)
        XCTAssertEqual(calls, [.systemDefault(item)])
        guard case .success(.opened) = result else {
            return XCTFail("Expected system open success without Accessibility")
        }
    }

    func testSelectedModesAndSystemDefaultIgnoreRuntimePermissions() async throws {
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(fileService: fileService)
        let folder = try makeItem(named: "Project", isDirectory: true)
        let file = try makeItem(named: "Document.txt")
        let application = try makeApplication(named: "Editor")
        let actions = [
            executor.prepareAction(
                for: HotkeyBinding(
                    target: .folder(folder, .application(application))
                ),
                authorization: deniedAuthorization,
                frontmostProcessIdentifier: nil,
                source: .manual
            ),
            executor.prepareAction(
                for: HotkeyBinding(target: .file(file, .systemDefault)),
                authorization: deniedAuthorization,
                frontmostProcessIdentifier: nil,
                source: .manual
            ),
            executor.prepareAction(
                for: HotkeyBinding(
                    target: .file(file, .application(application))
                ),
                authorization: deniedAuthorization,
                frontmostProcessIdentifier: nil,
                source: .manual
            ),
        ]

        for action in actions {
            XCTAssertTrue(action.isAccepted)
            _ = await execute(action)
        }
        let calls = await fileService.calls()

        XCTAssertEqual(
            calls,
            [
                .selected(folder, application),
                .systemDefault(file),
                .selected(file, application),
            ]
        )
    }

    func testUnavailableSelectedHandlerRejectsWithoutAlternateOpen() async throws {
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Document.txt")
        let missingApplication = ManagedApplication(
            displayName: "Missing",
            bundleIdentifier: "com.example.missing",
            fallbackPath: temporaryDirectory
                .appendingPathComponent("Missing.app").path,
            bookmarkData: Data()
        )
        let action = executor.prepareAction(
            for: HotkeyBinding(
                target: .file(item, .application(missingApplication))
            ),
            authorization: allowedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .manual
        )

        let result = await execute(action)
        let calls = await fileService.calls()

        XCTAssertFalse(action.isAccepted)
        XCTAssertTrue(calls.isEmpty)
        guard case .failure(.selectedHandlerUnavailable) = result else {
            return XCTFail("Expected selected-handler failure")
        }
    }

    func testSelectedServiceFailureDoesNotRetryWithSystemDefault() async throws {
        let fileService = ExecutorFileServiceSpy(
            error: NSError(
                domain: "BindingActionExecutorTests.Open",
                code: 41
            )
        )
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Document.txt")
        let application = try makeApplication(named: "Preview")

        let result = await execute(executor.prepareAction(
            for: HotkeyBinding(
                target: .file(item, .application(application))
            ),
            authorization: allowedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .manual
        ))
        let calls = await fileService.calls()

        XCTAssertEqual(calls, [.selected(item, application)])
        guard case .failure(.openFailed(let failure)) = result else {
            return XCTFail("Expected open failure")
        }
        XCTAssertEqual(failure.domain, "BindingActionExecutorTests.Open")
        XCTAssertEqual(failure.code, 41)
    }

    func testUnavailableTargetRejectsWithoutDispatch() async {
        let fileService = ExecutorFileServiceSpy()
        let executor = makeExecutor(fileService: fileService)
        let item = ManagedFileSystemItem(
            displayName: "Missing.txt",
            fallbackPath: temporaryDirectory
                .appendingPathComponent("Missing.txt").path,
            bookmarkData: Data()
        )
        let action = executor.prepareAction(
            for: HotkeyBinding(target: .file(item, .systemDefault)),
            authorization: allowedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .manual
        )

        let result = await execute(action)
        let calls = await fileService.calls()

        XCTAssertFalse(action.isAccepted)
        XCTAssertTrue(calls.isEmpty)
        guard case .failure(.targetUnavailable) = result else {
            return XCTFail("Expected target unavailable failure")
        }
    }

    func testFileServiceTargetUnavailableMapsToBindingTargetUnavailable() async throws {
        let fileService = ExecutorFileServiceSpy(
            error: FileSystemOpenServiceError.targetUnavailable("Document.txt")
        )
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Document.txt")

        let result = await execute(executor.prepareAction(
            for: HotkeyBinding(target: .file(item, .systemDefault)),
            authorization: allowedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .hotKey
        ))

        guard case .failure(.targetUnavailable) = result else {
            return XCTFail("Expected target unavailable failure")
        }
    }

    func testFileServiceHandlerUnavailableMapsToSelectedHandlerUnavailable() async throws {
        let fileService = ExecutorFileServiceSpy(
            error: FileSystemOpenServiceError
                .openingApplicationUnavailable("Preview")
        )
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Document.txt")
        let application = try makeApplication(named: "Preview")

        let result = await execute(executor.prepareAction(
            for: HotkeyBinding(
                target: .file(item, .application(application))
            ),
            authorization: allowedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .hotKey
        ))

        guard case .failure(.selectedHandlerUnavailable) = result else {
            return XCTFail("Expected selected handler unavailable failure")
        }
    }

    func testReturnsRefreshedItemFromFileService() async throws {
        let refreshedItem = ManagedFileSystemItem(
            displayName: "Refreshed",
            fallbackPath: "/tmp/refreshed",
            bookmarkData: Data([1, 2, 3])
        )
        let fileService = ExecutorFileServiceSpy(
            result: ResolvedFileSystemActionResult(
                refreshedItem: refreshedItem
            )
        )
        let executor = makeExecutor(fileService: fileService)
        let item = try makeItem(named: "Document.txt")

        let result = await execute(executor.prepareAction(
            for: HotkeyBinding(target: .file(item, .systemDefault)),
            authorization: allowedAuthorization,
            frontmostProcessIdentifier: nil,
            source: .manual
        ))

        guard case .success(.opened(let returnedItem)) = result else {
            return XCTFail("Expected opened result")
        }
        XCTAssertEqual(returnedItem, refreshedItem)
    }

    private var allowedAuthorization: BindingActionAuthorizationContext {
        BindingActionAuthorizationContext(
            accessibilityGranted: true
        )
    }

    private var deniedAuthorization: BindingActionAuthorizationContext {
        BindingActionAuthorizationContext(
            accessibilityGranted: false
        )
    }

    private func makeExecutor(
        toggleService: ExecutorToggleServiceSpy = ExecutorToggleServiceSpy(),
        fileService: ExecutorFileServiceSpy = ExecutorFileServiceSpy()
    ) -> BindingActionExecutor {
        BindingActionExecutor(
            applicationToggleService: toggleService,
            fileSystemOpenService: fileService
        )
    }

    private func execute(
        _ action: PreparedBindingAction
    ) async -> Result<BindingActionResult, BindingActionError> {
        await withCheckedContinuation { continuation in
            action.execute {
                continuation.resume(returning: $0)
            }
        }
    }

    private func makeApplication(named name: String) throws -> ManagedApplication {
        let url = temporaryDirectory.appendingPathComponent(
            "\(name).app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return ManagedApplication(
            displayName: name,
            bundleIdentifier: "com.example.\(name.lowercased())",
            fallbackPath: url.path,
            bookmarkData: Data()
        )
    }

    private func makeItem(
        named name: String,
        isDirectory: Bool = false
    ) throws -> ManagedFileSystemItem {
        let url = temporaryDirectory.appendingPathComponent(
            name,
            isDirectory: isDirectory
        )
        if isDirectory {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } else {
            try Data("fixture".utf8).write(to: url)
        }
        return ManagedFileSystemItem(
            displayName: name,
            fallbackPath: url.path,
            bookmarkData: Data()
        )
    }
}

@MainActor
private final class ExecutorToggleServiceSpy: ApplicationToggleServicing {
    struct Call {
        let application: ManagedApplication
        let frontmostProcessIdentifier: pid_t?
        let source: ToggleInvocationSource
    }

    var calls: [Call] = []
    var executionTiming: PreparedApplicationToggleExecutionTiming = .immediate
    var result: Result<ApplicationToggleResult, ApplicationToggleError> =
        .success(.hidden("Notes"))

    func prepareToggle(
        application: ManagedApplication,
        frontmostProcessIdentifier: pid_t?,
        invocationSource: ToggleInvocationSource
    ) -> PreparedApplicationToggle {
        calls.append(Call(
            application: application,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            source: invocationSource
        ))
        return PreparedApplicationToggle(
            executionTiming: executionTiming
        ) { completion in
            completion(self.result)
        }
    }
}

private actor ExecutorFileServiceSpy: FileSystemOpenServicing {
    enum Call: Equatable {
        case systemDefault(ManagedFileSystemItem)
        case selected(ManagedFileSystemItem, ManagedApplication)
    }

    private var recordedCalls: [Call] = []
    private let result: ResolvedFileSystemActionResult
    private let error: (any Error)?

    init(
        result: ResolvedFileSystemActionResult =
            ResolvedFileSystemActionResult(refreshedItem: nil),
        error: (any Error)? = nil
    ) {
        self.result = result
        self.error = error
    }

    func openWithSystemDefault(
        _ item: ManagedFileSystemItem
    ) async throws -> ResolvedFileSystemActionResult {
        recordedCalls.append(.systemDefault(item))
        if let error {
            throw error
        }
        return result
    }

    func open(
        _ item: ManagedFileSystemItem,
        with application: ManagedApplication
    ) async throws -> ResolvedFileSystemActionResult {
        recordedCalls.append(.selected(item, application))
        if let error {
            throw error
        }
        return result
    }

    func calls() -> [Call] {
        recordedCalls
    }
}
