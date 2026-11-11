import AppKit
import XCTest

@testable import AppWinkRuntime

@MainActor
final class HiddenBarControllerTests: XCTestCase {
    func testInstallationStartsCompactBeforeQueuedCollapse() async throws {
        let controller = HiddenBarController()
        defer { controller.teardown() }

        controller.setEnabled(true)
        let arrow = try XCTUnwrap(statusItem("arrowItem", in: controller))
        let pusher = try XCTUnwrap(statusItem("pusherItem", in: controller))

        XCTAssertEqual(pusher.length, 12, "Initial layout must not push the arrow out of the menu bar")
        XCTAssertTrue(arrow.isVisible)

        await finishQueuedInstallation()

        XCTAssertEqual(
            pusher.length,
            HiddenBarPresentationMetrics.collapsedPusherLength(for: NSScreen.screens.map { $0.frame.width })
        )
        XCTAssertTrue(arrow.isVisible)
    }

    func testMacOS27InstallationUsesFreshStablePlacementIdentities() async throws {
        guard HiddenBarPresentationMetrics.collapsePolicy() == .macOS27Capped else {
            throw XCTSkip("The placement migration applies to macOS 27 and later")
        }
        let controller = HiddenBarController()
        defer { controller.teardown() }

        controller.setEnabled(true)
        let arrow = try XCTUnwrap(statusItem("arrowItem", in: controller))
        let pusher = try XCTUnwrap(statusItem("pusherItem", in: controller))

        XCTAssertNotEqual(arrow.autosaveName, "com.kairanpeng.appwink.hidden-bar.arrow")
        XCTAssertNotEqual(pusher.autosaveName, "com.kairanpeng.appwink.hidden-bar.pusher")
        XCTAssertNotEqual(arrow.autosaveName, pusher.autosaveName)
        let names = [arrow.autosaveName, pusher.autosaveName]

        controller.setEnabled(false)
        controller.setEnabled(true)

        XCTAssertEqual(statusItem("arrowItem", in: controller)?.autosaveName, names[0])
        XCTAssertEqual(statusItem("pusherItem", in: controller)?.autosaveName, names[1])
        await finishQueuedInstallation()
    }

    func testDisablingBeforeQueuedCollapseKeepsItemsRemoved() async {
        let controller = HiddenBarController()
        controller.setEnabled(true)
        controller.setEnabled(false)

        await finishQueuedInstallation()

        XCTAssertNil(statusItem("arrowItem", in: controller))
        XCTAssertNil(statusItem("pusherItem", in: controller))
    }

    func testRepeatedEnablePreservesPendingCompactInstallation() async throws {
        let controller = HiddenBarController()
        defer { controller.teardown() }
        controller.setEnabled(true)
        let pusher = try XCTUnwrap(statusItem("pusherItem", in: controller))

        controller.setEnabled(true)

        XCTAssertTrue(statusItem("pusherItem", in: controller) === pusher)
        XCTAssertEqual(pusher.length, 12)
        await finishQueuedInstallation()
        XCTAssertGreaterThan(pusher.length, 12)
    }

    func testQueuedInstallationDoesNotOverrideUserExpansion() async throws {
        let controller = HiddenBarController()
        defer { controller.teardown() }
        controller.setEnabled(true)
        let arrow = try XCTUnwrap(statusItem("arrowItem", in: controller))
        let button = try XCTUnwrap(arrow.button)
        let pusher = try XCTUnwrap(statusItem("pusherItem", in: controller))

        button.performClick(nil)
        button.performClick(nil)
        await finishQueuedInstallation()

        XCTAssertEqual(pusher.length, 12)
    }

    private func statusItem(_ name: String, in controller: HiddenBarController) -> NSStatusItem? {
        Mirror(reflecting: controller).children.first { $0.label == name }?.value as? NSStatusItem
    }

    private func finishQueuedInstallation() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
