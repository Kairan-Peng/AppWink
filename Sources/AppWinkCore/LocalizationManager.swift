import Foundation
import SwiftUI

/// 支持的应用语言
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system = "system"  // 跟随系统
    case chinese = "zh-Hans"  // 简体中文
    case english = "en"  // 英文

    public var localizationKey: String {
        switch self {
        case .system:
            return "language.system"
        case .chinese:
            return "language.chinese"
        case .english:
            return "language.english"
        }
    }

    public func displayName(in bundle: Bundle? = nil) -> String {
        NSLocalizedString(localizationKey, bundle: bundle ?? LocalizationManager.resourcesBundle, comment: "")
    }

    public var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .chinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }
}

/// AppWink 自身界面的外观模式。
public enum AppAppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var localizationKey: String {
        switch self {
        case .system:
            return "appearanceMode.system"
        case .light:
            return "appearanceMode.light"
        case .dark:
            return "appearanceMode.dark"
        }
    }

    public func displayName(in bundle: Bundle? = nil) -> String {
        NSLocalizedString(localizationKey, bundle: bundle ?? LocalizationManager.resourcesBundle, comment: "")
    }
}

/// 本地化键值定义
public enum LocalizationKey: String, Sendable {
    // 通用
    case cancel = "general.cancel"
    case close = "general.close"
    case open = "general.open"
    case settings = "general.settings"
    case help = "general.help"
    case notConfigured = "general.notConfigured"
    case enabled = "general.enabled"
    case disabled = "general.disabled"
    case unavailable = "general.unavailable"
    case clear = "general.clear"
    
    // 品牌
    case tagline = "brand.tagline"
    
