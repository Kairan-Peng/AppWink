import Foundation

/// 为快速切换提供一组固定、可预测的默认快捷键分配规则。
public enum QuickSwitchShortcutPalette {
    public static let defaultModifiers: AppShortcutModifiers = [.option]

    /// 按数字、字母的键盘记忆顺序排列，便于用户形成稳定肌肉记忆。
    private static let orderedKeyCodes: [UInt16] = [
        18, 19, 20, 21, 23, 22, 26, 28, 25, 29, // 1...0
        12, 13, 14, 15, 17, 16, 32, 34, 31, 35, // Q...P
        0, 1, 2, 3, 5, 4, 38, 40, 37, // A...L
        6, 7, 8, 9, 11, 45, 46, // Z...M
    ]

    private static let advancedKeyCodes: Set<UInt16> = [
        24, 27, 30, 33, 39, 41, 42, 43, 44, 47, 50, // = - ] [ ' ; \ , . / `
    ]

    public static func isSupportedKeyCode(_ keyCode: UInt16) -> Bool {
        orderedKeyCodes.contains(keyCode)
    }

    public static func isAdvancedSupportedKeyCode(_ keyCode: UInt16) -> Bool {
        isSupportedKeyCode(keyCode) || advancedKeyCodes.contains(keyCode)
    }

    /// 为叠层和列表排序提供稳定权重；不在调色板中的快捷键统一排到末尾。
    public static func sortRank(for shortcut: AppShortcut?) -> Int {
        guard let shortcut else {
            return Int.max
        }

        guard let index = orderedKeyCodes.firstIndex(of: shortcut.keyCode), shortcut.modifiers == defaultModifiers else {
            return Int.max - 1
        }

        return index
    }
}
