import Foundation

import XCTest
@testable import AppWinkRuntime

final class HotkeyGuideStateStoreTests: XCTestCase {
    func testDismissedFlagDefaultsToFalse() {
        let suiteName = "HotkeyGuideStateStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsHotkeyGuideStateStore(defaults: defaults)

        XCTAssertFalse(store.isDismissed)
    }

    func testDismissedFlagPersistsAcrossStores() {
        let suiteName = "HotkeyGuideStateStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsHotkeyGuideStateStore(defaults: defaults)
        store.isDismissed = true

        XCTAssertTrue(UserDefaultsHotkeyGuideStateStore(defaults: defaults).isDismissed)
    }
}
