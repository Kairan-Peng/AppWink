import SwiftUI
import XCTest
import AppWinkCore
@testable import AppWinkRuntime

final class QuickSwitchOverlayStyleTests: XCTestCase {
    func testLegacyPanelChromeMatchesPreTokenOverlay() {
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.panelCornerRadius, 34)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.panelStrokeOpacity, 0.40)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.panelShadowOpacity, 0.10)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.panelShadowRadius, 30)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.panelShadowY, 18)
    }

    func testLegacyKeycapChromeMatchesPreTokenOverlay() {
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.keyCornerRadius, 18)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundKeyShadowOpacity, 0.10)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundKeyShadowRadius, 18)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundKeyShadowY, 10)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.referenceKeyStrokeOpacity, 0.07)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.shortcutKeyStrokeOpacity, 0.28)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundKeyStrokeOpacity, 0.46)
    }

    func testLegacyBoundKeyGlyphUsesPreTokenGlowValues() {
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundLabelOpacity, 0.95)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundLabelPrimaryShadowOpacity, 1.00)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundLabelSecondaryShadowOpacity, 0.32)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundLabelTertiaryShadowOpacity, 0.96)
    }

    func testBoundKeyGlyphShadowBaseFollowsSystemAppearance() {
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundLabelShadowBase(for: .light), .white)
        XCTAssertEqual(QuickSwitchOverlayLegacyStyle.boundLabelShadowBase(for: .dark), .black)
    }

    func testTargetFallbackSymbolsMatchApplicationFolderAndFileKinds() {
        XCTAssertEqual(
            HotkeyTargetKind.application.fallbackSymbolName,
            "app.fill"
        )
        XCTAssertEqual(
            HotkeyTargetKind.folder.fallbackSymbolName,
            "folder.fill"
        )
        XCTAssertEqual(
            HotkeyTargetKind.file.fallbackSymbolName,
            "doc.fill"
        )
    }
}
