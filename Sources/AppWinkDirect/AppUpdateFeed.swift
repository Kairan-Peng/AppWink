import Foundation
import AppWinkRuntime

enum AppUpdateFeed {
    static let infoPlistFeedURLKey = "SUFeedURL"
    static let appcastFileName = "appcast.xml"

    static var configuredFeedURL: URL? {
        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: infoPlistFeedURLKey) as? String,
              let feedURL = URL(string: feedURLString),
              let scheme = feedURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              feedURL.host?.isEmpty == false else {
            return nil
        }

        return feedURL
    }

    static var hasConfiguredFeedURL: Bool {
        configuredFeedURL != nil
    }

    static let archiveBaseNamePrefix = "AppWink"
}
