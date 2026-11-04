import Foundation

import XCTest
@testable import AppWinkCore

final class ManagedFileSystemItemTests: XCTestCase {
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

    func testInitializationCapturesMetadataAndResolvesFreshBookmark() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Original.txt")
        try Data("value".utf8).write(to: fileURL)

        let item = try ManagedFileSystemItem(url: fileURL)
        let resolution = try XCTUnwrap(item.resolve())

        XCTAssertEqual(item.displayName, FileManager.default.displayName(atPath: fileURL.path))
        XCTAssertEqual(item.fallbackPath, fileURL.path)
        XCTAssertFalse(item.bookmarkData.isEmpty)
        XCTAssertEqual(resolution.url.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertFalse(resolution.bookmarkIsStale)
    }

    func testResolvedBookmarkDoesNotRequireTargetToBeCurrentlyProbeable() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("External.txt")
        try Data("value".utf8).write(to: fileURL)
        let item = try ManagedFileSystemItem(url: fileURL)
        try FileManager.default.removeItem(at: fileURL)

        let resolution = try XCTUnwrap(
            item.resolve(bookmarkResolver: { _, bookmarkIsStale in
                bookmarkIsStale = false
                return fileURL
            })
        )

        XCTAssertEqual(
            resolution.url.standardizedFileURL.resolvingSymlinksInPath().path,
            fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    func testResolvedDisplayNameUsesCurrentFileName() throws {
        let originalURL = temporaryDirectory.appendingPathComponent("Before.txt")
        try Data("value".utf8).write(to: originalURL)
        let item = try ManagedFileSystemItem(url: originalURL)
        let renamedURL = temporaryDirectory.appendingPathComponent("After.txt")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)

        XCTAssertEqual(item.resolvedDisplayName(), "After.txt")
    }

    func testResolvedDisplayNameUsesStoredNameWhenItemIsUnavailable() {
        let item = ManagedFileSystemItem(
            displayName: "Remembered Name",
            fallbackPath: temporaryDirectory.appendingPathComponent("Missing.txt").path,
            bookmarkData: Data("invalid bookmark".utf8)
        )

        XCTAssertNil(item.resolve())
        XCTAssertEqual(item.resolvedDisplayName(), "Remembered Name")
    }

    func testInvalidBookmarkUsesExistingFallbackPathAsFreshResolution() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Fallback.txt")
        try Data("value".utf8).write(to: fileURL)
        let item = ManagedFileSystemItem(
            displayName: "Stored Name",
            fallbackPath: fileURL.path,
            bookmarkData: Data("invalid bookmark".utf8)
        )

        let resolution = try XCTUnwrap(item.resolve())

        XCTAssertEqual(resolution.url.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertFalse(resolution.bookmarkIsStale)
    }

    func testEmptyFallbackPathDoesNotResolveToCurrentDirectory() {
        let item = ManagedFileSystemItem(
            displayName: "Missing",
            fallbackPath: "",
            bookmarkData: Data("invalid bookmark".utf8)
        )

        XCTAssertNil(item.resolve())
    }

    func testRelativeFallbackPathDoesNotResolveAgainstCurrentDirectory() {
        let relativePath = "Package.swift"
        XCTAssertTrue(FileManager.default.fileExists(atPath: relativePath))
        let item = ManagedFileSystemItem(
            displayName: "Missing",
            fallbackPath: relativePath,
            bookmarkData: Data("invalid bookmark".utf8)
        )

        XCTAssertNil(item.resolve())
    }

    func testFreshResolutionDoesNotRefreshBookmark() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Fresh.txt")
        try Data("value".utf8).write(to: fileURL)
        let item = try ManagedFileSystemItem(url: fileURL)
        let resolution = try XCTUnwrap(item.resolve())

