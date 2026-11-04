import Foundation
import XCTest

final class AccessibilityPermissionCheckerTests: XCTestCase {
    func testAccessibilityRecoveryUsesCurrentPrivacySecuritySettingsExtension() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AppWink/AccessibilityPermissionChecker.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ))
    }
}
