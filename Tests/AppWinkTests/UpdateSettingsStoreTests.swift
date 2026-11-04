import Foundation

import XCTest
@testable import AppWinkRuntime

final class UpdateSettingsStoreTests: XCTestCase {
    func testAutomaticallyChecksForUpdatesDefaultsToFalseWhenNothingIsStored() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsUpdateSettingsStore(defaults: defaults)

        XCTAssertFalse(store.automaticallyChecksForUpdates)
    }

    func testSavingTrueAndReloadingReturnsTrue() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsUpdateSettingsStore(defaults: defaults)
        store.automaticallyChecksForUpdates = true

        XCTAssertTrue(UserDefaultsUpdateSettingsStore(defaults: defaults).automaticallyChecksForUpdates)
    }

    func testSavingFalseAndReloadingReturnsFalse() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsUpdateSettingsStore(defaults: defaults)
        store.automaticallyChecksForUpdates = true
        store.automaticallyChecksForUpdates = false

        XCTAssertFalse(UserDefaultsUpdateSettingsStore(defaults: defaults).automaticallyChecksForUpdates)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "UpdateSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return (.standard, suiteName)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