    // 设置界面
    case launchAtLogin = "settings.launchAtLogin"
    case launchAtLoginDescription = "settings.launchAtLoginDescription"
    case launchAtLoginRequiresApproval = "settings.launchAtLoginRequiresApproval"
    case launchAtLoginUnavailable = "settings.launchAtLoginUnavailable"
    case language = "settings.language"
    case appearanceMode = "settings.appearanceMode"
    case windowsStyleCut = "settings.windowsStyleCut"
    case mouseWheelWindowsScroll = "settings.mouseWheelWindowsScroll"
    case pressedKeysOverlay = "settings.pressedKeysOverlay"
    case virtualKeyboard = "settings.virtualKeyboard"
    case virtualKeyboardDelayValue = "settings.virtualKeyboardDelayValue"
    case hiddenBar = "settings.hiddenBar"
    case networkMonitor = "settings.networkMonitor"
    case hotKeyIconFlash = "settings.hotKeyIconFlash"
    case advancedHotkeys = "settings.advancedHotkeys"
    case activityMonitor = "settings.activityMonitor"
    case automaticallyCheckForUpdates = "settings.automaticallyCheckForUpdates"
    case settingsSectionGeneral = "settings.section.general"
    case settingsSectionFeatures = "settings.section.features"
    case settingsSectionAboutUpdates = "settings.section.aboutUpdates"
    case settingsFeatureStatusEnabled = "settings.feature.status.enabled"
    case settingsFeatureStatusDisabled = "settings.feature.status.disabled"
    case settingsFeatureStatusPermissionRequired = "settings.feature.status.permissionRequired"
    case settingsFeatureEnable = "settings.feature.enable"
    case settingsFeatureSettingsSection = "settings.feature.section.settings"
    case settingsFeatureHowItWorksSection = "settings.feature.section.howItWorks"
    case settingsFeatureOpenHint = "settings.feature.openHint"
    case settingsFeatureAppliesTo = "settings.feature.appliesTo"
    case settingsFeatureShortcut = "settings.feature.shortcut"
    case settingsFeatureAfterCut = "settings.feature.afterCut"
    case settingsFeatureDevice = "settings.feature.device"
    case settingsFeatureScrolling = "settings.feature.scrolling"
    case settingsFeatureUnaffected = "settings.feature.unaffected"
    case settingsFeatureShows = "settings.feature.shows"
    case settingsFeaturePosition = "settings.feature.position"
    case settingsFeatureTrigger = "settings.feature.trigger"
    case settingsFeatureShowAfter = "settings.feature.showAfter"
    case settingsFeatureControl = "settings.feature.control"
    case settingsFeatureArrangeItems = "settings.feature.arrangeItems"
    case settingsFeatureAutoCollapse = "settings.feature.autoCollapse"
    case settingsFeatureDisplay = "settings.feature.display"
    case settingsFeatureSource = "settings.feature.source"
    case settingsFeatureRefresh = "settings.feature.refresh"
    case settingsFeatureDuration = "settings.feature.duration"
    case settingsFeatureBehavior = "settings.feature.behavior"
    case settingsFeatureWhenFullscreen = "settings.feature.whenFullscreen"
    case settingsFeatureAfterCutValue = "settings.feature.afterCut.value"
    case settingsFeaturePhysicalMouseWheel = "settings.feature.physicalMouseWheel"
    case settingsFeatureWindowsDirectionSmooth = "settings.feature.windowsDirectionSmooth"
    case settingsFeatureTrackpadMagicMouse = "settings.feature.trackpadMagicMouse"
    case settingsFeatureModifiersCombinationsSingleKeys = "settings.feature.modifiersCombinationsSingleKeys"
    case settingsFeatureBottomCenterActiveDisplay = "settings.feature.bottomCenterActiveDisplay"
    case settingsFeatureHoldOption = "settings.feature.holdOption"
    case settingsFeatureMenuBarArrow = "settings.feature.menuBarArrow"
    case settingsFeatureCommandDragAcrossMarker = "settings.feature.commandDragAcrossMarker"
    case settingsFeatureThirtySeconds = "settings.feature.thirtySeconds"
    case settingsFeatureMenuBarUploadAboveDownload = "settings.feature.menuBarUploadAboveDownload"
    case settingsFeaturePrimaryNetworkInterface = "settings.feature.primaryNetworkInterface"
    case settingsFeatureEveryTwoSeconds = "settings.feature.everyTwoSeconds"
    case settingsFeatureAppWinkHotkeysOnly = "settings.feature.appWinkHotkeysOnly"
    case settingsFeatureTargetAppIconScreenCenter = "settings.feature.targetAppIconScreenCenter"
    case settingsFeatureAboutPoint45Seconds = "settings.feature.aboutPoint45Seconds"
    case settingsFeatureActivityMonitorBehavior = "settings.feature.activityMonitorBehavior"
    case settingsFeatureActivityMonitorFullscreenNoOp = "settings.feature.activityMonitorFullscreenNoOp"
    case settingsFeatureAdvancedHotkeysCombinations = "settings.feature.advancedHotkeysCombinations"
    case toolboxTitle = "toolbox.title"
    case toolboxFeatureToggles = "toolbox.featureToggles"
    case toolboxOther = "toolbox.other"
    case toolboxWindowsStyleCutSummary = "toolbox.windowsStyleCutSummary"
    case toolboxMouseWheelWindowsScrollSummary = "toolbox.mouseWheelWindowsScrollSummary"
    case toolboxPressedKeysOverlaySummary = "toolbox.pressedKeysOverlaySummary"
    case toolboxVirtualKeyboardSummary = "toolbox.virtualKeyboardSummary"
    case toolboxHiddenBarSummary = "toolbox.hiddenBarSummary"
    case toolboxNetworkMonitorSummary = "toolbox.networkMonitorSummary"
    case toolboxHotKeyIconFlashSummary = "toolbox.hotKeyIconFlashSummary"
    case toolboxActivityMonitorSummary = "toolbox.activityMonitorSummary"
    case toolboxAdvancedHotkeysSummary = "toolbox.advancedHotkeysSummary"
    case toolboxCheckForUpdates = "toolbox.checkForUpdates"
    case toolboxCurrentVersion = "toolbox.currentVersion"
    case toolboxAboutHelp = "toolbox.aboutHelp"
    case developmentBuild = "toolbox.developmentBuild"

