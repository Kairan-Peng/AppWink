import Foundation

public enum HotkeyTargetUpdateResult: Equatable, Sendable {
    case updated
    case unchanged
    case duplicate
    case bindingNotFound
}

/// 应用级配置模型，统一承载所有已保存的应用绑定信息。
public struct AppConfiguration: Codable, Equatable, Sendable {
    public var bindings: [HotkeyBinding]
    public var language: AppLanguage
    public var appearanceMode: AppAppearanceMode
    public var windowsStyleCutEnabled: Bool
    public var pressedKeysOverlayEnabled: Bool
    public var advancedHotkeysEnabled: Bool
    public var activityMonitorHotKeyEnabled: Bool
    public var hotKeyIconFlashEnabled: Bool
    public var hiddenBarEnabled: Bool
    public var networkStatusEnabled: Bool
    public var mouseWheelWindowsScrollEnabled: Bool
    public var virtualKeyboardEnabled: Bool
    public var virtualKeyboardRevealDelay: TimeInterval

    public init(
        bindings: [HotkeyBinding] = [],
        language: AppLanguage = .system,
        appearanceMode: AppAppearanceMode = .system,
        windowsStyleCutEnabled: Bool = false,
        pressedKeysOverlayEnabled: Bool = false,
        advancedHotkeysEnabled: Bool = false,
        activityMonitorHotKeyEnabled: Bool = false,
        hotKeyIconFlashEnabled: Bool = false,
        hiddenBarEnabled: Bool = false,
        networkStatusEnabled: Bool = false,
        mouseWheelWindowsScrollEnabled: Bool = false,
        virtualKeyboardEnabled: Bool = true,
        virtualKeyboardRevealDelay: TimeInterval = VirtualKeyboardRevealDelay.defaultValue
    ) {
        self.bindings = bindings
        self.language = language
        self.appearanceMode = appearanceMode
        self.windowsStyleCutEnabled = windowsStyleCutEnabled
        self.pressedKeysOverlayEnabled = pressedKeysOverlayEnabled
        self.advancedHotkeysEnabled = advancedHotkeysEnabled
        self.activityMonitorHotKeyEnabled = activityMonitorHotKeyEnabled
        self.hotKeyIconFlashEnabled = hotKeyIconFlashEnabled
        self.hiddenBarEnabled = hiddenBarEnabled
        self.networkStatusEnabled = networkStatusEnabled
        self.mouseWheelWindowsScrollEnabled = mouseWheelWindowsScrollEnabled
        self.virtualKeyboardEnabled = virtualKeyboardEnabled
        self.virtualKeyboardRevealDelay = VirtualKeyboardRevealDelay.normalized(virtualKeyboardRevealDelay)
    }

    public func containsBinding(
        matching target: HotkeyTarget,
        excludingBindingID: UUID? = nil
    ) -> Bool {
        bindings.contains { binding in
            binding.id != excludingBindingID &&
                binding.target.hasSameBindingIdentity(as: target)
        }
    }

    @discardableResult
    public mutating func updateTarget(
        _ target: HotkeyTarget,
        forBindingID bindingID: UUID
    ) -> HotkeyTargetUpdateResult {
        guard let bindingIndex = bindings.firstIndex(where: { $0.id == bindingID }) else {
            return .bindingNotFound
        }

        guard !bindings[bindingIndex].target.hasSameBindingIdentity(as: target) else {
            return .unchanged
        }

        guard !containsBinding(
            matching: target,
            excludingBindingID: bindingID
        ) else {
            return .duplicate
        }

        bindings[bindingIndex].target = target
        return .updated
    }

    /// 通过目标 offset 重排绑定顺序，保持持久化顺序和设置页显示顺序一致。
    public mutating func moveBinding(withID bindingID: UUID, toOffset destination: Int) {
        guard let sourceIndex = bindings.firstIndex(where: { $0.id == bindingID }) else {
            return
        }

        moveBinding(from: sourceIndex, toOffset: destination)
    }

    /// 语义与 SwiftUI 的 `move(fromOffsets:toOffset:)` 保持一致，便于拖拽排序直接复用。
    public mutating func moveBinding(from sourceIndex: Int, toOffset destination: Int) {
        guard bindings.indices.contains(sourceIndex) else {
            return
        }

        let clampedDestination = min(max(destination, 0), bindings.count)
        guard sourceIndex != clampedDestination, sourceIndex + 1 != clampedDestination else {
            return
        }

        let binding = bindings.remove(at: sourceIndex)
        let adjustedDestination = clampedDestination > sourceIndex ? clampedDestination - 1 : clampedDestination
        bindings.insert(binding, at: adjustedDestination)
    }

