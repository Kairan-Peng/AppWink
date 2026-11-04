import Foundation

/// 持久化后的应用描述，既保存展示信息，也保存可恢复访问权限的书签数据。
public struct ManagedApplication: Codable, Hashable, Sendable {
    public let displayName: String
    public let bundleIdentifier: String?
    public let fallbackPath: String
    /// 通过 bookmark 在应用被移动后尽量继续定位目标 `.app`。
    public let bookmarkData: Data

    public init(displayName: String, bundleIdentifier: String?, fallbackPath: String, bookmarkData: Data) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.fallbackPath = fallbackPath
        self.bookmarkData = bookmarkData
    }

    /// 从用户选中的应用包构造持久化模型，并优先提取更友好的展示名称。
    public init(url: URL) throws {
        let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let bundle = Bundle(url: url)
        let displayName = Self.resolvedDisplayName(
            for: .system,
            bundle: bundle,
            fallbackPath: url.path,
            storedDisplayName: nil
        )

        self.init(
            displayName: displayName,
            bundleIdentifier: bundle?.bundleIdentifier,
            fallbackPath: url.path,
            bookmarkData: bookmarkData)
    }

    public func localizedDisplayName(
        for language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        guard let resolvedURL = resolvedURL() else {
            return displayName
        }

        return Self.resolvedDisplayName(
            for: language,
            bundle: Bundle(url: resolvedURL),
            fallbackPath: resolvedURL.path,
            storedDisplayName: displayName,
            preferredLanguages: preferredLanguages
        )
    }

    /// 先尝试通过 bookmark 恢复真实位置；若书签失效，再回退到当时保存的路径。
    public func resolvedURL() -> URL? {
        var isStale = false

        if let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ),
           FileManager.default.fileExists(atPath: resolvedURL.path) {
            return resolvedURL
        }

        guard let fallbackURL = validatedFallbackURL else {
            return nil
        }

        return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }

    public func hasSameIdentity(as other: ManagedApplication) -> Bool {
        if let bundleIdentifier = bundleIdentifier.nonEmpty,
           let otherBundleIdentifier = other.bundleIdentifier.nonEmpty {
            return bundleIdentifier == otherBundleIdentifier
        }

        guard let url = resolvedURL() ?? validatedFallbackURL,
              let otherURL = other.resolvedURL() ?? other.validatedFallbackURL else {
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

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func resolvedDisplayName(
        for language: AppLanguage,
        bundle: Bundle?,
        fallbackPath: String,
        storedDisplayName: String?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        guard let bundle else {
            return storedDisplayName.nonEmpty ?? FileManager.default.displayName(atPath: fallbackPath)
        }

        let localizedBundle = LocalizationManager.localizedBundle(
            for: language,
            in: bundle,
            preferredLanguages: preferredLanguages
        )
        if let localizedDisplayName = localizedInfoPlistDisplayName(in: localizedBundle) {
            return localizedDisplayName
        }

        return rawInfoDictionaryDisplayName(in: bundle) ??
            storedDisplayName.nonEmpty ??
            FileManager.default.displayName(atPath: fallbackPath)
    }

    private static func localizedInfoPlistDisplayName(in bundle: Bundle) -> String? {
        displayNameKeys
            .lazy
            .map { key in
                bundle.localizedString(forKey: key, value: key, table: "InfoPlist")
            }
            .first(where: { value in
                !value.isEmpty && !displayNameKeys.contains(value)
            })
    }

    private static func rawInfoDictionaryDisplayName(in bundle: Bundle) -> String? {
        displayNameKeys
            .lazy
            .compactMap { bundle.infoDictionary?[$0] as? String }
            .first(where: { !$0.isEmpty })
    }

    private static let displayNameKeys = [
        "CFBundleDisplayName",
        kCFBundleNameKey as String,
    ]
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else {
            return nil
        }

        return self
    }
}
