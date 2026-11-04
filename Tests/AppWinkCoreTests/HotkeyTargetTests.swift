import Foundation

import XCTest
@testable import AppWinkCore

final class HotkeyTargetTests: XCTestCase {
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

    func testAllTargetModesRoundTripWithExplicitDiscriminators() throws {
        let item = makeItem(path: temporaryDirectory.appendingPathComponent("Target"))
        let application = makeApplication(
            name: "Handler",
            bundleIdentifier: "com.example.handler",
            path: temporaryDirectory.appendingPathComponent("Handler.app")
        )
        let cases: [(target: HotkeyTarget, targetType: String, openModeType: String?)] = [
            (.application(application), "application", nil),
            (.folder(item, .finderNewTab), "folder", "finderNewTab"),
            (.folder(item, .application(application)), "folder", "application"),
            (.file(item, .systemDefault), "file", "systemDefault"),
            (.file(item, .application(application)), "file", "application"),
        ]

        for testCase in cases {
            let data = try JSONEncoder().encode(testCase.target)
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )

            XCTAssertEqual(try JSONDecoder().decode(HotkeyTarget.self, from: data), testCase.target)
            XCTAssertEqual(object["type"] as? String, testCase.targetType)
            XCTAssertFalse(json.contains("\"_0\""))
            XCTAssertFalse(json.contains("\"_1\""))

            if let openModeType = testCase.openModeType {
                XCTAssertNotNil(object["item"])
                let openMode = try XCTUnwrap(object["openMode"] as? [String: Any])
                XCTAssertEqual(openMode["type"] as? String, openModeType)
                XCTAssertEqual(
                    openMode["application"] != nil,
                    openModeType == "application"
                )
            } else {
                XCTAssertNotNil(object["application"])
                XCTAssertNil(object["item"])
                XCTAssertNil(object["openMode"])
            }
        }
    }

    func testFinderNewTabModeRejectsApplicationPayload() throws {
        let application = makeApplication(
            bundleIdentifier: "com.example.handler",
            path: temporaryDirectory.appendingPathComponent("Handler.app")
        )
        var object = try jsonObject(for: FolderOpenMode.finderNewTab)
        object["application"] = try jsonObject(for: application)

        assertDecodingFails(FolderOpenMode.self, from: try jsonData(for: object))
    }

    func testSystemDefaultModeRejectsApplicationPayload() throws {
        let application = makeApplication(
            bundleIdentifier: "com.example.handler",
            path: temporaryDirectory.appendingPathComponent("Handler.app")
        )
        var object = try jsonObject(for: FileOpenMode.systemDefault)
        object["application"] = try jsonObject(for: application)

        assertDecodingFails(FileOpenMode.self, from: try jsonData(for: object))
    }

    func testApplicationTargetRejectsItemAndOpenModePayloads() throws {
        let item = makeItem(path: temporaryDirectory.appendingPathComponent("Target"))
        let application = makeApplication(
            bundleIdentifier: "com.example.application",
            path: temporaryDirectory.appendingPathComponent("Application.app")
        )
        let baseObject = try jsonObject(for: HotkeyTarget.application(application))
        var objectWithItem = baseObject
        objectWithItem["item"] = try jsonObject(for: item)
        var objectWithOpenMode = baseObject
        objectWithOpenMode["openMode"] = try jsonObject(for: FileOpenMode.systemDefault)

        for object in [objectWithItem, objectWithOpenMode] {
            assertDecodingFails(HotkeyTarget.self, from: try jsonData(for: object))
        }
    }

    func testFolderAndFileTargetsRejectTopLevelApplicationPayload() throws {
        let item = makeItem(path: temporaryDirectory.appendingPathComponent("Target"))
        let application = makeApplication(
            bundleIdentifier: "com.example.application",
            path: temporaryDirectory.appendingPathComponent("Application.app")
        )
        let targets: [HotkeyTarget] = [
            .folder(item, .finderNewTab),
            .file(item, .systemDefault),
        ]

        for target in targets {
            var object = try jsonObject(for: target)
            object["application"] = try jsonObject(for: application)

            assertDecodingFails(HotkeyTarget.self, from: try jsonData(for: object))
        }
    }

    func testKindsMatchTargetCases() {
        let item = makeItem(path: temporaryDirectory.appendingPathComponent("Target"))
        let application = makeApplication(
            bundleIdentifier: "com.example.application",
            path: temporaryDirectory.appendingPathComponent("Application.app")
        )

        XCTAssertEqual(HotkeyTarget.application(application).kind, .application)
        XCTAssertEqual(HotkeyTarget.folder(item, .finderNewTab).kind, .folder)
        XCTAssertEqual(HotkeyTarget.file(item, .systemDefault).kind, .file)
    }

    func testRequiredPermissionsMatchEveryTargetMode() {
        let item = makeItem(path: temporaryDirectory.appendingPathComponent("Target"))
        let application = makeApplication(
            bundleIdentifier: "com.example.application",
            path: temporaryDirectory.appendingPathComponent("Application.app")
        )

        XCTAssertEqual(
            HotkeyTarget.application(application).requiredPermissions,
            [.accessibility]
        )
        XCTAssertEqual(
            HotkeyTarget.folder(item, .finderNewTab).requiredPermissions,
            []
        )
        XCTAssertTrue(
            HotkeyTarget.folder(item, .application(application))
                .requiredPermissions.isEmpty
        )
        XCTAssertTrue(
            HotkeyTarget.file(item, .systemDefault).requiredPermissions.isEmpty
        )
        XCTAssertTrue(
            HotkeyTarget.file(item, .application(application))
                .requiredPermissions.isEmpty
        )
    }

    func testApplicationTargetsUseManagedApplicationIdentity() {
        let first = makeApplication(
            name: "First",
            bundleIdentifier: "com.example.shared",
            path: temporaryDirectory.appendingPathComponent("First.app"),
            bookmarkData: Data("first bookmark".utf8)
        )
        let second = makeApplication(
            name: "Second",
            bundleIdentifier: "com.example.shared",
            path: temporaryDirectory.appendingPathComponent("Second.app"),
            bookmarkData: Data("second bookmark".utf8)
        )

        XCTAssertTrue(
            HotkeyTarget.application(first)
                .hasSameBindingIdentity(as: .application(second))
        )
    }

    func testManagedApplicationsPreferNonEmptyBundleIdentifiers() {
        let path = temporaryDirectory.appendingPathComponent("Shared.app")
        let first = makeApplication(
            bundleIdentifier: "com.example.first",
            path: path
        )
        let second = makeApplication(
            bundleIdentifier: "com.example.second",
            path: path
        )

        XCTAssertFalse(first.hasSameIdentity(as: second))
    }

    func testManagedApplicationFallsBackToCanonicalURLIdentity() throws {
        let applicationURL = temporaryDirectory.appendingPathComponent(
            "Canonical.app",
            isDirectory: true
        )
        let symlinkURL = temporaryDirectory.appendingPathComponent("Alias.app")
        try FileManager.default.createDirectory(
            at: applicationURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: applicationURL
        )
        let first = makeApplication(
            bundleIdentifier: nil,
            path: applicationURL
        )
        let second = makeApplication(
            bundleIdentifier: "",
            path: symlinkURL
        )

        XCTAssertEqual(
            first.resolvedURL()?.standardizedFileURL.resolvingSymlinksInPath().path,
            second.resolvedURL()?.standardizedFileURL.resolvingSymlinksInPath().path
        )
        XCTAssertTrue(first.hasSameIdentity(as: second))
    }

    func testSameFileSystemTargetAndModeHasSameBindingIdentity() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Shared.txt")
        let symlinkURL = temporaryDirectory.appendingPathComponent("Alias.txt")
        try Data("value".utf8).write(to: fileURL)
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: fileURL
        )
        let first = try ManagedFileSystemItem(url: fileURL)
        let second = try ManagedFileSystemItem(url: symlinkURL)

        XCTAssertTrue(
            HotkeyTarget.file(first, .systemDefault)
                .hasSameBindingIdentity(as: .file(second, .systemDefault))
        )
    }

    func testSameFileSystemTargetWithDifferentModesIsNotDuplicate() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Shared.txt")
        try Data("value".utf8).write(to: fileURL)
        let item = try ManagedFileSystemItem(url: fileURL)
        let application = makeApplication(
            bundleIdentifier: "com.example.handler",
            path: temporaryDirectory.appendingPathComponent("Handler.app")
        )

        XCTAssertFalse(
            HotkeyTarget.file(item, .systemDefault)
                .hasSameBindingIdentity(as: .file(item, .application(application)))
        )
    }

    func testEquivalentApplicationsMakeSelectedHandlerModesIdentical() throws {
        let folderURL = temporaryDirectory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let item = try ManagedFileSystemItem(url: folderURL)
        let firstHandler = makeApplication(
            name: "First Handler",
            bundleIdentifier: "com.example.handler",
            path: temporaryDirectory.appendingPathComponent("First Handler.app"),
            bookmarkData: Data("first handler bookmark".utf8)
        )
        let secondHandler = makeApplication(
            name: "Second Handler",
            bundleIdentifier: "com.example.handler",
            path: temporaryDirectory.appendingPathComponent("Second Handler.app"),
            bookmarkData: Data("second handler bookmark".utf8)
        )

        XCTAssertTrue(
            HotkeyTarget.folder(item, .application(firstHandler))
                .hasSameBindingIdentity(
                    as: .folder(item, .application(secondHandler))
                )
        )
    }

    func testFolderAndFileCasesNeverHaveSameBindingIdentity() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Target")
        try Data("value".utf8).write(to: targetURL)
        let item = try ManagedFileSystemItem(url: targetURL)

        XCTAssertFalse(
            HotkeyTarget.folder(item, .finderNewTab)
                .hasSameBindingIdentity(as: .file(item, .systemDefault))
        )
    }

    private func makeItem(path: URL) -> ManagedFileSystemItem {
        ManagedFileSystemItem(
            displayName: path.lastPathComponent,
            fallbackPath: path.path,
            bookmarkData: Data("bookmark".utf8)
        )
    }

    private func makeApplication(
        name: String = "Application",
        bundleIdentifier: String?,
        path: URL,
        bookmarkData: Data = Data("bookmark".utf8)
    ) -> ManagedApplication {
        ManagedApplication(
            displayName: name,
            bundleIdentifier: bundleIdentifier,
            fallbackPath: path.path,
            bookmarkData: bookmarkData
        )
    }

    private func jsonObject<T: Encodable>(for value: T) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
                as? [String: Any]
        )
    }

    private func jsonData(for object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func assertDecodingFails<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try JSONDecoder().decode(type, from: data),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(error is DecodingError, file: file, line: line)
        }
    }
}
