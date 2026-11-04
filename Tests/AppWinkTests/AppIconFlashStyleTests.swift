import XCTest
@testable import AppWinkRuntime

final class AppIconFlashStyleTests: XCTestCase {
    func testHotKeyIconFlashUsesFullPeakOpacity() {
        XCTAssertEqual(SettingsDesignTokens.AppIconFlash.peakOpacity, 1.0)
    }

    func testHotKeyIconFlashUsesNoShadow() {
        XCTAssertEqual(SettingsDesignTokens.AppIconFlash.shadowOpacity, 0.0)
        XCTAssertEqual(SettingsDesignTokens.AppIconFlash.shadowRadius, 0)
        XCTAssertEqual(SettingsDesignTokens.AppIconFlash.shadowY, 0)
    }
}