    // 绑定列表
    case addTarget = "bindings.addTarget"
    case chooseTarget = "bindings.chooseTarget"
    case chooseTargetMessage = "bindings.chooseTargetMessage"
    case targetAlreadyExists = "bindings.targetAlreadyExists"
    case recordShortcut = "bindings.recordShortcut"
    case enableHotkey = "bindings.enableHotkey"
    case disableHotkey = "bindings.disableHotkey"
    case openWith = "bindings.openWith"
    case openTargetWithApplication = "bindings.openTargetWithApplication"
    case finderNewTab = "bindings.finderNewTab"
    case systemDefaultApplication = "bindings.systemDefaultApplication"
    case chooseOtherApplication = "bindings.chooseOtherApplication"
    case targetKindApplication = "bindings.targetKind.application"
    case targetKindFolder = "bindings.targetKind.folder"
    case targetKindFile = "bindings.targetKind.file"
    case action = "bindings.action"
    case applicationToggle = "bindings.applicationToggle"
    case targetAccessibilityValue = "bindings.targetAccessibilityValue"

    // 状态提示
    case targetUnavailable = "status.targetUnavailable"
    case openingApplicationUnavailable = "status.openingApplicationUnavailable"
    case shortcutConflict = "status.shortcutConflict"
    case shortcutConflictWith = "status.shortcutConflictWith"
    case accessibilityPermissionRequired = "status.accessibilityPermissionRequired"
    case addAccessibilityPermission = "status.addAccessibilityPermission"
    case openSystemSettings = "status.openSystemSettings"
    case issuesTitle = "status.issuesTitle"
    case targetsUnavailable = "status.targetsUnavailable"
    case shortcutConflictReminder = "status.shortcutConflictReminder"
    case configurationLoadFailed = "status.configurationLoadFailed"
    case configurationSaveFailed = "status.configurationSaveFailed"
    case targetAdded = "status.targetAdded"
    case targetRemoved = "status.targetRemoved"
    case addTargetFailed = "status.addTargetFailed"
    case bindingNotFound = "status.bindingNotFound"
    case openSystemSettingsFailed = "status.openSystemSettingsFailed"
    case openSystemSettingsSucceeded = "status.openSystemSettingsSucceeded"
    case launchAtLoginUpdateFailed = "status.launchAtLoginUpdateFailed"
    case launchAtLoginEnabled = "status.launchAtLoginEnabled"
    case launchAtLoginDisabled = "status.launchAtLoginDisabled"
    case languageUpdated = "status.languageUpdated"
    case appearanceModeUpdated = "status.appearanceModeUpdated"
    case hotKeyRegistrationFailed = "status.hotKeyRegistrationFailed"
    case windowsStyleCutEnabled = "status.windowsStyleCutEnabled"
    case windowsStyleCutDisabled = "status.windowsStyleCutDisabled"
    case windowsStyleCutPermissionRequired = "status.windowsStyleCutPermissionRequired"
    case mouseWheelWindowsScrollEnabled = "status.mouseWheelWindowsScrollEnabled"
    case mouseWheelWindowsScrollDisabled = "status.mouseWheelWindowsScrollDisabled"
    case mouseWheelWindowsScrollPermissionRequired = "status.mouseWheelWindowsScrollPermissionRequired"
    case pressedKeysOverlayEnabled = "status.pressedKeysOverlayEnabled"
    case pressedKeysOverlayDisabled = "status.pressedKeysOverlayDisabled"
    case pressedKeysOverlayPermissionRequired = "status.pressedKeysOverlayPermissionRequired"
    case virtualKeyboardEnabled = "status.virtualKeyboardEnabled"
    case virtualKeyboardDisabled = "status.virtualKeyboardDisabled"
    case hiddenBarEnabled = "status.hiddenBarEnabled"
    case hiddenBarDisabled = "status.hiddenBarDisabled"
    case networkMonitorEnabled = "status.networkMonitorEnabled"
    case networkMonitorDisabled = "status.networkMonitorDisabled"
    case networkMonitorAccessibilityValue = "networkMonitor.accessibilityValue"
    case hotKeyIconFlashEnabled = "status.hotKeyIconFlashEnabled"
    case hotKeyIconFlashDisabled = "status.hotKeyIconFlashDisabled"
    case advancedHotkeysEnabled = "status.advancedHotkeysEnabled"
    case advancedHotkeysDisabled = "status.advancedHotkeysDisabled"
    case activityMonitorHotKeyEnabled = "status.activityMonitorHotKeyEnabled"
    case activityMonitorHotKeyDisabled = "status.activityMonitorHotKeyDisabled"
    case activityMonitorHotKeyPermissionRequired = "status.activityMonitorHotKeyPermissionRequired"

