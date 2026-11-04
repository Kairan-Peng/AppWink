import Foundation

protocol HotkeyGuideStateStoring: AnyObject {
    var isDismissed: Bool { get set }
}

final class UserDefaultsHotkeyGuideStateStore: HotkeyGuideStateStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "appwink.hotkeyGuideDismissed") {
        self.defaults = defaults
        self.key = key
    }

    var isDismissed: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
