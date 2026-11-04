import AppWinkCore

struct HelpFeatureNote: Equatable {
    let titleKey: LocalizationKey
    let bodyKey: LocalizationKey
}

enum AppHelpContent {
    static let hotkeyUsageKeys: [LocalizationKey] = [
        .helpHotkeyUsageNotConfigured,
        .helpHotkeyUsageChooseTarget,
        .helpHotkeyUsageRecordShortcut,
        .helpHotkeyUsageApplicationToggle,
        .helpHotkeyUsageFinderNewTab,
        .helpHotkeyUsageFileSystemDefault,
        .helpHotkeyUsageSelectedApplication,
        .helpHotkeyUsageQuickSwitch,
    ]

    static let featureNotes: [HelpFeatureNote] = [
        HelpFeatureNote(titleKey: .windowsStyleCut, bodyKey: .toolboxWindowsStyleCutSummary),
        HelpFeatureNote(titleKey: .mouseWheelWindowsScroll, bodyKey: .toolboxMouseWheelWindowsScrollSummary),
        HelpFeatureNote(titleKey: .pressedKeysOverlay, bodyKey: .toolboxPressedKeysOverlaySummary),
        HelpFeatureNote(titleKey: .virtualKeyboard, bodyKey: .toolboxVirtualKeyboardSummary),
        HelpFeatureNote(titleKey: .hiddenBar, bodyKey: .toolboxHiddenBarSummary),
        HelpFeatureNote(titleKey: .networkMonitor, bodyKey: .toolboxNetworkMonitorSummary),
        HelpFeatureNote(titleKey: .hotKeyIconFlash, bodyKey: .toolboxHotKeyIconFlashSummary),
        HelpFeatureNote(titleKey: .advancedHotkeys, bodyKey: .toolboxAdvancedHotkeysSummary),
    ]
}