    // 切换结果
    case activated = "toggle.activated"
    case hidden = "toggle.hidden"

    // 错误信息
    case applicationUnavailable = "error.applicationUnavailable"
    case launchFailed = "error.launchFailed"
    case activationFailed = "error.activationFailed"
    case hideFailed = "error.hideFailed"

    // 帮助
    case helpHotkeyUsageTitle = "help.hotkeyUsage.title"
    case helpFeatureNotesTitle = "help.featureNotes.title"
    case helpHotkeyUsageNotConfigured = "help.hotkeyUsage.notConfigured"
    case helpHotkeyUsageChooseTarget = "help.hotkeyUsage.chooseTarget"
    case helpHotkeyUsageRecordShortcut = "help.hotkeyUsage.recordShortcut"
    case helpHotkeyUsageApplicationToggle = "help.hotkeyUsage.applicationToggle"
    case helpHotkeyUsageFinderNewTab = "help.hotkeyUsage.finderNewTab"
    case helpHotkeyUsageFileSystemDefault = "help.hotkeyUsage.fileSystemDefault"
    case helpHotkeyUsageSelectedApplication = "help.hotkeyUsage.selectedApplication"
    case helpHotkeyUsageQuickSwitch = "help.hotkeyUsage.quickSwitch"
    case hotkeyGuideTitle = "hotkeyGuide.title"
    case hotkeyGuideDismiss = "hotkeyGuide.dismiss"
    
    // 菜单栏
    case menuConfigureHotkeys = "menu.configureHotkeys"
    case menuOpenSettings = "menu.openSettings"
    case menuQuitApp = "menu.quitApp"
}

/// 本地化管理器
public final class LocalizationManager: ObservableObject, @unchecked Sendable {
    public static let shared = LocalizationManager()

    @Published public private(set) var currentLanguage: AppLanguage
    @Published public private(set) var bundle: Bundle

    private let userDefaultsKey = "appwink.selectedLanguage"

    private init() {
        // 从 UserDefaults 读取保存的语言设置
        let savedLanguage: AppLanguage
        if let savedLanguageRaw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let loadedLanguage = AppLanguage(rawValue: savedLanguageRaw) {
            savedLanguage = loadedLanguage
        } else {
            savedLanguage = .system
        }
        
        self.currentLanguage = savedLanguage
        self.bundle = LocalizationManager.bundle(for: savedLanguage)
    }

