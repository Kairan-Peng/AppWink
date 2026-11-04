import AppWinkCore
import XCTest
@testable import AppWinkRuntime

final class SettingsFeaturePresentationTests: XCTestCase {
    func testOffVirtualKeyboardDisablesSubordinateControls() {
        let row = ToolboxToggleRow(
            kind: .virtualKeyboard,
            isOn: false,
            status: .disabled
        )

        let state = SettingsFeatureControlState(row: row)

        XCTAssertFalse(state.subordinateControlsEnabled)
        XCTAssertFalse(state.showsPermissionCallout)
    }

    func testPermissionRequiredPressedKeysShowsPermissionCallout() {
        let row = ToolboxToggleRow(
            kind: .pressedKeysOverlay,
            isOn: true,
            status: .permissionRequired
        )

        let state = SettingsFeatureControlState(row: row)

        XCTAssertTrue(state.subordinateControlsEnabled)
        XCTAssertTrue(state.showsPermissionCallout)
    }

    func testStatusAndSectionKindsUseExpectedLocalizationKeys() {
        XCTAssertEqual(SettingsFeatureStatus.enabled.localizationKey, .settingsFeatureStatusEnabled)
        XCTAssertEqual(SettingsFeatureStatus.disabled.localizationKey, .settingsFeatureStatusDisabled)
        XCTAssertEqual(SettingsFeatureStatus.permissionRequired.localizationKey, .settingsFeatureStatusPermissionRequired)
        XCTAssertEqual(SettingsFeatureDetailSectionKind.settings.titleKey, .settingsFeatureSettingsSection)
        XCTAssertEqual(SettingsFeatureDetailSectionKind.howItWorks.titleKey, .settingsFeatureHowItWorksSection)
    }

    func testAllFeaturesHaveStableTitlesAndSystemImages() {
        let expectedKinds: [ToolboxToggleKind] = [
            .windowsStyleCut,
            .mouseWheelWindowsScroll,
            .pressedKeysOverlay,
            .virtualKeyboard,
            .hiddenBar,
            .networkMonitor,
            .hotKeyIconFlash,
            .advancedHotkeys,
        ]

        XCTAssertEqual(ToolboxToggleKind.allCases, expectedKinds)
        XCTAssertEqual(
            ToolboxToggleKind.allCases.map { $0.presentation.titleKey },
            [
                .windowsStyleCut,
                .mouseWheelWindowsScroll,
                .pressedKeysOverlay,
                .virtualKeyboard,
                .hiddenBar,
                .networkMonitor,
                .hotKeyIconFlash,
                .advancedHotkeys,
            ]
        )
        XCTAssertTrue(ToolboxToggleKind.allCases.allSatisfy { !$0.presentation.systemImage.isEmpty })
    }

    func testAccessibilityDependentFeaturesAreExact() {
        XCTAssertEqual(
            ToolboxToggleKind.allCases.filter(\.requiresAccessibilityPermission),
            [
                .windowsStyleCut,
                .mouseWheelWindowsScroll,
                .pressedKeysOverlay,
            ]
        )
    }

    func testPermissionMessagesMatchAccessibilityDependentFeatures() {
        XCTAssertEqual(ToolboxToggleKind.windowsStyleCut.permissionMessageKey, .windowsStyleCutPermissionRequired)
        XCTAssertEqual(
            ToolboxToggleKind.mouseWheelWindowsScroll.permissionMessageKey,
            .mouseWheelWindowsScrollPermissionRequired
        )
        XCTAssertEqual(ToolboxToggleKind.pressedKeysOverlay.permissionMessageKey, .pressedKeysOverlayPermissionRequired)
        XCTAssertNil(ToolboxToggleKind.virtualKeyboard.permissionMessageKey)
        XCTAssertNil(ToolboxToggleKind.hiddenBar.permissionMessageKey)
        XCTAssertNil(ToolboxToggleKind.networkMonitor.permissionMessageKey)
        XCTAssertNil(ToolboxToggleKind.hotKeyIconFlash.permissionMessageKey)
        XCTAssertNil(ToolboxToggleKind.advancedHotkeys.permissionMessageKey)
    }

    func testFeaturePresentationsContainExpectedMetadataAndRows() {
        XCTAssertEqual(
            ToolboxToggleKind.windowsStyleCut.presentation,
            SettingsFeaturePresentation(
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
        )
        XCTAssertEqual(
            ToolboxToggleKind.mouseWheelWindowsScroll.presentation,
            SettingsFeaturePresentation(
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
        )
        XCTAssertEqual(
            ToolboxToggleKind.pressedKeysOverlay.presentation,
            SettingsFeaturePresentation(
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
        )
        XCTAssertEqual(
            ToolboxToggleKind.virtualKeyboard.presentation,
            SettingsFeaturePresentation(
                systemImage: "keyboard.badge.ellipsis",
                titleKey: .virtualKeyboard,
                summaryKey: .toolboxVirtualKeyboardSummary,
                sectionKind: .settings,
                rows: [
                    .value(labelKey: .settingsFeatureTrigger, value: .localized(.settingsFeatureHoldOption)),
                    .virtualKeyboardDelay,
                ]
            )
        )
        XCTAssertEqual(
            ToolboxToggleKind.hiddenBar.presentation,
            SettingsFeaturePresentation(
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
        )
        XCTAssertEqual(
            ToolboxToggleKind.networkMonitor.presentation,
            SettingsFeaturePresentation(
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
        )
        XCTAssertEqual(
            ToolboxToggleKind.hotKeyIconFlash.presentation,
            SettingsFeaturePresentation(
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
        )
        XCTAssertEqual(
            ToolboxToggleKind.advancedHotkeys.presentation,
            SettingsFeaturePresentation(
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
        )
    }

    func testOnlyVirtualKeyboardHasDelayRow() {
        for kind in ToolboxToggleKind.allCases {
            let delayRowCount = kind.presentation.rows.reduce(into: 0) { count, row in
                if case .virtualKeyboardDelay = row {
                    count += 1
                }
            }
            XCTAssertEqual(delayRowCount, kind == .virtualKeyboard ? 1 : 0, "Unexpected delay rows for \(kind)")
        }
    }

    func testAdvancedHotkeysShowsLocalizedCombinationRule() {
        let shortcutRow = ToolboxToggleKind.advancedHotkeys.presentation.rows.first { row in
            guard case let .value(labelKey, _) = row else { return false }
            return labelKey == .settingsFeatureShortcut
        }

        guard let shortcutRow else {
            return XCTFail("Expected advanced-hotkeys shortcut row")
        }
        guard case let .value(_, value) = shortcutRow else {
            return XCTFail("Expected a read-only value row")
        }
        guard case let .localized(key) = value else {
            return XCTFail("Expected a localized shortcut value")
        }

        XCTAssertEqual(key, .settingsFeatureAdvancedHotkeysCombinations)
    }
}
