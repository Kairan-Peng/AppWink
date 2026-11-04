import Foundation

protocol UpdateSettingsStoring: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
}

final class UserDefaultsUpdateSettingsStore: UpdateSettingsStoring {
    private enum Keys {
        static let automaticallyChecksForUpdates = "appUpdate.automaticallyChecksForUpdates"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            defaults.bool(forKey: Keys.automaticallyChecksForUpdates)
        }
        set {
            defaults.set(newValue, forKey: Keys.automaticallyChecksForUpdates)
        }
    }
}
