import AppKit
import AppWinkCore
import XCTest
@testable import AppWinkRuntime

@MainActor
final class ShortcutRecorderFieldTests: XCTestCase {
    func testDefaultModeStillRecordsOptionLetter() throws {
        let recorder = RecorderTextField()

        recorder.keyDown(with: try makeKeyEvent(keyCode: 0, modifiers: []))

        XCTAssertEqual(recorder.currentShortcut, AppShortcut(keyCode: 0, modifiers: [.option]))
    }

    func testAdvancedModeRecordsPressedModifierCombinations() throws {
        let recorder = RecorderTextField()
        recorder.allowsAdvancedHotkeys = true

        recorder.keyDown(with: try makeKeyEvent(keyCode: 0, modifiers: [.command, .option]))
        XCTAssertEqual(recorder.currentShortcut, AppShortcut(keyCode: 0, modifiers: [.command, .option]))

        recorder.keyDown(with: try makeKeyEvent(keyCode: 29, modifiers: [.shift, .control]))
        XCTAssertEqual(recorder.currentShortcut, AppShortcut(keyCode: 29, modifiers: [.shift, .control]))
    }

    func testAdvancedModeKeepsOptionDefaultForBareKey() throws {
        let recorder = RecorderTextField()
        recorder.allowsAdvancedHotkeys = true

        recorder.keyDown(with: try makeKeyEvent(keyCode: 0, modifiers: []))

        XCTAssertEqual(recorder.currentShortcut, AppShortcut(keyCode: 0, modifiers: [.option]))
    }

    func testAdvancedModeRecordsRequestedPunctuationKeys() throws {
        let recorder = RecorderTextField()
        recorder.allowsAdvancedHotkeys = true
        let punctuationKeyCodes: [UInt16] = [50, 27, 24, 33, 30, 41, 39, 43, 47, 44, 42]

        for keyCode in punctuationKeyCodes {
            recorder.keyDown(with: try makeKeyEvent(keyCode: keyCode, modifiers: [.control]))
            XCTAssertEqual(
                recorder.currentShortcut,
                AppShortcut(keyCode: keyCode, modifiers: [.control])
            )
        }
    }

    func testDefaultModeStillRejectsPunctuationKeys() throws {
        let recorder = RecorderTextField()

        recorder.keyDown(with: try makeKeyEvent(keyCode: 50, modifiers: []))

        XCTAssertNil(recorder.currentShortcut)
    }

    func testRecorderClearsHoverAppearanceWhenRemovedFromWindow() {
        let recorder = RecorderTextField(frame: NSRect(x: 0, y: 0, width: 88, height: 38))
        recorder.layoutSubtreeIfNeeded()

        recorder.mouseEntered(with: makeMouseTrackingEvent())
        XCTAssertEqual(recorder.currentHoverStateForTesting, true)

        recorder.viewDidMoveToWindow()

        XCTAssertEqual(recorder.currentHoverStateForTesting, false)
    }

    func testRecorderReportsRecordingLifecycle() {
        let recorder = RecorderTextField(frame: NSRect(x: 0, y: 0, width: 88, height: 38))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var states: [Bool] = []
        recorder.recordingStateDidChange = { states.append($0) }
        window.contentView = recorder

        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertEqual(states, [true, false])
    }

    func testRecorderEndsRecordingWhenWindowResignsKey() async {
        let recorder = RecorderTextField(frame: NSRect(x: 0, y: 0, width: 88, height: 38))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var states: [Bool] = []
        recorder.recordingStateDidChange = { states.append($0) }
        window.contentView = recorder
        XCTAssertTrue(window.makeFirstResponder(recorder))

        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        await Task.yield()

        XCTAssertEqual(states, [true, false])
    }

    private func makeMouseTrackingEvent() -> NSEvent {
        NSEvent.enterExitEvent(
            with: .mouseEntered,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        )!
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}
