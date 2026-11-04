import AppKit
import XCTest
@testable import AppWinkRuntime

final class AppWindowForegroundControllerTests: XCTestCase {
    func testNormalizedCollectionBehaviorKeepsPrimaryWindowsManagedAndCycled() {
        let behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .ignoresCycle,
            .stationary
        ]

        let normalized = AppWindowForegroundController.normalizedCollectionBehavior(behavior)

        XCTAssertTrue(normalized.contains(.managed))
        XCTAssertTrue(normalized.contains(.participatesInCycle))
        XCTAssertTrue(normalized.contains(.canJoinAllSpaces))
        XCTAssertFalse(normalized.contains(.transient))
        XCTAssertFalse(normalized.contains(.ignoresCycle))
        XCTAssertFalse(normalized.contains(.stationary))
    }
}
