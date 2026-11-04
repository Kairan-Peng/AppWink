import Foundation
import UniformTypeIdentifiers

public enum HotkeyTargetFactory {
    public static func classify(_ url: URL) throws -> HotkeyTargetKind {
        if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            return .application
        }

        let values = try url.resourceValues(
            forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey]
        )

        if values.contentType?.conforms(to: .applicationBundle) == true {
            return .application
        }

        if values.isDirectory == true && values.isPackage != true {
            return .folder
        }

        return .file
    }

    public static func makeTarget(for url: URL) throws -> HotkeyTarget {
        switch try classify(url) {
        case .application:
            return .application(try ManagedApplication(url: url))
        case .folder:
            return .folder(
                try ManagedFileSystemItem(url: url),
                .finderNewTab
            )
        case .file:
            return .file(
                try ManagedFileSystemItem(url: url),
                .systemDefault
            )
        }
    }
}
