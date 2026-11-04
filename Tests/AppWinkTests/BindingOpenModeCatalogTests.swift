import Foundation
import XCTest
@testable import AppWinkRuntime

@MainActor
final class BindingOpenModeCatalogTests: XCTestCase {
    func testSystemDefaultApplicationReadsProviderEveryTime() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = try makeApplication(
            named: "First",
            bundleIdentifier: "com.example.first",
            in: directory
        )
        let secondURL = try makeApplication(
            named: "Second",
            bundleIdentifier: "com.example.second",
            in: directory
        )
        var currentURL = firstURL
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in currentURL },
            applicationURLs: { _ in [] }
        )
        let targetURL = directory.appendingPathComponent("Document.txt")

        XCTAssertEqual(
            catalog.systemDefaultApplication(for: targetURL)?.bundleIdentifier,
            "com.example.first"
        )

        currentURL = secondURL

        XCTAssertEqual(
            catalog.systemDefaultApplication(for: targetURL)?.bundleIdentifier,
            "com.example.second"
        )
    }

    func testApplicationCandidatesDeduplicateIdentityAndSortStably() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zuluURL = try makeApplication(
            named: "zulu",
            bundleIdentifier: "com.example.zulu",
            in: directory
        )
        let alphaURL = try makeApplication(
            named: "Alpha",
            bundleIdentifier: "com.example.alpha",
            in: directory
        )
        let duplicateZuluURL = try makeApplication(
            named: "Duplicate Zulu",
            bundleIdentifier: "com.example.zulu",
            in: directory
        )
        let betaURL = try makeApplication(
            named: "beta",
            bundleIdentifier: nil,
            in: directory
        )
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in nil },
            applicationURLs: { _ in
                [zuluURL, alphaURL, zuluURL, duplicateZuluURL, betaURL]
            }
        )

        let candidates = catalog.applicationCandidates(
            for: directory.appendingPathComponent("Document.txt")
        )

        XCTAssertEqual(candidates.map(\.displayName), ["Alpha", "beta", "zulu"])
        XCTAssertEqual(
            candidates.map(\.bundleIdentifier),
            ["com.example.alpha", nil, "com.example.zulu"]
        )
    }

    func testInvalidApplicationURLsAreIgnored() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingURL = directory.appendingPathComponent("Missing.app")
        let validURL = try makeApplication(
            named: "Valid",
            bundleIdentifier: "com.example.valid",
            in: directory
        )
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in missingURL },
            applicationURLs: { _ in [missingURL, validURL] }
        )
        let targetURL = directory.appendingPathComponent("Document.txt")

        XCTAssertNil(catalog.systemDefaultApplication(for: targetURL))
        XCTAssertEqual(
            catalog.applicationCandidates(for: targetURL).map(\.bundleIdentifier),
            ["com.example.valid"]
        )
    }

    func testSystemDefaultApplicationIgnoresExistingNonApplicationURL() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ordinaryFileURL = directory.appendingPathComponent("Notes.txt")
        try Data("value".utf8).write(to: ordinaryFileURL)
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in ordinaryFileURL },
            applicationURLs: { _ in [] }
        )

        XCTAssertNil(
            catalog.systemDefaultApplication(
                for: directory.appendingPathComponent("Document.txt")
            )
        )
    }

    func testApplicationCandidatesIgnoreExistingNonApplicationURLs() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ordinaryFileURL = directory.appendingPathComponent("Notes.txt")
        try Data("value".utf8).write(to: ordinaryFileURL)
        let ordinaryDirectoryURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: ordinaryDirectoryURL,
            withIntermediateDirectories: true
        )
        let validURL = try makeApplication(
            named: "Valid",
            bundleIdentifier: "com.example.valid",
            in: directory
        )
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in nil },
            applicationURLs: { _ in
                [ordinaryFileURL, ordinaryDirectoryURL, validURL]
            }
        )

        XCTAssertEqual(
            catalog.applicationCandidates(
                for: directory.appendingPathComponent("Document.txt")
            ).map(\.bundleIdentifier),
            ["com.example.valid"]
        )
    }

    func testEmptyApplicationCandidatesReturnsEmptyArray() {
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in nil },
            applicationURLs: { _ in [] }
        )

        XCTAssertTrue(
            catalog.applicationCandidates(
                for: URL(fileURLWithPath: "/tmp/Document.txt")
            ).isEmpty
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeApplication(
        named name: String,
        bundleIdentifier: String?,
        in directory: URL
    ) throws -> URL {
        let applicationURL = directory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )

        var infoPlist: [String: Any] = [
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
        ]
        infoPlist["CFBundleIdentifier"] = bundleIdentifier
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
