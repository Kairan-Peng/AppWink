import AppKit
import Carbon
import AppWinkCore

/// 将 `NSEvent` 修饰键转换为项目内部的快捷键模型，方便 UI 和系统事件对齐。
extension AppShortcutModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: AppShortcutModifiers = []

        if eventFlags.contains(.command) {
            modifiers.insert(.command)
        }

        if eventFlags.contains(.option) {
            modifiers.insert(.option)
        }

        if eventFlags.contains(.control) {
            modifiers.insert(.control)
        }

        if eventFlags.contains(.shift) {
            modifiers.insert(.shift)
        }

        self = modifiers
    }

    init(eventFlags: CGEventFlags) {
        var modifiers: AppShortcutModifiers = []

        if eventFlags.contains(.maskCommand) {
            modifiers.insert(.command)
        }

        if eventFlags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }

        if eventFlags.contains(.maskControl) {
            modifiers.insert(.control)
        }

        if eventFlags.contains(.maskShift) {
            modifiers.insert(.shift)
        }

        self = modifiers
    }
}

/// 提供 Carbon 热键注册所需的修饰键映射。
extension AppShortcut {
    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0

        if self.modifiers.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        if self.modifiers.contains(.option) {
            modifiers |= UInt32(optionKey)
        }

        if self.modifiers.contains(.control) {
            modifiers |= UInt32(controlKey)
        }

        if self.modifiers.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }

        return modifiers
    }
}
