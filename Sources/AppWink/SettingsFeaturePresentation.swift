import AppWinkCore

enum SettingsFeatureStatus: Equatable {
    case enabled
    case disabled
    case permissionRequired

    var localizationKey: LocalizationKey {
        switch self {
        case .enabled:
            return .settingsFeatureStatusEnabled
        case .disabled:
            return .settingsFeatureStatusDisabled
        case .permissionRequired:
            return .settingsFeatureStatusPermissionRequired
        }
    }
}

enum SettingsFeatureDetailValue: Equatable {
    case localized(LocalizationKey)
    case verbatim(String)
}

enum SettingsFeatureDetailRow: Equatable {
    case value(labelKey: LocalizationKey, value: SettingsFeatureDetailValue)
    case virtualKeyboardDelay
}

enum SettingsFeatureDetailSectionKind: Equatable {
    case settings
    case howItWorks

    var titleKey: LocalizationKey {
        switch self {
        case .settings:
            return .settingsFeatureSettingsSection
        case .howItWorks:
            return .settingsFeatureHowItWorksSection
        }
    }
}

struct SettingsFeaturePresentation: Equatable {
    let systemImage: String
    let titleKey: LocalizationKey
    let summaryKey: LocalizationKey
    let sectionKind: SettingsFeatureDetailSectionKind
    let rows: [SettingsFeatureDetailRow]
}

extension ToolboxToggleKind {
    var requiresAccessibilityPermission: Bool {
        permissionMessageKey != nil
    }

    var permissionMessageKey: LocalizationKey? {
        switch self {
        case .windowsStyleCut:
            return .windowsStyleCutPermissionRequired
        case .mouseWheelWindowsScroll:
            return .mouseWheelWindowsScrollPermissionRequired
        case .pressedKeysOverlay:
            return .pressedKeysOverlayPermissionRequired
        case .virtualKeyboard, .hiddenBar, .networkMonitor, .hotKeyIconFlash, .advancedHotkeys:
            return nil
        }
    }

    var presentation: SettingsFeaturePresentation {
        switch self {
        case .windowsStyleCut:
            return SettingsFeaturePresentation(
                systemImage: "scissors",
                titleKey: .windowsStyleCut,
                summaryKey: .toolboxWindowsStyleCutSummary,
                sectionKind: .howItWorks,
                rows: [
                    .value(labelKey: .settingsFeatureAppliesTo, value: .verbatim("Finder")),
                    .value(labelKey: .settingsFeatureShortcut, value: .verbatim("⌘X → ⌘V")),
                    .value(labelKey: .settingsFeatureAfterCut, value: .localized(.settingsFeatureAfterCutValue)),
                ]
            )
        case .mouseWheelWindowsScroll:
            return SettingsFeaturePresentation(
                systemImage: "computermouse",
                titleKey: .mouseWheelWindowsScroll,
                summaryKey: .toolboxMouseWheelWindowsScrollSummary,
                sectionKind: .howItWorks,
                rows: [
                    .value(labelKey: .settingsFeatureDevice, value: .localized(.settingsFeaturePhysicalMouseWheel)),
                    .value(labelKey: .settingsFeatureScrolling, value: .localized(.settingsFeatureWindowsDirectionSmooth)),
                    .value(labelKey: .settingsFeatureUnaffected, value: .localized(.settingsFeatureTrackpadMagicMouse)),
                ]
            )
        case .pressedKeysOverlay:
            return SettingsFeaturePresentation(
                systemImage: "keyboard",
                titleKey: .pressedKeysOverlay,
                summaryKey: .toolboxPressedKeysOverlaySummary,
                sectionKind: .howItWorks,
                rows: [
                    .value(
                        labelKey: .settingsFeatureShows,
                        value: .localized(.settingsFeatureModifiersCombinationsSingleKeys)
                    ),
                    .value(
                        labelKey: .settingsFeaturePosition,
                        value: .localized(.settingsFeatureBottomCenterActiveDisplay)
                    ),
                ]
            )
        case .virtualKeyboard:
            return SettingsFeaturePresentation(
                systemImage: "keyboard.badge.ellipsis",
                titleKey: .virtualKeyboard,
                summaryKey: .toolboxVirtualKeyboardSummary,
                sectionKind: .settings,
                rows: [
                    .value(labelKey: .settingsFeatureTrigger, value: .localized(.settingsFeatureHoldOption)),
                    .virtualKeyboardDelay,
                ]
            )
        case .hiddenBar:
            return SettingsFeaturePresentation(
                systemImage: HiddenBarPresentationMetrics.settingsRowIconSystemName,
                titleKey: .hiddenBar,
                summaryKey: .toolboxHiddenBarSummary,
                sectionKind: .howItWorks,
                rows: [
                    .value(labelKey: .settingsFeatureControl, value: .localized(.settingsFeatureMenuBarArrow)),
                    .value(
                        labelKey: .settingsFeatureArrangeItems,
                        value: .localized(.settingsFeatureCommandDragAcrossMarker)
                    ),
                    .value(labelKey: .settingsFeatureAutoCollapse, value: .localized(.settingsFeatureThirtySeconds)),
                ]
            )
        case .networkMonitor:
            return SettingsFeaturePresentation(
                systemImage: "network",
                titleKey: .networkMonitor,
                summaryKey: .toolboxNetworkMonitorSummary,
                sectionKind: .howItWorks,
                rows: [
                    .value(
                        labelKey: .settingsFeatureDisplay,
                        value: .localized(.settingsFeatureMenuBarUploadAboveDownload)
                    ),
                    .value(
                        labelKey: .settingsFeatureSource,
                        value: .localized(.settingsFeaturePrimaryNetworkInterface)
                    ),
                    .value(
                        labelKey: .settingsFeatureRefresh,
                        value: .localized(.settingsFeatureEveryTwoSeconds)
                    ),
                ]
            )
        case .hotKeyIconFlash:
            return SettingsFeaturePresentation(
                systemImage: "sparkles",
                titleKey: .hotKeyIconFlash,
                summaryKey: .toolboxHotKeyIconFlashSummary,
                sectionKind: .howItWorks,
                rows: [
                    .value(
                        labelKey: .settingsFeatureTrigger,
                        value: .localized(.settingsFeatureAppWinkHotkeysOnly)
                    ),
                    .value(
                        labelKey: .settingsFeatureDisplay,
                        value: .localized(.settingsFeatureTargetAppIconScreenCenter)
                    ),
                    .value(
                        labelKey: .settingsFeatureDuration,
                        value: .localized(.settingsFeatureAboutPoint45Seconds)
                    ),
                ]
            )
        case .advancedHotkeys:
            return SettingsFeaturePresentation(
                systemImage: "command",
                titleKey: .advancedHotkeys,
                summaryKey: .toolboxAdvancedHotkeysSummary,
                sectionKind: .howItWorks,
                rows: [
                    .value(
                        labelKey: .settingsFeatureShortcut,
                        value: .localized(.settingsFeatureAdvancedHotkeysCombinations)
                    ),
                ]
            )
        }
    }
}
