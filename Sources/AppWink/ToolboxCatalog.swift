import Foundation

struct ToolboxCatalogInput {
    let windowsStyleCutEnabled: Bool
    let mouseWheelWindowsScrollEnabled: Bool
    let pressedKeysOverlayEnabled: Bool
    let virtualKeyboardEnabled: Bool
    let hiddenBarEnabled: Bool
    let networkStatusEnabled: Bool
    let hotKeyIconFlashEnabled: Bool
    let advancedHotkeysEnabled: Bool
    let automaticUpdateChecksEnabled: Bool
    let showsAutomaticUpdateChecksControl: Bool
    let accessibilityPermissionGranted: Bool
    let canEditLaunchAtLogin: Bool
    let canCheckForUpdates: Bool
    let showsCheckForUpdatesAction: Bool
    let currentVersionText: String

    init(
        windowsStyleCutEnabled: Bool,
        mouseWheelWindowsScrollEnabled: Bool = false,
        pressedKeysOverlayEnabled: Bool,
        virtualKeyboardEnabled: Bool = true,
        hiddenBarEnabled: Bool = false,
        networkStatusEnabled: Bool = false,
        hotKeyIconFlashEnabled: Bool,
        advancedHotkeysEnabled: Bool = false,
        automaticUpdateChecksEnabled: Bool = false,
        showsAutomaticUpdateChecksControl: Bool = true,
        accessibilityPermissionGranted: Bool,
        canEditLaunchAtLogin: Bool = true,
        canCheckForUpdates: Bool = true,
        showsCheckForUpdatesAction: Bool = true,
        currentVersionText: String
    ) {
        self.windowsStyleCutEnabled = windowsStyleCutEnabled
        self.mouseWheelWindowsScrollEnabled = mouseWheelWindowsScrollEnabled
        self.pressedKeysOverlayEnabled = pressedKeysOverlayEnabled
        self.virtualKeyboardEnabled = virtualKeyboardEnabled
        self.hiddenBarEnabled = hiddenBarEnabled
        self.networkStatusEnabled = networkStatusEnabled
        self.hotKeyIconFlashEnabled = hotKeyIconFlashEnabled
        self.advancedHotkeysEnabled = advancedHotkeysEnabled
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        self.showsAutomaticUpdateChecksControl = showsAutomaticUpdateChecksControl
        self.accessibilityPermissionGranted = accessibilityPermissionGranted
        self.canEditLaunchAtLogin = canEditLaunchAtLogin
        self.canCheckForUpdates = canCheckForUpdates
        self.showsCheckForUpdatesAction = showsCheckForUpdatesAction
        self.currentVersionText = currentVersionText
    }
}

enum ToolboxToggleKind: String, Equatable, CaseIterable, Identifiable {
    case windowsStyleCut
    case mouseWheelWindowsScroll
    case pressedKeysOverlay
    case virtualKeyboard
    case hiddenBar
    case networkMonitor
    case hotKeyIconFlash
    case advancedHotkeys

    var id: String { rawValue }
}

struct ToolboxToggleRow: Equatable, Identifiable {
    let kind: ToolboxToggleKind
    let isOn: Bool
    let status: SettingsFeatureStatus

    var id: String { kind.id }
}

enum ToolboxOtherKind: String, Equatable, CaseIterable, Identifiable {
    case language
    case appearanceMode
    case launchAtLogin
    case automaticallyCheckForUpdates
    case checkForUpdates
    case help
    case currentVersion

    var id: String { rawValue }
}

struct ToolboxOtherRow: Equatable, Identifiable {
    let kind: ToolboxOtherKind
    let valueText: String?
    let isEnabled: Bool
    let isOn: Bool?

    var id: String { kind.id }

    init(
        kind: ToolboxOtherKind,
        valueText: String? = nil,
        isEnabled: Bool,
        isOn: Bool? = nil
    ) {
        self.kind = kind
        self.valueText = valueText
        self.isEnabled = isEnabled
        self.isOn = isOn
    }
}

struct ToolboxCatalogSnapshot: Equatable {
    let generalRows: [ToolboxOtherRow]
    let featureRows: [ToolboxToggleRow]
    let aboutAndUpdateRows: [ToolboxOtherRow]
}

