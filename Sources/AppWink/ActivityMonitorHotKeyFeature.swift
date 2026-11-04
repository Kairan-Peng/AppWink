import AppKit
import AppWinkCore

enum ActivityMonitorHotKeyFeature {
    static let shortcut = AppShortcut(keyCode: 47, modifiers: [.control, .command])
    static let bundleIdentifier = "com.apple.ActivityMonitor"
    static let fallbackPath = "/System/Applications/Utilities/Activity Monitor.app"

    static func makeManagedApplication(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) -> ManagedApplication? {
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return try? ManagedApplication(url: url)
        }

        let fallbackURL = URL(fileURLWithPath: fallbackPath)
        guard fileManager.fileExists(atPath: fallbackURL.path) else {
            return nil
        }

        return try? ManagedApplication(url: fallbackURL)
    }
}
