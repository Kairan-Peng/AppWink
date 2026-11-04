import XCTest
import ServiceManagement
@testable import AppWinkRuntime

final class LaunchAtLoginControllerTests: XCTestCase {
    func testStateMapsNotRegisteredToDisabled() {
        XCTAssertEqual(LaunchAtLoginController.state(for: .notRegistered), .disabled)
    }

    func testStateMapsEnabledToEnabled() {
        XCTAssertEqual(LaunchAtLoginController.state(for: .enabled), .enabled)
    }

    func testStateMapsRequiresApprovalToRequiresApproval() {
        XCTAssertEqual(LaunchAtLoginController.state(for: .requiresApproval), .requiresApproval)
    }

    func testStateTreatsNotFoundAsDisabledProbeState() {
        XCTAssertEqual(LaunchAtLoginController.state(for: .notFound), .disabled)
    }
}