        XCTAssertFalse(resolution.bookmarkIsStale)
        XCTAssertNil(try item.refreshingBookmarkIfNeeded(for: resolution))
    }

    func testStaleResolutionRefreshesCurrentMetadataAndBookmark() throws {
        let originalURL = temporaryDirectory.appendingPathComponent("Before.txt")
        try Data("value".utf8).write(to: originalURL)
        let item = try ManagedFileSystemItem(url: originalURL)
        let renamedURL = temporaryDirectory.appendingPathComponent("After.txt")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        let staleResolution = try XCTUnwrap(item.resolve())

        XCTAssertTrue(staleResolution.bookmarkIsStale)

        let refreshed = try XCTUnwrap(
            item.refreshingBookmarkIfNeeded(for: staleResolution)
        )

        XCTAssertEqual(refreshed.displayName, "After.txt")
        XCTAssertEqual(refreshed.fallbackPath, staleResolution.url.path)
        XCTAssertNotEqual(refreshed.bookmarkData, item.bookmarkData)
        XCTAssertEqual(
            refreshed.resolve()?.url.standardizedFileURL.resolvingSymlinksInPath(),
            renamedURL.standardizedFileURL.resolvingSymlinksInPath()
        )
    }

    func testSameResourceWithDifferentBookmarksHasSameIdentity() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("Shared.txt")
        try Data("value".utf8).write(to: fileURL)
        let first = try ManagedFileSystemItem(url: fileURL)
        let secondBookmark = try fileURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: [.fileSizeKey],
            relativeTo: nil
        )
        let second = ManagedFileSystemItem(
            displayName: "Different Snapshot",
            fallbackPath: fileURL.path,
            bookmarkData: secondBookmark
        )

        XCTAssertNotEqual(first.bookmarkData, second.bookmarkData)
        XCTAssertTrue(first.hasSameIdentity(as: second))
    }

    func testSameFileReachedThroughSymlinkHasSameIdentity() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Target.txt")
        let symlinkURL = temporaryDirectory.appendingPathComponent("Alias.txt")
        try Data("value".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: targetURL
        )

        XCTAssertTrue(
            try ManagedFileSystemItem(url: targetURL)
                .hasSameIdentity(as: ManagedFileSystemItem(url: symlinkURL))
        )
    }

    func testIdentityFallsBackToCanonicalPathsWhenResourceIdentifiersAreUnavailable() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent("Target.txt")
        try Data("value".utf8).write(to: fileURL)
        let alternatePath = folderURL
            .appendingPathComponent("..")
            .appendingPathComponent("Folder")
            .appendingPathComponent("Target.txt")
        let first = ManagedFileSystemItem(
            displayName: "First",
            fallbackPath: fileURL.path,
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let second = ManagedFileSystemItem(
            displayName: "Second",
            fallbackPath: alternatePath.path,
            bookmarkData: Data("invalid second bookmark".utf8)
        )

        XCTAssertTrue(
            first.hasSameIdentity(as: second, resourceIdentifier: { _ in nil })
        )
    }

    func testCanonicalPathFallbackIgnoresDirectoryURLTrailingSlash() throws {
        let folderURL = temporaryDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let first = ManagedFileSystemItem(
            displayName: "Folder",
            fallbackPath: folderURL.path,
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let second = ManagedFileSystemItem(
            displayName: "Folder",
            fallbackPath: folderURL.path + "/",
            bookmarkData: Data("invalid second bookmark".utf8)
        )

        XCTAssertTrue(
            first.hasSameIdentity(as: second, resourceIdentifier: { _ in nil })
        )
    }

    func testUnavailableItemsUseCanonicalFallbackIdentity() {
        let first = ManagedFileSystemItem(
            displayName: "First",
            fallbackPath: temporaryDirectory
                .appendingPathComponent("Unused")
                .appendingPathComponent("..")
                .appendingPathComponent("Missing")
                .path,
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let second = ManagedFileSystemItem(
            displayName: "Second",
            fallbackPath: temporaryDirectory.appendingPathComponent("Missing").path + "/",
            bookmarkData: Data("invalid second bookmark".utf8)
        )

        XCTAssertNil(first.resolve())
        XCTAssertNil(second.resolve())
        XCTAssertTrue(first.hasSameIdentity(as: second))
    }

    func testUnavailableItemsWithDifferentFallbacksHaveDifferentIdentity() {
        let first = ManagedFileSystemItem(
            displayName: "First",
            fallbackPath: temporaryDirectory.appendingPathComponent("First Missing").path,
            bookmarkData: Data("invalid first bookmark".utf8)
        )
        let second = ManagedFileSystemItem(
            displayName: "Second",
            fallbackPath: temporaryDirectory.appendingPathComponent("Second Missing").path,
            bookmarkData: Data("invalid second bookmark".utf8)
        )

        XCTAssertNil(first.resolve())
        XCTAssertNil(second.resolve())
        XCTAssertFalse(first.hasSameIdentity(as: second))
    }
}
