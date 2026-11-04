import Foundation

import XCTest
@testable import AppWinkCore

final class ManagedApplicationTests: XCTestCase {
    func testInvalidBookmarkWithEmptyFallbackDoesNotResolveCurrentDirectory() {
        let application = ManagedApplication(
            displayName: "Missing",
            bundleIdentifier: nil,
            fallbackPath: "",
            bookmarkData: Data("invalid bookmark".utf8)
        )

        XCTAssertNil(application.resolvedURL())
    }

    func testInvalidBookmarkWithRelativeFallbackDoesNotResolveCurrentDirectory() {
        let relativePath = "Package.swift"
        XCTAssertTrue(FileManager.default.fileExists(atPath: relativePath))
        let application = ManagedApplication(
            displayName: "Missing",
            bundleIdentifier: nil,
            fallbackPath: relativePath,
            bookmarkData: Data("invalid bookmark".utf8)
        )

        XCTAssertNil(application.resolvedURL())
    }

    func testInvalidApplicationsDoNotShareFallbackIdentity() {
        let firstEmpty = ManagedApplication(
            displayName: "First",
            bundleIdentifier: nil,
            fallbackPath: "",
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let secondEmpty = ManagedApplication(
            displayName: "Second",
            bundleIdentifier: nil,
            fallbackPath: "",
            bookmarkData: Data("invalid second bookmark".utf8)
        )
        let firstRelative = ManagedApplication(
            displayName: "First",
            bundleIdentifier: nil,
            fallbackPath: "Package.swift",
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let secondRelative = ManagedApplication(
            displayName: "Second",
            bundleIdentifier: nil,
            fallbackPath: "Package.swift",
            bookmarkData: Data("invalid second bookmark".utf8)
        )

        XCTAssertFalse(firstEmpty.hasSameIdentity(as: secondEmpty))
        XCTAssertFalse(firstRelative.hasSameIdentity(as: secondRelative))
    }

    func testUnavailableAbsoluteFallbacksWithSameCanonicalPathShareIdentity() {
        let baseDirectoryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let canonicalPath = "\(baseDirectoryPath)/Missing.app"
        let equivalentPath = "\(baseDirectoryPath)/Nested/../Missing.app/"
        let first = ManagedApplication(
            displayName: "First",
            bundleIdentifier: nil,
            fallbackPath: canonicalPath,
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let second = ManagedApplication(
            displayName: "Second",
            bundleIdentifier: nil,
            fallbackPath: equivalentPath,
            bookmarkData: Data("invalid second bookmark".utf8)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: equivalentPath))
        XCTAssertTrue(first.hasSameIdentity(as: second))
    }

    func testDifferentUnavailableAbsoluteFallbacksDoNotShareIdentity() {
        let baseDirectoryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let first = ManagedApplication(
            displayName: "First",
            bundleIdentifier: nil,
            fallbackPath: "\(baseDirectoryPath)/First.app",
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let second = ManagedApplication(
            displayName: "Second",
            bundleIdentifier: nil,
            fallbackPath: "\(baseDirectoryPath)/Second.app",
            bookmarkData: Data("invalid second bookmark".utf8)
        )

        XCTAssertFalse(first.hasSameIdentity(as: second))
    }

    func testMatchingBundleIdentifiersRemainIdenticalWithoutResolvableURLs() {
        let first = ManagedApplication(
            displayName: "First",
            bundleIdentifier: "com.example.shared",
            fallbackPath: "",
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let second = ManagedApplication(
            displayName: "Second",
            bundleIdentifier: "com.example.shared",
            fallbackPath: "Package.swift",
            bookmarkData: Data("invalid second bookmark".utf8)
        )

        XCTAssertTrue(first.hasSameIdentity(as: second))
    }

    func testLocalizedDisplayNameFollowsExplicitAppLanguage() throws {
        let applicationURL = try makeLocalizedApplicationBundle(
            baseDisplayName: "Base Utility",
            englishDisplayName: "English Utility",
            chineseDisplayName: "中文工具",
            chineseLocalizationName: "zh-Hans"
        )
        defer { try? FileManager.default.removeItem(at: applicationURL) }

        let application = try ManagedApplication(url: applicationURL)

        XCTAssertEqual(application.localizedDisplayName(for: .english), "English Utility")
        XCTAssertEqual(application.localizedDisplayName(for: .chinese), "中文工具")
    }

    func testLocalizedDisplayNameSupportsMacOSChineseLprojAlias() throws {
        let applicationURL = try makeLocalizedApplicationBundle(
            baseDisplayName: "Base Utility",
            englishDisplayName: "English Utility",
            chineseDisplayName: "中文工具",
            chineseLocalizationName: "zh_CN"
        )
        defer { try? FileManager.default.removeItem(at: applicationURL) }

        let application = try ManagedApplication(url: applicationURL)

        XCTAssertEqual(application.localizedDisplayName(for: .chinese), "中文工具")
    }

    func testLocalizedDisplayNameFollowsSystemPreferredLanguage() throws {
        let applicationURL = try makeLocalizedApplicationBundle(
            baseDisplayName: "Base Utility",
            englishDisplayName: "English Utility",
            chineseDisplayName: "中文工具",
            chineseLocalizationName: "zh_CN"
        )
        defer { try? FileManager.default.removeItem(at: applicationURL) }

        let application = try ManagedApplication(url: applicationURL)

        XCTAssertEqual(
            application.localizedDisplayName(for: .system, preferredLanguages: ["zh-Hans-CN"]),
            "中文工具"
        )
        XCTAssertEqual(
            application.localizedDisplayName(for: .system, preferredLanguages: ["en-US"]),
            "English Utility"
        )
    }

    private func makeLocalizedApplicationBundle(
        baseDisplayName: String,
        englishDisplayName: String,
        chineseDisplayName: String,
        chineseLocalizationName: String
    ) throws -> URL {
        let applicationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let contentsURL = applicationURL.appendingPathComponent("Contents")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let infoPlist: [String: Any] = [
            "CFBundleDisplayName": baseDisplayName,
            "CFBundleName": baseDisplayName,
            "CFBundleIdentifier": "com.example.\(UUID().uuidString)"
        ]
        let infoPlistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try infoPlistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        try writeInfoPlistStrings(
            displayName: englishDisplayName,
            to: resourcesURL.appendingPathComponent("en.lproj")
        )
        try writeInfoPlistStrings(
            displayName: chineseDisplayName,
            to: resourcesURL.appendingPathComponent("\(chineseLocalizationName).lproj")
        )

        return applicationURL
    }

    private func writeInfoPlistStrings(displayName: String, to localizationURL: URL) throws {
        try FileManager.default.createDirectory(at: localizationURL, withIntermediateDirectories: true)
        let strings = """
        "CFBundleDisplayName" = "\(displayName)";
        "CFBundleName" = "\(displayName)";
        """
        try strings.write(
            to: localizationURL.appendingPathComponent("InfoPlist.strings"),
            atomically: true,
            encoding: .utf8
        )
    }
}
