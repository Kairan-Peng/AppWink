import Foundation
import XCTest
@testable import AppWinkCore

final class AppShortcutTests: XCTestCase {
    func testDisplayStringFormatsModifierOrderAndKeyName() {
        let shortcut = AppShortcut(keyCode: 8, modifiers: [.command, .shift])

        XCTAssertEqual(shortcut.displayString, "⇧⌘C")
    }

    func testDisplayStringFallsBackForUnknownKeyCode() {
        let shortcut = AppShortcut(keyCode: 999, modifiers: [.control])

        XCTAssertEqual(shortcut.displayString, "⌃Key 999")
    }

    func testAdvancedPunctuationDisplay() {
        XCTAssertEqual(
            AppShortcut(keyCode: 50, modifiers: [.command]).displayString,
            "⌘`"
        )
        XCTAssertTrue(QuickSwitchShortcutPalette.isAdvancedSupportedKeyCode(50))
        XCTAssertTrue(QuickSwitchShortcutPalette.isAdvancedSupportedKeyCode(42))
        XCTAssertFalse(QuickSwitchShortcutPalette.isSupportedKeyCode(50))
    }

    func testAdvancedPunctuationShortcutRoundTripsThroughPersistenceShape() throws {
        let shortcut = AppShortcut(keyCode: 41, modifiers: [.control, .command])

        let data = try JSONEncoder().encode(shortcut)

        XCTAssertEqual(try JSONDecoder().decode(AppShortcut.self, from: data), shortcut)
    }

    func testQuickSwitchKeyboardLayoutOnlyMapsVisibleLeftHalfOptionShortcuts() {
        XCTAssertEqual(
            QuickSwitchKeyboardLayout.key(for: AppShortcut(keyCode: 18, modifiers: [.option]))?.label,
            "1")
        XCTAssertEqual(
            QuickSwitchKeyboardLayout.key(for: AppShortcut(keyCode: 17, modifiers: [.option]))?.label,
            "T")
        XCTAssertNil(QuickSwitchKeyboardLayout.key(for: AppShortcut(keyCode: 18, modifiers: [.command])))
        XCTAssertNil(QuickSwitchKeyboardLayout.key(for: AppShortcut(keyCode: 4, modifiers: [.option])))
        XCTAssertNil(QuickSwitchKeyboardLayout.key(for: AppShortcut(keyCode: 22, modifiers: [.option])))
        XCTAssertNil(QuickSwitchKeyboardLayout.key(for: AppShortcut(keyCode: 32, modifiers: [.option])))
    }

    func testQuickSwitchKeyboardLayoutAddsFunctionReferenceRowAboveDigits() {
        let labels = QuickSwitchKeyboardLayout.rows[0].map(\.label)

        XCTAssertEqual(labels, ["esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8"])
    }

    func testQuickSwitchKeyboardLayoutTopRowStartsWithBacktickThenOne() {
        let labels = QuickSwitchKeyboardLayout.rows[1].map(\.label)

        XCTAssertEqual(Array(labels.prefix(6)), ["`", "1", "2", "3", "4", "5"])
    }

    func testQuickSwitchKeyboardLayoutNumberRowAddsReferenceLabelsPastEight() {
        let labels = QuickSwitchKeyboardLayout.rows[1].map(\.label)

        XCTAssertEqual(Array(labels.suffix(7)), ["6", "7", "8", "9", "0", "-", "="])
    }

    func testQuickSwitchKeyboardLayoutUsesAnsiLikeReferenceKeyWidths() {
        XCTAssertEqual(QuickSwitchKeyboardLayout.rows[2].first?.widthUnits, 1.5)
        XCTAssertEqual(QuickSwitchKeyboardLayout.rows[3].first?.widthUnits, 1.75)
        XCTAssertEqual(QuickSwitchKeyboardLayout.rows[4].first?.widthUnits, 2.25)
    }

    func testQuickSwitchKeyboardLayoutAddsReferenceTailAfterG() {
        let labels = QuickSwitchKeyboardLayout.rows[3].map(\.label)

        XCTAssertEqual(labels, ["caps lock", "A", "S", "D", "F", "G", "H", "J", "K"])
    }

    func testQuickSwitchKeyboardLayoutUsesExtendedSpaceBarTail() {
        XCTAssertEqual(QuickSwitchKeyboardLayout.rows[5].last?.label, "space")
        XCTAssertEqual(QuickSwitchKeyboardLayout.rows[5].last?.widthUnits, 6)
    }

    func testQuickSwitchKeyboardLayoutUsesMacBookAirLikeBottomRowWidths() {
        let widths = QuickSwitchKeyboardLayout.rows[5].map(\.widthUnits)

        XCTAssertEqual(widths, [1, 1, 1, 1.263, 6])
    }

    func testQuickSwitchKeyboardLayoutUsesMacStyleModifierReferenceLabels() {
        let labels = QuickSwitchKeyboardLayout.rows[5].map(\.label)

        XCTAssertEqual(labels, ["fn", "⌃ control", "⌥ option", "⌘ command", "space"])
    }

    func testQuickSwitchKeyboardLayoutUsesMacStyleShiftReferenceLabel() {
        XCTAssertEqual(QuickSwitchKeyboardLayout.rows[4].first?.label, "⇧ shift")
    }
}
