import XCTest
@testable import AppWinkRuntime

final class FinderWindowServerWindowFilterTests: XCTestCase {
    func testTreatsLargeWindowBoundsAsBrowserWindow() {
        let result = FinderWindowServerWindowFilter().isBrowserWindow(
            bounds: CGRect(x: 427, y: 235, width: 913, height: 501))

        XCTAssertTrue(result)
    }

    func testRejectsThinMenuBarSizedWindowBounds() {
        let result = FinderWindowServerWindowFilter().isBrowserWindow(
            bounds: CGRect(x: 0, y: 0, width: 1680, height: 30))

        XCTAssertFalse(result)
    }

    func testRejectsSmallDesktopIconSizedWindowBounds() {
        let result = FinderWindowServerWindowFilter().isBrowserWindow(
            bounds: CGRect(x: 0, y: 550, width: 64, height: 64))

        XCTAssertFalse(result)
    }

    func testRejectsMissingBounds() {
        let result = FinderWindowServerWindowFilter().isBrowserWindow(bounds: nil)

        XCTAssertFalse(result)
    }
}
