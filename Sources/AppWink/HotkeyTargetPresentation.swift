import AppKit
import AppWinkCore
import Foundation

enum HotkeyTargetAvailability: Hashable {
    case available
    case targetUnavailable
    case openingApplicationUnavailable
}

extension HotkeyTargetKind {
    var fallbackSymbolName: String {
        switch self {
        case .application:
            "app.fill"
        case .folder:
            "folder.fill"
        case .file:
            "doc.fill"
        }
    }
}

struct HotkeyTargetPresentation {
    struct OpeningMode {
        let label: String
        let image: NSImage?
        let fallbackSymbolName: String
    }

    struct ApplicationOption: Identifiable {
        enum ID: Hashable {
            case bundleIdentifier(String)
            case canonicalPath(String)
        }

        let id: ID
        let application: ManagedApplication
        let displayName: String
        let image: NSImage?
        let isSelected: Bool
    }

    let displayName: String
    let targetImage: NSImage?
    let fallbackSymbolName: String
    let openingMode: OpeningMode?
    let finderOpeningMode: OpeningMode?
    let systemDefaultOpeningMode: OpeningMode?
    let applicationCandidates: [ApplicationOption]
    let accessibilityValue: String
    let availability: HotkeyTargetAvailability
}

struct HotkeyTargetPresentationResolver {
    private let catalog: BindingOpenModeCatalog
    private let resolveFileSystemItemURL: (ManagedFileSystemItem) -> URL?
    private let startAccessingSecurityScopedResource: (URL) -> Bool
    private let stopAccessingSecurityScopedResource: (URL) -> Void
    private let fileExistsAtPath: (String) -> Bool
    private let displayNameAtURL: (URL) -> String
    private let iconForURL: (URL) -> NSImage
    private let finderApplicationURL: () -> URL?

    init(
        catalog: BindingOpenModeCatalog = BindingOpenModeCatalog(),
        resolveFileSystemItemURL: @escaping (ManagedFileSystemItem) -> URL? = {
            Self.resolveFileSystemItemURL($0)
        },
        startAccessingSecurityScopedResource: @escaping (URL) -> Bool = {
            $0.startAccessingSecurityScopedResource()
        },
        stopAccessingSecurityScopedResource: @escaping (URL) -> Void = {
            $0.stopAccessingSecurityScopedResource()
        },
        fileExistsAtPath: @escaping (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        displayNameAtURL: @escaping (URL) -> String = {
            FileManager.default.displayName(atPath: $0.path)
        },
        iconForURL: @escaping (URL) -> NSImage = {
            NSWorkspace.shared.icon(forFile: $0.path)
        },
        finderApplicationURL: @escaping () -> URL? = {
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.finder"
            )
        }
    ) {
        self.catalog = catalog
        self.resolveFileSystemItemURL = resolveFileSystemItemURL
        self.startAccessingSecurityScopedResource =
            startAccessingSecurityScopedResource
        self.stopAccessingSecurityScopedResource =
            stopAccessingSecurityScopedResource
        self.fileExistsAtPath = fileExistsAtPath
        self.displayNameAtURL = displayNameAtURL
        self.iconForURL = iconForURL
        self.finderApplicationURL = finderApplicationURL
    }

    func resolve(
        binding: HotkeyBinding,
        availability requestedAvailability: HotkeyTargetAvailability,
        language: AppLanguage,
        localizationBundle: Bundle
    ) -> HotkeyTargetPresentation {
        guard requestedAvailability != .targetUnavailable else {
            return unavailableTargetPresentation(
                binding: binding,
                language: language,
                bundle: localizationBundle
            )
        }

        switch binding.target {
        case .application(let application):
            return applicationTargetPresentation(
                binding: binding,
                application: application,
                availability: requestedAvailability,
                language: language,
                bundle: localizationBundle
            )
        case .folder(let item, _), .file(let item, _):
            guard let targetURL = resolveFileSystemItemURL(item) else {
                return unavailableTargetPresentation(
                    binding: binding,
                    language: language,
                    bundle: localizationBundle
                )
            }

            let didStartAccess =
                startAccessingSecurityScopedResource(targetURL)
            defer {
                if didStartAccess {
                    stopAccessingSecurityScopedResource(targetURL)
                }
            }

            guard fileExistsAtPath(targetURL.path) else {
                return unavailableTargetPresentation(
                    binding: binding,
                    language: language,
                    bundle: localizationBundle
                )
            }

            return fileSystemTargetPresentation(
                binding: binding,
                targetURL: targetURL,
                availability: requestedAvailability,
                language: language,
                bundle: localizationBundle
            )
        }
    }

