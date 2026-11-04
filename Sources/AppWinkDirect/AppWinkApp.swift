import SwiftUI
import AppWinkRuntime

@main
struct AppWinkApp: App {
    @NSApplicationDelegateAdaptor(AppWinkAppDelegate.self) private var appDelegate

    var body: some Scene {
        AppWinkRuntimeScenes(driver: SparkleUpdateDriver())
    }
}
