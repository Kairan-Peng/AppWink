import Foundation

import XCTest
@testable import AppWinkCore

final class HotkeyTargetFactoryTests: XCTestCase {
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
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testClassifiesApplicationBundleBeforeDirectory() throws {
        let applicationURL = try makeApplicationBundle(named: "Example.app")
        let values = try applicationURL.resourceValues(
            forKeys: [.isDirectoryKey, .isPackageKey]
        )

        XCTAssertEqual(values.isDirectory, true)
        XCTAssertEqual(values.isPackage, true)
        XCTAssertEqual(try HotkeyTargetFactory.classify(applicationURL), .application)
    }

    func testClassifiesOrdinaryDirectoryAsFolder() throws {
        let directoryURL = temporaryDirectory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        XCTAssertEqual(try HotkeyTargetFactory.classify(directoryURL), .folder)
    }

    func testClassifiesOrdinaryFileAsFile() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)

        XCTAssertEqual(try HotkeyTargetFactory.classify(fileURL), .file)
    }

    func testClassifiesDocumentPackageAsFile() throws {
        let packageURL = temporaryDirectory.appendingPathComponent(
            "Document.rtfd",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try Data("value".utf8).write(
            to: packageURL.appendingPathComponent("TXT.rtf")
        )
        let values = try packageURL.resourceValues(
            forKeys: [.isDirectoryKey, .isPackageKey]
        )

        XCTAssertEqual(values.isDirectory, true)
        XCTAssertEqual(values.isPackage, true)
        XCTAssertEqual(try HotkeyTargetFactory.classify(packageURL), .file)
    }

    func testClassifiesUppercaseAppExtensionAsApplication() throws {
        let applicationURL = temporaryDirectory.appendingPathComponent(
            "Fallback.APP",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationURL,
            withIntermediateDirectories: true
        )

        XCTAssertEqual(try HotkeyTargetFactory.classify(applicationURL), .application)
    }

    func testClassifiesMissingUppercaseAppExtensionAsApplication() throws {
        let applicationURL = temporaryDirectory.appendingPathComponent("Broken.APP")

        XCTAssertFalse(FileManager.default.fileExists(atPath: applicationURL.path))
        XCTAssertEqual(try HotkeyTargetFactory.classify(applicationURL), .application)
    }

    func testClassifyPropagatesResourceValuesError() {
        let missingURL = temporaryDirectory.appendingPathComponent("Missing.txt")

        XCTAssertThrowsError(try HotkeyTargetFactory.classify(missingURL))
    }

    func testMakeTargetUsesDefaultFolderModeAndPath() throws {
        let folderURL = temporaryDirectory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )

        let target = try HotkeyTargetFactory.makeTarget(for: folderURL)

        guard case .folder(let item, let mode) = target else {
            return XCTFail("Expected folder target")
        }
        XCTAssertEqual(item.fallbackPath, folderURL.path)
        XCTAssertEqual(mode, .finderNewTab)
    }

    func testMakeTargetUsesSystemDefaultFileModeAndPath() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)

        let target = try HotkeyTargetFactory.makeTarget(for: fileURL)

        guard case .file(let item, let mode) = target else {
            return XCTFail("Expected file target")
        }
        XCTAssertEqual(item.fallbackPath, fileURL.path)
        XCTAssertEqual(mode, .systemDefault)
    }

    func testMakeTargetCreatesManagedApplicationWithPath() throws {
        let applicationURL = try makeApplicationBundle(named: "Example.app")

        let target = try HotkeyTargetFactory.makeTarget(for: applicationURL)

        guard case .application(let application) = target else {
            return XCTFail("Expected application target")
        }
        XCTAssertEqual(application.fallbackPath, applicationURL.path)
    }

    private func makeApplicationBundle(named name: String) throws -> URL {
        let applicationURL = temporaryDirectory.appendingPathComponent(
            name,
            isDirectory: true
        )
        let contentsURL = applicationURL.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.example.\(UUID().uuidString)",
            "CFBundleName": "Example",
            "CFBundlePackageType": "APPL",
        ]
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