    private func applicationTargetPresentation(
        binding: HotkeyBinding,
        application: ManagedApplication,
        availability: HotkeyTargetAvailability,
        language: AppLanguage,
        bundle: Bundle
    ) -> HotkeyTargetPresentation {
        guard let applicationURL = application.resolvedURL() else {
            return unavailableTargetPresentation(
                binding: binding,
                language: language,
                bundle: bundle
            )
        }

        let displayName = binding.source == .activityMonitorFeature
            ? localized(.activityMonitor, bundle: bundle)
            : application.localizedDisplayName(for: language)
        return makePresentation(
            binding: binding,
            displayName: displayName,
            targetImage: iconForURL(applicationURL),
            availability: availability,
            language: language,
            bundle: bundle,
            systemDefaultApplication: nil,
            candidates: []
        )
    }

    private func fileSystemTargetPresentation(
        binding: HotkeyBinding,
        targetURL: URL,
        availability: HotkeyTargetAvailability,
        language: AppLanguage,
        bundle: Bundle
    ) -> HotkeyTargetPresentation {
        let systemDefaultApplication: ManagedApplication?
        let candidates: [ManagedApplication]
        switch binding.target {
        case .application:
            systemDefaultApplication = nil
            candidates = []
        case .folder:
            systemDefaultApplication = nil
            candidates = catalog.applicationCandidates(for: targetURL)
        case .file:
            systemDefaultApplication =
                catalog.systemDefaultApplication(for: targetURL)
            candidates = catalog.applicationCandidates(for: targetURL)
        }

        return makePresentation(
            binding: binding,
            displayName: displayNameAtURL(targetURL),
            targetImage: iconForURL(targetURL),
            availability: availability,
            language: language,
            bundle: bundle,
            systemDefaultApplication: systemDefaultApplication,
            candidates: candidates
        )
    }

    private func unavailableTargetPresentation(
        binding: HotkeyBinding,
        language: AppLanguage,
        bundle: Bundle
    ) -> HotkeyTargetPresentation {
        makePresentation(
            binding: binding,
            displayName: storedDisplayName(for: binding),
            targetImage: nil,
            availability: .targetUnavailable,
            language: language,
            bundle: bundle,
            systemDefaultApplication: nil,
            candidates: []
        )
    }

    private func makePresentation(
        binding: HotkeyBinding,
        displayName: String,
        targetImage: NSImage?,
        availability: HotkeyTargetAvailability,
        language: AppLanguage,
        bundle: Bundle,
        systemDefaultApplication: ManagedApplication?,
        candidates: [ManagedApplication]
    ) -> HotkeyTargetPresentation {
        let systemDefaultOpeningMode = systemDefaultOpeningMode(
            application: systemDefaultApplication,
            language: language,
            bundle: bundle
        )
        let finderOpeningMode: HotkeyTargetPresentation.OpeningMode?
        if case .folder = binding.target {
            finderOpeningMode = HotkeyTargetPresentation.OpeningMode(
                label: localized(.finderNewTab, bundle: bundle),
                image: finderApplicationURL().map(iconForURL),
                fallbackSymbolName: "folder"
            )
        } else {
            finderOpeningMode = nil
        }
        let openingMode = openingMode(
            for: binding.target,
            availability: availability,
            language: language,
            bundle: bundle,
            finderOpeningMode: finderOpeningMode,
            systemDefaultOpeningMode: systemDefaultOpeningMode
        )
        let selectedApplicationID =
            selectedApplication(for: binding.target).map(applicationID)
        let applicationOptions = candidates.map { application in
            applicationOption(
                application,
                selectedApplicationID: selectedApplicationID,
                language: language
            )
        }
        let targetDescription = availability == .targetUnavailable
            ? localized(.targetUnavailable, bundle: bundle)
            : displayName
        let modeTitle: String
        let modeDescription: String
        if let openingMode {
            modeTitle = localized(.openWith, bundle: bundle)
            modeDescription = openingMode.label
        } else {
            modeTitle = localized(.action, bundle: bundle)
            modeDescription = localized(.applicationToggle, bundle: bundle)
        }

        return HotkeyTargetPresentation(
            displayName: displayName,
            targetImage: targetImage,
            fallbackSymbolName: binding.target.kind.fallbackSymbolName,
            openingMode: openingMode,
            finderOpeningMode: finderOpeningMode,
            systemDefaultOpeningMode: binding.target.kind == .file
                ? systemDefaultOpeningMode
                : nil,
            applicationCandidates: applicationOptions,
            accessibilityValue: localized(
                .targetAccessibilityValue,
                bundle: bundle,
                arguments: targetKind(binding.target.kind, bundle: bundle),
                targetDescription,
                modeTitle,
                modeDescription
            ),
            availability: availability
        )
    }

