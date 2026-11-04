import CoreGraphics
import XCTest
@testable import AppWinkRuntime

@MainActor
final class PressedKeysMonitorControllerTests: XCTestCase {
    func testPublishesDedupedDisplayTransitionsForModifierAndKeyLifecycle() {
        var publishedValues: [String?] = []
        let controller = PressedKeysMonitorController { publishedValues.append($0) }

        controller.handleModifierFlagsChanged([.command])
        controller.handleModifierFlagsChanged([.command])
        controller.handleKeyDown(keyCode: 40, modifiers: [.command], isARepeat: false)
        controller.handleKeyDown(keyCode: 40, modifiers: [.command], isARepeat: true)
        controller.handleKeyUp(keyCode: 40, modifiers: [.command])
        controller.handleModifierFlagsChanged([])

        XCTAssertEqual(publishedValues, ["⌘", "⌘K", "⌘", nil])
    }

    func testStopResetsVisibleStateAndPublishesNilOnce() {
        var publishedValues: [String?] = []
        let controller = PressedKeysMonitorController { publishedValues.append($0) }

        controller.handleModifierFlagsChanged([.option])
        controller.handleKeyDown(keyCode: 40, modifiers: [.option], isARepeat: false)

        controller.stop()
        controller.stop()

        XCTAssertEqual(publishedValues, ["⌥", "⌥K", nil])
    }

    func testHandlersAreIgnoredAfterStopUntilRestart() {
        var publishedValues: [String?] = []
        let controller = PressedKeysMonitorController { publishedValues.append($0) }

        controller.handleModifierFlagsChanged([.command])
        controller.stop()
        controller.handleModifierFlagsChanged([.option])
        controller.handleKeyDown(keyCode: 40, modifiers: [.option], isARepeat: false)
        controller.start()
        controller.handleModifierFlagsChanged([.option])

        XCTAssertEqual(publishedValues, ["⌘", nil, "⌥"])
    }

    func testKeyUpWhileModifierRemainsHeldReturnsToModifierOnly() {
        var publishedValues: [String?] = []
        let controller = PressedKeysMonitorController { publishedValues.append($0) }

        controller.handleModifierFlagsChanged([.option])
        controller.handleKeyDown(keyCode: 12, modifiers: [.option], isARepeat: false)
        controller.handleKeyUp(keyCode: 12, modifiers: [.option])

        XCTAssertEqual(publishedValues, ["⌥", "⌥Q", "⌥"])
    }

    func testModifierRefreshAfterMainKeyReleaseDoesNotRecreateStaleCombination() {
        var publishedValues: [String?] = []
        let controller = PressedKeysMonitorController { publishedValues.append($0) }

        controller.handleModifierFlagsChanged([.option])
        controller.handleKeyDown(keyCode: 12, modifiers: [.option], isARepeat: false)
        controller.handleKeyUp(keyCode: 12, modifiers: [.option])
        controller.handleModifierFlagsChanged([.option])
        controller.handleModifierFlagsChanged([])

        XCTAssertEqual(publishedValues, ["⌥", "⌥Q", "⌥", nil])
    }

    func testCGEventPathPublishesHotkeyMainKeyAlongsideModifier() {
        var publishedValues: [String?] = []
        let controller = PressedKeysMonitorController { publishedValues.append($0) }

        controller.handleCGEvent(type: .flagsChanged, keyCode: 58, flags: [.maskAlternate])
        controller.handleCGEvent(type: .keyDown, keyCode: 12, flags: [.maskAlternate])
        controller.handleCGEvent(type: .keyUp, keyCode: 12, flags: [.maskAlternate])
        controller.handleCGEvent(type: .flagsChanged, keyCode: 58, flags: [])

        XCTAssertEqual(publishedValues, ["⌥", "⌥Q", "⌥", nil])
    }

    func testCGEventPathClearsTabAfterAltTabKeyUp() {
        var publishedValues: [String?] = []
        let controller = PressedKeysMonitorController { publishedValues.append($0) }

        controller.handleCGEvent(type: .flagsChanged, keyCode: 58, flags: [.maskAlternate])
        controller.handleCGEvent(type: .keyDown, keyCode: 48, flags: [.maskAlternate])
        controller.handleCGEvent(type: .keyUp, keyCode: 48, flags: [.maskAlternate])
        controller.handleCGEvent(type: .flagsChanged, keyCode: 58, flags: [])

        XCTAssertEqual(publishedValues, ["⌥", "⌥⇥", "⌥", nil])
    }

    func testCGEventPathRecordsDiagnosticsWhenSampling() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        recorder.startSampling(round: .optionalFeatures)
        let controller = PressedKeysMonitorController(
            performanceDiagnosticsRecorder: recorder,
            onDisplayTextChange: { _ in }
        )

        controller.handleCGEvent(type: .keyDown, keyCode: 12, flags: [.maskAlternate])

        XCTAssertEqual(recorder.snapshot().counters["eventListener.pressedKeysCallback"], 1)
    }
}
