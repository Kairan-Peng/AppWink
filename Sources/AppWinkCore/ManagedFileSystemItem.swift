import Foundation

public struct ManagedFileSystemItem: Codable, Hashable, Sendable {
    public struct Resolution: Sendable {
        public let url: URL
        public let bookmarkIsStale: Bool
    }

    public let displayName: String
    public let fallbackPath: String
    public let bookmarkData: Data

    public init(displayName: String, fallbackPath: String, bookmarkData: Data) {
        self.displayName = displayName
        self.fallbackPath = fallbackPath
        self.bookmarkData = bookmarkData
    }

    public init(url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        self.init(
            displayName: FileManager.default.displayName(atPath: url.path),
            fallbackPath: url.path,
            bookmarkData: bookmarkData
        )
    }

    public func resolve() -> Resolution? {
        resolve(bookmarkResolver: { bookmarkData, bookmarkIsStale in
            try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkIsStale
            )
        })
    }

    func resolve(
        bookmarkResolver: (Data, inout Bool) throws -> URL
    ) -> Resolution? {
        var bookmarkIsStale = false
        if let url = try? bookmarkResolver(bookmarkData, &bookmarkIsStale) {
            return Resolution(url: url, bookmarkIsStale: bookmarkIsStale)
        }

        guard let fallbackURL = validatedFallbackURL,
              FileManager.default.fileExists(atPath: fallbackURL.path) else {
            return nil
        }

        return Resolution(url: fallbackURL, bookmarkIsStale: false)
    }

    public func resolvedDisplayName() -> String {
        guard let resolution = resolve() else {
            return displayName
        }

        return FileManager.default.displayName(atPath: resolution.url.path)
    }

    public func refreshingBookmarkIfNeeded(
        for resolution: Resolution
    ) throws -> ManagedFileSystemItem? {
        guard resolution.bookmarkIsStale else {
            return nil
        }

        return try ManagedFileSystemItem(url: resolution.url)
    }

    public func hasSameIdentity(as other: ManagedFileSystemItem) -> Bool {
        hasSameIdentity(as: other, resourceIdentifier: Self.resourceIdentifier)
    }

    func hasSameIdentity(
        as other: ManagedFileSystemItem,
        resourceIdentifier: (URL) -> NSObject?
    ) -> Bool {
        let resolvedURL = resolve()?.url
        let otherResolvedURL = other.resolve()?.url

        if let resolvedURL,
           let otherResolvedURL,
           let identifier = resourceIdentifier(resolvedURL),
           let otherIdentifier = resourceIdentifier(otherResolvedURL) {
            return identifier.isEqual(otherIdentifier)
        }

        guard let url = resolvedURL ?? validatedFallbackURL,
              let otherURL = otherResolvedURL ?? other.validatedFallbackURL else {
            return false
        }

        return Self.canonicalURL(url).path == Self.canonicalURL(otherURL).path
    }

    private var validatedFallbackURL: URL? {
        guard !fallbackPath.isEmpty,
              (fallbackPath as NSString).isAbsolutePath else {
            return nil
        }

        return URL(fileURLWithPath: fallbackPath)
    }

    private static func resourceIdentifier(for url: URL) -> NSObject? {
        let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
        return values?.fileResourceIdentifier as? NSObject
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
