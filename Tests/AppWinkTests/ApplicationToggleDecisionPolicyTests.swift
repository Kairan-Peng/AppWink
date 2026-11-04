import XCTest
@testable import AppWinkRuntime

final class ApplicationToggleDecisionPolicyTests: XCTestCase {
    func testBackgroundTargetChoosesSystemEquivalentActivate() {
        let snapshot = ApplicationToggleDecisionSnapshot.backgroundTarget

        XCTAssertEqual(
            ApplicationToggleDecisionPolicy().decision(for: snapshot),
            .systemEquivalentActivate)
    }

    func testFrontmostImmersiveTargetChoosesNoOpFrontmostImmersiveWindow() {
        let snapshot = ApplicationToggleDecisionSnapshot.frontmostImmersive

        XCTAssertEqual(
            ApplicationToggleDecisionPolicy().decision(for: snapshot),
            .noOpFrontmostImmersiveWindow)
    }

    func testFrontmostNormalTargetWithVisibleRegularWindowChoosesHide() {
        let snapshot = ApplicationToggleDecisionSnapshot.frontmostNormalWithVisibleRegularWindow

        XCTAssertEqual(
            ApplicationToggleDecisionPolicy().decision(for: snapshot),
            .hide)
    }

    func testFrontmostNormalTargetWithoutVisibleRegularWindowChoosesSystemEquivalentActivate() {
        let snapshot = ApplicationToggleDecisionSnapshot.frontmostNormalWithoutVisibleRegularWindow

        XCTAssertEqual(
            ApplicationToggleDecisionPolicy().decision(for: snapshot),
            .systemEquivalentActivate)
    }
}
