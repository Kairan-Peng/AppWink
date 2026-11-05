import AppKit
import XCTest
@testable import AppWinkRuntime

@MainActor
final class AppWindowChromeConfiguratorTests: XCTestCase {
    func testWindowControlsRemainAboveContentAfterInitialAttachment() async throws {
        let (window, _) = makeWindow()
        defer { window.close() }

        await drainLayoutQueue()

        try assertWindowControlsAreUnobscured(window)
    }

    func testWindowControlsRemainAboveContentAfterReconfigurationAndResize() async throws {
        let (window, configurator) = makeWindow()
        defer { window.close() }
        let contentView = try XCTUnwrap(window.contentView)
        let frameView = try XCTUnwrap(contentView.superview)
        // Reproduce a hosting view being installed above existing window chrome.
        frameView.addSubview(contentView, positioned: .above, relativeTo: nil)

        configurator.configureWindow()
        window.setContentSize(NSSize(width: 720, height: 650))
        await drainLayoutQueue()

        try assertWindowControlsAreUnobscured(window)
    }

    private func makeWindow() -> (NSWindow, AppWindowChromeConfigurator.ConfiguringView) {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 615, height: 625),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Window controls regression"
        let configurator = AppWindowChromeConfigurator.ConfiguringView(
            toolbarIdentifier: AppWindowChromeIdentifier.main,
            minWidth: 615,
            minHeight: 625,
            preferredFrameWidth: nil,
            fixedFrameHeight: nil,
            titlebarHeight: 52,
            titleOverride: nil,
            titlebarBackAction: nil,
            titlebarBackAccessibilityLabel: "Back",
            titlebarHelpAction: nil,
            titlebarHelpAccessibilityLabel: "Help"
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 615, height: 625))
        contentView.addSubview(configurator)
        window.contentView = contentView
        return (window, configurator)
    }

    private func assertWindowControlsAreUnobscured(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let frameView = try XCTUnwrap(window.contentView?.superview, file: file, line: line)
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try XCTUnwrap(window.standardWindowButton(buttonType), file: file, line: line)
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor, file: file, line: line)
            XCTAssertFalse(button.visibleRect.isEmpty, file: file, line: line)
            let center = button.convert(
                NSPoint(x: button.bounds.midX, y: button.bounds.midY),
                to: frameView
            )
            let hitView = frameView.hitTest(center)
            XCTAssertTrue(
                hitView === button || hitView?.isDescendant(of: button) == true,
                "Content must not cover the native \(buttonType) button",
                file: file,
                line: line
            )
        }
        let titleView = try XCTUnwrap(
            frameView.subviews.compactMap { $0 as? NSTextField }.first {
                $0.stringValue == window.title
            },
            file: file,
            line: line
        )
        let contentIndex = try XCTUnwrap(frameView.subviews.firstIndex { $0 === window.contentView })
        let titleIndex = try XCTUnwrap(frameView.subviews.firstIndex { $0 === titleView })
        XCTAssertLessThan(contentIndex, titleIndex, "Content must not cover the title", file: file, line: line)
    }

    private func drainLayoutQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
