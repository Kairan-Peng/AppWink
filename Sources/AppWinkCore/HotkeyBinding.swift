import Foundation

public enum HotkeyBindingSource: String, Codable, Hashable, Sendable {
    case user
    case activityMonitorFeature
}

public struct HotkeyBinding: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var target: HotkeyTarget
    public var shortcut: AppShortcut?
    public var isEnabled: Bool
    public var source: HotkeyBindingSource

    public init(
        id: UUID = UUID(),
        target: HotkeyTarget,
        shortcut: AppShortcut? = nil,
        isEnabled: Bool = true,
        source: HotkeyBindingSource = .user
    ) {
        self.id = id
        self.target = target
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case target
        case application
        case shortcut
        case toggleShortcut
        case isEnabled
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        if container.contains(.target) {
            self.target = try container.decode(HotkeyTarget.self, forKey: .target)
        } else {
            self.target = .application(
                try container.decode(ManagedApplication.self, forKey: .application)
            )
        }

        if container.contains(.shortcut) {
            self.shortcut = try container.decodeIfPresent(
                AppShortcut.self,
                forKey: .shortcut
            )
        } else {
            self.shortcut = try container.decodeIfPresent(
                AppShortcut.self,
                forKey: .toggleShortcut
            )
        }

        self.isEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? true
        self.source = try container.decodeIfPresent(
            HotkeyBindingSource.self,
            forKey: .source
        ) ?? .user
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(shortcut, forKey: .shortcut)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(source, forKey: .source)
    }
}