    private func openingMode(
        for target: HotkeyTarget,
        availability: HotkeyTargetAvailability,
        language: AppLanguage,
        bundle: Bundle,
        finderOpeningMode: HotkeyTargetPresentation.OpeningMode?,
        systemDefaultOpeningMode: HotkeyTargetPresentation.OpeningMode
    ) -> HotkeyTargetPresentation.OpeningMode? {
        switch target {
        case .application:
            return nil
        case .folder(_, .finderNewTab):
            return finderOpeningMode
        case .folder(_, .application(let application)),
             .file(_, .application(let application)):
            guard availability != .openingApplicationUnavailable else {
                return unavailableOpeningApplicationMode(bundle: bundle)
            }
            return applicationOpeningMode(
                application,
                language: language,
                bundle: bundle
            )
        case .file(_, .systemDefault):
            return systemDefaultOpeningMode
        }
    }

    private func systemDefaultOpeningMode(
        application: ManagedApplication?,
        language: AppLanguage,
        bundle: Bundle
    ) -> HotkeyTargetPresentation.OpeningMode {
        guard let application,
              let applicationURL = application.resolvedURL() else {
            return HotkeyTargetPresentation.OpeningMode(
                label: localized(
                    .systemDefaultApplication,
                    bundle: bundle,
                    arguments: localized(
                        .openingApplicationUnavailable,
                        bundle: bundle
                    )
                ),
                image: nil,
                fallbackSymbolName: "app.fill"
            )
        }

        return HotkeyTargetPresentation.OpeningMode(
            label: localized(
                .systemDefaultApplication,
                bundle: bundle,
                arguments: application.localizedDisplayName(for: language)
            ),
            image: iconForURL(applicationURL),
            fallbackSymbolName: "app.fill"
        )
    }

    private func applicationOpeningMode(
        _ application: ManagedApplication,
        language: AppLanguage,
        bundle: Bundle
    ) -> HotkeyTargetPresentation.OpeningMode {
        guard let applicationURL = application.resolvedURL() else {
            return unavailableOpeningApplicationMode(bundle: bundle)
        }

        return HotkeyTargetPresentation.OpeningMode(
            label: application.localizedDisplayName(for: language),
            image: iconForURL(applicationURL),
            fallbackSymbolName: "app.fill"
        )
    }

    private func unavailableOpeningApplicationMode(
        bundle: Bundle
    ) -> HotkeyTargetPresentation.OpeningMode {
        HotkeyTargetPresentation.OpeningMode(
            label: localized(.openingApplicationUnavailable, bundle: bundle),
            image: nil,
            fallbackSymbolName: "app.fill"
        )
    }

    private func applicationOption(
        _ application: ManagedApplication,
        selectedApplicationID: HotkeyTargetPresentation.ApplicationOption.ID?,
        language: AppLanguage
    ) -> HotkeyTargetPresentation.ApplicationOption {
        let id = applicationID(application)
        let applicationURL = application.resolvedURL()
        return HotkeyTargetPresentation.ApplicationOption(
            id: id,
            application: application,
            displayName: application.localizedDisplayName(for: language),
            image: applicationURL.map(iconForURL),
            isSelected: id == selectedApplicationID
        )
    }

    private func applicationID(
        _ application: ManagedApplication
    ) -> HotkeyTargetPresentation.ApplicationOption.ID {
        if let bundleIdentifier = application.bundleIdentifier,
           !bundleIdentifier.isEmpty {
            return .bundleIdentifier(bundleIdentifier)
        }

        return .canonicalPath(
            (application.resolvedURL() ??
                URL(fileURLWithPath: application.fallbackPath))
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
        )
    }

    private func selectedApplication(
        for target: HotkeyTarget
    ) -> ManagedApplication? {
        switch target {
        case .folder(_, .application(let application)),
             .file(_, .application(let application)):
            application
        case .application, .folder(_, .finderNewTab), .file(_, .systemDefault):
            nil
        }
    }

    private func storedDisplayName(for binding: HotkeyBinding) -> String {
        switch binding.target {
        case .application(let application):
            return application.displayName
        case .folder(let item, _), .file(let item, _):
            return item.displayName
        }
    }

    private func targetKind(
        _ kind: HotkeyTargetKind,
        bundle: Bundle
    ) -> String {
        switch kind {
        case .application:
            localized(.targetKindApplication, bundle: bundle)
        case .folder:
            localized(.targetKindFolder, bundle: bundle)
        case .file:
            localized(.targetKindFile, bundle: bundle)
        }
    }

    private func localized(
        _ key: LocalizationKey,
        bundle: Bundle,
        arguments: CVarArg...
    ) -> String {
        let format = NSLocalizedString(key.rawValue, bundle: bundle, comment: "")
        return arguments.isEmpty
            ? format
            : String(format: format, arguments: arguments)
    }

    private static func resolveFileSystemItemURL(
        _ item: ManagedFileSystemItem
    ) -> URL? {
        var bookmarkIsStale = false
        if let url = try? URL(
            resolvingBookmarkData: item.bookmarkData,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ) {
            return url
        }

        guard !item.fallbackPath.isEmpty,
              (item.fallbackPath as NSString).isAbsolutePath else {
            return nil
        }
        return URL(fileURLWithPath: item.fallbackPath)
    }
}