    /// 设置应用语言
    public func setLanguage(_ language: AppLanguage) {
        guard currentLanguage != language else { return }

        if Thread.isMainThread {
            applyLanguageChange(language)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyLanguageChange(language)
            }
        }
    }

    private func applyLanguageChange(_ language: AppLanguage) {
        currentLanguage = language
        bundle = LocalizationManager.bundle(for: language)
        UserDefaults.standard.set(language.rawValue, forKey: userDefaultsKey)
    }

    /// 获取当前语言的 bundle
    static func localizedBundle(
        for language: AppLanguage,
        in rootBundle: Bundle? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bundle {
        let rootBundle = rootBundle ?? resourcesBundle
        if let languageCode = language.localeIdentifier {
            return localizedBundle(forIdentifier: languageCode, in: rootBundle) ?? rootBundle
        }

        for preferredLanguage in preferredLanguages {
            if let bundle = localizedBundle(forIdentifier: preferredLanguage, in: rootBundle) {
                return bundle
            }
        }

        return rootBundle
    }

    private static func localizedBundle(forIdentifier identifier: String, in rootBundle: Bundle) -> Bundle? {
        for candidate in localizationCandidates(for: identifier) {
            if let bundle = bundle(forLocalization: candidate, in: rootBundle) {
                return bundle
            }
        }

        if let matchedLocalization = rootBundle.localizations.first(where: {
            localizationIdentifiersMatch($0, identifier)
        }),
           let bundle = bundle(forLocalization: matchedLocalization, in: rootBundle) {
            return bundle
        }

        return nil
    }

    private static func bundle(forLocalization localization: String, in rootBundle: Bundle) -> Bundle? {
        guard let path = rootBundle.path(forResource: localization, ofType: "lproj") else {
            return nil
        }

        return Bundle(path: path)
    }

    private static func localizationIdentifiersMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhsCandidates = localizationCandidates(for: lhs).map(normalizedLocalizationIdentifier)
        let rhsCandidates = localizationCandidates(for: rhs).map(normalizedLocalizationIdentifier)

        return lhsCandidates.contains { candidate in
            rhsCandidates.contains(candidate)
        }
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        localizedBundle(for: language)
    }

    fileprivate static var resourcesBundle: Bundle {
        let resourceBundleName = "AppWink_AppWinkCore"
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("\(resourceBundleName).bundle"),
           let bundle = Bundle(url: resourceURL) {
            return bundle
        }

        return .module
    }

    private static func localizationCandidates(for identifier: String) -> [String] {
        let hyphenated = identifier.replacingOccurrences(of: "_", with: "-")
        let components = hyphenated.split(separator: "-").map(String.init)
        guard let language = components.first else {
            return [identifier]
        }

        let script = components.dropFirst().first(where: { $0.count == 4 })
        let region = components.dropFirst().first(where: { $0.count == 2 || $0.count == 3 })
        var candidates = [identifier, hyphenated]

        if let script {
            candidates.append("\(language)-\(script)")
        }

        if let region {
            candidates.append("\(language)-\(region)")
        }

        if language.lowercased() == "zh" {
            if let script, script.lowercased() == "hans" {
                candidates.append("zh_CN")
            }

            if let region, region.lowercased() == "cn" {
                candidates.append("zh-Hans")
                candidates.append("zh_CN")
            }

            if let script, script.lowercased() == "hant" {
                candidates.append("zh_TW")
            }

            if let region, ["tw", "hk", "mo"].contains(region.lowercased()) {
                candidates.append("zh-Hant")
                candidates.append("zh_TW")
            }
        }

        candidates.append(language)

        return candidates
            .flatMap { candidate in
                [
                    candidate,
                    candidate.replacingOccurrences(of: "-", with: "_"),
                    candidate.lowercased(),
                ]
            }
            .reduce(into: [String]()) { result, candidate in
                guard !result.contains(candidate) else {
                    return
                }
                result.append(candidate)
            }
    }

    private static func normalizedLocalizationIdentifier(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    /// 本地化字符串
    public func string(for key: LocalizationKey) -> String {
        return NSLocalizedString(key.rawValue, bundle: bundle, comment: "")
    }

    /// 带参数的本地化字符串
    public func string(for key: LocalizationKey, arguments: CVarArg...) -> String {
        let format = string(for: key)
        return String(format: format, arguments: arguments)
    }

    public func string(for key: LocalizationKey, arguments: [CVarArg]) -> String {
        let format = string(for: key)
        return String(format: format, arguments: arguments)
    }

    public var usesEnglishInterface: Bool {
        interfaceLanguageCode.hasPrefix("en")
    }

    public var listSeparator: String {
        usesEnglishInterface ? ", " : "、"
    }

    public var clauseSeparator: String {
        usesEnglishInterface ? "; " : "；"
    }

    public var colonSeparator: String {
        usesEnglishInterface ? ": " : "："
    }

    private var interfaceLanguageCode: String {
        bundle.preferredLocalizations.first ??
        LocalizationManager.resourcesBundle.preferredLocalizations.first ??
        Locale.autoupdatingCurrent.identifier
    }
}

// MARK: - SwiftUI Helpers

public extension View {
    /// 应用语言环境
    func appLanguage(_ language: AppLanguage) -> some View {
        let locale = language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
        return self.environment(\.locale, locale)
    }
}
