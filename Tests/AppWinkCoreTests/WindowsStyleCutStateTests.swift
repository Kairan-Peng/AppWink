import Foundation

import XCTest
@testable import AppWinkCore

final class WindowsStyleCutStateTests: XCTestCase {
    func testCutInFinderEntersPendingCutStateAndRequestsCopyShortcut() {
        var state = WindowsStyleCutState()

        let outcome = state.handle(command: .cut, isFinderFrontmost: true)

        XCTAssertEqual(outcome, .interceptAsCopy)
        XCTAssertTrue(state.hasPendingCut)
    }

    func testPasteInFinderAfterCutRequestsMovePasteAndClearsPendingState() {
        var state = WindowsStyleCutState(hasPendingCut: true)

        let outcome = state.handle(command: .paste, isFinderFrontmost: true)

        XCTAssertEqual(outcome, .interceptAsMovePaste)
        XCTAssertFalse(state.hasPendingCut)
    }

    func testCopyAlwaysClearsPendingCutState() {
        var state = WindowsStyleCutState(hasPendingCut: true)

        let outcome = state.handle(command: .copy, isFinderFrontmost: false)

        XCTAssertEqual(outcome, .passThrough)
        XCTAssertFalse(state.hasPendingCut)
    }

    func testCutOutsideFinderPassesThroughAndClearsPendingState() {
        var state = WindowsStyleCutState(hasPendingCut: true)

        let outcome = state.handle(command: .cut, isFinderFrontmost: false)

        XCTAssertEqual(outcome, .passThrough)
        XCTAssertFalse(state.hasPendingCut)
    }

    func testPasteWithoutPendingCutPassesThrough() {
        var state = WindowsStyleCutState()

        let outcome = state.handle(command: .paste, isFinderFrontmost: true)

        XCTAssertEqual(outcome, .passThrough)
        XCTAssertFalse(state.hasPendingCut)
    }
}
