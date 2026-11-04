import Foundation

import XCTest
@testable import AppWinkCore

final class AppConfigurationStoreTests: XCTestCase {
    func testLoadReturnsEmptyConfigurationByDefault() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsAppConfigurationStore(
            defaults: defaults,
            storageKey: "configuration",
            legacyStorageKeys: [],
            legacyPersistentDomains: []
        )

        XCTAssertEqual(try store.load(), AppConfiguration())
    }

    func testSaveAndLoadRoundTripsConfiguration() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let applicationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")

        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: applicationURL) }

        let configuration = AppConfiguration(
            bindings: [
                HotkeyBinding(
                    target: .application(
                        try ManagedApplication(url: applicationURL)
                    ),
                    shortcut: AppShortcut(
                        keyCode: 8,
                        modifiers: [.command, .option]
                    ))
            ],
            language: .english,
            windowsStyleCutEnabled: true)

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testLoadMigratesLegacySingleApplicationConfiguration() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let applicationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")

        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: applicationURL) }

        let legacyApplication = try ManagedApplication(url: applicationURL)
        let legacyShortcut = AppShortcut(keyCode: 8, modifiers: [.command, .option])

        struct LegacyConfiguration: Codable {
            let selectedApplication: ManagedApplication
            let launchShortcut: AppShortcut
            let quitShortcut: AppShortcut?
        }

        let data = try JSONEncoder().encode(
            LegacyConfiguration(
                selectedApplication: legacyApplication,
                launchShortcut: legacyShortcut,
                quitShortcut: nil))
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertEqual(configuration.bindings.count, 1)
        XCTAssertEqual(
            configuration.bindings.first?.target,
            .application(legacyApplication)
        )
        XCTAssertEqual(configuration.bindings.first?.shortcut, legacyShortcut)
    }

    func testLoadDefaultsBindingEnabledToTrueWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let applicationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")

        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: applicationURL) }

        let application = try ManagedApplication(url: applicationURL)
        let shortcut = AppShortcut(keyCode: 8, modifiers: [.command, .option])

        struct LegacyBinding: Codable {
            let id: UUID
            let application: ManagedApplication
            let toggleShortcut: AppShortcut?
        }

        struct StoredConfiguration: Codable {
            let bindings: [LegacyBinding]
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(
                bindings: [
                    LegacyBinding(
                        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                        application: application,
                        toggleShortcut: shortcut)
                ]))
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertEqual(configuration.bindings.count, 1)
        XCTAssertEqual(configuration.bindings.first?.isEnabled, true)
        XCTAssertEqual(configuration.bindings.first?.source, .user)
    }

    func testLoadDefaultsLanguageToSystemWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
        }

        let data = try JSONEncoder().encode(StoredConfiguration(bindings: []))
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertEqual(configuration.language, .system)
    }

    func testLoadDefaultsAppearanceModeToSystemWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(bindings: [], language: .english)
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertEqual(configuration.appearanceMode, .system)
    }

    func testLoadDefaultsWindowsStyleCutToFalseWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(bindings: [], language: .english)
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertFalse(configuration.windowsStyleCutEnabled)
    }

    func testLoadDefaultsActivityMonitorHotKeyEnabledToFalseWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
            let windowsStyleCutEnabled: Bool
            let pressedKeysOverlayEnabled: Bool
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(
                bindings: [],
                language: .english,
                windowsStyleCutEnabled: true,
                pressedKeysOverlayEnabled: true
            )
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertFalse(configuration.activityMonitorHotKeyEnabled)
    }

    func testLoadDefaultsAdvancedHotkeysEnabledToFalseWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(bindings: [], language: .english)
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")

        XCTAssertFalse(try store.load().advancedHotkeysEnabled)
    }

    func testLoadDefaultsHotKeyIconFlashEnabledToFalseWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
            let windowsStyleCutEnabled: Bool
            let pressedKeysOverlayEnabled: Bool
            let activityMonitorHotKeyEnabled: Bool
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(
                bindings: [],
                language: .english,
                windowsStyleCutEnabled: true,
                pressedKeysOverlayEnabled: true,
                activityMonitorHotKeyEnabled: true
            )
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertFalse(configuration.hotKeyIconFlashEnabled)
    }

    func testLoadDefaultsHiddenBarEnabledToFalseWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
            let windowsStyleCutEnabled: Bool
            let pressedKeysOverlayEnabled: Bool
            let activityMonitorHotKeyEnabled: Bool
            let hotKeyIconFlashEnabled: Bool
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(
                bindings: [],
                language: .english,
                windowsStyleCutEnabled: true,
                pressedKeysOverlayEnabled: true,
                activityMonitorHotKeyEnabled: true,
                hotKeyIconFlashEnabled: true
            )
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertFalse(configuration.hiddenBarEnabled)
    }

    func testLoadDefaultsNetworkStatusEnabledToFalseWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let hiddenBarEnabled: Bool
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(bindings: [], hiddenBarEnabled: true)
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertFalse(configuration.networkStatusEnabled)
    }

    func testLoadDefaultsMouseWheelWindowsScrollEnabledToFalseWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
            let windowsStyleCutEnabled: Bool
            let pressedKeysOverlayEnabled: Bool
            let activityMonitorHotKeyEnabled: Bool
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(
                bindings: [],
                language: .english,
                windowsStyleCutEnabled: true,
                pressedKeysOverlayEnabled: true,
                activityMonitorHotKeyEnabled: true
            )
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertFalse(configuration.mouseWheelWindowsScrollEnabled)
    }

    func testLoadDefaultsPressedKeysOverlayEnabledToFalseWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
            let windowsStyleCutEnabled: Bool
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(
                bindings: [],
                language: .english,
                windowsStyleCutEnabled: true
            )
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertFalse(configuration.pressedKeysOverlayEnabled)
    }

    func testLoadDefaultsVirtualKeyboardSettingsWhenMissingFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let language: AppLanguage
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(bindings: [], language: .english)
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertTrue(configuration.virtualKeyboardEnabled)
        XCTAssertEqual(configuration.virtualKeyboardRevealDelay, VirtualKeyboardRevealDelay.defaultValue)
    }

    func testLoadNormalizesVirtualKeyboardRevealDelayFromStoredData() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct StoredConfiguration: Codable {
            let bindings: [HotkeyBinding]
            let virtualKeyboardEnabled: Bool
            let virtualKeyboardRevealDelay: TimeInterval
        }

        let data = try JSONEncoder().encode(
            StoredConfiguration(
                bindings: [],
                virtualKeyboardEnabled: true,
                virtualKeyboardRevealDelay: 0.74
            )
        )
        defaults.set(data, forKey: "configuration")

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        let configuration = try store.load()

        XCTAssertEqual(configuration.virtualKeyboardRevealDelay, 0.75)
    }

    func testSaveAndLoadRoundTripsPressedKeysOverlayEnabled() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            windowsStyleCutEnabled: true,
            pressedKeysOverlayEnabled: true
        )

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testSaveAndLoadRoundTripsVirtualKeyboardSettings() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            virtualKeyboardEnabled: false,
            virtualKeyboardRevealDelay: 1.5
        )

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testSaveAndLoadRoundTripsHotKeyIconFlashEnabled() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            windowsStyleCutEnabled: true,
            pressedKeysOverlayEnabled: true,
            activityMonitorHotKeyEnabled: true,
            hotKeyIconFlashEnabled: true
        )

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testSaveAndLoadRoundTripsAdvancedHotkeysEnabled() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            advancedHotkeysEnabled: true
        )
        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")

        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testSaveAndLoadRoundTripsHiddenBarEnabled() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            windowsStyleCutEnabled: true,
            pressedKeysOverlayEnabled: true,
            activityMonitorHotKeyEnabled: true,
            hotKeyIconFlashEnabled: true,
            hiddenBarEnabled: true
        )

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testSaveAndLoadRoundTripsNetworkStatusEnabled() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            hiddenBarEnabled: true,
            networkStatusEnabled: true
        )

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertTrue(try store.load().networkStatusEnabled)
    }

    func testSaveAndLoadRoundTripsMouseWheelWindowsScrollEnabled() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            windowsStyleCutEnabled: true,
            pressedKeysOverlayEnabled: true,
            activityMonitorHotKeyEnabled: true,
            mouseWheelWindowsScrollEnabled: true
        )

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testSaveAndLoadRoundTripsAppearanceMode() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            appearanceMode: .dark
        )

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testSaveAndLoadRoundTripsActivityMonitorHotKeyEnabled() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(
            bindings: [],
            language: .english,
            windowsStyleCutEnabled: true,
            pressedKeysOverlayEnabled: true,
            activityMonitorHotKeyEnabled: true
        )

        let store = UserDefaultsAppConfigurationStore(defaults: defaults, storageKey: "configuration")
        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testLocalizationManagerResolvesChineseBundleFromLowercaseLprojDirectory() {
        let bundle = LocalizationManager.localizedBundle(for: .chinese)
        let localizedLanguage = NSLocalizedString("settings.language", bundle: bundle, comment: "")

        XCTAssertEqual(localizedLanguage, "语言")
        XCTAssertTrue(bundle.bundlePath.lowercased().hasSuffix("zh-hans.lproj"))
    }

    func testLoadMigratesConfigurationFromLegacyPersistentDomain() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        let legacyDomainName = "com.kairanpeng.mytool.tests.\(UUID().uuidString)"
        let currentStorageKey = "com.kairanpeng.appwink.configuration.test"
        let legacyStorageKey = "com.kairanpeng.mytool.configuration.test"

        guard let defaults = UserDefaults(suiteName: suiteName),
              let legacyDefaults = UserDefaults(suiteName: legacyDomainName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            legacyDefaults.removePersistentDomain(forName: legacyDomainName)
        }

        let applicationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")

        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: applicationURL) }

        let configuration = AppConfiguration(
            bindings: [
                HotkeyBinding(
                    target: .application(
                        try ManagedApplication(url: applicationURL)
                    ),
                    shortcut: AppShortcut(
                        keyCode: 8,
                        modifiers: [.command, .option]
                    ))
            ],
            language: .english)

        let legacyData = try JSONEncoder().encode(configuration)
        legacyDefaults.set(legacyData, forKey: legacyStorageKey)

        let store = UserDefaultsAppConfigurationStore(
            defaults: defaults,
            storageKey: currentStorageKey,
            legacyStorageKeys: [legacyStorageKey],
            legacyPersistentDomains: [legacyDomainName]
        )

        XCTAssertEqual(try store.load(), configuration)
        XCTAssertNotNil(defaults.data(forKey: currentStorageKey))
    }

    func testMalformedBindingArrayThrowsWithoutChangingStoredBytes() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let malformedData = Data(
            #"{"bindings":[{"id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"}]}"#.utf8
        )
        defaults.set(malformedData, forKey: "configuration")
        let store = UserDefaultsAppConfigurationStore(
            defaults: defaults,
            storageKey: "configuration",
            legacyStorageKeys: [],
            legacyPersistentDomains: []
        )

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.data(forKey: "configuration"), malformedData)
    }

    func testMalformedCurrentPayloadDoesNotFallBackToLegacyConfiguration() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let malformedData = Data(#"{"bindings":null}"#.utf8)
        defaults.set(malformedData, forKey: "configuration")
        defaults.set(
            try JSONEncoder().encode(AppConfiguration()),
            forKey: "legacy-configuration"
        )
        let store = UserDefaultsAppConfigurationStore(
            defaults: defaults,
            storageKey: "configuration",
            legacyStorageKeys: ["legacy-configuration"],
            legacyPersistentDomains: []
        )

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.data(forKey: "configuration"), malformedData)
    }

    func testLegacyKeySingleApplicationMigrationWritesCanonicalShape() throws {
        let suiteName = "AppWinkCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let application = ManagedApplication(
            displayName: "Legacy",
            bundleIdentifier: "com.example.legacy",
            fallbackPath: "/Applications/Legacy.app",
            bookmarkData: Data("bookmark".utf8)
        )
        let shortcut = AppShortcut(keyCode: 8, modifiers: [.option])
        struct LegacyConfiguration: Encodable {
            let selectedApplication: ManagedApplication
            let launchShortcut: AppShortcut
        }
        defaults.set(
            try JSONEncoder().encode(
                LegacyConfiguration(
                    selectedApplication: application,
                    launchShortcut: shortcut
                )
            ),
            forKey: "legacy-configuration"
        )
        let store = UserDefaultsAppConfigurationStore(
            defaults: defaults,
            storageKey: "configuration",
            legacyStorageKeys: ["legacy-configuration"],
            legacyPersistentDomains: []
        )

        _ = try store.load()

        let migratedData = try XCTUnwrap(
            defaults.data(forKey: "configuration")
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        let bindings = try XCTUnwrap(object["bindings"] as? [[String: Any]])
        let binding = try XCTUnwrap(bindings.first)
        XCTAssertNotNil(binding["target"])
        XCTAssertNotNil(binding["shortcut"])
        XCTAssertNil(binding["application"])
        XCTAssertNil(binding["toggleShortcut"])
        XCTAssertNil(object["selectedApplication"])
        XCTAssertNil(object["launchShortcut"])
        XCTAssertNil(object["quitShortcut"])
    }
}
