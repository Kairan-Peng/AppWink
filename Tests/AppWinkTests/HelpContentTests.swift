import AppWinkCore
import XCTest
@testable import AppWinkRuntime

final class HelpContentTests: XCTestCase {
    private var originalLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        originalLanguage = LocalizationManager.shared.currentLanguage
    }

    override func tearDown() {
        LocalizationManager.shared.setLanguage(originalLanguage)
        super.tearDown()
    }

    func testHotkeyUsageKeysContainExpectedUsageItems() {
        XCTAssertEqual(AppHelpContent.hotkeyUsageKeys, [
            .helpHotkeyUsageNotConfigured,
            .helpHotkeyUsageChooseTarget,
            .helpHotkeyUsageRecordShortcut,
            .helpHotkeyUsageApplicationToggle,
            .helpHotkeyUsageFinderNewTab,
            .helpHotkeyUsageFileSystemDefault,
            .helpHotkeyUsageSelectedApplication,
            .helpHotkeyUsageQuickSwitch,
        ])
    }

    func testHotkeyUsageExplainsEveryTargetOpeningBehavior() {
        LocalizationManager.shared.setLanguage(.english)

        let copy = AppHelpContent.hotkeyUsageKeys.map {
            LocalizationManager.shared.string(for: $0)
        }.joined(separator: " ")

        XCTAssertTrue(copy.contains("activate"))
        XCTAssertTrue(copy.contains("hide"))
        XCTAssertTrue(copy.contains("double-clicked in Finder"))
        XCTAssertTrue(copy.contains("current system default"))
        XCTAssertTrue(copy.contains("selected application"))
    }

    func testFeatureNotesUseSettingsFeatureTitleKeys() {
        XCTAssertEqual(
            AppHelpContent.featureNotes,
            [
                HelpFeatureNote(titleKey: .windowsStyleCut, bodyKey: .toolboxWindowsStyleCutSummary),
                HelpFeatureNote(titleKey: .mouseWheelWindowsScroll, bodyKey: .toolboxMouseWheelWindowsScrollSummary),
                HelpFeatureNote(titleKey: .pressedKeysOverlay, bodyKey: .toolboxPressedKeysOverlaySummary),
                HelpFeatureNote(titleKey: .virtualKeyboard, bodyKey: .toolboxVirtualKeyboardSummary),
                HelpFeatureNote(titleKey: .hiddenBar, bodyKey: .toolboxHiddenBarSummary),
                HelpFeatureNote(titleKey: .networkMonitor, bodyKey: .toolboxNetworkMonitorSummary),
                HelpFeatureNote(titleKey: .hotKeyIconFlash, bodyKey: .toolboxHotKeyIconFlashSummary),
                HelpFeatureNote(titleKey: .advancedHotkeys, bodyKey: .toolboxAdvancedHotkeysSummary),
            ]
        )
    }
}
