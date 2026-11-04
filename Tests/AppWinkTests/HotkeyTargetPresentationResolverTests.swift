import AppKit
import AppWinkCore
import XCTest
@testable import AppWinkRuntime

final class HotkeyTargetPresentationResolverTests: XCTestCase {
    func testFilePresentationPerformsResourceQueriesInsideSecurityScope() throws {
        let targetURL = URL(fileURLWithPath: "/private/tmp/Scoped.txt")
        let recorder = SecurityScopePresentationRecorder(startResult: true)
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { url in
                recorder.recordExternalQuery("default", url: url)
                return nil
            },
            applicationURLs: { url in
                recorder.recordExternalQuery("candidates", url: url)
                return []
            }
        )
        let resolver = HotkeyTargetPresentationResolver(
            catalog: catalog,
            resolveFileSystemItemURL: { _ in targetURL },
            startAccessingSecurityScopedResource: recorder.start,
            stopAccessingSecurityScopedResource: recorder.stop,
            fileExistsAtPath: recorder.fileExists,
            displayNameAtURL: recorder.displayName,
            iconForURL: recorder.icon
        )
        let item = ManagedFileSystemItem(
            displayName: "Stored",
            fallbackPath: targetURL.path,
            bookmarkData: Data()
        )
        let binding = HotkeyBinding(target: .file(item, .systemDefault))

        let presentation = resolver.resolve(
            binding: binding,
            availability: .available,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )

        XCTAssertEqual(presentation.displayName, "Scoped.txt")
        XCTAssertNotNil(presentation.targetImage)
        XCTAssertEqual(presentation.availability, .available)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertTrue(recorder.externalQueriesWereScoped)
    }

    func testScopeIsNotStoppedWhenAccessWasNotStarted() {
        let targetURL = URL(fileURLWithPath: "/private/tmp/Scoped Folder")
        let recorder = SecurityScopePresentationRecorder(startResult: false)
        let resolver = makeResolver(
            targetURL: targetURL,
            recorder: recorder
        )
        let item = ManagedFileSystemItem(
            displayName: "Stored",
            fallbackPath: targetURL.path,
            bookmarkData: Data()
        )

        _ = resolver.resolve(
            binding: HotkeyBinding(
                target: .folder(item, .finderNewTab)
            ),
            availability: .available,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )

        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.stopCount, 0)
        XCTAssertEqual(recorder.fileExistsCount, 1)
    }

    func testMissingTargetSkipsPresentationAndLaunchServicesQueries() {
        let targetURL = URL(fileURLWithPath: "/private/tmp/Missing.txt")
        let recorder = SecurityScopePresentationRecorder(
            startResult: true,
            fileExists: false
        )
        let resolver = makeResolver(
            targetURL: targetURL,
            recorder: recorder
        )
        let item = ManagedFileSystemItem(
            displayName: "Missing.txt",
            fallbackPath: targetURL.path,
            bookmarkData: Data()
        )

        let presentation = resolver.resolve(
            binding: HotkeyBinding(target: .file(item, .systemDefault)),
            availability: .available,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )

        XCTAssertEqual(presentation.availability, .targetUnavailable)
        XCTAssertNil(presentation.targetImage)
        XCTAssertEqual(recorder.displayNameCount, 0)
        XCTAssertEqual(recorder.iconCount, 0)
        XCTAssertEqual(recorder.catalogQueryCount, 0)
        XCTAssertEqual(recorder.stopCount, 1)
    }

    func testKnownUnavailableTargetKeepsSelectedHandlerSnapshot() throws {
        let targetURL = URL(fileURLWithPath: "/private/tmp/Missing.txt")
        let applicationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: applicationURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: applicationURL) }
        let recorder = SecurityScopePresentationRecorder(startResult: true)
        let resolver = makeResolver(
            targetURL: targetURL,
            recorder: recorder
        )
        let item = ManagedFileSystemItem(
            displayName: "Missing.txt",
            fallbackPath: targetURL.path,
            bookmarkData: Data()
        )
        let application = ManagedApplication(
            displayName: "Editor",
            bundleIdentifier: "com.example.editor",
            fallbackPath: applicationURL.path,
            bookmarkData: Data()
        )

        let presentation = resolver.resolve(
            binding: HotkeyBinding(
                target: .file(item, .application(application))
            ),
            availability: .targetUnavailable,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )

        XCTAssertEqual(presentation.availability, .targetUnavailable)
        XCTAssertEqual(presentation.openingMode?.label, "Editor")
        XCTAssertNotNil(presentation.openingMode?.image)
        XCTAssertTrue(
            presentation.accessibilityValue.contains(
                NSLocalizedString(
                    LocalizationKey.targetUnavailable.rawValue,
                    bundle: LocalizationManager.shared.bundle,
                    comment: ""
                )
            )
        )
        XCTAssertTrue(presentation.accessibilityValue.contains("Editor"))
        XCTAssertEqual(recorder.startCount, 0)
        XCTAssertEqual(recorder.fileExistsCount, 0)
        XCTAssertEqual(recorder.displayNameCount, 0)
        XCTAssertEqual(recorder.iconCount, 1)
        XCTAssertEqual(recorder.catalogQueryCount, 0)
    }

    func testFolderPresentationDoesNotQuerySystemDefaultApplication() {
        let targetURL = URL(fileURLWithPath: "/private/tmp/Folder")
        let recorder = SecurityScopePresentationRecorder(startResult: true)
        let resolver = makeResolver(
            targetURL: targetURL,
            recorder: recorder
        )
        let item = ManagedFileSystemItem(
            displayName: "Folder",
            fallbackPath: targetURL.path,
            bookmarkData: Data()
        )

        _ = resolver.resolve(
            binding: HotkeyBinding(target: .folder(item, .finderNewTab)),
            availability: .available,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )

        XCTAssertFalse(recorder.queryNames.contains("default"))
        XCTAssertEqual(recorder.queryNames.filter { $0 == "candidates" }.count, 1)
    }

    func testCandidateSnapshotHasStableIDNameIconAndSelection() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let targetURL = temporaryDirectory.appendingPathComponent("File.txt")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: targetURL.path,
                contents: Data()
            )
        )
        let identifiedApplicationURL = try makeApplicationBundle(
            named: "Identified",
            bundleIdentifier: "com.example.identified",
            in: temporaryDirectory
        )
        let pathApplicationURL = try makeApplicationBundle(
            named: "Path Only",
            bundleIdentifier: nil,
            in: temporaryDirectory
        )
        let selectedApplication = try ManagedApplication(
            url: identifiedApplicationURL
        )
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in nil },
            applicationURLs: { _ in
                [identifiedApplicationURL, pathApplicationURL]
            }
        )
        let resolver = HotkeyTargetPresentationResolver(
            catalog: catalog,
            resolveFileSystemItemURL: { _ in targetURL },
            startAccessingSecurityScopedResource: { _ in false },
            stopAccessingSecurityScopedResource: { _ in },
            fileExistsAtPath: { _ in true },
            displayNameAtURL: { $0.lastPathComponent },
            iconForURL: { _ in
                NSImage(size: NSSize(width: 16, height: 16))
            }
        )
        let item = ManagedFileSystemItem(
            displayName: "File.txt",
            fallbackPath: targetURL.path,
            bookmarkData: Data()
        )
        let binding = HotkeyBinding(
            target: .file(item, .application(selectedApplication))
        )

        let first = resolver.resolve(
            binding: binding,
            availability: .available,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )
        let second = resolver.resolve(
            binding: binding,
            availability: .available,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )

        XCTAssertEqual(
            first.applicationCandidates.map(\.id),
            second.applicationCandidates.map(\.id)
        )
        XCTAssertEqual(
            Set(first.applicationCandidates.map(\.id)),
            Set([
                .bundleIdentifier("com.example.identified"),
                .canonicalPath(
                    pathApplicationURL.standardizedFileURL
                        .resolvingSymlinksInPath().path
                ),
            ])
        )
        XCTAssertTrue(
            first.applicationCandidates.allSatisfy {
                !$0.displayName.isEmpty && $0.image != nil
            }
        )
        XCTAssertEqual(
            first.applicationCandidates.filter(\.isSelected).count,
            1
        )
        XCTAssertFalse(
            Mirror(reflecting: first).children.contains {
                $0.label == "targetURL"
            }
        )
        XCTAssertFalse(
            Mirror(reflecting: first.openingMode as Any).children.contains {
                $0.label == "applicationURL"
            }
        )
    }

    func testMovedBookmarkOnlyHandlerMatchesLaunchServicesCandidate() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let targetURL = temporaryDirectory.appendingPathComponent("File.txt")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: targetURL.path,
                contents: Data()
            )
        )
        let originalApplicationURL = try makeApplicationBundle(
            named: "Original",
            bundleIdentifier: nil,
            in: temporaryDirectory
        )
        let selectedApplication = try ManagedApplication(
            url: originalApplicationURL
        )
        let movedApplicationURL = temporaryDirectory
            .appendingPathComponent("Moved.app", isDirectory: true)
        try FileManager.default.moveItem(
            at: originalApplicationURL,
            to: movedApplicationURL
        )
        XCTAssertEqual(
            selectedApplication.resolvedURL()?.standardizedFileURL
                .resolvingSymlinksInPath().path,
            movedApplicationURL.standardizedFileURL
                .resolvingSymlinksInPath().path
        )
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in nil },
            applicationURLs: { _ in [movedApplicationURL] }
        )
        let resolver = HotkeyTargetPresentationResolver(
            catalog: catalog,
            resolveFileSystemItemURL: { _ in targetURL },
            startAccessingSecurityScopedResource: { _ in false },
            stopAccessingSecurityScopedResource: { _ in },
            fileExistsAtPath: { _ in true },
            displayNameAtURL: { $0.lastPathComponent },
            iconForURL: { _ in
                NSImage(size: NSSize(width: 16, height: 16))
            }
        )
        let target = ManagedFileSystemItem(
            displayName: "File.txt",
            fallbackPath: targetURL.path,
            bookmarkData: Data()
        )

        let presentation = resolver.resolve(
            binding: HotkeyBinding(
                target: .file(
                    target,
                    .application(selectedApplication)
                )
            ),
            availability: .available,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )

        let candidate = try XCTUnwrap(
            presentation.applicationCandidates.first
        )
        XCTAssertEqual(
            candidate.id,
            .canonicalPath(
                movedApplicationURL.standardizedFileURL
                    .resolvingSymlinksInPath().path
            )
        )
        XCTAssertTrue(candidate.isSelected)
    }

    private func makeResolver(
        targetURL: URL,
        recorder: SecurityScopePresentationRecorder
    ) -> HotkeyTargetPresentationResolver {
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { url in
                recorder.recordExternalQuery("default", url: url)
                return nil
            },
            applicationURLs: { url in
                recorder.recordExternalQuery("candidates", url: url)
                return []
            }
        )
        return HotkeyTargetPresentationResolver(
            catalog: catalog,
            resolveFileSystemItemURL: { _ in targetURL },
            startAccessingSecurityScopedResource: recorder.start,
            stopAccessingSecurityScopedResource: recorder.stop,
            fileExistsAtPath: recorder.fileExists,
            displayNameAtURL: recorder.displayName,
            iconForURL: recorder.icon
        )
    }

    private func makeApplicationBundle(
        named name: String,
        bundleIdentifier: String?,
        in directory: URL
    ) throws -> URL {
        let applicationURL = directory
            .appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        var infoPlist: [String: Any] = [
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
        ]
        if let bundleIdentifier {
            infoPlist["CFBundleIdentifier"] = bundleIdentifier
        }
        let infoPlistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try infoPlistData.write(
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        return applicationURL
    }
}

