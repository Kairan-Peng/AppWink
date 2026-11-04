import AppKit
import Foundation
import AppWinkCore

struct BindingOpenModeCatalog {
    private let systemDefaultApplicationURL: (URL) -> URL?
    private let applicationURLs: (URL) -> [URL]

    init(
        systemDefaultApplicationURL: @escaping (URL) -> URL? = {
            NSWorkspace.shared.urlForApplication(toOpen: $0)
        },
        applicationURLs: @escaping (URL) -> [URL] = {
            NSWorkspace.shared.urlsForApplications(toOpen: $0)
        }
    ) {
        self.systemDefaultApplicationURL = systemDefaultApplicationURL
        self.applicationURLs = applicationURLs
    }

    func systemDefaultApplication(for targetURL: URL) -> ManagedApplication? {
        systemDefaultApplicationURL(targetURL).flatMap(application)
    }

    func applicationCandidates(for targetURL: URL) -> [ManagedApplication] {
        var candidates: [ManagedApplication] = []

        for application in applicationURLs(targetURL).compactMap(application)
        where !candidates.contains(where: {
            $0.hasSameIdentity(as: application)
        }) {
            candidates.append(application)
        }

        return candidates.enumerated().sorted { lhs, rhs in
            let comparison = lhs.element.displayName.localizedCaseInsensitiveCompare(
                rhs.element.displayName
            )
            return comparison == .orderedSame
                ? lhs.offset < rhs.offset
                : comparison == .orderedAscending
        }.map(\.element)
    }

    func application(at url: URL) -> ManagedApplication? {
        guard Bundle(url: url)?
            .object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else {
            return nil
        }

        return try? ManagedApplication(url: url)
    }
}
