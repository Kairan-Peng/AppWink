import AppKit
import AppWinkCore
import XCTest
@testable import AppWinkRuntime

final class HotkeyTargetPresentationTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var originalLanguage: AppLanguage = .system

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalLanguage = LocalizationManager.shared.currentLanguage
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        LocalizationManager.shared.setLanguage(originalLanguage)
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        try super.tearDownWithError()
    }

    func testApplicationTargetHasNoOpeningModeMenu() throws {
        let application = try makeApplication(named: "Notes")
        let presentation = makePresentation(
            for: HotkeyBinding(target: .application(application))
        )

        XCTAssertNil(presentation.openingMode)
        XCTAssertEqual(presentation.displayName, "Notes")
        XCTAssertEqual(presentation.fallbackSymbolName, "app.fill")
    }

    func testFolderTargetUsesFinderByDefault() throws {
        let folder = try makeFolder(named: "Project")
        let presentation = makePresentation(
            for: HotkeyBinding(target: .folder(folder, .finderNewTab))
        )

        XCTAssertEqual(presentation.openingMode?.label, "Finder")
        XCTAssertNotNil(presentation.openingMode?.image)
        XCTAssertNotNil(presentation.finderOpeningMode?.image)
        XCTAssertEqual(presentation.openingMode?.fallbackSymbolName, "folder")
    }

    func testFileTargetUpdatesSystemDefaultApplicationLabelDynamically() throws {
        let file = try makeFile(named: "Report.pdf")
        let preview = try makeApplication(named: "Preview")
        let acrobat = try makeApplication(named: "Acrobat")
        let binding = HotkeyBinding(target: .file(file, .systemDefault))

        let previewPresentation = makePresentation(
            for: binding,
            systemDefaultApplication: preview
        )
        let acrobatPresentation = makePresentation(
            for: binding,
            systemDefaultApplication: acrobat
        )

        XCTAssertEqual(
            previewPresentation.openingMode?.label,
            "System Default (Preview)"
        )
        XCTAssertEqual(
            acrobatPresentation.openingMode?.label,
            "System Default (Acrobat)"
        )
    }

    func testSelectedApplicationUsesLocalizedNameAndMaterializedIcon() throws {
        let file = try makeFile(named: "Report.pdf")
        let preview = try makeApplication(named: "Preview")
        let binding = HotkeyBinding(
            target: .file(file, .application(preview))
        )

        let presentation = makePresentation(for: binding)

        XCTAssertEqual(presentation.openingMode?.label, "Preview")
        XCTAssertNotNil(presentation.openingMode?.image)
    }

    func testSelectedApplicationModeStillPresentsDynamicSystemDefaultOption() throws {
        let file = try makeFile(named: "Report.pdf")
        let preview = try makeApplication(named: "Preview")
        let acrobat = try makeApplication(named: "Acrobat")
        let binding = HotkeyBinding(
            target: .file(file, .application(preview))
        )

        let presentation = makePresentation(
            for: binding,
            systemDefaultApplication: acrobat
        )

        XCTAssertEqual(
            presentation.systemDefaultOpeningMode?.label,
            "System Default (Acrobat)"
        )
        XCTAssertNotNil(presentation.systemDefaultOpeningMode?.image)
    }

    func testUnavailableTargetAndHandlerUseTargetNeutralCopyWithoutPaths() {
        let missingTarget = ManagedFileSystemItem(
            displayName: "Missing Report",
            fallbackPath: temporaryDirectoryURL
                .appendingPathComponent("private-report.pdf").path,
            bookmarkData: Data()
        )
        let missingHandler = ManagedApplication(
            displayName: "Missing Editor",
            bundleIdentifier: "example.missing-editor",
            fallbackPath: temporaryDirectoryURL
                .appendingPathComponent("Missing Editor.app").path,
            bookmarkData: Data()
        )
        let binding = HotkeyBinding(
            target: .file(missingTarget, .application(missingHandler))
        )

        let presentation = makePresentation(
            for: binding,
            availability: .targetUnavailable
        )

        XCTAssertEqual(presentation.displayName, "Missing Report")
        XCTAssertNil(presentation.targetImage)
        XCTAssertEqual(
            presentation.openingMode?.label,
            "Opening Application Unavailable"
        )
        XCTAssertTrue(presentation.accessibilityValue.contains("Target Unavailable"))
        XCTAssertFalse(presentation.accessibilityValue.contains(temporaryDirectoryURL.path))
    }

    func testAccessibilityValueIncludesTargetKindAndOpeningMode() throws {
        let folder = try makeFolder(named: "Project")
        let presentation = makePresentation(
            for: HotkeyBinding(target: .folder(folder, .finderNewTab))
        )

        XCTAssertEqual(
            presentation.accessibilityValue,
            "Folder: Project; Open With: Finder"
        )
    }

    func testMenuBarAccessibilityDistinguishesSameNamedFolderAndFileModesWithoutPaths() throws {
        let folderContainer = temporaryDirectoryURL
            .appendingPathComponent("folder-container", isDirectory: true)
        let fileContainer = temporaryDirectoryURL
            .appendingPathComponent("file-container", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderContainer,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fileContainer,
            withIntermediateDirectories: true
        )
        let folderURL = folderContainer
            .appendingPathComponent("Shared", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let fileURL = fileContainer.appendingPathComponent("Shared")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: Data()
            )
        )
        let folderPresentation = makePresentation(
            for: HotkeyBinding(
                target: .folder(
                    try ManagedFileSystemItem(url: folderURL),
                    .finderNewTab
                )
            )
        )
        let filePresentation = makePresentation(
            for: HotkeyBinding(
                target: .file(
                    try ManagedFileSystemItem(url: fileURL),
                    .systemDefault
                )
            )
        )

        let folderAccessibility = MenuBarBindingAccessibility(
            presentation: folderPresentation,
            shortcut: "⌥A",
            state: "Enabled"
        )
        let fileAccessibility = MenuBarBindingAccessibility(
            presentation: filePresentation,
            shortcut: "⌥B",
            state: "Unavailable"
        )

        XCTAssertEqual(
            folderAccessibility.label,
            folderPresentation.accessibilityValue
        )
        XCTAssertEqual(
            fileAccessibility.label,
            filePresentation.accessibilityValue
        )
        XCTAssertNotEqual(
            folderAccessibility.label,
            fileAccessibility.label
        )
        XCTAssertTrue(
            folderAccessibility.label.contains("Finder")
        )
        XCTAssertTrue(
            fileAccessibility.label.contains("System Default")
        )
        XCTAssertEqual(folderAccessibility.value, "⌥A, Enabled")
        XCTAssertEqual(fileAccessibility.value, "⌥B, Unavailable")
        XCTAssertFalse(
            [
                folderAccessibility.label,
                folderAccessibility.value,
                fileAccessibility.label,
                fileAccessibility.value,
            ]
                .joined()
                .contains(temporaryDirectoryURL.path)
        )
    }

    private func makePresentation(
        for binding: HotkeyBinding,
        systemDefaultApplication: ManagedApplication? = nil,
        availability: HotkeyTargetAvailability = .available
    ) -> HotkeyTargetPresentation {
        LocalizationManager.shared.setLanguage(.english)
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in
                systemDefaultApplication?.resolvedURL()
            },
            applicationURLs: { _ in [] }
        )
        return HotkeyTargetPresentationResolver(catalog: catalog).resolve(
            binding: binding,
            availability: availability,
            language: .english,
            localizationBundle: LocalizationManager.shared.bundle
        )
    }

    private func makeApplication(named name: String) throws -> ManagedApplication {
        let url = temporaryDirectoryURL
            .appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        let contentsURL = url.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        let infoPlistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "example.\(name.lowercased())",
                "CFBundleName": name,
                "CFBundlePackageType": "APPL",
            ],
            format: .xml,
            options: 0
        )
        try infoPlistData.write(
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        return ManagedApplication(
            displayName: name,
            bundleIdentifier: "example.\(name.lowercased())",
            fallbackPath: url.path,
            bookmarkData: Data()
        )
    }

    private func makeFolder(named name: String) throws -> ManagedFileSystemItem {
        let url = temporaryDirectoryURL
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return ManagedFileSystemItem(
            displayName: name,
            fallbackPath: url.path,
            bookmarkData: Data()
        )
    }

    private func makeFile(named name: String) throws -> ManagedFileSystemItem {
        let url = temporaryDirectoryURL.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        return ManagedFileSystemItem(
            displayName: name,
            fallbackPath: url.path,
            bookmarkData: Data()
        )
    }
}
