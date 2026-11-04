import XCTest
@testable import AppWinkRuntime

final class ToolboxCatalogTests: XCTestCase {
    func testBuildKeepsRowsInStableSectionOrder() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: true,
            mouseWheelWindowsScrollEnabled: true,
            pressedKeysOverlayEnabled: true,
            virtualKeyboardEnabled: true,
            hiddenBarEnabled: true,
            networkStatusEnabled: true,
            hotKeyIconFlashEnabled: true,
            advancedHotkeysEnabled: true,
            automaticUpdateChecksEnabled: true,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        XCTAssertEqual(snapshot.generalRows.map(\.kind), [.language, .appearanceMode, .launchAtLogin])
        XCTAssertEqual(snapshot.featureRows.map(\.kind), [.windowsStyleCut, .mouseWheelWindowsScroll, .pressedKeysOverlay, .virtualKeyboard, .hiddenBar, .networkMonitor, .hotKeyIconFlash, .advancedHotkeys])
        XCTAssertEqual(snapshot.featureRows.map(\.isOn), [true, true, true, true, true, true, true, true])
        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.kind), [.automaticallyCheckForUpdates, .checkForUpdates, .currentVersion, .help])
    }

    func testBuildUsesEnabledIntentAndSystemPermissionForMixedFeatureState() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: true,
            mouseWheelWindowsScrollEnabled: false,
            pressedKeysOverlayEnabled: true,
            virtualKeyboardEnabled: false,
            hiddenBarEnabled: true,
            networkStatusEnabled: false,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: true,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        XCTAssertEqual(snapshot.featureRows.map(\.isOn), [true, false, true, false, true, false, false, true])
        XCTAssertEqual(snapshot.featureRows.map(\.status), [.permissionRequired, .disabled, .permissionRequired, .disabled, .enabled, .disabled, .disabled, .enabled])
    }

    func testBuildMarksEnabledAccessibilityFeaturesPermissionRequiredWhenPermissionIsMissing() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: true,
            mouseWheelWindowsScrollEnabled: true,
            pressedKeysOverlayEnabled: true,
            virtualKeyboardEnabled: true,
            hiddenBarEnabled: true,
            networkStatusEnabled: true,
            hotKeyIconFlashEnabled: true,
            advancedHotkeysEnabled: true,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        XCTAssertEqual(
            snapshot.featureRows.map(\.status),
            [.permissionRequired, .permissionRequired, .permissionRequired, .enabled, .enabled, .enabled, .enabled, .enabled]
        )
    }

    func testBuildMarksEveryEnabledFeatureEnabledWhenPermissionIsGranted() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: true,
            mouseWheelWindowsScrollEnabled: true,
            pressedKeysOverlayEnabled: true,
            virtualKeyboardEnabled: true,
            hiddenBarEnabled: true,
            networkStatusEnabled: true,
            hotKeyIconFlashEnabled: true,
            advancedHotkeysEnabled: true,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: true,
            canCheckForUpdates: true
        ))

        XCTAssertEqual(snapshot.featureRows.map(\.status), [.enabled, .enabled, .enabled, .enabled, .enabled, .enabled, .enabled, .enabled])
    }

    func testBuildMarksDisabledFeaturesDisabledWhenPermissionIsMissing() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            mouseWheelWindowsScrollEnabled: false,
            pressedKeysOverlayEnabled: false,
            virtualKeyboardEnabled: false,
            hiddenBarEnabled: false,
            networkStatusEnabled: false,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        XCTAssertEqual(snapshot.featureRows.map(\.status), [.disabled, .disabled, .disabled, .disabled, .disabled, .disabled, .disabled, .disabled])
    }

    func testBuildKeepsGeneralAndAboutAndUpdateRowsInStableOrder() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: true,
            canEditLaunchAtLogin: true,
            canCheckForUpdates: true
        ))

        XCTAssertEqual(snapshot.generalRows.map(\.kind), [.language, .appearanceMode, .launchAtLogin])
        XCTAssertEqual(snapshot.generalRows.map(\.valueText), [nil, nil, nil])
        XCTAssertEqual(snapshot.generalRows.map(\.isEnabled), [true, true, true])
        XCTAssertEqual(snapshot.generalRows.map(\.isOn), [nil, nil, nil])
        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.kind), [.automaticallyCheckForUpdates, .checkForUpdates, .currentVersion, .help])
        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.valueText), [nil, nil, "0.1.6", nil])
        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.isEnabled), [true, true, false, true])
        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.isOn), [false, nil, nil, nil])
    }

    func testBuildReflectsAutomaticUpdateChecksAndCheckForUpdatesEnabledStateIndependently() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: true,
            accessibilityPermissionGranted: true,
            canEditLaunchAtLogin: true,
            canCheckForUpdates: false
        ))

        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.kind), [.automaticallyCheckForUpdates, .checkForUpdates, .currentVersion, .help])
        XCTAssertEqual(snapshot.aboutAndUpdateRows[0].isOn, true)
        XCTAssertEqual(snapshot.aboutAndUpdateRows[1].isEnabled, false)
        XCTAssertFalse(snapshot.aboutAndUpdateRows[2].isEnabled)
    }

    func testBuildOmitsAutomaticUpdateChecksRowWhenChannelHidesIt() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: true,
            showsAutomaticUpdateChecksControl: false,
            accessibilityPermissionGranted: true,
            canCheckForUpdates: true
        ))

        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.kind), [.checkForUpdates, .currentVersion, .help])
    }

    func testBuildOmitsCheckForUpdatesRowWhenChannelHidesIt() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: false
        ))

        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.kind), [.automaticallyCheckForUpdates, .currentVersion, .help])
    }

    func testBuildKeepsAdvancedHotkeysAvailableWithoutAccessibility() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: true,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        let row = snapshot.featureRows.first { $0.kind == .advancedHotkeys }
        XCTAssertEqual(row?.status, .enabled)
    }

    func testBuildReflectsHiddenBarState() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            hiddenBarEnabled: true,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        let row = snapshot.featureRows.first { $0.kind == .hiddenBar }
        XCTAssertEqual(row?.isOn, true)
    }

    func testBuildKeepsEnabledNetworkMonitorAvailableWithoutAccessibilityPermission() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            networkStatusEnabled: true,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        let row = snapshot.featureRows.first { $0.kind == .networkMonitor }
        XCTAssertEqual(row?.isOn, true)
        XCTAssertEqual(row?.status, .enabled)
    }

    func testBuildReflectsVirtualKeyboardState() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            virtualKeyboardEnabled: true,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        let row = snapshot.featureRows.first { $0.kind == .virtualKeyboard }
        XCTAssertEqual(row?.isOn, true)
    }

    func testBuildReflectsHotKeyIconFlashState() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            hotKeyIconFlashEnabled: true,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: false,
            canCheckForUpdates: true
        ))

        let row = snapshot.featureRows.first { $0.kind == .hotKeyIconFlash }
        XCTAssertEqual(row?.isOn, true)
    }

    func testBuildDisablesLaunchAtLoginRowWhenLoginItemEditingIsUnavailable() {
        let snapshot = ToolboxCatalog.build(from: makeInput(
            windowsStyleCutEnabled: false,
            pressedKeysOverlayEnabled: false,
            hotKeyIconFlashEnabled: false,
            advancedHotkeysEnabled: false,
            automaticUpdateChecksEnabled: false,
            accessibilityPermissionGranted: true,
            canEditLaunchAtLogin: false,
            canCheckForUpdates: true
        ))

        XCTAssertEqual(snapshot.generalRows[2].kind, .launchAtLogin)
        XCTAssertFalse(snapshot.generalRows[2].isEnabled)
    }

    private func makeInput(
        windowsStyleCutEnabled: Bool,
        mouseWheelWindowsScrollEnabled: Bool = false,
        pressedKeysOverlayEnabled: Bool,
        virtualKeyboardEnabled: Bool = false,
        hiddenBarEnabled: Bool = false,
        networkStatusEnabled: Bool = false,
        hotKeyIconFlashEnabled: Bool = false,
        advancedHotkeysEnabled: Bool,
        automaticUpdateChecksEnabled: Bool,
        showsAutomaticUpdateChecksControl: Bool = true,
        accessibilityPermissionGranted: Bool,
        canEditLaunchAtLogin: Bool = true,
        canCheckForUpdates: Bool,
        showsCheckForUpdatesAction: Bool = true
    ) -> ToolboxCatalogInput {
        ToolboxCatalogInput(
            windowsStyleCutEnabled: windowsStyleCutEnabled,
            mouseWheelWindowsScrollEnabled: mouseWheelWindowsScrollEnabled,
            pressedKeysOverlayEnabled: pressedKeysOverlayEnabled,
            virtualKeyboardEnabled: virtualKeyboardEnabled,
            hiddenBarEnabled: hiddenBarEnabled,
            networkStatusEnabled: networkStatusEnabled,
            hotKeyIconFlashEnabled: hotKeyIconFlashEnabled,
            advancedHotkeysEnabled: advancedHotkeysEnabled,
            automaticUpdateChecksEnabled: automaticUpdateChecksEnabled,
            showsAutomaticUpdateChecksControl: showsAutomaticUpdateChecksControl,
            accessibilityPermissionGranted: accessibilityPermissionGranted,
            canEditLaunchAtLogin: canEditLaunchAtLogin,
            canCheckForUpdates: canCheckForUpdates,
            showsCheckForUpdatesAction: showsCheckForUpdatesAction,
            currentVersionText: "0.1.6"
        )
    }
}
