import Foundation

import XCTest
@testable import AppWinkCore

final class LocalizationManagerTests: XCTestCase {
    func testSystemLanguageUsesFirstMatchingSystemPreferredLocalization() {
        let bundle = LocalizationManager.localizedBundle(
            for: .system,
            preferredLanguages: ["zh-Hans-CN", "en"]
        )
        let localizedLanguage = NSLocalizedString("settings.language", bundle: bundle, comment: "")

        XCTAssertEqual(localizedLanguage, "语言")
        XCTAssertTrue(bundle.bundlePath.lowercased().hasSuffix("zh-hans.lproj"))
    }
}
