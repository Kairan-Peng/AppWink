import Foundation

import XCTest
@testable import AppWinkRuntime

@MainActor
final class AppUpdateCoordinatorTests: XCTestCase {
    func testCheckForUpdatesForwardsToDriver() {
        let driver = FakeUpdateDriver()
        let store = UserDefaultsUpdateSettingsStore(defaults: isolatedDefaults())
        let coordinator = AppUpdateCoordinator(driver: driver, settingsStore: store)

        coordinator.checkForUpdates()

        XCTAssertEqual(driver.checkForUpdatesCallCount, 1)
    }

    func testSetAutomaticallyChecksForUpdatesUpdatesDriverAndStore() {
        let driver = FakeUpdateDriver()
        let defaults = isolatedDefaults()
        let store = UserDefaultsUpdateSettingsStore(defaults: defaults)
        let coordinator = AppUpdateCoordinator(driver: driver, settingsStore: store)

        coordinator.setAutomaticallyChecksForUpdates(true)

        XCTAssertTrue(driver.automaticallyChecksForUpdates)
        XCTAssertTrue(store.automaticallyChecksForUpdates)
        XCTAssertTrue(coordinator.automaticallyChecksForUpdates)
    }

    func testRefreshStateMirrorsCanCheckForUpdatesFromDriver() {
        let driver = FakeUpdateDriver()
        driver.canCheckForUpdates = false
        let coordinator = AppUpdateCoordinator(driver: driver, settingsStore: UserDefaultsUpdateSettingsStore(defaults: isolatedDefaults()))

        coordinator.refreshState()

        XCTAssertFalse(coordinator.canCheckForUpdates)
    }

    func testDriverStateChangesRefreshPublishedStateAutomatically() {
        let driver = FakeUpdateDriver()
        let coordinator = AppUpdateCoordinator(driver: driver, settingsStore: UserDefaultsUpdateSettingsStore(defaults: isolatedDefaults()))

        driver.canCheckForUpdates = false
        driver.automaticallyChecksForUpdates = true

        XCTAssertFalse(coordinator.canCheckForUpdates)
        XCTAssertTrue(coordinator.automaticallyChecksForUpdates)
    }

    func testRefreshStateMirrorsVisibilityFlagsFromDriver() {
        let driver = FakeUpdateDriver()
        driver.supportsAutomaticUpdateChecks = false
        driver.showsCheckForUpdatesAction = false
        let coordinator = AppUpdateCoordinator(driver: driver, settingsStore: UserDefaultsUpdateSettingsStore(defaults: isolatedDefaults()))

        coordinator.refreshState()

        XCTAssertFalse(coordinator.showsAutomaticUpdateChecksControl)
        XCTAssertFalse(coordinator.showsCheckForUpdatesAction)
    }

    func testDriverVisibilityStateChangesRefreshPublishedVisibilityAutomatically() {
        let driver = FakeUpdateDriver()
        let coordinator = AppUpdateCoordinator(driver: driver, settingsStore: UserDefaultsUpdateSettingsStore(defaults: isolatedDefaults()))

        driver.supportsAutomaticUpdateChecks = false
        driver.showsCheckForUpdatesAction = false

        XCTAssertFalse(coordinator.showsAutomaticUpdateChecksControl)
        XCTAssertFalse(coordinator.showsCheckForUpdatesAction)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "AppUpdateCoordinatorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
final class FakeUpdateDriver: AppUpdateDriving {
    var stateDidChange: (() -> Void)?
    var checkForUpdatesCallCount = 0

    private var isNotifyingStateChange = false
    var canCheckForUpdates: Bool {
        get { storedCanCheckForUpdates }
        set {
            storedCanCheckForUpdates = newValue
            notifyStateChangeIfNeeded()
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { storedAutomaticallyChecksForUpdates }
        set {
            storedAutomaticallyChecksForUpdates = newValue
            notifyStateChangeIfNeeded()
        }
    }

    var supportsAutomaticUpdateChecks: Bool {
        get { storedSupportsAutomaticUpdateChecks }
        set {
            storedSupportsAutomaticUpdateChecks = newValue
            notifyStateChangeIfNeeded()
        }
    }

    var showsCheckForUpdatesAction: Bool {
        get { storedShowsCheckForUpdatesAction }
        set {
            storedShowsCheckForUpdatesAction = newValue
            notifyStateChangeIfNeeded()
        }
    }

    private var storedCanCheckForUpdates = true
    private var storedAutomaticallyChecksForUpdates = false
    private var storedSupportsAutomaticUpdateChecks = true
    private var storedShowsCheckForUpdatesAction = true

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    private func notifyStateChangeIfNeeded() {
        guard !isNotifyingStateChange else {
            return
        }

        isNotifyingStateChange = true
        stateDidChange?()
        isNotifyingStateChange = false
    }
}
