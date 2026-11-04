import XCTest
@testable import AppWinkRuntime

final class NonFinderCurrentSpaceVisibilityPolicyTests: XCTestCase {
    func testFallsBackToWindowServerCurrentSpaceSignalWhenAccessibilityVisibilityIsUnavailable() {
        let result = NonFinderCurrentSpaceVisibilityPolicy().hasVisibleWindowOnCurrentSpace(
            accessibilityDerivedVisibility: nil,
            currentSpaceWindowServerWindowCount: 1
        )

        XCTAssertTrue(result)
    }

    func testTreatsAppAsWindowlessWhenAccessibilityVisibilityIsUnavailableAndCurrentSpaceHasNoWindowServerMatch() {
        let result = NonFinderCurrentSpaceVisibilityPolicy().hasVisibleWindowOnCurrentSpace(
            accessibilityDerivedVisibility: nil,
            currentSpaceWindowServerWindowCount: 0
        )

        XCTAssertFalse(result)
    }

    func testPrefersAccessibilityDerivedVisibilityWhenAvailable() {
        let result = NonFinderCurrentSpaceVisibilityPolicy().hasVisibleWindowOnCurrentSpace(
            accessibilityDerivedVisibility: true,
            currentSpaceWindowServerWindowCount: 0
        )

        XCTAssertTrue(result)
    }
}
