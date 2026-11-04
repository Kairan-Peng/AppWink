import XCTest
@testable import AppWinkRuntime

final class PressedKeysOverlayStateTests: XCTestCase {
    func testPureModifierDisplayShowsSymbolOnly() {
        var state = PressedKeysOverlayState()

        state.applyModifierFlags([.command, .shift])

        XCTAssertEqual(state.displayText, "⇧⌘")
    }

    func testModifierPlusMainKeyDisplayShowsCombinedText() {
        var state = PressedKeysOverlayState()

        state.applyModifierFlags([.command])
        state.handleKeyDown(keyCode: 40, modifiers: [.command], isARepeat: false)

        XCTAssertEqual(state.displayText, "⌘K")
    }

    func testModifierVirtualKeyCodesAreIgnoredByReducer() {
        var state = PressedKeysOverlayState()

        state.applyModifierFlags([.command])
        state.handleKeyDown(keyCode: 55, modifiers: [.command], isARepeat: false)
        state.handleKeyUp(keyCode: 55, modifiers: [.command])

        XCTAssertEqual(state.displayText, "⌘")
        XCTAssertEqual(state.pressedKeyCodes, [])
    }

    func testRepeatedKeyDownSuppressionDoesNotDuplicateHeldKey() {
        var state = PressedKeysOverlayState()

        state.handleKeyDown(keyCode: 40, modifiers: [], isARepeat: false)
        state.handleKeyDown(keyCode: 40, modifiers: [], isARepeat: true)

        XCTAssertEqual(state.displayText, "K")
        XCTAssertEqual(state.pressedKeyCodes, [40])
    }

    func testReleasingAllKeysClearsDisplay() {
        var state = PressedKeysOverlayState()

        state.applyModifierFlags([.option])
        state.handleKeyDown(keyCode: 40, modifiers: [.option], isARepeat: false)
        state.handleKeyUp(keyCode: 40, modifiers: [.option])
        state.applyModifierFlags([])

        XCTAssertNil(state.displayText)
    }

    func testReleasingMainKeyWhileModifierRemainsShowsModifierOnlyText() {
        var state = PressedKeysOverlayState()

        state.applyModifierFlags([.option])
        state.handleKeyDown(keyCode: 40, modifiers: [.option], isARepeat: false)
        state.handleKeyUp(keyCode: 40, modifiers: [.option])

        XCTAssertEqual(state.displayText, "⌥")
        XCTAssertEqual(state.pressedKeyCodes, [])
    }

    func testMultipleHeldNonModifierKeysRemainStableInPressOrder() {
        var state = PressedKeysOverlayState()

        state.handleKeyDown(keyCode: 40, modifiers: [], isARepeat: false)
        state.handleKeyDown(keyCode: 37, modifiers: [], isARepeat: false)
        state.handleKeyDown(keyCode: 40, modifiers: [], isARepeat: true)

        XCTAssertEqual(state.displayText, "K L")
        XCTAssertEqual(state.pressedKeyCodes, [40, 37])
    }
}