    /// 按给定的完整 ID 顺序重排绑定，供拖拽预览结束后一次性提交最终顺序。
    public mutating func setBindingOrder(_ orderedBindingIDs: [UUID]) {
        guard orderedBindingIDs.count == bindings.count else {
            return
        }

        let bindingsByID = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
        let uniqueOrderedBindingIDs = Set(orderedBindingIDs)
        guard uniqueOrderedBindingIDs.count == bindings.count,
              uniqueOrderedBindingIDs == Set(bindingsByID.keys) else {
            return
        }

        bindings = orderedBindingIDs.compactMap { bindingsByID[$0] }
    }

    /// 兼容旧版单应用配置结构，避免历史数据在升级后失效。
    private enum CodingKeys: String, CodingKey {
        case bindings
        case selectedApplication
        case launchShortcut
        case quitShortcut
        case language
        case appearanceMode
        case windowsStyleCutEnabled
        case pressedKeysOverlayEnabled
        case advancedHotkeysEnabled
        case activityMonitorHotKeyEnabled
        case hotKeyIconFlashEnabled
        case hiddenBarEnabled
        case networkStatusEnabled
        case mouseWheelWindowsScrollEnabled
        case virtualKeyboardEnabled
        case virtualKeyboardRevealDelay
    }

    /// 优先按新版多绑定结构解码；如果没有 `bindings`，则回退解析旧版单应用字段。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 读取语言设置，默认跟随系统
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        self.appearanceMode = try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system
        self.windowsStyleCutEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .windowsStyleCutEnabled
        ) ?? false
        self.pressedKeysOverlayEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .pressedKeysOverlayEnabled
        ) ?? false
        self.advancedHotkeysEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .advancedHotkeysEnabled
        ) ?? false
        self.activityMonitorHotKeyEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .activityMonitorHotKeyEnabled
        ) ?? false
        self.hotKeyIconFlashEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .hotKeyIconFlashEnabled
        ) ?? false
        self.hiddenBarEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .hiddenBarEnabled
        ) ?? false
        self.networkStatusEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .networkStatusEnabled
        ) ?? false
        self.mouseWheelWindowsScrollEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .mouseWheelWindowsScrollEnabled
        ) ?? false
        self.virtualKeyboardEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .virtualKeyboardEnabled
        ) ?? true
        self.virtualKeyboardRevealDelay = VirtualKeyboardRevealDelay.normalized(
            try container.decodeIfPresent(
                TimeInterval.self,
                forKey: .virtualKeyboardRevealDelay
            ) ?? VirtualKeyboardRevealDelay.defaultValue
        )

        if container.contains(.bindings) {
            self.bindings = try container.decode(
                [HotkeyBinding].self,
                forKey: .bindings
            )
            return
        }

        let selectedApplication = try container.decodeIfPresent(ManagedApplication.self, forKey: .selectedApplication)
        let launchShortcut = try container.decodeIfPresent(AppShortcut.self, forKey: .launchShortcut)
        let quitShortcut = try container.decodeIfPresent(AppShortcut.self, forKey: .quitShortcut)

        if let selectedApplication {
            self.bindings = [
                HotkeyBinding(
                    target: .application(selectedApplication),
                    shortcut: launchShortcut ?? quitShortcut
                )
            ]
        } else {
            self.bindings = []
        }
    }

    /// 持久化时始终写回新版结构，确保迁移完成后格式保持一致。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bindings, forKey: .bindings)
        try container.encode(language, forKey: .language)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(windowsStyleCutEnabled, forKey: .windowsStyleCutEnabled)
        try container.encode(pressedKeysOverlayEnabled, forKey: .pressedKeysOverlayEnabled)
        try container.encode(advancedHotkeysEnabled, forKey: .advancedHotkeysEnabled)
        try container.encode(activityMonitorHotKeyEnabled, forKey: .activityMonitorHotKeyEnabled)
        try container.encode(hotKeyIconFlashEnabled, forKey: .hotKeyIconFlashEnabled)
        try container.encode(hiddenBarEnabled, forKey: .hiddenBarEnabled)
        try container.encode(networkStatusEnabled, forKey: .networkStatusEnabled)
        try container.encode(mouseWheelWindowsScrollEnabled, forKey: .mouseWheelWindowsScrollEnabled)
        try container.encode(virtualKeyboardEnabled, forKey: .virtualKeyboardEnabled)
        try container.encode(virtualKeyboardRevealDelay, forKey: .virtualKeyboardRevealDelay)
    }
}
