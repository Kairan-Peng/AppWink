import Foundation

/// 快捷键修饰键集合，使用 `OptionSet` 以便组合多个修饰键。
public struct AppShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
}

/// 抽象一个可持久化、可比较的应用快捷键定义。
public struct AppShortcut: Codable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: AppShortcutModifiers

    public init(keyCode: UInt16, modifiers: AppShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 用于设置页和叠层展示，按 macOS 常见顺序输出修饰键符号与按键名称。
    public var displayString: String {
        let symbols = Self.modifierDisplayOrder.compactMap { modifier in
            modifiers.contains(modifier) ? Self.modifierSymbols[modifier] : nil
        }

        return symbols.joined() + Self.displayName(for: keyCode)
    }

    /// 将虚拟键码映射为用户可读名称，未知键码保留原始编号便于排查。
    public static func displayName(for keyCode: UInt16) -> String {
        Self.keyNames[keyCode] ?? "Key \(keyCode)"
    }

    /// 与 `modifierSymbols` 配合使用，确保展示顺序稳定，不受集合内部顺序影响。
    private static let modifierDisplayOrder: [AppShortcutModifiers] = [
        .control,
        .option,
        .shift,
        .command,
    ]

    private static let modifierSymbols: [AppShortcutModifiers: String] = [
        .control: "⌃",
        .option: "⌥",
        .shift: "⇧",
        .command: "⌘",
    ]

    /// 常见 macOS 虚拟键码的人类可读映射，覆盖字母、数字、功能键和方向键。
    private static let keyNames: [UInt16: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        36: "↩",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        48: "⇥",
        49: "Space",
        50: "`",
        51: "⌫",
        53: "⎋",
        65: "Keypad .",
        67: "Keypad *",
        69: "Keypad +",
        71: "Keypad Clear",
        75: "Keypad /",
        76: "Keypad ↩",
        78: "Keypad -",
        81: "Keypad =",
        82: "Keypad 0",
        83: "Keypad 1",
        84: "Keypad 2",
        85: "Keypad 3",
        86: "Keypad 4",
        87: "Keypad 5",
        88: "Keypad 6",
        89: "Keypad 7",
        91: "Keypad 8",
        92: "Keypad 9",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        114: "Help",
        115: "Home",
        116: "Page Up",
        117: "⌦",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
    ]
}