private final class SecurityScopePresentationRecorder {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var fileExistsCount = 0
    private(set) var displayNameCount = 0
    private(set) var iconCount = 0
    private(set) var queryNames: [String] = []
    private(set) var externalQueriesWereScoped = true

    private let startResult: Bool
    private let targetExists: Bool
    private var scopeIsActive = false

    init(startResult: Bool, fileExists: Bool = true) {
        self.startResult = startResult
        self.targetExists = fileExists
    }

    var catalogQueryCount: Int {
        queryNames.count
    }

    func start(_ url: URL) -> Bool {
        startCount += 1
        scopeIsActive = startResult
        return startResult
    }

    func stop(_ url: URL) {
        stopCount += 1
        scopeIsActive = false
    }

    func fileExists(_ path: String) -> Bool {
        fileExistsCount += 1
        recordScopedState()
        return targetExists
    }

    func displayName(_ url: URL) -> String {
        displayNameCount += 1
        recordScopedState()
        return url.lastPathComponent
    }

    func icon(_ url: URL) -> NSImage {
        iconCount += 1
        recordScopedState()
        return NSImage(size: NSSize(width: 16, height: 16))
    }

    func recordExternalQuery(_ name: String, url: URL) {
        queryNames.append(name)
        recordScopedState()
    }

    private func recordScopedState() {
        if startResult, !scopeIsActive {
            externalQueriesWereScoped = false
        }
    }
}
