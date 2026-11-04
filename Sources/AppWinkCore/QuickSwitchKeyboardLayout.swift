import Foundation

/// 为长按 `Option` 的覆盖层提供一套稳定的主键区布局数据。
public enum QuickSwitchKeyboardLayout {
    /// 单个虚拟键帽的展示元数据。
    public struct Key: Identifiable, Equatable, Sendable {
        public enum Role: String, Sendable {
            case shortcut
            case reference
        }

        public let id: String
        public let label: String
        public let widthUnits: Double
        public let role: Role
        public let keyCode: UInt16?

        public init(
            id: String,
            label: String,
            widthUnits: Double = 1,
            role: Role,
            keyCode: UInt16? = nil
        ) {
            self.id = id
            self.label = label
            self.widthUnits = widthUnits
            self.role = role
            self.keyCode = keyCode
        }

        public var isShortcutKey: Bool {
            role == .shortcut
        }
    }

    /// 核心可绑定键只保留到 `5 / T / G / B` 为止，右侧补少量模糊参考键来弱化裁切边缘。
    public static let rows: [[Key]] = [
        [
            reference("escape", "esc", widthUnits: 1.25),
            reference("f1", "F1"),
            reference("f2", "F2"),
            reference("f3", "F3"),
            reference("f4", "F4"),
            reference("f5", "F5"),
            reference("f6", "F6"),
            reference("f7", "F7"),
            reference("f8", "F8"),
        ],
        [
            reference("backtick", "`"),
            shortcut(18),
            shortcut(19),
            shortcut(20),
            shortcut(21),
            shortcut(23),
            reference("digit-6", "6"),
            reference("digit-7", "7"),
            reference("digit-8", "8"),
            reference("digit-9", "9"),
            reference("digit-0", "0"),
            reference("minus", "-"),
            reference("equal", "="),
        ],
        [
            reference("tab", "tab", widthUnits: 1.5),
            shortcut(12),
            shortcut(13),
            shortcut(14),
            shortcut(15),
            shortcut(17),
            reference("letter-y", "Y"),
            reference("letter-u", "U"),
            reference("letter-i", "I"),
        ],
        [
            reference("caps-lock", "caps lock", widthUnits: 1.75),
            shortcut(0),
            shortcut(1),
            shortcut(2),
            shortcut(3),
            shortcut(5),
            reference("letter-h", "H"),
            reference("letter-j", "J"),
            reference("letter-k", "K"),
        ],
        [
            reference("left-shift", "⇧ shift", widthUnits: 2.25),
            shortcut(6),
            shortcut(7),
            shortcut(8),
            shortcut(9),
            shortcut(11),
            reference("letter-n", "N"),
            reference("letter-m", "M"),
            reference("comma", ","),
        ],
        [
            reference("fn", "fn", widthUnits: 1),
            reference("control", "⌃ control", widthUnits: 1),
            reference("option", "⌥ option", widthUnits: 1),
            reference("command", "⌘ command", widthUnits: 1.263),
            reference("space", "space", widthUnits: 6),
        ],
    ]

    private static var shortcutKeys: [Key] {
        rows.flatMap { $0 }.filter(\.isShortcutKey)
    }

    /// 只有默认的 `⌥ + 字母/数字` 才会映射到虚拟键盘的可高亮键帽上。
    public static func key(for shortcut: AppShortcut?) -> Key? {
        guard let shortcut, shortcut.modifiers == QuickSwitchShortcutPalette.defaultModifiers else {
            return nil
        }

        return shortcutKeys.first { $0.keyCode == shortcut.keyCode }
    }

    private static func shortcut(_ keyCode: UInt16) -> Key {
        Key(
            id: "shortcut-\(keyCode)",
            label: AppShortcut.displayName(for: keyCode),
            role: .shortcut,
            keyCode: keyCode)
    }

    private static func reference(_ id: String, _ label: String, widthUnits: Double = 1) -> Key {
        Key(
            id: id,
            label: label,
            widthUnits: widthUnits,
            role: .reference)
    }
}
