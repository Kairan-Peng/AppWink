import Combine
import Foundation
import SwiftUI
import AppWinkCore

@MainActor
public protocol AppUpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var stateDidChange: (() -> Void)? { get set }
    var supportsAutomaticUpdateChecks: Bool { get }
    var showsCheckForUpdatesAction: Bool { get }

    func checkForUpdates()
}

public extension AppUpdateDriving {
    var supportsAutomaticUpdateChecks: Bool { canCheckForUpdates }
    var showsCheckForUpdatesAction: Bool { canCheckForUpdates }
}

@MainActor
final class AppUpdateCoordinator: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var showsAutomaticUpdateChecksControl: Bool
    @Published private(set) var showsCheckForUpdatesAction: Bool

    private let driver: AppUpdateDriving
    private let settingsStore: UpdateSettingsStoring?

    init(
        driver: AppUpdateDriving,
        settingsStore: UpdateSettingsStoring? = UserDefaultsUpdateSettingsStore()
    ) {
        self.driver = driver
        self.settingsStore = settingsStore

        if let settingsStore {
            driver.automaticallyChecksForUpdates = settingsStore.automaticallyChecksForUpdates
        }

        self.canCheckForUpdates = false
        self.automaticallyChecksForUpdates = false
        self.showsAutomaticUpdateChecksControl = false
        self.showsCheckForUpdatesAction = false
        bindDriverStateChanges()
        refreshState()
    }

    func checkForUpdates() {
        guard showsCheckForUpdatesAction else {
            return
        }

        driver.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ newValue: Bool) {
        settingsStore?.automaticallyChecksForUpdates = newValue
        driver.automaticallyChecksForUpdates = newValue
        automaticallyChecksForUpdates = newValue
    }

    func refreshState() {
        canCheckForUpdates = driver.canCheckForUpdates
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
        showsAutomaticUpdateChecksControl = driver.supportsAutomaticUpdateChecks
        showsCheckForUpdatesAction = driver.showsCheckForUpdatesAction
    }

    private func bindDriverStateChanges() {
        driver.stateDidChange = { [weak self] in
            self?.refreshState()
        }
    }
}

public struct AppWinkRuntimeScenes<Driver: AppUpdateDriving>: Scene {
    @StateObject private var appController = AppController()
    @StateObject private var updateCoordinator: AppUpdateCoordinator
    @StateObject private var localizationManager = LocalizationManager.shared

    public init(driver: Driver) {
        _updateCoordinator = StateObject(
            wrappedValue: AppUpdateCoordinator(driver: driver, settingsStore: nil)
        )
    }

    public var body: some Scene {
        Window(AppBrand.displayName, id: AppScene.mainWindowID) {
            ContentView()
                .id(localizationManager.currentLanguage)
                .environmentObject(appController.model)
                .environmentObject(updateCoordinator)
                .environmentObject(localizationManager)
                .appLanguage(localizationManager.currentLanguage)
                .preferredColorScheme(appController.model.appearanceMode.preferredColorScheme)
        }
        .defaultSize(
            width: SettingsDesignTokens.Window.minWidth,
            height: SettingsDesignTokens.Window.minHeight
        )
        .windowStyle(.hiddenTitleBar)

        Window(localizationManager.string(for: .settings), id: AppScene.settingsWindowID) {
            SettingsWindowView()
                .id(localizationManager.currentLanguage)
                .environmentObject(appController.model)
                .environmentObject(updateCoordinator)
                .environmentObject(localizationManager)
                .appLanguage(localizationManager.currentLanguage)
                .preferredColorScheme(appController.model.appearanceMode.preferredColorScheme)
        }
        .defaultSize(
            width: SettingsDesignTokens.SettingsWindow.minWidth,
            height: SettingsDesignTokens.SettingsWindow.minHeight
        )
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContentView()
                .id(localizationManager.currentLanguage)
                .environmentObject(appController.model)
                .environmentObject(updateCoordinator)
                .environmentObject(localizationManager)
                .appLanguage(localizationManager.currentLanguage)
                .preferredColorScheme(appController.model.appearanceMode.preferredColorScheme)
        } label: {
            Image(nsImage: StatusBarIconProvider.image)
                .accessibilityLabel(Text(AppBrand.displayName))
        }
    }
}

private extension AppAppearanceMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppScene {
    static let mainWindowID = "main-window"
    static let settingsWindowID = "settings-window"
}
