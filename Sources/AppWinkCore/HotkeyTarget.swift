import Foundation

public enum HotkeyActionPermission: String, Hashable, Sendable {
    case accessibility
}

public enum HotkeyTargetKind: String, Codable, Hashable, Sendable {
    case application
    case folder
    case file
}

public enum FolderOpenMode: Codable, Hashable, Sendable {
    /// Legacy persistence discriminator retained for existing configurations.
    /// Runtime behavior now delegates folder opening to macOS/Finder.
    case finderNewTab
    case application(ManagedApplication)

    private enum ModeType: String, Codable {
        case finderNewTab
        case application
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case application
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ModeType.self, forKey: .type) {
        case .finderNewTab:
            guard !container.contains(.application) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .application,
                    in: container,
                    debugDescription: "finderNewTab must not contain an application"
                )
            }
            self = .finderNewTab
        case .application:
            self = .application(
                try container.decode(ManagedApplication.self, forKey: .application)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .finderNewTab:
            try container.encode(ModeType.finderNewTab, forKey: .type)
        case .application(let application):
            try container.encode(ModeType.application, forKey: .type)
            try container.encode(application, forKey: .application)
        }
    }
}

public enum FileOpenMode: Codable, Hashable, Sendable {
    case systemDefault
    case application(ManagedApplication)

    private enum ModeType: String, Codable {
        case systemDefault
        case application
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case application
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ModeType.self, forKey: .type) {
        case .systemDefault:
            guard !container.contains(.application) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .application,
                    in: container,
                    debugDescription: "systemDefault must not contain an application"
                )
            }
            self = .systemDefault
        case .application:
            self = .application(
                try container.decode(ManagedApplication.self, forKey: .application)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemDefault:
            try container.encode(ModeType.systemDefault, forKey: .type)
        case .application(let application):
            try container.encode(ModeType.application, forKey: .type)
            try container.encode(application, forKey: .application)
        }
    }
}

public enum HotkeyTarget: Codable, Hashable, Sendable {
    case application(ManagedApplication)
    case folder(ManagedFileSystemItem, FolderOpenMode)
    case file(ManagedFileSystemItem, FileOpenMode)

    private enum CodingKeys: String, CodingKey {
        case type
        case application
        case item
        case openMode
    }

    public var kind: HotkeyTargetKind {
        switch self {
        case .application:
            .application
        case .folder:
            .folder
        case .file:
            .file
        }
    }

    public var requiredPermissions: Set<HotkeyActionPermission> {
        switch self {
        case .application:
            [.accessibility]
        case .folder(_, .finderNewTab):
            []
        case .folder(_, .application), .file:
            []
        }
    }

    public func hasSameBindingIdentity(as other: Self) -> Bool {
        switch (self, other) {
        case let (.application(application), .application(otherApplication)):
            application.hasSameIdentity(as: otherApplication)
        case let (.folder(item, openMode), .folder(otherItem, otherOpenMode)):
            item.hasSameIdentity(as: otherItem) &&
                openMode.hasSameIdentity(as: otherOpenMode)
        case let (.file(item, openMode), .file(otherItem, otherOpenMode)):
            item.hasSameIdentity(as: otherItem) &&
                openMode.hasSameIdentity(as: otherOpenMode)
        default:
            false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(HotkeyTargetKind.self, forKey: .type) {
        case .application:
            if container.contains(.item) {
                throw DecodingError.dataCorruptedError(
                    forKey: .item,
                    in: container,
                    debugDescription: "application target must not contain an item"
                )
            }
            if container.contains(.openMode) {
                throw DecodingError.dataCorruptedError(
                    forKey: .openMode,
                    in: container,
                    debugDescription: "application target must not contain an openMode"
                )
            }
            self = .application(
                try container.decode(ManagedApplication.self, forKey: .application)
            )
        case .folder:
            guard !container.contains(.application) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .application,
                    in: container,
                    debugDescription: "folder target must not contain an application"
                )
            }
            self = .folder(
                try container.decode(ManagedFileSystemItem.self, forKey: .item),
                try container.decode(FolderOpenMode.self, forKey: .openMode)
            )
        case .file:
            guard !container.contains(.application) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .application,
                    in: container,
                    debugDescription: "file target must not contain an application"
                )
            }
            self = .file(
                try container.decode(ManagedFileSystemItem.self, forKey: .item),
                try container.decode(FileOpenMode.self, forKey: .openMode)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)

        switch self {
        case .application(let application):
            try container.encode(application, forKey: .application)
        case let .folder(item, openMode):
            try container.encode(item, forKey: .item)
            try container.encode(openMode, forKey: .openMode)
        case let .file(item, openMode):
            try container.encode(item, forKey: .item)
            try container.encode(openMode, forKey: .openMode)
        }
    }
}

private extension FolderOpenMode {
    func hasSameIdentity(as other: FolderOpenMode) -> Bool {
        switch (self, other) {
        case (.finderNewTab, .finderNewTab):
            true
        case let (.application(application), .application(otherApplication)):
            application.hasSameIdentity(as: otherApplication)
        default:
            false
        }
    }
}

private extension FileOpenMode {
    func hasSameIdentity(as other: FileOpenMode) -> Bool {
        switch (self, other) {
        case (.systemDefault, .systemDefault):
            true
        case let (.application(application), .application(otherApplication)):
            application.hasSameIdentity(as: otherApplication)
        default:
            false
        }
    }
}
