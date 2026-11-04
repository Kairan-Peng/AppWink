import AppKit
import Foundation
import XCTest
import AppWinkCore
@testable import AppWinkRuntime

@MainActor
final class AppModelTests: XCTestCase {
    func testFreshInstallationRegistersAndExecutesHotkeysWithoutActivation() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Application",
            bundleIdentifier: "com.example.application",
            in: directory
        )
        let binding = HotkeyBinding(
            target: .application(try ManagedApplication(url: applicationURL)),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let manager = HotKeyManagerSpy()
        let executor = BindingActionExecutorSpy()
        let model = makeModel(
            hotKeyManager: manager,
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        XCTAssertEqual(manager.lastRequests.map(\.action), [.binding(binding.id)])
        XCTAssertTrue(model.canPerformMenuBarSwitchAction(for: binding.id))

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: try XCTUnwrap(binding.shortcut),
            frontmostProcessIdentifier: 55
        )

        XCTAssertTrue(waitUntil { executor.calls.count == 1 })
        XCTAssertEqual(executor.calls.first?.source, .hotKey)
        XCTAssertNil(model.statusMessage)

        model.performAction(for: binding.id, source: .manual)

        XCTAssertTrue(waitUntil { executor.calls.count == 2 })
        XCTAssertEqual(executor.calls.last?.source, .manual)
    }

    func testExpiredCommercialStateStillRegistersConfiguredHotKeys() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Application",
            bundleIdentifier: "com.example.application",
            in: directory
        )
        let binding = HotkeyBinding(
            target: .application(try ManagedApplication(url: applicationURL)),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let namespace = "art.awink.AppWink.direct-license."
        let expiredAnchor = Data(#"{"startedAt":-800000000}"#.utf8)
        let obsoleteStates: [[String: Data]] = [
            [
                "monetization.trialAnchor": expiredAnchor,
                namespace + "trial-anchor": expiredAnchor,
            ],
            [
                namespace + "device-id": Data("obsolete-device".utf8),
                namespace + "license-key": Data("obsolete-license".utf8),
                namespace + "activation-id": Data("obsolete-activation".utf8),
                namespace + "entitlement-envelope": Data(#"{"state":"expired"}"#.utf8),
                namespace + "revocation-envelope": Data(#"{"state":"revoked"}"#.utf8),
                namespace + "manifest-envelope": Data("invalid-manifest".utf8),
            ],
            [
                "monetization.trialAnchor": Data([0x00, 0xFF]),
                namespace + "trial-anchor": Data("invalid-anchor".utf8),
                namespace + "entitlement-envelope": Data("invalid-entitlement".utf8),
            ],
        ]

        for obsoleteState in obsoleteStates {
            let suiteName = "AppWinkTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            for (key, value) in obsoleteState {
                defaults.set(value, forKey: key)
            }
            let manager = HotKeyManagerSpy()
            let executor = BindingActionExecutorSpy()
            let model = makeModel(
                hotKeyManager: manager,
                bindingActionExecutor: executor,
                bindings: [binding],
                networkStatusEnabled: true,
                configurationDefaults: defaults
            )

            model.handleApplicationDidBecomeActive()

            XCTAssertEqual(manager.lastRequests.map(\.action), [.binding(binding.id)])
            XCTAssertTrue(model.canPerformMenuBarSwitchAction(for: binding.id))
            XCTAssertTrue(model.networkStatusRuntimeEnabled)
            model.handleHotKeyTrigger(
                for: binding.id,
                shortcut: try XCTUnwrap(binding.shortcut),
                frontmostProcessIdentifier: 55
            )
            XCTAssertTrue(waitUntil { executor.calls.count == 1 })
            XCTAssertNil(model.statusMessage)

            model.setHotKeyIconFlashEnabled(true)

            XCTAssertTrue(model.hotKeyIconFlashRuntimeEnabled)
            XCTAssertTrue(try UserDefaultsAppConfigurationStore(defaults: defaults).load().hotKeyIconFlashEnabled)
            for (key, value) in obsoleteState {
                XCTAssertEqual(defaults.data(forKey: key), value, key)
            }
        }
    }

    func testLaunchingFreeVersionPreservesExistingConfigurationBytes() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Application",
            bundleIdentifier: "com.example.application",
            in: directory
        )
        let folderURL = directory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("fixture".utf8).write(to: fileURL)
        let application = try ManagedApplication(url: applicationURL)
        let configuration = AppConfiguration(
            bindings: [
                HotkeyBinding(
                    target: .file(try ManagedFileSystemItem(url: fileURL), .application(application)),
                    shortcut: AppShortcut(keyCode: 0, modifiers: [.command, .shift]),
                    isEnabled: false
                ),
                HotkeyBinding(
                    target: .folder(try ManagedFileSystemItem(url: folderURL), .finderNewTab),
                    shortcut: AppShortcut(keyCode: 1, modifiers: [.option])
                ),
                HotkeyBinding(
                    target: .application(application),
                    shortcut: AppShortcut(keyCode: 2, modifiers: [.control, .option])
                ),
            ],
            language: .english,
            appearanceMode: .dark,
            windowsStyleCutEnabled: true,
            pressedKeysOverlayEnabled: true,
            advancedHotkeysEnabled: true,
            hotKeyIconFlashEnabled: true,
            hiddenBarEnabled: true,
            networkStatusEnabled: true,
            mouseWheelWindowsScrollEnabled: true,
            virtualKeyboardEnabled: false,
            virtualKeyboardRevealDelay: 0.75
        )
        let storageKey = "com.kairanpeng.appwink.configuration"
        let originalBytes = try JSONEncoder().encode(configuration)
        defaults.set(originalBytes, forKey: storageKey)
        defaults.set(Data("obsolete-commercial-state".utf8), forKey: "monetization.trialAnchor")
        let store = UserDefaultsAppConfigurationStore(
            defaults: defaults,
            legacyStorageKeys: [],
            legacyPersistentDomains: []
        )
        let model = AppModel(
            store: store,
            hotKeyManager: HotKeyManagerSpy(),
            bindingActionExecutor: BindingActionExecutorSpy(),
            launchAtLoginController: TestLaunchAtLoginController(),
            hotkeyGuideStore: FakeHotkeyGuideStateStore(),
            accessibilityPermissionStatusProvider: { false }
        )

        model.handleApplicationDidBecomeActive()

        XCTAssertEqual(model.configuration, configuration)
        XCTAssertEqual(try store.load(), configuration)
        XCTAssertEqual(defaults.data(forKey: storageKey), originalBytes)
        XCTAssertTrue(model.networkStatusRuntimeEnabled)
        XCTAssertFalse(model.accessibilityPermissionGranted)
        XCTAssertTrue(model.shouldShowAccessibilityPermissionCallout)
    }

    func testSettingsWindowRouteStartsAtSettings() {
        let model = makeModel()

        XCTAssertEqual(model.settingsWindowRoute, .settings)
    }

    func testShowSettingsWindowHelpSetsHelpRoute() {
        let model = makeModel()

        model.showSettingsWindowHelp()

        XCTAssertEqual(model.settingsWindowRoute, .help)
    }

    func testShowSettingsFeatureRoutesEveryFeature() {
        for kind in ToolboxToggleKind.allCases {
            let model = makeModel(accessibilityPermissionGranted: false)

            model.showSettingsFeature(kind)

            XCTAssertEqual(model.settingsWindowRoute, .feature(kind))
        }
    }

    func testShowSettingsWindowHomeReturnsToSettingsHome() {
        let model = makeModel()

        model.showSettingsWindowHelp()
        model.showSettingsWindowHome()

        XCTAssertEqual(model.settingsWindowRoute, .settings)
    }

    func testShowSettingsWindowHomeReturnsFromFeatureRoute() {
        let model = makeModel()
        model.showSettingsFeature(.hiddenBar)

        model.showSettingsWindowHome()

        XCTAssertEqual(model.settingsWindowRoute, .settings)
    }

    func testOpenSettingsWindowResetsFeatureRouteToHome() {
        let model = makeModel()
        model.setSettingsWindowPresenter {}
        model.showSettingsFeature(.virtualKeyboard)

        model.openSettingsWindow()

        XCTAssertEqual(model.settingsWindowRoute, .settings)
    }

    func testOpenSettingsWindowUsesOnlySettingsPresenter() {
        let model = makeModel()
        var mainPresenterCallCount = 0
        var settingsPresenterCallCount = 0
        model.setMainWindowPresenter {
            mainPresenterCallCount += 1
        }
        model.setSettingsWindowPresenter {
            settingsPresenterCallCount += 1
        }

        model.openSettingsWindow()

        XCTAssertEqual(model.settingsWindowRoute, .settings)
        XCTAssertEqual(mainPresenterCallCount, 0)
        XCTAssertEqual(settingsPresenterCallCount, 1)
    }

    func testSettingsRouteChangesRecordDiagnosticsWhenSampling() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        recorder.startSampling(round: .core)
        let model = makeModel(performanceDiagnosticsRecorder: recorder)

        model.showSettingsWindowHelp()
        model.showSettingsWindowHome()
        model.showSettingsFeature(.virtualKeyboard)

        let counters = recorder.snapshot().counters
        XCTAssertEqual(counters["uiTransition.settingsHelpOpened"], 1)
        XCTAssertEqual(counters["uiTransition.settingsHomeOpened"], 1)
        XCTAssertEqual(counters["uiTransition.settingsFeatureOpened.virtualKeyboard"], 1)
    }

    func testOpenHotkeyConfigurationUsesOnlyMainPresenter() {
        let model = makeModel()
        var mainPresenterCallCount = 0
        var settingsPresenterCallCount = 0
        model.setMainWindowPresenter {
            mainPresenterCallCount += 1
        }
        model.setSettingsWindowPresenter {
            settingsPresenterCallCount += 1
        }

        model.openHotkeyConfiguration()

        XCTAssertEqual(mainPresenterCallCount, 1)
        XCTAssertEqual(settingsPresenterCallCount, 0)
    }

    func testFirstMainWindowAppearanceAutoShowsHotkeyGuideWhenNotDismissed() {
        let model = makeModel()

        model.handleMainHotkeyWindowAppeared()

        XCTAssertTrue(model.hotkeyGuideIsRequested)
        XCTAssertTrue(model.shouldShowHotkeyGuideBanner)
    }

    func testDismissedHotkeyGuideSuppressesAutoShow() {
        let model = makeModel(hotkeyGuideStore: FakeHotkeyGuideStateStore(isDismissed: true))

        model.handleMainHotkeyWindowAppeared()

        XCTAssertFalse(model.hotkeyGuideIsRequested)
        XCTAssertFalse(model.shouldShowHotkeyGuideBanner)
    }

    func testDismissHotkeyGuideHidesGuideAndPersistsDismissal() {
        let hotkeyGuideStore = FakeHotkeyGuideStateStore()
        let model = makeModel(hotkeyGuideStore: hotkeyGuideStore)
        model.handleMainHotkeyWindowAppeared()

        model.dismissHotkeyGuide()

        XCTAssertFalse(model.hotkeyGuideIsRequested)
        XCTAssertFalse(model.shouldShowHotkeyGuideBanner)
        XCTAssertTrue(hotkeyGuideStore.isDismissed)
    }

    func testManualHelpButtonShowsHotkeyGuideAfterPriorDismissal() {
        let model = makeModel(hotkeyGuideStore: FakeHotkeyGuideStateStore(isDismissed: true))

        model.toggleHotkeyGuideFromHelpButton()

        XCTAssertTrue(model.hotkeyGuideIsRequested)
        XCTAssertTrue(model.shouldShowHotkeyGuideBanner)
    }

    func testManualHelpButtonDismissesVisibleHotkeyGuideAndPersistsDismissal() {
        let hotkeyGuideStore = FakeHotkeyGuideStateStore()
        let model = makeModel(hotkeyGuideStore: hotkeyGuideStore)
        model.handleMainHotkeyWindowAppeared()

        model.toggleHotkeyGuideFromHelpButton()

        XCTAssertFalse(model.hotkeyGuideIsRequested)
        XCTAssertFalse(model.shouldShowHotkeyGuideBanner)
        XCTAssertTrue(hotkeyGuideStore.isDismissed)
    }

    func testShortcutConflictSuppressesAutoGuideUntilConflictClears() {
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let notes = makeBinding(
            named: "Notes",
            fallbackPath: "/System/Applications/Notes.app",
            shortcut: shortcut
        )
        let textEdit = makeBinding(
            named: "TextEdit",
            fallbackPath: "/System/Applications/TextEdit.app",
            shortcut: shortcut
        )
        let model = makeModel(bindings: [notes, textEdit])

        model.handleMainHotkeyWindowAppeared()

        XCTAssertTrue(model.hotkeyGuideIsRequested)
        XCTAssertFalse(model.shouldShowHotkeyGuideBanner)

        model.setShortcut(nil, for: textEdit.id)

        XCTAssertNil(model.shortcutConflictReminder)
        XCTAssertTrue(model.hotkeyGuideIsRequested)
        XCTAssertTrue(model.shouldShowHotkeyGuideBanner)
    }

    func testHelpButtonDuringShortcutConflictKeepsGuidePendingUntilConflictClears() {
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let notes = makeBinding(
            named: "Notes",
            fallbackPath: "/System/Applications/Notes.app",
            shortcut: shortcut
        )
        let textEdit = makeBinding(
            named: "TextEdit",
            fallbackPath: "/System/Applications/TextEdit.app",
            shortcut: shortcut
        )
        let model = makeModel(
            bindings: [notes, textEdit],
            hotkeyGuideStore: FakeHotkeyGuideStateStore(isDismissed: true)
        )

        model.toggleHotkeyGuideFromHelpButton()

        XCTAssertTrue(model.hotkeyGuideIsRequested)
        XCTAssertFalse(model.shouldShowHotkeyGuideBanner)

        model.setShortcut(nil, for: textEdit.id)

        XCTAssertNil(model.shortcutConflictReminder)
        XCTAssertTrue(model.hotkeyGuideIsRequested)
        XCTAssertTrue(model.shouldShowHotkeyGuideBanner)
    }

    func testToolboxSnapshotRowsStayOrderedAndWindowsStyleCutIsDisabledByDefault() {
        let model = makeModel()
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: false,
            showsAutomaticUpdateChecksControl: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: true
        )

        XCTAssertEqual(
            snapshot.featureRows.map(\.kind),
            [.windowsStyleCut, .mouseWheelWindowsScroll, .pressedKeysOverlay, .virtualKeyboard, .hiddenBar, .networkMonitor, .hotKeyIconFlash, .advancedHotkeys]
        )
        XCTAssertEqual(
            snapshot.generalRows.map(\.kind),
            [.language, .appearanceMode, .launchAtLogin]
        )
        XCTAssertEqual(
            snapshot.aboutAndUpdateRows.map(\.kind),
            [.automaticallyCheckForUpdates, .checkForUpdates, .currentVersion, .help]
        )
        XCTAssertEqual(snapshot.aboutAndUpdateRows[0].isOn, false)
    }

    func testToolboxSnapshotReflectsPressedKeysOverlayEnabledState() {
        let model = makeModel(pressedKeysOverlayEnabled: true)
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: false,
            showsAutomaticUpdateChecksControl: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: true
        )

        let overlayRow = snapshot.featureRows.first { $0.kind == .pressedKeysOverlay }

        XCTAssertEqual(overlayRow?.isOn, true)
    }

    func testToolboxSnapshotReflectsVirtualKeyboardEnabledState() {
        let model = makeModel(virtualKeyboardEnabled: false)
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: false,
            showsAutomaticUpdateChecksControl: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: true
        )

        let row = snapshot.featureRows.first { $0.kind == .virtualKeyboard }

        XCTAssertEqual(row?.isOn, false)
    }

    func testToolboxSnapshotReflectsHiddenBarEnabledState() {
        let model = makeModel(hiddenBarEnabled: true)
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: false,
            showsAutomaticUpdateChecksControl: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: true
        )

        let hiddenBarRow = snapshot.featureRows.first { $0.kind == .hiddenBar }

        XCTAssertEqual(hiddenBarRow?.isOn, true)
    }

    func testToolboxSnapshotReflectsSavedNetworkStatusWithoutAccessibilityRequirement() {
        let model = makeModel(
            networkStatusEnabled: true,
            accessibilityPermissionGranted: false
        )
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: false,
            showsAutomaticUpdateChecksControl: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: true
        )

        let row = snapshot.featureRows.first { $0.kind == .networkMonitor }
        XCTAssertEqual(row?.isOn, true)
        XCTAssertEqual(row?.status, .enabled)
    }

    func testToolboxSnapshotReflectsMouseWheelWindowsScrollEnabledState() {
        let model = makeModel(mouseWheelWindowsScrollEnabled: true)
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: false,
            showsAutomaticUpdateChecksControl: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: true
        )

        let row = snapshot.featureRows.first { $0.kind == .mouseWheelWindowsScroll }

        XCTAssertEqual(row?.isOn, true)
    }

    func testToolboxSnapshotReflectsAdvancedHotkeysEnabledState() {
        let model = makeModel(advancedHotkeysEnabled: true)
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: false,
            showsAutomaticUpdateChecksControl: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: true
        )

        let advancedHotkeysRow = snapshot.featureRows.first { $0.kind == .advancedHotkeys }

        XCTAssertEqual(advancedHotkeysRow?.isOn, true)
    }

    func testAppearanceModeDefaultsToSystemAndCanBeUpdated() {
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }

        let model = makeModel()

        XCTAssertEqual(model.appearanceMode, .system)

        model.setAppearanceMode(.dark)

        XCTAssertEqual(model.appearanceMode, .dark)
        XCTAssertEqual(model.configuration.appearanceMode, .dark)
        XCTAssertEqual(application.appearance?.name, NSAppearance.Name.darkAqua)
    }

    func testToolboxSnapshotOmitsUpdaterRowsWhenChannelHidesThem() {
        let model = makeModel()
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: false,
            showsAutomaticUpdateChecksControl: false,
            canCheckForUpdates: false,
            showsCheckForUpdatesAction: false
        )

        XCTAssertEqual(snapshot.featureRows.map(\.kind), [.windowsStyleCut, .mouseWheelWindowsScroll, .pressedKeysOverlay, .virtualKeyboard, .hiddenBar, .networkMonitor, .hotKeyIconFlash, .advancedHotkeys])
        XCTAssertEqual(snapshot.generalRows.map(\.kind), [.language, .appearanceMode, .launchAtLogin])
        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.kind), [.currentVersion, .help])
    }

    func testToolboxSnapshotKeepsAutomaticUpdateChecksWhenManualUpdateCheckIsHidden() {
        let model = makeModel()
        let snapshot = model.toolboxSnapshot(
            automaticUpdateChecksEnabled: true,
            showsAutomaticUpdateChecksControl: true,
            canCheckForUpdates: true,
            showsCheckForUpdatesAction: false
        )

        XCTAssertEqual(snapshot.featureRows.map(\.kind), [.windowsStyleCut, .mouseWheelWindowsScroll, .pressedKeysOverlay, .virtualKeyboard, .hiddenBar, .networkMonitor, .hotKeyIconFlash, .advancedHotkeys])
        XCTAssertEqual(snapshot.generalRows.map(\.kind), [.language, .appearanceMode, .launchAtLogin])
        XCTAssertEqual(snapshot.aboutAndUpdateRows.map(\.kind), [.automaticallyCheckForUpdates, .currentVersion, .help])
        XCTAssertEqual(snapshot.aboutAndUpdateRows[0].isOn, true)
    }

    func testHiddenPressedKeysOverlayStateDoesNotTriggerAccessibilityPermissionCallout() {
        let model = makeModel(
            pressedKeysOverlayEnabled: true,
            accessibilityPermissionGranted: false
        )

        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)
    }

    func testHiddenBarStateDoesNotTriggerAccessibilityPermissionCallout() {
        let model = makeModel(
            hiddenBarEnabled: true,
            accessibilityPermissionGranted: false
        )

        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)
    }

    func testRetiredActivityMonitorHotKeyDoesNotContributeToAccessibilityPermissionCallout() {
        let model = makeModel(
            activityMonitorHotKeyEnabled: true,
            accessibilityPermissionGranted: false
        )

        XCTAssertFalse(model.activityMonitorHotKeyEnabled)
        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)
    }

    func testSetPressedKeysOverlayEnabledUpdatesConfigurationAndInvokesCallback() {
        let model = makeModel(accessibilityPermissionGranted: true)
        var callbackCount = 0
        model.pressedKeysOverlaySettingsDidChange = {
            callbackCount += 1
        }

        model.setPressedKeysOverlayEnabled(true)

        XCTAssertTrue(model.pressedKeysOverlayEnabled)
        XCTAssertEqual(model.configuration.pressedKeysOverlayEnabled, true)
        XCTAssertEqual(callbackCount, 1)
    }

    func testSetPressedKeysOverlayEnabledWithoutPermissionShowsPermissionRequiredStatus() {
        let model = makeModel(accessibilityPermissionGranted: false)

        model.setPressedKeysOverlayEnabled(true)

        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .pressedKeysOverlayPermissionRequired)
        )
    }

    func testSetVirtualKeyboardEnabledUpdatesConfigurationStatusAndCallback() {
        let model = makeModel(virtualKeyboardEnabled: false)
        var callbackCount = 0
        model.virtualKeyboardSettingsDidChange = {
            callbackCount += 1
        }

        model.setVirtualKeyboardEnabled(true)

        XCTAssertTrue(model.virtualKeyboardEnabled)
        XCTAssertEqual(model.configuration.virtualKeyboardEnabled, true)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .virtualKeyboardEnabled)
        )
    }

    func testSetVirtualKeyboardRevealDelayNormalizesAndInvokesCallback() {
        let model = makeModel()
        var callbackCount = 0
        model.virtualKeyboardSettingsDidChange = {
            callbackCount += 1
        }

        model.setVirtualKeyboardRevealDelay(0.74)

        XCTAssertEqual(model.virtualKeyboardRevealDelay, 0.75)
        XCTAssertEqual(model.configuration.virtualKeyboardRevealDelay, 0.75)
        XCTAssertEqual(callbackCount, 1)
    }

    func testVirtualKeyboardDisabledHidesOverlayBindings() {
        let binding = makeBinding(
            named: "Safari",
            shortcut: AppShortcut(keyCode: 12, modifiers: [.option])
        )
        let model = makeModel(
            hotKeyManager: HotKeyManagerSpy(),
            bindings: [binding],
            virtualKeyboardEnabled: false
        )

        XCTAssertTrue(model.overlayBindings.isEmpty)
    }

    func testQuickSwitchBindingsPreserveConfiguredOrderAcrossTargetKinds() {
        let bindings = [
            HotkeyBinding(
                target: .file(
                    makeFileSystemItem(named: "Report.txt"),
                    .systemDefault
                ),
                shortcut: AppShortcut(keyCode: 2, modifiers: [.option])
            ),
            makeBinding(
                named: "Application",
                shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
            ),
            HotkeyBinding(
                target: .folder(
                    makeFileSystemItem(named: "Project"),
                    .finderNewTab
                ),
                shortcut: AppShortcut(keyCode: 1, modifiers: [.option])
            ),
        ]
        let model = makeModel(
            hotKeyManager: HotKeyManagerSpy(),
            bindings: bindings,
            staticBindingAvailabilityProvider: { _ in .available }
        )

        XCTAssertEqual(
            model.overlayBindings.map(\.id),
            bindings.map(\.id)
        )
    }

    func testTargetDisplayNameUsesStoredFileSystemNameWithoutResolving() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Actual.txt")
        try Data("value".utf8).write(to: fileURL)
        let binding = HotkeyBinding(
            target: .file(
                ManagedFileSystemItem(
                    displayName: "Stored Name",
                    fallbackPath: fileURL.path,
                    bookmarkData: Data()
                ),
                .systemDefault
            )
        )
        let model = makeModel(bindings: [binding])

        XCTAssertEqual(
            model.targetDisplayName(for: binding),
            "Stored Name"
        )
    }

    func testSetHiddenBarEnabledUpdatesConfigurationStatusAndCallback() {
        let model = makeModel(accessibilityPermissionGranted: true)
        var callbackCount = 0
        model.hiddenBarSettingsDidChange = {
            callbackCount += 1
        }

        model.setHiddenBarEnabled(true)

        XCTAssertTrue(model.hiddenBarEnabled)
        XCTAssertEqual(model.configuration.hiddenBarEnabled, true)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .hiddenBarEnabled)
        )
    }

    func testSetHiddenBarEnabledNoOpDoesNotInvokeCallback() {
        let model = makeModel(hiddenBarEnabled: true)
        var callbackCount = 0
        model.hiddenBarSettingsDidChange = {
            callbackCount += 1
        }

        model.setHiddenBarEnabled(true)

        XCTAssertEqual(callbackCount, 0)
    }

    func testSetHiddenBarDisabledUpdatesStatusAndCallback() {
        let model = makeModel(hiddenBarEnabled: true)
        var callbackCount = 0
        model.hiddenBarSettingsDidChange = {
            callbackCount += 1
        }

        model.setHiddenBarEnabled(false)

        XCTAssertFalse(model.hiddenBarEnabled)
        XCTAssertEqual(model.configuration.hiddenBarEnabled, false)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .hiddenBarDisabled)
        )
    }

    func testSetNetworkStatusEnabledUpdatesSavedAndRuntimeStateAndPersists() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = makeModel(configurationDefaults: defaults)
        var callbackCount = 0
        model.networkStatusSettingsDidChange = {
            callbackCount += 1
        }

        model.setNetworkStatusEnabled(true)

        XCTAssertTrue(model.networkStatusEnabled)
        XCTAssertTrue(model.networkStatusRuntimeEnabled)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .networkMonitorEnabled)
        )
        XCTAssertTrue(try UserDefaultsAppConfigurationStore(defaults: defaults).load().networkStatusEnabled)
    }

    func testSetNetworkStatusDisabledUpdatesSavedAndRuntimeStateAndPersists() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = makeModel(
            networkStatusEnabled: true,
            configurationDefaults: defaults
        )
        var callbackCount = 0
        model.networkStatusSettingsDidChange = {
            callbackCount += 1
        }

        model.setNetworkStatusEnabled(false)

        XCTAssertFalse(model.networkStatusEnabled)
        XCTAssertFalse(model.networkStatusRuntimeEnabled)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .networkMonitorDisabled)
        )
        XCTAssertFalse(try UserDefaultsAppConfigurationStore(defaults: defaults).load().networkStatusEnabled)
    }

    func testSetNetworkStatusEnabledNoOpDoesNotInvokeCallback() {
        let model = makeModel(networkStatusEnabled: true)
        var callbackCount = 0
        model.networkStatusSettingsDidChange = {
            callbackCount += 1
        }

        model.setNetworkStatusEnabled(true)

        XCTAssertEqual(callbackCount, 0)
    }

    func testSetMouseWheelWindowsScrollEnabledUpdatesConfigurationAndInvokesCallback() {
        let model = makeModel(accessibilityPermissionGranted: true)
        var callbackCount = 0
        model.mouseWheelScrollSettingsDidChange = {
            callbackCount += 1
        }

        model.setMouseWheelWindowsScrollEnabled(true)

        XCTAssertTrue(model.mouseWheelWindowsScrollEnabled)
        XCTAssertEqual(model.configuration.mouseWheelWindowsScrollEnabled, true)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .mouseWheelWindowsScrollEnabled)
        )
    }

    func testSetMouseWheelWindowsScrollEnabledWithoutPermissionShowsPermissionRequiredStatus() {
        let model = makeModel(accessibilityPermissionGranted: false)

        model.setMouseWheelWindowsScrollEnabled(true)

        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .mouseWheelWindowsScrollPermissionRequired)
        )
    }

    func testSetActivityMonitorHotKeyEnabledUpdatesConfigurationAndStatus() {
        let model = makeModel(accessibilityPermissionGranted: true)

        model.setActivityMonitorHotKeyEnabled(true)

        XCTAssertTrue(model.activityMonitorHotKeyEnabled)
        XCTAssertEqual(model.configuration.activityMonitorHotKeyEnabled, true)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .activityMonitorHotKeyEnabled)
        )
    }

    func testSetAdvancedHotkeysEnabledUpdatesConfigurationWithoutRefreshingRegistrations() {
        let hotKeyManager = HotKeyManagerSpy()
        let model = makeModel(hotKeyManager: hotKeyManager)
        let initialUpdateCount = hotKeyManager.updateCallCount

        model.setAdvancedHotkeysEnabled(true)

        XCTAssertTrue(model.advancedHotkeysEnabled)
        XCTAssertEqual(model.configuration.advancedHotkeysEnabled, true)
        XCTAssertEqual(hotKeyManager.updateCallCount, initialUpdateCount)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .advancedHotkeysEnabled)
        )
    }

    func testShortcutRecordingSuspendsHotKeysAndRestoresUpdatedRegistrations() {
        let hotKeyManager = HotKeyManagerSpy()
        let toggleService = ToggleServiceSpy()
        let originalShortcut = AppShortcut(keyCode: 2, modifiers: [.option])
        let updatedShortcut = AppShortcut(keyCode: 2, modifiers: [.command, .option])
        let binding = makeBinding(named: "Safari", shortcut: originalShortcut)
        let model = makeModel(
            hotKeyManager: hotKeyManager,
            toggleService: toggleService,
            bindings: [binding]
        )

        model.setShortcutRecordingActive(true)

        XCTAssertEqual(hotKeyManager.unregisterAllCallCount, 1)
        XCTAssertTrue(hotKeyManager.lastRequests.isEmpty)

        model.handleHotKeyAction(
            .binding(binding.id),
            shortcut: originalShortcut,
            frontmostProcessIdentifier: 321
        )
        XCTAssertTrue(toggleService.calls.isEmpty)

        model.setShortcut(updatedShortcut, for: binding.id)
        XCTAssertTrue(hotKeyManager.lastRequests.isEmpty)

        model.setShortcutRecordingActive(false)

        XCTAssertEqual(hotKeyManager.lastRequests.map(\.shortcut), [updatedShortcut])
    }

    func testSetActivityMonitorHotKeyEnabledAddsFixedBindingToHotkeyList() throws {
        let hotKeyManager = HotKeyManagerSpy()
        let model = makeModel(
            hotKeyManager: hotKeyManager,
            activityMonitorApplicationProvider: { self.makeActivityMonitorApplication() },
            accessibilityPermissionGranted: true
        )

        model.setActivityMonitorHotKeyEnabled(true)

        let binding = try XCTUnwrap(model.bindings.first {
            self.isActivityMonitorBinding($0)
        })
        XCTAssertEqual(binding.shortcut, ActivityMonitorHotKeyFeature.shortcut)
        XCTAssertTrue(binding.isEnabled)
        XCTAssertEqual(binding.source, .activityMonitorFeature)
        XCTAssertFalse(model.canEditShortcut(for: binding.id))
        XCTAssertEqual(hotKeyManager.lastRequests.map(\.action), [.binding(binding.id)])
        XCTAssertEqual(hotKeyManager.lastRequests.map(\.shortcut), [ActivityMonitorHotKeyFeature.shortcut])
    }

    func testRetiredActivityMonitorFeatureIsRemovedOnLoadWithoutDeletingUserBinding() {
        let managedBinding = HotkeyBinding(
            target: .application(makeActivityMonitorApplication()),
            source: .activityMonitorFeature
        )
        let userBinding = HotkeyBinding(
            target: .application(makeActivityMonitorApplication()),
            source: .user
        )

        let model = makeModel(
            bindings: [managedBinding, userBinding],
            activityMonitorHotKeyEnabled: true
        )

        XCTAssertFalse(model.activityMonitorHotKeyEnabled)
        XCTAssertFalse(model.bindings.contains { $0.id == managedBinding.id })
        XCTAssertTrue(model.bindings.contains { $0.id == userBinding.id })
    }

    func testDisabledActivityMonitorFeatureRemovesManagedNonApplicationBindings() {
        let bindings = [
            HotkeyBinding(
                target: .folder(
                    makeFileSystemItem(named: "Folder"),
                    .finderNewTab
                ),
                source: .activityMonitorFeature
            ),
            HotkeyBinding(
                target: .file(
                    makeFileSystemItem(named: "Document.txt"),
                    .systemDefault
                ),
                source: .activityMonitorFeature
            ),
        ]

        let model = makeModel(
            activityMonitorApplicationProvider: { nil },
            bindings: bindings,
            activityMonitorHotKeyEnabled: false
        )

        XCTAssertFalse(
            model.bindings.contains { $0.source == .activityMonitorFeature }
        )
    }

    func testEnabledActivityMonitorFeatureRemovesUnrepairableManagedNonApplicationBinding() {
        let managedOrphan = HotkeyBinding(
            target: .folder(
                makeFileSystemItem(named: "Folder"),
                .finderNewTab
            ),
            source: .activityMonitorFeature
        )

        let model = makeModel(
            activityMonitorApplicationProvider: { nil },
            bindings: [managedOrphan],
            activityMonitorHotKeyEnabled: true
        )

        XCTAssertFalse(
            model.bindings.contains { $0.source == .activityMonitorFeature }
        )
    }

    func testSetActivityMonitorHotKeyEnabledWithoutPermissionShowsPermissionRequiredStatus() {
        let model = makeModel(accessibilityPermissionGranted: false)

        model.setActivityMonitorHotKeyEnabled(true)

        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .activityMonitorHotKeyPermissionRequired)
        )
    }

    func testSetHotKeyIconFlashEnabledPersistsWithoutRefreshingHotKeyRegistration() {
        let hotKeyManager = HotKeyManagerSpy()
        let binding = makeBinding(
            named: "Safari",
            shortcut: AppShortcut(keyCode: 12, modifiers: [.option])
        )
        let model = makeModel(
            hotKeyManager: hotKeyManager,
            bindings: [binding],
            accessibilityPermissionGranted: false
        )
        let initialUpdateCallCount = hotKeyManager.updateCallCount

        model.setHotKeyIconFlashEnabled(true)

        XCTAssertTrue(model.hotKeyIconFlashEnabled)
        XCTAssertEqual(model.configuration.hotKeyIconFlashEnabled, true)
        XCTAssertEqual(hotKeyManager.updateCallCount, initialUpdateCallCount)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(for: .hotKeyIconFlashEnabled)
        )
    }

    func testHotKeyRegistrationRecordsDiagnosticsWhenSampling() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        recorder.startSampling(round: .core)
        let hotKeyManager = HotKeyManagerSpy()
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let binding = makeBinding(named: "Safari", shortcut: shortcut)

        _ = makeModel(
            hotKeyManager: hotKeyManager,
            bindings: [binding],
            performanceDiagnosticsRecorder: recorder
        )

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.counters["registration.refreshHotKeys"], 1)
        let metadata = snapshot.rawEvents.first { $0.name == "refreshHotKeys" }?.metadata ?? [:]
        XCTAssertEqual(metadata["bindingCount"], "1")
        XCTAssertEqual(metadata["invalidBindingCount"], "0")
        XCTAssertEqual(metadata["duplicateConflictCount"], "0")
        XCTAssertEqual(metadata["registerableShortcutCount"], "1")
        XCTAssertEqual(metadata["registrationFailureCount"], "0")
        XCTAssertFalse(metadata.keys.contains { $0.localizedCaseInsensitiveContains("path") })
        XCTAssertFalse(metadata.keys.contains { $0.localizedCaseInsensitiveContains("license") })
        XCTAssertFalse(metadata.keys.contains { $0.localizedCaseInsensitiveContains("user") })

        let loadMetadata = snapshot.durationSamples["configuration.load"]?.first?.metadata ?? [:]
        XCTAssertEqual(loadMetadata["bindingCount"], "1")
    }

    func testValidationDiagnosticsUseFinalConflictCounts() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        recorder.startSampling(round: .core)
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let notes = makeBinding(
            named: "Notes",
            fallbackPath: ActivityMonitorHotKeyFeature.fallbackPath,
            shortcut: shortcut
        )
        let textEdit = makeBinding(
            named: "TextEdit",
            fallbackPath: ActivityMonitorHotKeyFeature.fallbackPath,
            shortcut: shortcut
        )

        _ = makeModel(
            bindings: [notes, textEdit],
            performanceDiagnosticsRecorder: recorder
        )

        let metadata = recorder.snapshot()
            .durationSamples["configuration.refreshValidation"]?
            .first?
            .metadata ?? [:]
        XCTAssertEqual(metadata["bindingCount"], "2")
        XCTAssertEqual(metadata["invalidBindingCount"], "0")
        XCTAssertEqual(metadata["duplicateConflictCount"], "2")
        XCTAssertEqual(metadata["registerableShortcutCount"], "0")
        XCTAssertEqual(metadata["registrationFailureCount"], "0")

        let loadMetadata = recorder.snapshot()
            .durationSamples["configuration.load"]?
            .first?
            .metadata ?? [:]
        XCTAssertEqual(loadMetadata["bindingCount"], "2")
        XCTAssertEqual(loadMetadata["invalidBindingCount"], "0")
        XCTAssertEqual(loadMetadata["duplicateConflictCount"], "2")
        XCTAssertEqual(loadMetadata["registerableShortcutCount"], "0")
    }

    func testHotKeyRegistrationDiagnosticsIncludeFailureCount() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        recorder.startSampling(round: .core)
        let binding = makeBinding(
            named: "Safari",
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let hotKeyManager = HotKeyManagerSpy(failures: [.binding(binding.id)])

        _ = makeModel(
            hotKeyManager: hotKeyManager,
            bindings: [binding],
            performanceDiagnosticsRecorder: recorder
        )

        let refreshMetadata = recorder.snapshot()
            .durationSamples["registration.refreshHotKeys"]?
            .first?
            .metadata ?? [:]
        XCTAssertEqual(refreshMetadata["registerableShortcutCount"], "1")
        XCTAssertEqual(refreshMetadata["registrationFailureCount"], "1")
    }

    func testRefreshHotKeyRegistrationOmitsActivityMonitorRequestWhenDisabled() {
        let hotKeyManager = HotKeyManagerSpy()

        _ = makeModel(
            hotKeyManager: hotKeyManager,
            activityMonitorHotKeyEnabled: false
        )

        XCTAssertFalse(hotKeyManager.lastRequests.contains { $0.action == .activityMonitor })
    }

    func testRetiredActivityMonitorShortcutNoLongerCreatesAConflict() {
        let hotKeyManager = HotKeyManagerSpy()
        let binding = makeBinding(
            named: "Safari",
            shortcut: ActivityMonitorHotKeyFeature.shortcut
        )

        let model = makeModel(
            hotKeyManager: hotKeyManager,
            bindings: [binding]
        )

        XCTAssertFalse(model.isBindingDuplicateShortcut(binding.id))
        XCTAssertTrue(model.isBindingRegistered(binding.id))
        XCTAssertFalse(model.shortcutConflictMessages.contains { $0.contains("Safari") })
        XCTAssertTrue(hotKeyManager.lastRequests.contains { $0.action == .binding(binding.id) })
    }

    func testHandleHotKeyActionRoutesBindingThroughToggleService() {
        let toggleService = ToggleServiceSpy()
        let binding = makeBinding(named: "Safari")
        let model = makeModel(toggleService: toggleService, bindings: [binding])

        model.handleHotKeyAction(
            .binding(binding.id),
            shortcut: AppShortcut(keyCode: 12, modifiers: [.option]),
            frontmostProcessIdentifier: 777
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertEqual(toggleService.calls.first?.bindingName, "Safari")
        XCTAssertEqual(toggleService.calls.first?.frontmostProcessIdentifier, 777)
        XCTAssertEqual(toggleService.calls.first?.invocationSource, .hotKey)
        XCTAssertNil(model.statusMessage)
    }

    func testHandleHotKeyActionRoutesActivityMonitorThroughToggleService() {
        let toggleService = ToggleServiceSpy()
        let model = makeModel(
            toggleService: toggleService,
            activityMonitorApplicationProvider: {
                ManagedApplication(
                    displayName: "Activity Monitor",
                    bundleIdentifier: ActivityMonitorHotKeyFeature.bundleIdentifier,
                    fallbackPath: ActivityMonitorHotKeyFeature.fallbackPath,
                    bookmarkData: Data()
                )
            }
        )
        var events: [String] = []
        model.beforeBindingAction = {
            events.append("before")
        }

        model.handleHotKeyAction(
            .activityMonitor,
            shortcut: ActivityMonitorHotKeyFeature.shortcut,
            frontmostProcessIdentifier: 321
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertEqual(toggleService.calls.count, 1)
        XCTAssertEqual(toggleService.calls.first?.bindingName, "Activity Monitor")
        XCTAssertEqual(toggleService.calls.first?.frontmostProcessIdentifier, 321)
        XCTAssertEqual(toggleService.calls.first?.invocationSource, .hotKey)
        XCTAssertEqual(events, ["before"])
        XCTAssertNil(model.statusMessage)
    }

    func testHandleHotKeyActionSkipsUnresolvedActivityMonitor() {
        let toggleService = ToggleServiceSpy()
        let model = makeModel(
            toggleService: toggleService,
            activityMonitorApplicationProvider: { nil }
        )

        model.handleHotKeyAction(
            .activityMonitor,
            shortcut: ActivityMonitorHotKeyFeature.shortcut,
            frontmostProcessIdentifier: 321
        )

        XCTAssertFalse(toggleService.waitForCall(timeout: 0.2))
        XCTAssertTrue(toggleService.calls.isEmpty)
        XCTAssertNil(model.statusMessage)
    }

    func testCurrentVersionTextIsNonEmpty() {
        let model = makeModel()

        XCTAssertFalse(model.currentVersionText.isEmpty)
        XCTAssertFalse(model.currentVersionText.contains("("))
        XCTAssertFalse(model.currentVersionText.contains(")"))
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            XCTAssertFalse(model.currentVersionText.contains(bundleIdentifier))
        }
    }

    func testPerformanceDiagnosticsSheetStartsHidden() {
        let model = makeModel()

        XCTAssertFalse(model.isPerformanceDiagnosticsPresented)
    }

    func testVersionRowHiddenEntryCanOpenPerformanceDiagnostics() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        let model = makeModel(performanceDiagnosticsRecorder: recorder)

        model.openPerformanceDiagnosticsFromVersionRow()

        XCTAssertTrue(model.isPerformanceDiagnosticsPresented)
        XCTAssertEqual(recorder.snapshot().counters["uiTransition.diagnosticsOpenedFromVersionRow"], 1)
    }

    func testPerformanceDiagnosticsOpenAndDismissUpdatesPresentationAndEvents() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        let model = makeModel(performanceDiagnosticsRecorder: recorder)

        model.openPerformanceDiagnostics()
        XCTAssertTrue(model.isPerformanceDiagnosticsPresented)

        model.dismissPerformanceDiagnostics()
        XCTAssertFalse(model.isPerformanceDiagnosticsPresented)

        recorder.startSampling(round: .core)
        model.openPerformanceDiagnostics()
        model.dismissPerformanceDiagnostics()

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.counters["uiTransition.diagnosticsSurfaceOpened"], 1)
        XCTAssertEqual(snapshot.counters["uiTransition.diagnosticsSurfaceClosed"], 1)
    }

    func testPerformanceDiagnosticsStartSamplingRecordsCountersAndMetadata() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        let binding = makeBinding(named: "Safari")
        let model = makeModel(
            bindings: [binding],
            windowsStyleCutEnabled: true,
            mouseWheelWindowsScrollEnabled: true,
            pressedKeysOverlayEnabled: true,
            virtualKeyboardEnabled: true,
            hiddenBarEnabled: true,
            hotKeyIconFlashEnabled: true,
            performanceDiagnosticsRecorder: recorder
        )

        model.startPerformanceDiagnosticsSampling(round: .idleAndStress)

        let snapshot = recorder.snapshot()
        XCTAssertTrue(snapshot.isSampling)
        XCTAssertEqual(snapshot.round, .idleAndStress)
        XCTAssertEqual(snapshot.counters["resource.samplingStart"], 1)
        XCTAssertEqual(snapshot.counters["uiTransition.diagnosticsSamplingStarted"], 1)

        let resourceMetadata = snapshot.rawEvents.first { $0.name == "samplingStart" }?.metadata ?? [:]
        XCTAssertNotNil(UInt64(resourceMetadata["residentMemoryBytes"] ?? ""))
        XCTAssertNotNil(Double(resourceMetadata["cpuTimeSeconds"] ?? ""))
        XCTAssertNotNil(Int(resourceMetadata["threadCount"] ?? ""))
        XCTAssertEqual(resourceMetadata["processIdentifier"], String(ProcessInfo.processInfo.processIdentifier))
        XCTAssertEqual(Set(resourceMetadata.keys), [
            "residentMemoryBytes",
            "cpuTimeSeconds",
            "threadCount",
            "processIdentifier",
        ])

        let runtimeMetadata = snapshot.rawEvents.first { $0.name == "diagnosticsSamplingStarted" }?.metadata ?? [:]
        XCTAssertEqual(runtimeMetadata["bindingCount"], "1")
        XCTAssertEqual(runtimeMetadata["windowsStyleCutRuntimeEnabled"], "true")
        XCTAssertEqual(runtimeMetadata["mouseWheelWindowsScrollRuntimeEnabled"], "true")
        XCTAssertEqual(runtimeMetadata["pressedKeysOverlayRuntimeEnabled"], "true")
        XCTAssertEqual(runtimeMetadata["virtualKeyboardRuntimeEnabled"], "true")
        XCTAssertEqual(runtimeMetadata["hiddenBarRuntimeEnabled"], "true")
        XCTAssertEqual(runtimeMetadata["hotKeyIconFlashRuntimeEnabled"], "true")
        XCTAssertEqual(runtimeMetadata["activityMonitorHotKeyRuntimeEnabled"], "false")
    }

    func testPerformanceDiagnosticsStopSamplingRecordsStopMetadataBeforeStopping() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        let model = makeModel(performanceDiagnosticsRecorder: recorder)
        model.startPerformanceDiagnosticsSampling(round: .core)

        model.stopPerformanceDiagnosticsSampling()

        let snapshot = recorder.snapshot()
        XCTAssertFalse(snapshot.isSampling)
        XCTAssertEqual(snapshot.counters["resource.samplingStop"], 1)
        XCTAssertEqual(snapshot.counters["uiTransition.diagnosticsSamplingStopped"], 1)

        let resourceMetadata = snapshot.rawEvents.first { $0.name == "samplingStop" }?.metadata ?? [:]
        XCTAssertEqual(Set(resourceMetadata.keys), [
            "residentMemoryBytes",
            "cpuTimeSeconds",
            "threadCount",
            "processIdentifier",
        ])
    }

    func testPerformanceDiagnosticsClearSessionResetsRecorder() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        let model = makeModel(performanceDiagnosticsRecorder: recorder)
        model.startPerformanceDiagnosticsSampling(round: .core)

        model.clearPerformanceDiagnosticsSession()

        let snapshot = recorder.snapshot()
        XCTAssertFalse(snapshot.isSampling)
        XCTAssertNil(snapshot.round)
        XCTAssertEqual(snapshot.totalEventCount, 0)
        XCTAssertTrue(snapshot.rawEvents.isEmpty)
    }

    func testPerformanceDiagnosticsUpdateNotesUpdatesRecorder() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        let model = makeModel(performanceDiagnosticsRecorder: recorder)

        model.updatePerformanceDiagnosticsNotes("Activity Monitor idle CPU stayed near zero.")

        XCTAssertEqual(recorder.snapshot().notes, "Activity Monitor idle CPU stayed near zero.")
    }

    func testPerformanceDiagnosticsRuntimeMetadataContainsOnlySafeFields() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        let model = makeModel(
            bindings: [
                makeBinding(
                    named: "Sensitive",
                    fallbackPath: "/Users/example/Documents/Sensitive.app"
                ),
            ],
            performanceDiagnosticsRecorder: recorder
        )

        model.startPerformanceDiagnosticsSampling(round: .optionalFeatures)

        let metadata = recorder.snapshot().rawEvents
            .first { $0.name == "diagnosticsSamplingStarted" }?
            .metadata ?? [:]
        XCTAssertEqual(Set(metadata.keys), [
            "bindingCount",
            "windowsStyleCutRuntimeEnabled",
            "mouseWheelWindowsScrollRuntimeEnabled",
            "pressedKeysOverlayRuntimeEnabled",
            "virtualKeyboardRuntimeEnabled",
            "hiddenBarRuntimeEnabled",
            "hotKeyIconFlashRuntimeEnabled",
            "activityMonitorHotKeyRuntimeEnabled",
        ])
        XCTAssertFalse(metadata.values.contains { $0.contains("/Users") })
        XCTAssertFalse(metadata.keys.contains { $0.localizedCaseInsensitiveContains("path") })
        XCTAssertFalse(metadata.keys.contains { $0.localizedCaseInsensitiveContains("license") })
        XCTAssertFalse(metadata.keys.contains { $0.localizedCaseInsensitiveContains("host") })
        XCTAssertFalse(metadata.keys.contains { $0.localizedCaseInsensitiveContains("user") })
    }

    func testPerformActionRoutesHotKeyAndManualThroughTheSameToggleService() {
        let toggleService = ToggleServiceSpy()
        let binding = makeBinding(named: "Safari")
        let model = makeModel(toggleService: toggleService, bindings: [binding])

        model.performAction(for: binding.id, frontmostProcessIdentifier: 101, source: .hotKey)
        model.performAction(for: binding.id, frontmostProcessIdentifier: 202, source: .manual)

        XCTAssertTrue(waitUntil { toggleService.calls.count == 2 })
        XCTAssertEqual(toggleService.calls.count, 2)
        XCTAssertEqual(toggleService.calls.map(\.bindingName), ["Safari", "Safari"])
        XCTAssertEqual(toggleService.calls.map(\.frontmostProcessIdentifier), [101, 202])
        XCTAssertEqual(toggleService.calls.map(\.invocationSource), [.hotKey, .manual])
    }

    func testManualSourceShowsStatusBannerButHotKeySourceDoesNot() {
        let toggleService = ToggleServiceSpy()
        let binding = makeBinding(named: "Safari")
        let model = makeModel(toggleService: toggleService, bindings: [binding])

        model.performAction(for: binding.id, source: .hotKey)
        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertNil(model.statusMessage)

        model.performAction(for: binding.id, source: .manual)
        XCTAssertTrue(waitUntil { toggleService.calls.count == 2 })
        XCTAssertEqual(model.statusMessage, ApplicationToggleResult.hidden("Safari").message)
    }

    func testEnabledBindingHotKeyPublishesAppFlashPayload() {
        let toggleService = ToggleServiceSpy()
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let binding = makeBinding(named: "Safari", shortcut: shortcut)
        let model = makeModel(
            toggleService: toggleService,
            bindings: [binding],
            hotKeyIconFlashEnabled: true
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: shortcut,
            frontmostProcessIdentifier: 101
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertTrue(waitUntil { !payloads.isEmpty })
        XCTAssertEqual(
            payloads.first?.targetDisplayName,
            model.targetDisplayName(for: binding)
        )
        XCTAssertNotNil(payloads.first?.targetImage)
        XCTAssertEqual(payloads.first?.fallbackSymbolName, "app.fill")
        XCTAssertGreaterThan(payloads.first?.screenFrame.width ?? 0, 0)
        XCTAssertGreaterThan(payloads.first?.screenFrame.height ?? 0, 0)
        XCTAssertEqual(toggleService.calls.count, 1)
        XCTAssertEqual(toggleService.calls.first?.frontmostProcessIdentifier, 101)
        XCTAssertNil(model.statusMessage)
    }

    func testAcceptedHotKeysPublishMaterializedTargetFlashForEveryTargetKind() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Application",
            bundleIdentifier: "com.example.application",
            in: directory
        )
        let folderURL = directory.appendingPathComponent(
            "Project",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("Report.txt")
        try Data("value".utf8).write(to: fileURL)
        let bindings = [
            HotkeyBinding(
                target: .application(
                    try ManagedApplication(url: applicationURL)
                ),
                shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
            ),
            HotkeyBinding(
                target: .folder(
                    try ManagedFileSystemItem(url: folderURL),
                    .finderNewTab
                ),
                shortcut: AppShortcut(keyCode: 1, modifiers: [.option])
            ),
            HotkeyBinding(
                target: .file(
                    try ManagedFileSystemItem(url: fileURL),
                    .systemDefault
                ),
                shortcut: AppShortcut(keyCode: 2, modifiers: [.option])
            ),
        ]
        let executor = BindingActionExecutorSpy()
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: bindings,
            hotKeyIconFlashEnabled: true
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        for binding in bindings {
            model.handleHotKeyTrigger(
                for: binding.id,
                shortcut: try XCTUnwrap(binding.shortcut),
                frontmostProcessIdentifier: 101
            )
        }

        XCTAssertTrue(waitUntil { payloads.count == bindings.count })
        XCTAssertEqual(
            payloads.map(\.targetDisplayName),
            ["Application", "Project", "Report.txt"]
        )
        XCTAssertEqual(
            payloads.map(\.fallbackSymbolName),
            ["app.fill", "folder.fill", "doc.fill"]
        )
        XCTAssertTrue(payloads.allSatisfy { $0.targetImage != nil })
        XCTAssertEqual(executor.calls.map(\.source), [.hotKey, .hotKey, .hotKey])
        XCTAssertNil(model.statusMessage)
    }

    func testTargetFlashPayloadEqualityIncludesPresentationAndImage() {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let frame = CGRect(x: 1, y: 2, width: 300, height: 200)
        let payload = HotKeyTargetFlashPayload(
            targetDisplayName: "Report.txt",
            targetImage: image,
            fallbackSymbolName: "doc.fill",
            screenFrame: frame
        )

        XCTAssertEqual(
            payload,
            HotKeyTargetFlashPayload(
                targetDisplayName: "Report.txt",
                targetImage: image,
                fallbackSymbolName: "doc.fill",
                screenFrame: frame
            )
        )
        XCTAssertNotEqual(
            payload,
            HotKeyTargetFlashPayload(
                targetDisplayName: "Report.txt",
                targetImage: nil,
                fallbackSymbolName: "doc.fill",
                screenFrame: frame
            )
        )
        XCTAssertNotEqual(
            payload,
            HotKeyTargetFlashPayload(
                targetDisplayName: "Project",
                targetImage: image,
                fallbackSymbolName: "folder.fill",
                screenFrame: frame
            )
        )
    }

    func testRejectedHotKeyDoesNotPublishTargetFlashPayload() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Report.txt")
        try Data("value".utf8).write(to: fileURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            ),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let executor = BindingActionExecutorSpy(isAccepted: false)
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding],
            hotKeyIconFlashEnabled: true
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: try XCTUnwrap(binding.shortcut),
            frontmostProcessIdentifier: nil
        )

        XCTAssertFalse(waitUntil(timeout: 0.2) { !payloads.isEmpty })
        XCTAssertTrue(payloads.isEmpty)
        XCTAssertNil(model.statusMessage)
    }

    func testManualFileAndFolderActionsDoNotPublishTargetFlash() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Project",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("Report.txt")
        try Data("value".utf8).write(to: fileURL)
        let bindings = [
            HotkeyBinding(
                target: .folder(
                    try ManagedFileSystemItem(url: folderURL),
                    .finderNewTab
                )
            ),
            HotkeyBinding(
                target: .file(
                    try ManagedFileSystemItem(url: fileURL),
                    .systemDefault
                )
            ),
        ]
        let executor = BindingActionExecutorSpy()
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: bindings,
            hotKeyIconFlashEnabled: true
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        for binding in bindings {
            model.performAction(for: binding.id, source: .manual)
        }

        XCTAssertFalse(waitUntil(timeout: 0.2) { !payloads.isEmpty })
        XCTAssertTrue(payloads.isEmpty)
        XCTAssertEqual(executor.calls.map(\.source), [.manual, .manual])
    }

    func testDisabledHotKeyIconFlashDoesNotPublishPayload() {
        let toggleService = ToggleServiceSpy()
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let binding = makeBinding(named: "Safari", shortcut: shortcut)
        let model = makeModel(
            toggleService: toggleService,
            bindings: [binding],
            hotKeyIconFlashEnabled: false
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: shortcut,
            frontmostProcessIdentifier: 101
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertFalse(waitUntil(timeout: 0.2) { !payloads.isEmpty })
        XCTAssertTrue(payloads.isEmpty)
    }

    func testActivityMonitorHotKeyPublishesAppFlashPayloadWhenEnabled() {
        let toggleService = ToggleServiceSpy()
        let activityMonitorApplication = ManagedApplication(
            displayName: "Activity Monitor",
            bundleIdentifier: ActivityMonitorHotKeyFeature.bundleIdentifier,
            fallbackPath: ActivityMonitorHotKeyFeature.fallbackPath,
            bookmarkData: Data()
        )
        let model = makeModel(
            toggleService: toggleService,
            activityMonitorApplicationProvider: { activityMonitorApplication },
            hotKeyIconFlashEnabled: true,
            activityMonitorHotKeyEnabled: true
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        model.handleHotKeyAction(
            .activityMonitor,
            shortcut: ActivityMonitorHotKeyFeature.shortcut,
            frontmostProcessIdentifier: 321
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertTrue(waitUntil { !payloads.isEmpty })
        XCTAssertEqual(
            payloads.first?.targetDisplayName,
            LocalizationManager.shared.string(for: .activityMonitor)
        )
        XCTAssertNotNil(payloads.first?.targetImage)
        XCTAssertEqual(payloads.first?.fallbackSymbolName, "app.fill")
        XCTAssertGreaterThan(payloads.first?.screenFrame.width ?? 0, 0)
        XCTAssertGreaterThan(payloads.first?.screenFrame.height ?? 0, 0)
        XCTAssertNil(model.statusMessage)
    }

    func testUnresolvedActivityMonitorHotKeyDoesNotPublishAppFlashPayload() {
        let toggleService = ToggleServiceSpy()
        let model = makeModel(
            toggleService: toggleService,
            activityMonitorApplicationProvider: { nil },
            hotKeyIconFlashEnabled: true,
            activityMonitorHotKeyEnabled: true
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        model.handleHotKeyAction(
            .activityMonitor,
            shortcut: ActivityMonitorHotKeyFeature.shortcut,
            frontmostProcessIdentifier: 321
        )

        XCTAssertFalse(toggleService.waitForCall(timeout: 0.2))
        XCTAssertFalse(waitUntil(timeout: 0.2) { !payloads.isEmpty })
        XCTAssertTrue(payloads.isEmpty)
    }

    func testActivityMonitorHotKeyWithUnresolvedApplicationSkipsTargetFlash() {
        let toggleService = ToggleServiceSpy()
        let recorder = PerformanceDiagnosticsRecorder(
            clock: ManualPerformanceDiagnosticsClock()
        )
        recorder.startSampling(round: .core)
        let missingApplication = ManagedApplication(
            displayName: "Activity Monitor",
            bundleIdentifier: ActivityMonitorHotKeyFeature.bundleIdentifier,
            fallbackPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).app")
                .path,
            bookmarkData: Data()
        )
        let model = makeModel(
            toggleService: toggleService,
            activityMonitorApplicationProvider: { missingApplication },
            hotKeyIconFlashEnabled: true,
            activityMonitorHotKeyEnabled: true,
            performanceDiagnosticsRecorder: recorder
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        model.handleHotKeyAction(
            .activityMonitor,
            shortcut: ActivityMonitorHotKeyFeature.shortcut,
            frontmostProcessIdentifier: 321
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertFalse(waitUntil(timeout: 0.2) { !payloads.isEmpty })
        XCTAssertTrue(payloads.isEmpty)
        let snapshot = recorder.snapshot()
        XCTAssertEqual(
            snapshot.counters["hotkey.prepareToggleRequested"],
            1
        )
        XCTAssertEqual(
            snapshot.rawEvents.last {
                $0.name == "appIconFlashPayload"
            }?.metadata["result"],
            "skipped"
        )
    }

    func testMissingBindingHotKeyDoesNotPublishAppFlashPayload() {
        let toggleService = ToggleServiceSpy()
        let model = makeModel(
            toggleService: toggleService,
            hotKeyIconFlashEnabled: true
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        model.handleHotKeyTrigger(
            for: UUID(),
            shortcut: AppShortcut(keyCode: 12, modifiers: [.option]),
            frontmostProcessIdentifier: 101
        )

        XCTAssertFalse(toggleService.waitForCall(timeout: 0.2))
        XCTAssertFalse(waitUntil(timeout: 0.2) { !payloads.isEmpty })
        XCTAssertTrue(payloads.isEmpty)
    }

    func testManualToggleDoesNotPublishAppFlashPayload() {
        let toggleService = ToggleServiceSpy()
        let binding = makeBinding(named: "Safari")
        let model = makeModel(
            toggleService: toggleService,
            bindings: [binding],
            hotKeyIconFlashEnabled: true
        )
        var payloads: [HotKeyTargetFlashPayload] = []
        model.hotKeyTargetFlashDidTrigger = { payloads.append($0) }

        model.performAction(for: binding.id, source: .manual)

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertFalse(waitUntil(timeout: 0.2) { !payloads.isEmpty })
        XCTAssertTrue(payloads.isEmpty)
    }

    func testHandleHotKeyTriggerExecutesToggleBeforeAppFlashCallback() {
        let toggleService = ToggleServiceSpy()
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let binding = makeBinding(named: "Safari", shortcut: shortcut)
        let model = makeModel(
            toggleService: toggleService,
            bindings: [binding],
            hotKeyIconFlashEnabled: true
        )
        var events: [String] = []

        model.beforeBindingAction = {
            events.append("before")
        }
        model.hotKeyTargetFlashDidTrigger = { _ in
            events.append("flash")
        }
        toggleService.onToggle = {
            events.append("toggle")
        }

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: shortcut,
            frontmostProcessIdentifier: 101
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertEqual(Array(events.prefix(2)), ["before", "toggle"])
        XCTAssertTrue(waitUntil { events == ["before", "toggle", "flash"] })
    }

    func testBindingActionFeedbackOrderRefreshesPermissionBeforePreparationAndFlash() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Application",
            bundleIdentifier: "com.example.application",
            in: directory
        )
        let shortcut = AppShortcut(keyCode: 0, modifiers: [.option])
        let binding = HotkeyBinding(
            target: .application(try ManagedApplication(url: applicationURL)),
            shortcut: shortcut
        )
        var events: [String] = []
        let executor = BindingActionExecutorSpy(
            result: .success(.application(.hidden("Application")))
        )
        executor.onPrepare = { events.append("prepare") }
        executor.onExecute = { events.append("execute") }
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding],
            hotKeyIconFlashEnabled: true,
            accessibilityPermissionStatusProvider: {
                events.append("permission")
                return true
            }
        )
        events.removeAll()
        model.beforeBindingAction = { events.append("before") }
        model.hotKeyTargetFlashDidTrigger = { _ in events.append("flash") }

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: shortcut,
            frontmostProcessIdentifier: 123
        )

        XCTAssertTrue(waitUntil {
            events == [
                "permission",
                "before",
                "prepare",
                "execute",
                "flash",
            ]
        })
    }

    func testApplicationHotKeySuppressesRegistrationFailureBanner() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Application",
            bundleIdentifier: "com.example.application",
            in: directory
        )
        let shortcut = AppShortcut(keyCode: 0, modifiers: [.option])
        let binding = HotkeyBinding(
            target: .application(try ManagedApplication(url: applicationURL)),
            shortcut: shortcut
        )
        var registrationShouldFail = false
        let manager = HotKeyManagerSpy(failurePredicate: { _ in
            registrationShouldFail
        })
        let recorder = PerformanceDiagnosticsRecorder(
            clock: ManualPerformanceDiagnosticsClock()
        )
        recorder.startSampling(round: .core)
        let toggleService = ToggleServiceSpy()
        let model = makeModel(
            hotKeyManager: manager,
            toggleService: toggleService,
            bindings: [binding],
            performanceDiagnosticsRecorder: recorder
        )
        let initialUpdateCallCount = manager.updateCallCount
        registrationShouldFail = true

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: shortcut,
            frontmostProcessIdentifier: nil
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertEqual(manager.updateCallCount, initialUpdateCallCount + 1)
        XCTAssertEqual(
            recorder.snapshot().rawEvents
                .last { $0.name == "refreshHotKeyFailures" }?
                .metadata["registrationFailureCount"],
            "1"
        )
        XCTAssertNil(model.statusMessage)
    }

    func testFixedActivityMonitorHotKeySuppressesRegistrationFailureBanner() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Activity Monitor",
            bundleIdentifier: ActivityMonitorHotKeyFeature.bundleIdentifier,
            in: directory
        )
        let application = try ManagedApplication(url: applicationURL)
        var registrationShouldFail = false
        let manager = HotKeyManagerSpy(failurePredicate: { _ in
            registrationShouldFail
        })
        let toggleService = ToggleServiceSpy()
        let model = makeModel(
            hotKeyManager: manager,
            toggleService: toggleService,
            activityMonitorApplicationProvider: { application },
            activityMonitorHotKeyEnabled: true
        )
        registrationShouldFail = true

        model.handleHotKeyAction(
            .activityMonitor,
            shortcut: ActivityMonitorHotKeyFeature.shortcut,
            frontmostProcessIdentifier: nil
        )

        XCTAssertTrue(toggleService.waitForCall())
        XCTAssertNil(model.statusMessage)
    }

    func testHotKeyActionRecordsEndToEndStagesWhenSampling() {
        let shortcut = AppShortcut(keyCode: 8, modifiers: [.option])
        let binding = makeBinding(
            named: "Safari",
            fallbackPath: ActivityMonitorHotKeyFeature.fallbackPath,
            shortcut: shortcut
        )
        let toggleService = ToggleServiceSpy()
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        recorder.startSampling(round: .core)
        let model = makeModel(
            toggleService: toggleService,
            bindings: [binding],
            hotKeyIconFlashEnabled: true,
            performanceDiagnosticsRecorder: recorder
        )

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: shortcut,
            frontmostProcessIdentifier: 123
        )
        XCTAssertTrue(toggleService.waitForCall())

        let counters = recorder.snapshot().counters
        XCTAssertEqual(counters["hotkey.handleHotKeyAction"], 1)
        XCTAssertEqual(counters["hotkey.bindingResolution"], 1)
        XCTAssertEqual(counters["hotkey.accessibilityRefresh"], 1)
        XCTAssertEqual(counters["hotkey.beforeBindingAction"], 1)
        XCTAssertEqual(counters["hotkey.prepareActionRequested"], 1)
        XCTAssertEqual(counters["hotkey.appIconFlashPayload"], 1)
        XCTAssertEqual(counters["hotkey.completion"], 1)
    }

    func testAddTargetAddsApplicationWithDefaultBindingState() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Example",
            bundleIdentifier: "com.example.app",
            in: directory
        )
        let model = makeModel()

        model.addTarget(at: applicationURL)

        let binding = try XCTUnwrap(model.bindings.first)
        guard case .application(let application) = binding.target else {
            return XCTFail("Expected application target")
        }
        XCTAssertEqual(application.bundleIdentifier, "com.example.app")
        XCTAssertNil(binding.shortcut)
        XCTAssertTrue(binding.isEnabled)
        XCTAssertEqual(binding.source, .user)
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(
                for: .targetAdded,
                arguments: model.localizedDisplayName(for: application)
            )
        )
    }

    func testAddTargetAddsFolderWithFinderDefaultMode() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let model = makeModel()

        model.addTarget(at: folderURL)

        let binding = try XCTUnwrap(model.bindings.first)
        guard case .folder(let item, let mode) = binding.target else {
            return XCTFail("Expected folder target")
        }
        XCTAssertEqual(item.fallbackPath, folderURL.path)
        XCTAssertEqual(mode, .finderNewTab)
        XCTAssertNil(binding.shortcut)
        XCTAssertTrue(binding.isEnabled)
        XCTAssertEqual(binding.source, .user)
    }

    func testAddTargetAddsFileWithSystemDefaultMode() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let model = makeModel()

        model.addTarget(at: fileURL)

        let binding = try XCTUnwrap(model.bindings.first)
        guard case .file(let item, let mode) = binding.target else {
            return XCTFail("Expected file target")
        }
        XCTAssertEqual(item.fallbackPath, fileURL.path)
        XCTAssertEqual(mode, .systemDefault)
        XCTAssertNil(binding.shortcut)
        XCTAssertTrue(binding.isEnabled)
        XCTAssertEqual(binding.source, .user)
    }

    func testAddTargetTreatsDocumentPackageAsFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let packageURL = directory.appendingPathComponent(
            "Document.rtfd",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try Data("value".utf8).write(
            to: packageURL.appendingPathComponent("TXT.rtf")
        )
        let model = makeModel()

        model.addTarget(at: packageURL)

        guard case .file(let item, .systemDefault) = model.bindings.first?.target else {
            return XCTFail("Expected document package file target")
        }
        XCTAssertEqual(item.fallbackPath, packageURL.path)
    }

    func testAddTargetRejectsExactDuplicateApplicationAndKeepsStatusBehavior() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Example",
            bundleIdentifier: "com.example.app",
            in: directory
        )
        let model = makeModel()

        model.addTarget(at: applicationURL)
        model.addTarget(at: applicationURL)

        XCTAssertEqual(model.bindings.count, 1)
        guard case .application(let application) = model.bindings.first?.target else {
            return XCTFail("Expected application target")
        }
        XCTAssertEqual(
            model.statusMessage,
            LocalizationManager.shared.string(
                for: .targetAlreadyExists,
                arguments: model.localizedDisplayName(for: application)
            )
        )
    }

    func testAddTargetRejectsExactDuplicateFolder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let model = makeModel()

        model.addTarget(at: folderURL)
        model.addTarget(at: folderURL)

        XCTAssertEqual(model.bindings.count, 1)
    }

    func testAddTargetRejectsExactDuplicateFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let model = makeModel()

        model.addTarget(at: fileURL)
        model.addTarget(at: fileURL)

        XCTAssertEqual(model.bindings.count, 1)
    }

    func testAddTargetRollsBackAndCanRetryAfterSaveFailure() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let store = UserDefaultsAppConfigurationStore(defaults: defaults)
        var saveShouldFail = true
        let model = makeModel(
            configurationDefaults: defaults,
            configurationSaver: { configuration in
                if saveShouldFail {
                    throw NSError(
                        domain: "AppModelTests.SaveFailure",
                        code: 1
                    )
                }
                try store.save(configuration)
            }
        )

        model.addTarget(at: folderURL)

        XCTAssertTrue(model.bindings.isEmpty)
        XCTAssertTrue(try store.load().bindings.isEmpty)

        saveShouldFail = false
        model.addTarget(at: folderURL)

        XCTAssertEqual(model.bindings.count, 1)
        XCTAssertEqual(try store.load().bindings.count, 1)
    }

    func testSameFileCanBeAddedAgainAfterExistingBindingChangesMode() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let model = makeModel()
        model.addTarget(at: fileURL)
        let firstBindingID = try XCTUnwrap(model.bindings.first?.id)

        model.setOpeningApplication(handlerURL, for: firstBindingID)
        model.addTarget(at: fileURL)

        XCTAssertEqual(model.bindings.count, 2)
        guard case .file(_, .application(let handler)) = model.bindings[0].target,
              case .file(_, .systemDefault) = model.bindings[1].target else {
            return XCTFail("Expected selected and system-default file modes")
        }
        XCTAssertEqual(handler.bundleIdentifier, "com.example.handler")
    }

    func testSetFolderOpenModeUpdatesMatchingFolder() throws {
        let item = makeFileSystemItem(named: "Folder")
        let binding = HotkeyBinding(target: .folder(item, .finderNewTab))
        let handler = ManagedApplication(
            displayName: "Handler",
            bundleIdentifier: "com.example.handler",
            fallbackPath: "/Applications/Handler.app",
            bookmarkData: Data()
        )
        let model = makeModel(bindings: [binding])

        model.setFolderOpenMode(.application(handler), for: binding.id)

        XCTAssertEqual(
            model.bindings.first?.target,
            .folder(item, .application(handler))
        )
    }

    func testSetFolderOpenModeRollsBackAfterSaveFailure() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = makeFileSystemItem(named: "Folder")
        let binding = HotkeyBinding(target: .folder(item, .finderNewTab))
        let handler = ManagedApplication(
            displayName: "Handler",
            bundleIdentifier: "com.example.handler",
            fallbackPath: "/Applications/Handler.app",
            bookmarkData: Data()
        )
        let hotKeyManager = HotKeyManagerSpy()
        let model = makeModel(
            hotKeyManager: hotKeyManager,
            bindings: [binding],
            accessibilityPermissionGranted: false,
            configurationDefaults: defaults,
            configurationSaver: { _ in
                throw NSError(
                    domain: "AppModelTests.SaveFailure",
                    code: 1
                )
            }
        )
        let originalConfiguration = model.configuration
        let refreshCountBefore = hotKeyManager.updateCallCount

        model.setFolderOpenMode(
            .application(handler),
            for: binding.id
        )

        XCTAssertEqual(model.configuration, originalConfiguration)
        XCTAssertEqual(
            try UserDefaultsAppConfigurationStore(defaults: defaults).load(),
            originalConfiguration
        )
        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)
        XCTAssertEqual(
            hotKeyManager.updateCallCount,
            refreshCountBefore + 1
        )
    }

    func testSetFileOpenModeUpdatesMatchingFile() throws {
        let item = makeFileSystemItem(named: "Document.txt")
        let binding = HotkeyBinding(target: .file(item, .systemDefault))
        let handler = ManagedApplication(
            displayName: "Handler",
            bundleIdentifier: "com.example.handler",
            fallbackPath: "/Applications/Handler.app",
            bookmarkData: Data()
        )
        let model = makeModel(bindings: [binding])

        model.setFileOpenMode(.application(handler), for: binding.id)

        XCTAssertEqual(
            model.bindings.first?.target,
            .file(item, .application(handler))
        )
    }

    func testModeSettersIgnoreMismatchedAndMissingBindings() {
        let folder = HotkeyBinding(
            target: .folder(makeFileSystemItem(named: "Folder"), .finderNewTab)
        )
        let file = HotkeyBinding(
            target: .file(makeFileSystemItem(named: "Document.txt"), .systemDefault)
        )
        let model = makeModel(bindings: [folder, file])
        let originalConfiguration = model.configuration

        model.setFileOpenMode(.systemDefault, for: folder.id)
        model.setFolderOpenMode(.finderNewTab, for: file.id)
        model.setFolderOpenMode(.finderNewTab, for: UUID())

        XCTAssertEqual(model.configuration, originalConfiguration)
    }

    func testDuplicateModeChangeDoesNotMutateOrPersist() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = makeFileSystemItem(named: "Document.txt")
        let handler = ManagedApplication(
            displayName: "Handler",
            bundleIdentifier: "com.example.handler",
            fallbackPath: "/Applications/Handler.app",
            bookmarkData: Data()
        )
        let defaultBinding = HotkeyBinding(target: .file(item, .systemDefault))
        let selectedBinding = HotkeyBinding(
            target: .file(item, .application(handler))
        )
        let recorder = PerformanceDiagnosticsRecorder(
            clock: ManualPerformanceDiagnosticsClock()
        )
        recorder.startSampling(round: .core)
        let model = makeModel(
            bindings: [defaultBinding, selectedBinding],
            performanceDiagnosticsRecorder: recorder,
            configurationDefaults: defaults
        )
        let originalConfiguration = model.configuration
        let persistedBefore = try UserDefaultsAppConfigurationStore(
            defaults: defaults
        ).load()
        let persistCountBefore = recorder.snapshot()
            .durationSamples["configuration.persistConfiguration"]?.count ?? 0

        model.setFileOpenMode(
            .application(handler),
            for: defaultBinding.id
        )

        XCTAssertEqual(model.configuration, originalConfiguration)
        XCTAssertEqual(
            try UserDefaultsAppConfigurationStore(defaults: defaults).load(),
            persistedBefore
        )
        XCTAssertEqual(
            recorder.snapshot()
                .durationSamples["configuration.persistConfiguration"]?.count ?? 0,
            persistCountBefore
        )
    }

    func testUnchangedModeDoesNotPersist() {
        let binding = HotkeyBinding(
            target: .file(makeFileSystemItem(named: "Document.txt"), .systemDefault)
        )
        let recorder = PerformanceDiagnosticsRecorder(
            clock: ManualPerformanceDiagnosticsClock()
        )
        recorder.startSampling(round: .core)
        let model = makeModel(
            bindings: [binding],
            performanceDiagnosticsRecorder: recorder
        )
        let persistCountBefore = recorder.snapshot()
            .durationSamples["configuration.persistConfiguration"]?.count ?? 0

        model.setFileOpenMode(.systemDefault, for: binding.id)

        XCTAssertEqual(
            recorder.snapshot()
                .durationSamples["configuration.persistConfiguration"]?.count ?? 0,
            persistCountBefore
        )
    }

    func testSetOpeningApplicationStoresNoncandidateApplicationForFolder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let binding = HotkeyBinding(
            target: .folder(
                try ManagedFileSystemItem(url: folderURL),
                .finderNewTab
            )
        )
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in nil },
            applicationURLs: { _ in [] }
        )
        let model = makeModel(
            bindings: [binding],
            bindingOpenModeCatalog: catalog
        )
        XCTAssertTrue(
            model.targetPresentation(for: binding)
                .applicationCandidates.isEmpty
        )

        model.setOpeningApplication(handlerURL, for: binding.id)

        guard case .folder(_, .application(let application)) =
                model.bindings.first?.target else {
            return XCTFail("Expected selected folder handler")
        }
        XCTAssertEqual(application.bundleIdentifier, "com.example.handler")
    }

    func testSetOpeningApplicationPersistsSelectedFileHandler() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            )
        )
        let model = makeModel(
            bindings: [binding],
            configurationDefaults: defaults
        )

        model.setOpeningApplication(handlerURL, for: binding.id)

        let persisted = try UserDefaultsAppConfigurationStore(
            defaults: defaults
        ).load()
        guard case .file(_, .application(let application)) =
                persisted.bindings.first?.target else {
            return XCTFail("Expected persisted selected file handler")
        }
        XCTAssertEqual(application.bundleIdentifier, "com.example.handler")
    }

    func testSetOpeningApplicationRollsBackAfterSaveFailure() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            )
        )
        let model = makeModel(
            bindings: [binding],
            configurationDefaults: defaults,
            configurationSaver: { _ in
                throw NSError(
                    domain: "AppModelTests.SaveFailure",
                    code: 1
                )
            }
        )
        let originalConfiguration = model.configuration

        model.setOpeningApplication(handlerURL, for: binding.id)

        XCTAssertEqual(model.configuration, originalConfiguration)
        XCTAssertEqual(
            try UserDefaultsAppConfigurationStore(defaults: defaults).load(),
            originalConfiguration
        )
    }

    func testSetOpeningApplicationRejectsNonApplicationURLs() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let ordinaryFileURL = directory.appendingPathComponent("Notes.txt")
        try Data("value".utf8).write(to: ordinaryFileURL)
        let ordinaryDirectoryURL = directory.appendingPathComponent(
            "Ordinary",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: ordinaryDirectoryURL,
            withIntermediateDirectories: true
        )
        let fakeApplicationURL = directory.appendingPathComponent(
            "Fake.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fakeApplicationURL,
            withIntermediateDirectories: true
        )
        let nonApplicationBundleURL = try makeApplicationBundle(
            named: "Plugin",
            bundleIdentifier: "com.example.plugin",
            packageType: "BNDL",
            in: directory
        )
        let binding = HotkeyBinding(
            target: .folder(
                try ManagedFileSystemItem(url: folderURL),
                .finderNewTab
            )
        )
        let model = makeModel(
            bindings: [binding],
            configurationDefaults: defaults
        )
        let originalConfiguration = model.configuration

        for url in [
            ordinaryFileURL,
            ordinaryDirectoryURL,
            fakeApplicationURL,
            nonApplicationBundleURL,
        ] {
            model.setOpeningApplication(url, for: binding.id)
        }

        XCTAssertEqual(model.configuration, originalConfiguration)
        XCTAssertEqual(
            try UserDefaultsAppConfigurationStore(defaults: defaults).load(),
            originalConfiguration
        )
    }

    func testTargetPresentationIsCachedUntilSettingsRefresh() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            )
        )
        var fileExistsQueryCount = 0
        var availabilityQueryCount = 0
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in nil },
            applicationURLs: { _ in [] }
        )
        let resolver = HotkeyTargetPresentationResolver(
            catalog: catalog,
            resolveFileSystemItemURL: { _ in fileURL },
            startAccessingSecurityScopedResource: { _ in false },
            stopAccessingSecurityScopedResource: { _ in },
            fileExistsAtPath: { _ in
                fileExistsQueryCount += 1
                return true
            },
            displayNameAtURL: { $0.lastPathComponent },
            iconForURL: { _ in NSImage(size: NSSize(width: 16, height: 16)) }
        )
        let model = makeModel(
            bindings: [binding],
            bindingOpenModeCatalog: catalog,
            targetPresentationResolver: resolver,
            staticBindingAvailabilityProvider: { _ in
                availabilityQueryCount += 1
                return .available
            }
        )
        let availabilityQueriesAfterInitialization =
            availabilityQueryCount

        _ = model.targetPresentation(for: binding)
        _ = model.targetPresentation(for: binding)

        XCTAssertEqual(fileExistsQueryCount, 1)
        XCTAssertEqual(
            availabilityQueryCount,
            availabilityQueriesAfterInitialization
        )

        model.handleSettingsWindowAppeared()
        _ = model.targetPresentation(for: binding)

        XCTAssertEqual(fileExistsQueryCount, 2)
    }

    func testStaticAvailabilityDistinguishesTargetAndHandlerFailures() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let missingTarget = ManagedFileSystemItem(
            displayName: "Missing.txt",
            fallbackPath: directory
                .appendingPathComponent("Missing.txt").path,
            bookmarkData: Data()
        )
        let missingHandler = ManagedApplication(
            displayName: "Missing Handler",
            bundleIdentifier: "com.example.missing-handler",
            fallbackPath: directory
                .appendingPathComponent("Missing Handler.app").path,
            bookmarkData: Data()
        )
        let targetFailureBinding = HotkeyBinding(
            target: .file(missingTarget, .systemDefault)
        )
        let handlerFailureBinding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .application(missingHandler)
            )
        )
        let model = makeModel(
            bindings: [targetFailureBinding, handlerFailureBinding]
        )

        XCTAssertEqual(
            model.bindingAvailability(for: targetFailureBinding.id),
            .targetUnavailable
        )
        XCTAssertEqual(
            model.bindingAvailability(for: handlerFailureBinding.id),
            .openingApplicationUnavailable
        )
        XCTAssertEqual(
            model.targetPresentation(for: targetFailureBinding).availability,
            .targetUnavailable
        )
        let handlerPresentation = model.targetPresentation(
            for: handlerFailureBinding
        )
        XCTAssertEqual(
            handlerPresentation.availability,
            .openingApplicationUnavailable
        )
        XCTAssertNotNil(handlerPresentation.targetImage)
        XCTAssertNil(handlerPresentation.openingMode?.image)
    }

    func testTargetUpdateInvalidatesOnlyRelatedPresentation() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("First.txt")
        let secondURL = directory.appendingPathComponent("Second.txt")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let firstBinding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: firstURL),
                .systemDefault
            )
        )
        let secondBinding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: secondURL),
                .systemDefault
            )
        )
        var queryCounts: [String: Int] = [:]
        let resolver = HotkeyTargetPresentationResolver(
            catalog: BindingOpenModeCatalog(
                systemDefaultApplicationURL: { _ in nil },
                applicationURLs: { _ in [] }
            ),
            resolveFileSystemItemURL: {
                URL(fileURLWithPath: $0.fallbackPath)
            },
            startAccessingSecurityScopedResource: { _ in false },
            stopAccessingSecurityScopedResource: { _ in },
            fileExistsAtPath: {
                queryCounts[$0, default: 0] += 1
                return true
            },
            displayNameAtURL: { $0.lastPathComponent },
            iconForURL: { _ in NSImage(size: NSSize(width: 16, height: 16)) }
        )
        let model = makeModel(
            bindings: [firstBinding, secondBinding],
            targetPresentationResolver: resolver
        )

        _ = model.targetPresentation(for: firstBinding)
        _ = model.targetPresentation(for: secondBinding)
        model.setFileOpenMode(
            .application(try ManagedApplication(url: handlerURL)),
            for: firstBinding.id
        )

        let updatedFirstBinding = try XCTUnwrap(
            model.bindings.first { $0.id == firstBinding.id }
        )
        _ = model.targetPresentation(for: updatedFirstBinding)
        _ = model.targetPresentation(for: secondBinding)

        XCTAssertEqual(queryCounts[firstURL.path], 2)
        XCTAssertEqual(queryCounts[secondURL.path], 1)
    }

    func testSelectedApplicationPresentationRefreshesDynamicSystemDefault() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let selectedURL = try makeApplicationBundle(
            named: "Selected",
            bundleIdentifier: "com.example.selected",
            in: directory
        )
        let firstDefaultURL = try makeApplicationBundle(
            named: "First",
            bundleIdentifier: "com.example.first",
            in: directory
        )
        let secondDefaultURL = try makeApplicationBundle(
            named: "Second",
            bundleIdentifier: "com.example.second",
            in: directory
        )
        var currentDefaultURL = firstDefaultURL
        let catalog = BindingOpenModeCatalog(
            systemDefaultApplicationURL: { _ in currentDefaultURL },
            applicationURLs: { _ in [] }
        )
        let resolver = HotkeyTargetPresentationResolver(catalog: catalog)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .application(try ManagedApplication(url: selectedURL))
            )
        )
        let model = makeModel(
            bindings: [binding],
            bindingOpenModeCatalog: catalog,
            targetPresentationResolver: resolver
        )

        let first = model.targetPresentation(for: binding)
        currentDefaultURL = secondDefaultURL
        let cached = model.targetPresentation(for: binding)

        XCTAssertTrue(
            first.systemDefaultOpeningMode?.label.contains("First") == true
        )
        XCTAssertTrue(
            cached.systemDefaultOpeningMode?.label.contains("First") == true
        )

        model.handleApplicationDidBecomeActive()
        let refreshed = model.targetPresentation(for: binding)

        XCTAssertTrue(
            refreshed.systemDefaultOpeningMode?.label.contains("Second") ==
                true
        )
    }

    func testSwitchingDefaultFolderToSelectedApplicationKeepsPermissionFree() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let hotKeyManager = HotKeyManagerSpy()
        let binding = HotkeyBinding(
            target: .folder(
                try ManagedFileSystemItem(url: folderURL),
                .finderNewTab
            ),
            shortcut: AppShortcut(keyCode: 12, modifiers: [.option])
        )
        let model = makeModel(
            hotKeyManager: hotKeyManager,
            bindings: [binding],
            accessibilityPermissionGranted: false
        )
        let refreshCountBefore = hotKeyManager.updateCallCount
        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)
        XCTAssertTrue(model.isBindingRegistered(binding.id))

        model.setOpeningApplication(handlerURL, for: binding.id)

        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)
        XCTAssertTrue(model.isBindingRegistered(binding.id))
        XCTAssertEqual(hotKeyManager.updateCallCount, refreshCountBefore + 1)
    }

    func testSwitchingSelectedFolderToFinderKeepsPermissionFreeAndPersists() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let handler = try ManagedApplication(url: handlerURL)
        let hotKeyManager = HotKeyManagerSpy()
        let binding = HotkeyBinding(
            target: .folder(
                try ManagedFileSystemItem(url: folderURL),
                .application(handler)
            ),
            shortcut: AppShortcut(keyCode: 12, modifiers: [.option])
        )
        let model = makeModel(
            hotKeyManager: hotKeyManager,
            bindings: [binding],
            accessibilityPermissionGranted: false,
            configurationDefaults: defaults
        )
        let refreshCountBefore = hotKeyManager.updateCallCount
        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)

        model.setFolderOpenMode(.finderNewTab, for: binding.id)

        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)
        XCTAssertTrue(model.isBindingRegistered(binding.id))
        XCTAssertEqual(hotKeyManager.updateCallCount, refreshCountBefore + 1)
        let persisted = try UserDefaultsAppConfigurationStore(
            defaults: defaults
        ).load()
        guard case .folder(_, .finderNewTab) =
                persisted.bindings.first?.target else {
            return XCTFail("Expected persisted Finder folder mode")
        }
    }

    func testRegistrationUsesTargetSpecificPermissionMatrix() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Application",
            bundleIdentifier: "com.example.application",
            in: directory
        )
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let application = try ManagedApplication(url: applicationURL)
        let handler = try ManagedApplication(url: handlerURL)
        let folder = try ManagedFileSystemItem(url: folderURL)
        let file = try ManagedFileSystemItem(url: fileURL)
        let bindings = [
            HotkeyBinding(
                target: .application(application),
                shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
            ),
            HotkeyBinding(
                target: .folder(folder, .finderNewTab),
                shortcut: AppShortcut(keyCode: 1, modifiers: [.option])
            ),
            HotkeyBinding(
                target: .folder(folder, .application(handler)),
                shortcut: AppShortcut(keyCode: 2, modifiers: [.option])
            ),
            HotkeyBinding(
                target: .file(file, .systemDefault),
                shortcut: AppShortcut(keyCode: 3, modifiers: [.option])
            ),
            HotkeyBinding(
                target: .file(file, .application(handler)),
                shortcut: AppShortcut(keyCode: 4, modifiers: [.option])
            ),
        ]

        let deniedManager = HotKeyManagerSpy()
        _ = makeModel(
            hotKeyManager: deniedManager,
            bindings: bindings,
            accessibilityPermissionGranted: false
        )
        XCTAssertEqual(
            deniedManager.lastRequests.map(\.action),
            bindings[1...4].map { .binding($0.id) }
        )

        let allowedManager = HotKeyManagerSpy()
        _ = makeModel(
            hotKeyManager: allowedManager,
            bindings: bindings,
            accessibilityPermissionGranted: true
        )
        XCTAssertEqual(
            allowedManager.lastRequests.map(\.action),
            bindings.map { .binding($0.id) }
        )
    }

    func testInvalidTargetAndHandlerBlockOnlyTheirBindings() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let validFileURL = directory.appendingPathComponent("Valid.txt")
        try Data("value".utf8).write(to: validFileURL)
        let validFile = try ManagedFileSystemItem(url: validFileURL)
        let missingFile = makeFileSystemItem(named: "Missing.txt")
        let missingHandler = ManagedApplication(
            displayName: "Missing Handler",
            bundleIdentifier: "com.example.missing-handler",
            fallbackPath: directory.appendingPathComponent("Missing.app").path,
            bookmarkData: Data()
        )
        let invalidTarget = HotkeyBinding(
            target: .file(missingFile, .systemDefault),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let invalidHandler = HotkeyBinding(
            target: .file(validFile, .application(missingHandler)),
            shortcut: AppShortcut(keyCode: 1, modifiers: [.option])
        )
        let valid = HotkeyBinding(
            target: .file(validFile, .systemDefault),
            shortcut: AppShortcut(keyCode: 2, modifiers: [.option])
        )
        let manager = HotKeyManagerSpy()
        let model = makeModel(
            hotKeyManager: manager,
            bindings: [invalidTarget, invalidHandler, valid]
        )

        XCTAssertTrue(model.isBindingInvalid(invalidTarget.id))
        XCTAssertTrue(model.isBindingInvalid(invalidHandler.id))
        XCTAssertFalse(model.isBindingInvalid(valid.id))
        XCTAssertFalse(model.canPerformAction(for: invalidTarget.id))
        XCTAssertFalse(
            model.canPerformMenuBarSwitchAction(for: invalidTarget.id)
        )
        XCTAssertFalse(model.canPerformAction(for: invalidHandler.id))
        XCTAssertFalse(
            model.canPerformMenuBarSwitchAction(for: invalidHandler.id)
        )
        XCTAssertEqual(manager.lastRequests.map(\.action), [.binding(valid.id)])
    }

    func testShortcutConflictIsTargetNeutral() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Application",
            bundleIdentifier: "com.example.application",
            in: directory
        )
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let shortcut = AppShortcut(keyCode: 0, modifiers: [.option])
        let application = HotkeyBinding(
            target: .application(try ManagedApplication(url: applicationURL)),
            shortcut: shortcut
        )
        let file = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            ),
            shortcut: shortcut
        )
        let model = makeModel(bindings: [application, file])

        XCTAssertTrue(model.isBindingDuplicateShortcut(application.id))
        XCTAssertTrue(model.isBindingDuplicateShortcut(file.id))
        XCTAssertFalse(model.isBindingRegistered(application.id))
        XCTAssertFalse(model.isBindingRegistered(file.id))
    }

    func testAccessibilityRefreshImmediatelyUpdatesRegistration() {
        let permissionState = AccessibilityPermissionState(granted: false)
        let manager = HotKeyManagerSpy()
        let binding = makeBinding(
            named: "Safari",
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let model = makeModel(
            hotKeyManager: manager,
            bindings: [binding],
            accessibilityPermissionStatusProvider: {
                permissionState.granted
            }
        )
        let originalConfiguration = model.configuration
        XCTAssertTrue(manager.lastRequests.isEmpty)

        permissionState.granted = true
        model.refreshAccessibilityPermissionStatus()

        XCTAssertEqual(
            manager.lastRequests.map(\.action),
            [.binding(binding.id)]
        )

        permissionState.granted = false
        model.refreshAccessibilityPermissionStatus()

        XCTAssertTrue(manager.lastRequests.isEmpty)
        XCTAssertTrue(model.shouldShowAccessibilityPermissionCallout)

        permissionState.granted = true
        model.refreshAccessibilityPermissionStatus()

        XCTAssertEqual(manager.lastRequests.map(\.action), [.binding(binding.id)])
        XCTAssertFalse(model.shouldShowAccessibilityPermissionCallout)
        XCTAssertEqual(model.configuration, originalConfiguration)
    }

    func testHotKeyFailureDoesNotShowBannerButManualFailureDoes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            )
        )
        let executor = BindingActionExecutorSpy(
            result: .failure(
                .openFailed(
                    BindingActionFailure(
                        NSError(domain: "AppModelTests.Open", code: 17)
                    )
                )
            )
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        model.performAction(for: binding.id, source: .hotKey)
        XCTAssertNil(model.statusMessage)

        model.performAction(for: binding.id, source: .manual)
        XCTAssertNotNil(model.statusMessage)
    }

    func testRefreshedItemReplacesSameTargetAndPersistsSilently() throws {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let originalItem = try ManagedFileSystemItem(url: fileURL)
        let refreshedItem = ManagedFileSystemItem(
            displayName: "Refreshed",
            fallbackPath: fileURL.path,
            bookmarkData: Data([1, 2, 3])
        )
        let binding = HotkeyBinding(
            target: .file(originalItem, .systemDefault),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let store = UserDefaultsAppConfigurationStore(defaults: defaults)
        let executor = BindingActionExecutorSpy(
            result: .success(.opened(refreshedItem: refreshedItem))
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding],
            configurationDefaults: defaults,
            configurationSaver: { try store.save($0) }
        )

        model.performAction(for: binding.id, source: .hotKey)

        guard case .file(let updatedItem, .systemDefault) =
                model.bindings.first?.target else {
            return XCTFail("Expected same file mode")
        }
        XCTAssertEqual(model.bindings.first?.id, binding.id)
        XCTAssertEqual(model.bindings.first?.shortcut, binding.shortcut)
        XCTAssertEqual(updatedItem, refreshedItem)
        XCTAssertEqual(try store.load().bindings.first, model.bindings.first)
        XCTAssertNil(model.statusMessage)
    }

    func testRefreshedItemSaveFailureRollsBackWithoutBanner() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let originalItem = try ManagedFileSystemItem(url: fileURL)
        let refreshedItem = ManagedFileSystemItem(
            displayName: "Refreshed",
            fallbackPath: fileURL.path,
            bookmarkData: Data([1, 2, 3])
        )
        let binding = HotkeyBinding(
            target: .file(originalItem, .systemDefault)
        )
        let executor = BindingActionExecutorSpy(
            result: .success(.opened(refreshedItem: refreshedItem))
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding],
            configurationSaver: { _ in
                throw NSError(domain: "AppModelTests.Save", code: 91)
            }
        )

        model.performAction(for: binding.id, source: .hotKey)

        XCTAssertEqual(model.bindings.first, binding)
        XCTAssertNil(model.statusMessage)
    }

    func testOlderManualCompletionCannotOverrideNewerRuntimeFailure() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let originalItem = try ManagedFileSystemItem(url: fileURL)
        let refreshedItem = ManagedFileSystemItem(
            displayName: "Old Refresh",
            fallbackPath: fileURL.path,
            bookmarkData: Data([1, 2, 3])
        )
        let binding = HotkeyBinding(
            target: .file(originalItem, .systemDefault),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let executor = DeferredBindingActionExecutorSpy()
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        model.performAction(for: binding.id, source: .manual)
        model.performAction(for: binding.id, source: .manual)

        executor.complete(at: 1, with: .failure(.targetUnavailable))
        XCTAssertTrue(model.isBindingInvalid(binding.id))
        XCTAssertFalse(model.isBindingRegistered(binding.id))
        XCTAssertEqual(
            model.statusMessage,
            BindingActionError.targetUnavailable.errorDescription
        )

        executor.complete(
            at: 0,
            with: .success(.opened(refreshedItem: refreshedItem))
        )

        XCTAssertEqual(model.bindings.first, binding)
        XCTAssertTrue(model.isBindingInvalid(binding.id))
        XCTAssertFalse(model.isBindingRegistered(binding.id))
        XCTAssertEqual(
            model.statusMessage,
            BindingActionError.targetUnavailable.errorDescription
        )
    }

    func testOutOfOrderHotKeyCompletionsEachFinishDiagnostics() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            ),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let recorder = PerformanceDiagnosticsRecorder(
            clock: ManualPerformanceDiagnosticsClock()
        )
        recorder.startSampling(round: .core)
        let executor = DeferredBindingActionExecutorSpy()
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding],
            performanceDiagnosticsRecorder: recorder
        )
        let shortcut = try XCTUnwrap(binding.shortcut)

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: shortcut,
            frontmostProcessIdentifier: nil
        )
        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: shortcut,
            frontmostProcessIdentifier: nil
        )

        executor.complete(at: 1, with: .failure(.targetUnavailable))
        executor.complete(
            at: 0,
            with: .success(.opened(refreshedItem: nil))
        )

        let completions = recorder.snapshot().rawEvents.filter {
            $0.name == "completion" &&
                $0.metadata["bindingID"] == binding.id.uuidString
        }
        XCTAssertEqual(completions.count, 2)
        XCTAssertEqual(
            Set(completions.compactMap { $0.metadata["result"] }),
            Set(["failure", "success"])
        )
    }

    func testRemovingBindingInvalidatesInFlightCompletion() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            )
        )
        let executor = DeferredBindingActionExecutorSpy()
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        model.performAction(for: binding.id, source: .manual)
        model.removeBinding(binding.id)
        let removalStatus = model.statusMessage

        executor.complete(
            at: 0,
            with: .success(.opened(refreshedItem: nil))
        )

        XCTAssertFalse(model.bindings.contains { $0.id == binding.id })
        XCTAssertEqual(model.statusMessage, removalStatus)
    }

    func testModeChangeInvalidatesNextRunLoopCompletionWithoutCancellingIt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let handler = try ManagedApplication(url: handlerURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            ),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let executor = DeferredBindingActionExecutorSpy(
            executionTiming: .nextRunLoop
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        model.performAction(for: binding.id, source: .manual)
        model.setFileOpenMode(.application(handler), for: binding.id)

        XCTAssertTrue(waitUntil {
            executor.pendingCompletionCount == 1
        })
        executor.complete(at: 0, with: .failure(.targetUnavailable))

        guard case .file(_, .application(let updatedHandler)) =
                model.bindings.first?.target else {
            return XCTFail("Expected updated file handler")
        }
        XCTAssertEqual(updatedHandler, handler)
        XCTAssertFalse(model.isBindingInvalid(binding.id))
        XCTAssertTrue(model.isBindingRegistered(binding.id))
        XCTAssertNil(model.statusMessage)
    }

    func testNewestFileRefreshWinsWhenCompletionsArriveInReverseOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let originalItem = try ManagedFileSystemItem(url: fileURL)
        let olderRefresh = ManagedFileSystemItem(
            displayName: "Older Refresh",
            fallbackPath: fileURL.path,
            bookmarkData: Data([1])
        )
        let newestRefresh = ManagedFileSystemItem(
            displayName: "Newest Refresh",
            fallbackPath: fileURL.path,
            bookmarkData: Data([2])
        )
        let binding = HotkeyBinding(
            target: .file(originalItem, .systemDefault)
        )
        let executor = DeferredBindingActionExecutorSpy()
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        model.performAction(for: binding.id, source: .hotKey)
        model.performAction(for: binding.id, source: .hotKey)
        executor.complete(
            at: 1,
            with: .success(.opened(refreshedItem: newestRefresh))
        )
        executor.complete(
            at: 0,
            with: .success(.opened(refreshedItem: olderRefresh))
        )

        guard case .file(let storedItem, .systemDefault) =
                model.bindings.first?.target else {
            return XCTFail("Expected system-default file target")
        }
        XCTAssertEqual(storedItem, newestRefresh)
    }

    func testNewestFolderRefreshWinsWhenCompletionsArriveInReverseOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent(
            "Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let originalItem = try ManagedFileSystemItem(url: folderURL)
        let olderRefresh = ManagedFileSystemItem(
            displayName: "Older Refresh",
            fallbackPath: folderURL.path,
            bookmarkData: Data([1])
        )
        let newestRefresh = ManagedFileSystemItem(
            displayName: "Newest Refresh",
            fallbackPath: folderURL.path,
            bookmarkData: Data([2])
        )
        let binding = HotkeyBinding(
            target: .folder(originalItem, .finderNewTab)
        )
        let executor = DeferredBindingActionExecutorSpy()
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        model.performAction(for: binding.id, source: .hotKey)
        model.performAction(for: binding.id, source: .hotKey)
        executor.complete(
            at: 1,
            with: .success(.opened(refreshedItem: newestRefresh))
        )
        executor.complete(
            at: 0,
            with: .success(.opened(refreshedItem: olderRefresh))
        )

        guard case .folder(let storedItem, .finderNewTab) =
                model.bindings.first?.target else {
            return XCTFail("Expected Finder-tab folder target")
        }
        XCTAssertEqual(storedItem, newestRefresh)
    }

    func testHotKeyStaleItemRefreshSuppressesRegistrationFailureBanner() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let originalItem = try ManagedFileSystemItem(url: fileURL)
        let refreshedItem = ManagedFileSystemItem(
            displayName: "Refreshed",
            fallbackPath: fileURL.path,
            bookmarkData: Data([1, 2, 3])
        )
        let binding = HotkeyBinding(
            target: .file(originalItem, .systemDefault),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        var registrationShouldFail = false
        let manager = HotKeyManagerSpy(failurePredicate: { _ in
            registrationShouldFail
        })
        let executor = BindingActionExecutorSpy(
            result: .success(.opened(refreshedItem: refreshedItem))
        )
        let model = makeModel(
            hotKeyManager: manager,
            bindingActionExecutor: executor,
            bindings: [binding]
        )
        registrationShouldFail = true

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: try XCTUnwrap(binding.shortcut),
            frontmostProcessIdentifier: nil
        )

        XCTAssertEqual(manager.updateCallCount, 2)
        XCTAssertNil(model.statusMessage)
    }

    func testDeletedFileHotKeyInvalidatesAndUnregistersWithoutBanner() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        let otherFileURL = directory.appendingPathComponent("Other.txt")
        try Data("value".utf8).write(to: fileURL)
        try Data("other".utf8).write(to: otherFileURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            ),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let unaffectedBinding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: otherFileURL),
                .systemDefault
            ),
            shortcut: AppShortcut(keyCode: 1, modifiers: [.option])
        )
        var registrationShouldFail = false
        let manager = HotKeyManagerSpy(failurePredicate: { _ in
            registrationShouldFail
        })
        let model = makeModel(
            hotKeyManager: manager,
            bindings: [binding, unaffectedBinding]
        )
        XCTAssertTrue(model.isBindingRegistered(binding.id))
        XCTAssertTrue(model.isBindingRegistered(unaffectedBinding.id))
        registrationShouldFail = true
        try FileManager.default.removeItem(at: fileURL)

        model.handleHotKeyTrigger(
            for: binding.id,
            shortcut: try XCTUnwrap(binding.shortcut),
            frontmostProcessIdentifier: nil
        )

        XCTAssertTrue(waitUntil {
            model.isBindingInvalid(binding.id) &&
                !model.isBindingRegistered(binding.id)
        })
        XCTAssertTrue(model.isBindingRegistered(unaffectedBinding.id))
        XCTAssertEqual(
            Set(model.bindings.map(\.id)),
            Set([binding.id, unaffectedBinding.id])
        )
        XCTAssertEqual(
            model.bindingAvailability(for: binding.id),
            .targetUnavailable
        )
        let presentation = model.targetPresentation(for: binding)
        XCTAssertEqual(presentation.availability, .targetUnavailable)
        XCTAssertNil(presentation.targetImage)
        XCTAssertTrue(
            presentation.accessibilityValue.contains(
                LocalizationManager.shared.string(for: .targetUnavailable)
            )
        )
        XCTAssertNil(model.statusMessage)
    }

    func testRuntimeTargetUnavailableAllowsSuccessfulManualRetry() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            ),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let executor = BindingActionExecutorSpy(
            result: .failure(.targetUnavailable)
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )
        XCTAssertTrue(model.isBindingRegistered(binding.id))

        model.performAction(for: binding.id, source: .hotKey)

        XCTAssertTrue(model.isBindingInvalid(binding.id))
        XCTAssertFalse(model.isBindingRegistered(binding.id))
        XCTAssertNil(model.statusMessage)
        XCTAssertEqual(
            model.bindingAvailability(for: binding.id),
            .targetUnavailable
        )
        XCTAssertTrue(model.canPerformAction(for: binding.id))
        XCTAssertTrue(model.canPerformMenuBarSwitchAction(for: binding.id))

        model.performAction(for: binding.id, source: .manual)

        XCTAssertTrue(model.isBindingInvalid(binding.id))
        XCTAssertFalse(model.isBindingRegistered(binding.id))
        XCTAssertTrue(model.canPerformAction(for: binding.id))
        XCTAssertEqual(
            model.statusMessage,
            BindingActionError.targetUnavailable.errorDescription
        )

        executor.result = .success(.opened(refreshedItem: nil))
        model.performAction(for: binding.id, source: .manual)

        XCTAssertFalse(model.isBindingInvalid(binding.id))
        XCTAssertTrue(model.isBindingRegistered(binding.id))
        XCTAssertEqual(model.bindingAvailability(for: binding.id), .available)
        XCTAssertEqual(model.statusMessage, "Opened Document.txt")
    }

    func testDeletedSelectedHandlerManualActionInvalidatesOnlyItsBinding() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        let otherFileURL = directory.appendingPathComponent("Other.txt")
        try Data("value".utf8).write(to: fileURL)
        try Data("other".utf8).write(to: otherFileURL)
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let handler = try ManagedApplication(url: handlerURL)
        let selectedHandlerBinding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .application(handler)
            ),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let unaffectedBinding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: otherFileURL),
                .systemDefault
            ),
            shortcut: AppShortcut(keyCode: 1, modifiers: [.option])
        )
        let manager = HotKeyManagerSpy()
        let model = makeModel(
            hotKeyManager: manager,
            bindings: [selectedHandlerBinding, unaffectedBinding]
        )
        XCTAssertTrue(model.isBindingRegistered(selectedHandlerBinding.id))
        XCTAssertTrue(model.isBindingRegistered(unaffectedBinding.id))
        try FileManager.default.removeItem(at: handlerURL)

        model.performAction(
            for: selectedHandlerBinding.id,
            source: .manual
        )

        XCTAssertTrue(model.isBindingInvalid(selectedHandlerBinding.id))
        XCTAssertFalse(model.isBindingRegistered(selectedHandlerBinding.id))
        XCTAssertTrue(model.isBindingRegistered(unaffectedBinding.id))
        XCTAssertEqual(
            Set(model.bindings.map(\.id)),
            Set([selectedHandlerBinding.id, unaffectedBinding.id])
        )
        XCTAssertEqual(
            model.bindingAvailability(for: selectedHandlerBinding.id),
            .openingApplicationUnavailable
        )
        let presentation = model.targetPresentation(
            for: selectedHandlerBinding
        )
        XCTAssertEqual(
            presentation.availability,
            .openingApplicationUnavailable
        )
        XCTAssertNotNil(presentation.targetImage)
        XCTAssertEqual(
            presentation.openingMode?.label,
            LocalizationManager.shared.string(
                for: .openingApplicationUnavailable
            )
        )
        XCTAssertTrue(
            presentation.accessibilityValue.contains(
                LocalizationManager.shared.string(
                    for: .openingApplicationUnavailable
                )
            )
        )
        XCTAssertEqual(
            model.statusMessage,
            BindingActionError.selectedHandlerUnavailable.errorDescription
        )
    }

    func testSuccessfulManualRetryClearsHandlerAvailabilityAndPresentation() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .application(try ManagedApplication(url: handlerURL))
            )
        )
        let executor = BindingActionExecutorSpy(
            result: .failure(.selectedHandlerUnavailable)
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        model.performAction(for: binding.id, source: .manual)
        XCTAssertEqual(
            model.targetPresentation(for: binding).availability,
            .openingApplicationUnavailable
        )

        executor.result = .success(.opened(refreshedItem: nil))
        model.performAction(for: binding.id, source: .manual)

        let presentation = model.targetPresentation(for: binding)
        XCTAssertEqual(model.bindingAvailability(for: binding.id), .available)
        XCTAssertEqual(presentation.availability, .available)
        XCTAssertEqual(presentation.openingMode?.label, "Handler")
        XCTAssertNotNil(presentation.openingMode?.image)
    }

    func testTargetReplacementClearsRuntimeInvalidAndAvailabilityCache() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Document.txt")
        try Data("value".utf8).write(to: fileURL)
        let handlerURL = try makeApplicationBundle(
            named: "Handler",
            bundleIdentifier: "com.example.handler",
            in: directory
        )
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            )
        )
        let executor = BindingActionExecutorSpy(
            result: .failure(.targetUnavailable)
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding]
        )

        model.performAction(for: binding.id, source: .manual)
        XCTAssertTrue(model.hasRuntimeInvalidBindingState(for: binding.id))
        XCTAssertTrue(model.hasCachedBindingAvailability(for: binding.id))

        model.setFileOpenMode(
            .application(try ManagedApplication(url: handlerURL)),
            for: binding.id
        )

        XCTAssertFalse(model.hasRuntimeInvalidBindingState(for: binding.id))
        XCTAssertFalse(model.hasCachedBindingAvailability(for: binding.id))
        XCTAssertEqual(model.bindingAvailability(for: binding.id), .available)
    }

    func testManagedActivityMonitorDeletionClearsRuntimeAndAvailabilityState() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationURL = try makeApplicationBundle(
            named: "Activity Monitor",
            bundleIdentifier: ActivityMonitorHotKeyFeature.bundleIdentifier,
            in: directory
        )
        let application = try ManagedApplication(url: applicationURL)
        let executor = BindingActionExecutorSpy(
            result: .failure(.targetUnavailable)
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            activityMonitorApplicationProvider: { application }
        )
        model.setActivityMonitorHotKeyEnabled(true)
        let binding = try XCTUnwrap(
            model.bindings.first { $0.source == .activityMonitorFeature }
        )

        model.performAction(for: binding.id, source: .manual)
        XCTAssertTrue(model.hasRuntimeInvalidBindingState(for: binding.id))
        XCTAssertTrue(model.hasCachedBindingAvailability(for: binding.id))

        model.setActivityMonitorHotKeyEnabled(false)

        XCTAssertFalse(model.hasRuntimeInvalidBindingState(for: binding.id))
        XCTAssertFalse(model.hasCachedBindingAvailability(for: binding.id))
        XCTAssertFalse(model.bindings.contains { $0.id == binding.id })
    }

    func testBindingActionDiagnosticsAreTargetNeutralAndPathFree() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Sensitive.txt")
        try Data("value".utf8).write(to: fileURL)
        let binding = HotkeyBinding(
            target: .file(
                try ManagedFileSystemItem(url: fileURL),
                .systemDefault
            ),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let recorder = PerformanceDiagnosticsRecorder(
            clock: ManualPerformanceDiagnosticsClock()
        )
        recorder.startSampling(round: .core)
        let executor = BindingActionExecutorSpy(
            result: .failure(
                .openFailed(
                    BindingActionFailure(
                        NSError(domain: "AppModelTests.Open", code: 17)
                    )
                )
            )
        )
        let model = makeModel(
            bindingActionExecutor: executor,
            bindings: [binding],
            performanceDiagnosticsRecorder: recorder
        )

        model.performAction(for: binding.id, source: .hotKey)

        let metadata = try XCTUnwrap(
            recorder.snapshot().rawEvents
                .last { $0.name == "completion" }?
                .metadata
        )
        XCTAssertEqual(metadata["bindingID"], binding.id.uuidString)
        XCTAssertEqual(metadata["targetKind"], "file")
        XCTAssertEqual(metadata["openModeKind"], "systemDefault")
        XCTAssertEqual(metadata["invocationSource"], "hotKey")
        XCTAssertEqual(metadata["stage"], "completion")
        XCTAssertEqual(metadata["result"], "failure")
        XCTAssertEqual(metadata["errorDomain"], "AppModelTests.Open")
        XCTAssertEqual(metadata["errorCode"], "17")
        XCTAssertFalse(metadata.values.contains {
            $0.contains(directory.path) || $0.contains(fileURL.path)
        })
    }

    func testDefaultFolderDiagnosticsDescribeCurrentSystemOpenBehavior() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let binding = HotkeyBinding(
            target: .folder(
                try ManagedFileSystemItem(url: directory),
                .finderNewTab
            ),
            shortcut: AppShortcut(keyCode: 0, modifiers: [.option])
        )
        let recorder = PerformanceDiagnosticsRecorder(
            clock: ManualPerformanceDiagnosticsClock()
        )
        recorder.startSampling(round: .core)
        let model = makeModel(
            bindingActionExecutor: BindingActionExecutorSpy(
                result: .success(.opened(refreshedItem: nil))
            ),
            bindings: [binding],
            performanceDiagnosticsRecorder: recorder
        )

        model.performAction(for: binding.id, source: .hotKey)

        let metadata = try XCTUnwrap(
            recorder.snapshot().rawEvents
                .last { $0.name == "completion" }?
                .metadata
        )
        XCTAssertEqual(metadata["targetKind"], "folder")
        XCTAssertEqual(metadata["openModeKind"], "systemDefault")
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return condition()
    }

    private func makeBinding(
        named name: String,
        fallbackPath: String? = nil,
        shortcut: AppShortcut? = nil
    ) -> HotkeyBinding {
        HotkeyBinding(
            target: .application(
                ManagedApplication(
                    displayName: name,
                    bundleIdentifier: nil,
                    fallbackPath: fallbackPath ?? "/Applications/\(name).app",
                    bookmarkData: Data()
                )
            ),
            shortcut: shortcut
        )
    }

    private func isActivityMonitorBinding(_ binding: HotkeyBinding) -> Bool {
        guard case .application(let application) = binding.target else {
            return false
        }

        return application.bundleIdentifier ==
            ActivityMonitorHotKeyFeature.bundleIdentifier
    }

    private func makeActivityMonitorApplication() -> ManagedApplication {
        ManagedApplication(
            displayName: "Activity Monitor",
            bundleIdentifier: ActivityMonitorHotKeyFeature.bundleIdentifier,
            fallbackPath: ActivityMonitorHotKeyFeature.fallbackPath,
            bookmarkData: Data()
        )
    }

    private func makeFileSystemItem(named name: String) -> ManagedFileSystemItem {
        ManagedFileSystemItem(
            displayName: name,
            fallbackPath: "/tmp/\(name)",
            bookmarkData: Data()
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeApplicationBundle(
        named name: String,
        bundleIdentifier: String?,
        packageType: String = "APPL",
        in directory: URL
    ) throws -> URL {
        let applicationURL = directory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        var infoPlist: [String: Any] = [
            "CFBundleName": name,
            "CFBundlePackageType": packageType,
        ]
        infoPlist["CFBundleIdentifier"] = bundleIdentifier
        let infoPlistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try infoPlistData.write(
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        return applicationURL
    }

    private func makeModel(
        hotKeyManager: any GlobalHotKeyManaging = GlobalHotKeyManager(),
        toggleService: any ApplicationToggleServicing = ApplicationToggleService(),
        bindingActionExecutor: (any BindingActionExecuting)? = nil,
        activityMonitorApplicationProvider: @escaping @MainActor () -> ManagedApplication? = {
            ActivityMonitorHotKeyFeature.makeManagedApplication()
        },
        bindings: [HotkeyBinding] = [],
        windowsStyleCutEnabled: Bool = false,
        mouseWheelWindowsScrollEnabled: Bool = false,
        pressedKeysOverlayEnabled: Bool = false,
        virtualKeyboardEnabled: Bool = true,
        virtualKeyboardRevealDelay: TimeInterval = VirtualKeyboardRevealDelay.defaultValue,
        hiddenBarEnabled: Bool = false,
        networkStatusEnabled: Bool = false,
        hotKeyIconFlashEnabled: Bool = false,
        advancedHotkeysEnabled: Bool = false,
        activityMonitorHotKeyEnabled: Bool = false,
        accessibilityPermissionGranted: Bool = true,
        accessibilityPermissionStatusProvider:
            (@MainActor () -> Bool)? = nil,
        hotkeyGuideStore: any HotkeyGuideStateStoring = FakeHotkeyGuideStateStore(),
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared,
        configurationDefaults: UserDefaults? = nil,
        bindingOpenModeCatalog: BindingOpenModeCatalog = BindingOpenModeCatalog(),
        targetPresentationResolver: HotkeyTargetPresentationResolver? = nil,
        staticBindingAvailabilityProvider:
            ((HotkeyBinding) -> HotkeyTargetAvailability)? = nil,
        configurationSaver: ((AppConfiguration) throws -> Void)? = nil
    ) -> AppModel {
        let suiteName = "AppWinkTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let shouldRemovePersistentDomain: Bool
        if let configurationDefaults {
            defaults = configurationDefaults
            shouldRemovePersistentDomain = false
        } else if let isolatedDefaults = UserDefaults(suiteName: suiteName) {
            defaults = isolatedDefaults
            shouldRemovePersistentDomain = true
        } else {
            fatalError("Failed to create isolated UserDefaults suite")
        }

        let store = UserDefaultsAppConfigurationStore(defaults: defaults)
        do {
            try store.save(AppConfiguration(
                bindings: bindings,
                windowsStyleCutEnabled: windowsStyleCutEnabled,
                pressedKeysOverlayEnabled: pressedKeysOverlayEnabled,
                advancedHotkeysEnabled: advancedHotkeysEnabled,
                activityMonitorHotKeyEnabled: activityMonitorHotKeyEnabled,
                hotKeyIconFlashEnabled: hotKeyIconFlashEnabled,
                hiddenBarEnabled: hiddenBarEnabled,
                networkStatusEnabled: networkStatusEnabled,
                mouseWheelWindowsScrollEnabled: mouseWheelWindowsScrollEnabled,
                virtualKeyboardEnabled: virtualKeyboardEnabled,
                virtualKeyboardRevealDelay: virtualKeyboardRevealDelay
            ))
        } catch {
            fatalError("Failed to seed configuration: \(error)")
        }

        let model = AppModel(
            store: store,
            hotKeyManager: hotKeyManager,
            applicationToggleService: toggleService,
            bindingActionExecutor: bindingActionExecutor,
            activityMonitorApplicationProvider: activityMonitorApplicationProvider,
            finderWindowsCutPasteService: FinderWindowsCutPasteService(),
            launchAtLoginController: TestLaunchAtLoginController(),
            hotkeyGuideStore: hotkeyGuideStore,
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder,
            localizationManager: .shared,
            accessibilityPermissionStatusProvider:
                accessibilityPermissionStatusProvider ?? {
                    accessibilityPermissionGranted
                },
            bindingOpenModeCatalog: bindingOpenModeCatalog,
            targetPresentationResolver: targetPresentationResolver,
            staticBindingAvailabilityProvider:
                staticBindingAvailabilityProvider,
            configurationSaver: configurationSaver
        )

        if shouldRemovePersistentDomain {
            addTeardownBlock {
                defaults.removePersistentDomain(forName: suiteName)
            }
            defaults.removePersistentDomain(forName: suiteName)
        }
        return model
    }
}

@MainActor
private final class AccessibilityPermissionState {
    var granted: Bool

    init(granted: Bool) {
        self.granted = granted
    }
}

@MainActor
private final class BindingActionExecutorSpy: BindingActionExecuting {
    struct Call {
        let binding: HotkeyBinding
        let authorization: BindingActionAuthorizationContext
        let frontmostProcessIdentifier: pid_t?
        let source: ToggleInvocationSource
    }

    private(set) var calls: [Call] = []
    var result: Result<BindingActionResult, BindingActionError>
    var isAccepted: Bool
    var executionTiming: PreparedApplicationToggleExecutionTiming
    var onPrepare: (() -> Void)?
    var onExecute: (() -> Void)?

    init(
        result: Result<BindingActionResult, BindingActionError> =
            .success(.opened(refreshedItem: nil)),
        isAccepted: Bool = true,
        executionTiming: PreparedApplicationToggleExecutionTiming = .immediate
    ) {
        self.result = result
        self.isAccepted = isAccepted
        self.executionTiming = executionTiming
    }

    func prepareAction(
        for binding: HotkeyBinding,
        authorization: BindingActionAuthorizationContext,
        frontmostProcessIdentifier: pid_t?,
        source: ToggleInvocationSource
    ) -> PreparedBindingAction {
        calls.append(Call(
            binding: binding,
            authorization: authorization,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            source: source
        ))
        onPrepare?()
        return PreparedBindingAction(
            executionTiming: executionTiming,
            isAccepted: isAccepted
        ) { completion in
            self.onExecute?()
            completion(self.result)
        }
    }
}

@MainActor
private final class DeferredBindingActionExecutorSpy:
    BindingActionExecuting {
    private typealias Completion = @MainActor (
        Result<BindingActionResult, BindingActionError>
    ) -> Void

    private var completions: [Int: Completion] = [:]
    private var nextExecutionIndex = 0
    private let executionTiming: PreparedApplicationToggleExecutionTiming

    var pendingCompletionCount: Int {
        completions.count
    }

    init(
        executionTiming: PreparedApplicationToggleExecutionTiming = .immediate
    ) {
        self.executionTiming = executionTiming
    }

    func prepareAction(
        for binding: HotkeyBinding,
        authorization: BindingActionAuthorizationContext,
        frontmostProcessIdentifier: pid_t?,
        source: ToggleInvocationSource
    ) -> PreparedBindingAction {
        PreparedBindingAction(
            executionTiming: executionTiming,
            isAccepted: true
        ) { completion in
            let executionIndex = self.nextExecutionIndex
            self.nextExecutionIndex += 1
            self.completions[executionIndex] = completion
        }
    }

    func complete(
        at executionIndex: Int,
        with result: Result<BindingActionResult, BindingActionError>
    ) {
        guard let completion = completions.removeValue(
            forKey: executionIndex
        ) else {
            preconditionFailure("Missing deferred binding action completion")
        }

        completion(result)
    }
}

private final class FakeHotkeyGuideStateStore: HotkeyGuideStateStoring {
    var isDismissed: Bool

    init(isDismissed: Bool = false) {
        self.isDismissed = isDismissed
    }
}

@MainActor
private final class ToggleServiceSpy: ApplicationToggleServicing {
    struct Call {
        let bindingName: String
        let frontmostProcessIdentifier: pid_t?
        let invocationSource: ToggleInvocationSource
    }

    private(set) var calls: [Call] = []
    var result: Result<ApplicationToggleResult, ApplicationToggleError>
    var onToggle: (() -> Void)?
    var executionTiming: PreparedApplicationToggleExecutionTiming = .nextRunLoop

    init(result: Result<ApplicationToggleResult, ApplicationToggleError> = .success(.hidden("Safari"))) {
        self.result = result
    }

    func prepareToggle(
        application: ManagedApplication,
        frontmostProcessIdentifier: pid_t?,
        invocationSource: ToggleInvocationSource
    ) -> PreparedApplicationToggle {
        PreparedApplicationToggle(executionTiming: executionTiming) { completion in
            self.calls.append(.init(
                bindingName: application.displayName,
                frontmostProcessIdentifier: frontmostProcessIdentifier,
                invocationSource: invocationSource
            ))
            self.onToggle?()
            completion(self.result)
        }
    }

    func waitForCall(timeout: TimeInterval = 1.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while calls.isEmpty && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return !calls.isEmpty
    }
}

private final class HotKeyManagerSpy: GlobalHotKeyManaging {
    private let lock = NSLock()
    private var storedLastRequests: [HotKeyRegistrationRequest] = []
    private var storedUpdateCallCount = 0
    private var storedUnregisterAllCallCount = 0
    private let failures: [HotKeyRegistrationAction]
    private let failurePredicate: ((HotKeyRegistrationAction) -> Bool)?

    var lastRequests: [HotKeyRegistrationRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedLastRequests
    }

    var updateCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedUpdateCallCount
    }

    var unregisterAllCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedUnregisterAllCallCount
    }

    init(
        failures: [HotKeyRegistrationAction] = [],
        failurePredicate: ((HotKeyRegistrationAction) -> Bool)? = nil
    ) {
        self.failures = failures
        self.failurePredicate = failurePredicate
    }

    func updateRegistrations(
        requests: [HotKeyRegistrationRequest],
        actionHandler: @escaping @MainActor (HotKeyRegistrationAction, AppShortcut, pid_t?) -> Void
    ) -> [HotKeyRegistrationAction] {
        lock.lock()
        storedLastRequests = requests
        storedUpdateCallCount += 1
        lock.unlock()
        if let failurePredicate {
            return requests.map(\.action).filter(failurePredicate)
        }

        return failures
    }

    func unregisterAll() {
        lock.lock()
        storedLastRequests.removeAll()
        storedUnregisterAllCallCount += 1
        lock.unlock()
    }
}

@MainActor
private final class TestLaunchAtLoginController: LaunchAtLoginControlling {
    private var currentState: LaunchAtLoginState = .disabled

    func status() -> LaunchAtLoginState {
        currentState
    }

    func setEnabled(_ enabled: Bool) throws {
        currentState = enabled ? .enabled : .disabled
    }
}
