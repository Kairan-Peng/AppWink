import XCTest
@testable import AppWinkRuntime

final class FinderCurrentSpaceVisibilityPolicyTests: XCTestCase {
    func testFallsBackToWindowServerCurrentSpaceSignalWhenAccessibilityVisibilityIsUnavailable() {
        let result = FinderCurrentSpaceVisibilityPolicy().hasVisibleWindowOnCurrentSpace(
            accessibilityDerivedVisibility: nil,
            currentSpaceWindowServerWindowCount: 1)

        XCTAssertTrue(result)
    }

    func testTreatsFinderAsWindowlessWhenAccessibilityVisibilityIsUnavailableAndCurrentSpaceHasNoWindowServerMatch() {
        let result = FinderCurrentSpaceVisibilityPolicy().hasVisibleWindowOnCurrentSpace(
            accessibilityDerivedVisibility: nil,
            currentSpaceWindowServerWindowCount: 0)

        XCTAssertFalse(result)
    }

    func testPrefersAccessibilityDerivedVisibilityWhenAvailable() {
        let result = FinderCurrentSpaceVisibilityPolicy().hasVisibleWindowOnCurrentSpace(
            accessibilityDerivedVisibility: true,
            currentSpaceWindowServerWindowCount: 0)

        XCTAssertTrue(result)
    }
}