enum ToolboxCatalog {
    static func build(from input: ToolboxCatalogInput) -> ToolboxCatalogSnapshot {
        let featureRows = [
            ToolboxToggleRow(
                kind: .windowsStyleCut,
                isOn: input.windowsStyleCutEnabled,
                status: featureStatus(
                    kind: .windowsStyleCut,
                    isOn: input.windowsStyleCutEnabled,
                    accessibilityPermissionGranted: input.accessibilityPermissionGranted
                )
            ),
            ToolboxToggleRow(
                kind: .mouseWheelWindowsScroll,
                isOn: input.mouseWheelWindowsScrollEnabled,
                status: featureStatus(
                    kind: .mouseWheelWindowsScroll,
                    isOn: input.mouseWheelWindowsScrollEnabled,
                    accessibilityPermissionGranted: input.accessibilityPermissionGranted
                )
            ),
            ToolboxToggleRow(
                kind: .pressedKeysOverlay,
                isOn: input.pressedKeysOverlayEnabled,
                status: featureStatus(
                    kind: .pressedKeysOverlay,
                    isOn: input.pressedKeysOverlayEnabled,
                    accessibilityPermissionGranted: input.accessibilityPermissionGranted
                )
            ),
            ToolboxToggleRow(
                kind: .virtualKeyboard,
                isOn: input.virtualKeyboardEnabled,
                status: featureStatus(
                    kind: .virtualKeyboard,
                    isOn: input.virtualKeyboardEnabled,
                    accessibilityPermissionGranted: input.accessibilityPermissionGranted
                )
            ),
            ToolboxToggleRow(
                kind: .hiddenBar,
                isOn: input.hiddenBarEnabled,
                status: featureStatus(
                    kind: .hiddenBar,
                    isOn: input.hiddenBarEnabled,
                    accessibilityPermissionGranted: input.accessibilityPermissionGranted
                )
            ),
            ToolboxToggleRow(
                kind: .networkMonitor,
                isOn: input.networkStatusEnabled,
                status: featureStatus(
                    kind: .networkMonitor,
                    isOn: input.networkStatusEnabled,
                    accessibilityPermissionGranted: input.accessibilityPermissionGranted
                )
            ),
            ToolboxToggleRow(
                kind: .hotKeyIconFlash,
                isOn: input.hotKeyIconFlashEnabled,
                status: featureStatus(
                    kind: .hotKeyIconFlash,
                    isOn: input.hotKeyIconFlashEnabled,
                    accessibilityPermissionGranted: input.accessibilityPermissionGranted
                )
            ),
            ToolboxToggleRow(
                kind: .advancedHotkeys,
                isOn: input.advancedHotkeysEnabled,
                status: featureStatus(
                    kind: .advancedHotkeys,
                    isOn: input.advancedHotkeysEnabled,
                    accessibilityPermissionGranted: input.accessibilityPermissionGranted
                )
            ),
        ]

        let generalRows = [
            ToolboxOtherRow(kind: .language, valueText: nil, isEnabled: true),
            ToolboxOtherRow(kind: .appearanceMode, valueText: nil, isEnabled: true),
            ToolboxOtherRow(kind: .launchAtLogin, valueText: nil, isEnabled: input.canEditLaunchAtLogin),
        ]
        let automaticUpdateChecksRows = input.showsAutomaticUpdateChecksControl
            ? [
                ToolboxOtherRow(
                    kind: .automaticallyCheckForUpdates,
                    valueText: nil,
                    isEnabled: true,
                    isOn: input.automaticUpdateChecksEnabled
                ),
            ]
            : []
        let updateActionRows = input.showsCheckForUpdatesAction
            ? [ToolboxOtherRow(kind: .checkForUpdates, valueText: nil, isEnabled: input.canCheckForUpdates)]
            : []
        let trailingOtherRows = [
            ToolboxOtherRow(kind: .currentVersion, valueText: input.currentVersionText, isEnabled: false),
            ToolboxOtherRow(kind: .help, valueText: nil, isEnabled: true),
        ]

        return ToolboxCatalogSnapshot(
            generalRows: generalRows,
            featureRows: featureRows,
            aboutAndUpdateRows: automaticUpdateChecksRows + updateActionRows + trailingOtherRows
        )
    }

    private static func featureStatus(
        kind: ToolboxToggleKind,
        isOn: Bool,
        accessibilityPermissionGranted: Bool
    ) -> SettingsFeatureStatus {
        guard isOn else { return .disabled }
        guard !kind.requiresAccessibilityPermission || accessibilityPermissionGranted else {
            return .permissionRequired
        }
        return .enabled
    }
}
