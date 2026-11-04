import AppWinkCore

/// 纯状态 reducer，用于把键盘事件归一化成 pressed-keys overlay 的可展示文本。
struct PressedKeysOverlayState: Sendable, Equatable {
    private(set) var pressedModifiers: AppShortcutModifiers = []
    private(set) var pressedKeyCodes: [UInt16] = []

    var displayText: String? {
        let modifierText = Self.modifierText(for: pressedModifiers)
        let keyText = pressedKeyCodes.map(AppShortcut.displayName(for:)).joined(separator: " ")

        if modifierText.isEmpty && keyText.isEmpty {
            return nil
        }

        return modifierText + keyText
    }

    mutating func applyModifierFlags(_ modifiers: AppShortcutModifiers) {
        pressedModifiers = modifiers
    }

    mutating func handleKeyDown(keyCode: UInt16, modifiers: AppShortcutModifiers, isARepeat: Bool) {
        pressedModifiers = modifiers

        guard !Self.modifierKeyCodes.contains(keyCode) else {
            return
        }

        guard !isARepeat, !pressedKeyCodes.contains(keyCode) else {
            return
        }

        pressedKeyCodes.append(keyCode)
    }

    mutating func handleKeyUp(keyCode: UInt16, modifiers: AppShortcutModifiers) {
        pressedModifiers = modifiers

        guard !Self.modifierKeyCodes.contains(keyCode) else {
            return
        }

        pressedKeyCodes.removeAll { $0 == keyCode }
    }

    private static func modifierText(for modifiers: AppShortcutModifiers) -> String {
        modifierDisplayOrder.compactMap { modifier in
            modifiers.contains(modifier) ? modifierSymbols[modifier] : nil
        }
        .joined()
    }

    /// 与 `AppShortcut.displayString` 保持一致，确保修饰键顺序稳定。
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

    /// macOS modifier keys on the hardware keyboard should never appear as pressed-key text.
    private static let modifierKeyCodes: Set<UInt16> = Set(54...63)
}
