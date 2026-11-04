import Foundation
import Sparkle
import AppWinkRuntime

@MainActor
final class SparkleUpdateDriver: AppUpdateDriving {
    private let controller: SPUStandardUpdaterController
    private var canCheckForUpdatesObservation: NSKeyValueObservation?
    private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?

    var stateDidChange: (() -> Void)?

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var supportsAutomaticUpdateChecks: Bool {
        AppUpdateFeed.hasConfiguredFeedURL
    }

    var showsCheckForUpdatesAction: Bool {
        AppUpdateFeed.hasConfiguredFeedURL
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: AppUpdateFeed.hasConfiguredFeedURL,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        observeUpdaterState()
    }

    func checkForUpdates() {
        guard controller.updater.canCheckForUpdates else {
            return
        }

        controller.checkForUpdates(nil)
    }

    private func observeUpdaterState() {
        let updater = controller.updater
        canCheckForUpdatesObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.stateDidChange?()
            }
        }
        automaticallyChecksForUpdatesObservation = updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.stateDidChange?()
            }
        }
    }
}
