import AppWinkCore
import XCTest
@testable import AppWinkRuntime

final class LocalizationCopyTests: XCTestCase {
    private var originalLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        originalLanguage = LocalizationManager.shared.currentLanguage
    }

    override func tearDown() {
        LocalizationManager.shared.setLanguage(originalLanguage)
        super.tearDown()
    }

    func testEnglishSettingsFeatureToggleLabelsUseShortCopy() {
        LocalizationManager.shared.setLanguage(.english)

        XCTAssertEqual(LocalizationManager.shared.string(for: .windowsStyleCut), "⌘X Cut")
        XCTAssertEqual(LocalizationManager.shared.string(for: .mouseWheelWindowsScroll), "Wheel Reverse")
        XCTAssertEqual(LocalizationManager.shared.string(for: .pressedKeysOverlay), "Key Display")
        XCTAssertEqual(LocalizationManager.shared.string(for: .virtualKeyboard), "Virtual Keyboard")
        XCTAssertEqual(LocalizationManager.shared.string(for: .virtualKeyboardDelayValue, arguments: "0.75"), "0.75 s")
        XCTAssertEqual(LocalizationManager.shared.string(for: .hiddenBar), "Hide Menu Bar")
        XCTAssertEqual(LocalizationManager.shared.string(for: .networkMonitor), "Network Monitor")
        XCTAssertEqual(LocalizationManager.shared.string(for: .hotKeyIconFlash), "Hotkey Hint")
        XCTAssertEqual(LocalizationManager.shared.string(for: .activityMonitor), "Activity Monitor")
    }

    func testChineseSettingsFeatureToggleLabelsUseShortCopy() {
        LocalizationManager.shared.setLanguage(.chinese)

        XCTAssertEqual(LocalizationManager.shared.string(for: .windowsStyleCut), "⌘X 剪切")
        XCTAssertEqual(LocalizationManager.shared.string(for: .mouseWheelWindowsScroll), "滚轮反向")
        XCTAssertEqual(LocalizationManager.shared.string(for: .pressedKeysOverlay), "按键显示")
        XCTAssertEqual(LocalizationManager.shared.string(for: .virtualKeyboard), "虚拟键盘")
        XCTAssertEqual(LocalizationManager.shared.string(for: .virtualKeyboardDelayValue, arguments: "0.75"), "0.75 秒")
        XCTAssertEqual(LocalizationManager.shared.string(for: .hiddenBar), "隐藏菜单栏")
        XCTAssertEqual(LocalizationManager.shared.string(for: .networkMonitor), "网络监控")
        XCTAssertEqual(LocalizationManager.shared.string(for: .hotKeyIconFlash), "热键提示")
        XCTAssertEqual(LocalizationManager.shared.string(for: .activityMonitor), "活动监视器")
    }

    func testAppearanceModeCopyResolvesInEnglishAndChinese() {
        LocalizationManager.shared.setLanguage(.english)
        XCTAssertEqual(LocalizationManager.shared.string(for: .appearanceMode), "Appearance Mode")
        XCTAssertEqual(AppAppearanceMode.system.displayName(in: LocalizationManager.shared.bundle), "Follow System")
        XCTAssertEqual(AppAppearanceMode.light.displayName(in: LocalizationManager.shared.bundle), "Light")
        XCTAssertEqual(AppAppearanceMode.dark.displayName(in: LocalizationManager.shared.bundle), "Dark")

        LocalizationManager.shared.setLanguage(.chinese)
        XCTAssertEqual(LocalizationManager.shared.string(for: .appearanceMode), "外观模式")
        XCTAssertEqual(AppAppearanceMode.system.displayName(in: LocalizationManager.shared.bundle), "跟随系统")
        XCTAssertEqual(AppAppearanceMode.light.displayName(in: LocalizationManager.shared.bundle), "浅色")
        XCTAssertEqual(AppAppearanceMode.dark.displayName(in: LocalizationManager.shared.bundle), "深色")
    }

    func testSettingsFeatureStatusMessagesUseShortCopy() {
        LocalizationManager.shared.setLanguage(.english)
        XCTAssertEqual(LocalizationManager.shared.string(for: .virtualKeyboardEnabled), "Virtual Keyboard is enabled.")
        XCTAssertEqual(LocalizationManager.shared.string(for: .hiddenBarEnabled), "Hide Menu Bar is enabled.")
        XCTAssertEqual(LocalizationManager.shared.string(for: .networkMonitorEnabled), "Network Monitor is enabled.")
        XCTAssertEqual(LocalizationManager.shared.string(for: .networkMonitorDisabled), "Network Monitor is disabled.")
        XCTAssertEqual(LocalizationManager.shared.string(for: .hotKeyIconFlashEnabled), "Hotkey Hint is enabled.")

        LocalizationManager.shared.setLanguage(.chinese)
        XCTAssertEqual(LocalizationManager.shared.string(for: .virtualKeyboardEnabled), "已开启虚拟键盘。")
        XCTAssertEqual(LocalizationManager.shared.string(for: .hiddenBarEnabled), "已开启隐藏菜单栏。")
        XCTAssertEqual(LocalizationManager.shared.string(for: .networkMonitorEnabled), "已开启网络监控。")
        XCTAssertEqual(LocalizationManager.shared.string(for: .networkMonitorDisabled), "已关闭网络监控。")
        XCTAssertEqual(LocalizationManager.shared.string(for: .hotKeyIconFlashEnabled), "已开启热键提示。")
    }

    func testAdvancedHotkeysCopyIsConciseAndExact() {
        LocalizationManager.shared.setLanguage(.english)
        XCTAssertEqual(
            LocalizationManager.shared.string(for: .toolboxAdvancedHotkeysSummary),
            "Records the modifiers you press; bare keys continue to use Option."
        )
        XCTAssertEqual(
            LocalizationManager.shared.string(for: .settingsFeatureAdvancedHotkeysCombinations),
            "One or more of ⌘, ⌥, ⌃, ⇧ + A–Z, 0–9, or ` - = [ ] ; ' , . / \\"
        )

        LocalizationManager.shared.setLanguage(.chinese)
        XCTAssertEqual(
            LocalizationManager.shared.string(for: .toolboxAdvancedHotkeysSummary),
            "按实际输入记录修饰键；未输入修饰键时仍自动使用 Option。"
        )
        XCTAssertEqual(
            LocalizationManager.shared.string(for: .settingsFeatureAdvancedHotkeysCombinations),
            "一个或多个 ⌘、⌥、⌃、⇧ + A–Z、0–9 或 ` - = [ ] ; ' , . / \\"
        )
    }

    func testTopActionLabelsUseShortCopy() {
        LocalizationManager.shared.setLanguage(.english)
        XCTAssertEqual(LocalizationManager.shared.string(for: .accessibilityPermissionRequired), "Accessibility Permission")
        XCTAssertEqual(LocalizationManager.shared.string(for: .addAccessibilityPermission), "Permissions")
        XCTAssertEqual(LocalizationManager.shared.string(for: .addTarget), "Add")

        LocalizationManager.shared.setLanguage(.chinese)
        XCTAssertEqual(LocalizationManager.shared.string(for: .accessibilityPermissionRequired), "辅助功能权限")
        XCTAssertEqual(LocalizationManager.shared.string(for: .addAccessibilityPermission), "添加权限")
        XCTAssertEqual(LocalizationManager.shared.string(for: .addTarget), "添加")
    }

    func testTargetAndOpeningModeCopyUsesApprovedEnglishAndChineseText() {
        let expectedCopy: [(LocalizationKey, String, String)] = [
            (.chooseTarget, "Choose Target", "选择目标"),
            (
                .chooseTargetMessage,
                "Choose an application, folder, or file to bind a hotkey.",
                "选择要绑定热键的应用、文件夹或文件。"
            ),
            (.targetUnavailable, "Target Unavailable", "目标不可用"),
            (
                .openingApplicationUnavailable,
                "Opening Application Unavailable",
                "打开应用不可用"
            ),
            (.openWith, "Open With", "打开方式"),
            (.finderNewTab, "Finder", "Finder"),
            (
                .chooseOtherApplication,
                "Choose Other Application...",
                "选择其他应用…"
            ),
        ]

        for language in [AppLanguage.english, .chinese] {
            LocalizationManager.shared.setLanguage(language)

            for (key, english, chinese) in expectedCopy {
                XCTAssertEqual(
                    LocalizationManager.shared.string(for: key),
                    language == .english ? english : chinese
                )
            }
        }

        LocalizationManager.shared.setLanguage(.english)
        XCTAssertEqual(
            LocalizationManager.shared.string(
                for: .openTargetWithApplication,
                arguments: ["Finder", "Downloads"]
            ),
            "Use Finder to open Downloads"
        )
        LocalizationManager.shared.setLanguage(.chinese)
        XCTAssertEqual(
            LocalizationManager.shared.string(
                for: .openTargetWithApplication,
                arguments: ["Finder", "下载"]
            ),
            "使用“Finder”打开“下载”"
        )
    }

    func testSystemDefaultApplicationCopyFormatsTheCurrentApplicationDynamically() {
        LocalizationManager.shared.setLanguage(.english)
        XCTAssertEqual(
            LocalizationManager.shared.string(
                for: .systemDefaultApplication,
                arguments: "Preview"
            ),
            "System Default (Preview)"
        )

        LocalizationManager.shared.setLanguage(.chinese)
        XCTAssertEqual(
            LocalizationManager.shared.string(
                for: .systemDefaultApplication,
                arguments: "预览"
            ),
            "系统默认（预览）"
        )
    }

    func testHelpContentKeysResolveInEnglishAndChinese() {
        assertHelpContentKeysResolve(in: .english)
        assertHelpContentKeysResolve(in: .chinese)
    }

    func testSettingsFeatureDetailCopyResolvesInEnglishAndChinese() {
        let expectedCopy: [(LocalizationKey, String, String)] = [
            (.settingsSectionGeneral, "General", "通用"),
            (.settingsSectionFeatures, "Features", "功能"),
            (.settingsSectionAboutUpdates, "About & Updates", "关于与更新"),
            (.settingsFeatureStatusEnabled, "Enabled", "已启用"),
            (.settingsFeatureStatusDisabled, "Disabled", "未启用"),
            (.settingsFeatureStatusPermissionRequired, "Permission Required", "需要权限"),
            (.settingsFeatureEnable, "Enable This Feature", "启用此功能"),
            (.settingsFeatureSettingsSection, "Settings", "设置"),
            (.settingsFeatureHowItWorksSection, "How It Works", "工作方式"),
            (.settingsFeatureOpenHint, "Open Feature Settings", "打开功能设置"),
            (.settingsFeatureAppliesTo, "Applies To", "适用于"),
            (.settingsFeatureShortcut, "Shortcut", "快捷键"),
            (.settingsFeatureAfterCut, "Copy After Cut", "剪切后复制"),
            (.settingsFeatureDevice, "Device", "设备"),
            (.settingsFeatureScrolling, "Scrolling", "滚动方式"),
            (.settingsFeatureUnaffected, "Unaffected", "不受影响"),
            (.settingsFeatureShows, "Shows", "显示内容"),
            (.settingsFeaturePosition, "Position", "位置"),
            (.settingsFeatureTrigger, "Trigger", "触发方式"),
            (.settingsFeatureShowAfter, "Show After", "显示延迟"),
            (.settingsFeatureControl, "Control", "控制方式"),
            (.settingsFeatureArrangeItems, "Arrange Items", "排列图标"),
            (.settingsFeatureAutoCollapse, "Auto-Collapse", "自动收起"),
            (.settingsFeatureDisplay, "Display", "显示方式"),
            (.settingsFeatureSource, "Source", "来源"),
            (.settingsFeatureRefresh, "Refresh", "刷新"),
            (.settingsFeatureDuration, "Duration", "显示时长"),
            (.settingsFeatureBehavior, "Behavior", "行为"),
            (.settingsFeatureWhenFullscreen, "Fullscreen / Split View", "全屏 / 分屏"),
            (
                .settingsFeatureAfterCutValue,
                "Cancels the pending cut and uses normal copy behavior.",
                "取消待剪切状态并恢复普通复制。"
            ),
            (.settingsFeaturePhysicalMouseWheel, "Physical Mouse Wheel", "实体鼠标滚轮"),
            (.settingsFeatureWindowsDirectionSmooth, "Windows Direction + Smooth", "Windows 方向并平滑滚动"),
            (.settingsFeatureTrackpadMagicMouse, "Trackpad and Magic Mouse", "触控板和 Magic Mouse"),
            (
                .settingsFeatureModifiersCombinationsSingleKeys,
                "Modifiers, Combinations, and Single Keys",
                "修饰键、组合键与单键"
            ),
            (
                .settingsFeatureBottomCenterActiveDisplay,
                "Bottom Center of the Active Display",
                "当前显示器底部居中"
            ),
            (.settingsFeatureHoldOption, "Hold ⌥", "长按 ⌥"),
            (.settingsFeatureMenuBarArrow, "Menu Bar Arrow", "菜单栏箭头"),
            (
                .settingsFeatureCommandDragAcrossMarker,
                "Command-drag items across the boundary marker. Items on the left are hidden; items on the right stay visible.",
                "按住 Command 将图标拖过分界线；左侧图标会隐藏，右侧图标保持显示。"
            ),
            (.settingsFeatureThirtySeconds, "30 Seconds", "30 秒"),
            (
                .toolboxNetworkMonitorSummary,
                "Shows live upload and download speeds in the menu bar.",
                "在菜单栏实时显示本机的上传和下载速度。"
            ),
            (
                .settingsFeatureMenuBarUploadAboveDownload,
                "Menu Bar, upload above download",
                "菜单栏，上行在上、下行在下"
            ),
            (
                .settingsFeaturePrimaryNetworkInterface,
                "Current primary network interface",
                "当前主网络接口"
            ),
            (.settingsFeatureEveryTwoSeconds, "Every 2 seconds", "每 2 秒"),
            (.settingsFeatureAppWinkHotkeysOnly, "AppWink Hotkeys Only", "仅 AppWink 热键"),
            (
                .settingsFeatureTargetAppIconScreenCenter,
                "Target App Icon at Screen Center",
                "屏幕中央的目标应用图标"
            ),
            (.settingsFeatureAboutPoint45Seconds, "About 0.45 Seconds", "约 0.45 秒"),
            (
                .settingsFeatureActivityMonitorBehavior,
                "Show when inactive; hide when frontmost in a normal window.",
                "未在前台时显示；在普通窗口前台时隐藏。"
            ),
            (.settingsFeatureActivityMonitorFullscreenNoOp, "Repeated triggers do nothing.", "重复触发时不执行操作。"),
        ]

        for language in [AppLanguage.english, .chinese] {
            LocalizationManager.shared.setLanguage(language)

            for (key, english, chinese) in expectedCopy {
                XCTAssertEqual(
                    LocalizationManager.shared.string(for: key),
                    language == .english ? english : chinese,
                    "Unexpected copy for \(key.rawValue) in \(language.rawValue)"
                )
            }
        }
    }

    func testNetworkMonitorAccessibilityValueFormatsUploadAndDownloadSpeeds() {
        LocalizationManager.shared.setLanguage(.english)
        XCTAssertEqual(
            LocalizationManager.shared.string(
                for: .networkMonitorAccessibilityValue,
                arguments: "21 KB/s", "134 KB/s"
            ),
            "Upload 21 KB/s, Download 134 KB/s"
        )

        LocalizationManager.shared.setLanguage(.chinese)
        XCTAssertEqual(
            LocalizationManager.shared.string(
                for: .networkMonitorAccessibilityValue,
                arguments: "21 KB/s", "134 KB/s"
            ),
            "上传 21 KB/s，下载 134 KB/s"
        )
    }

    private func assertHelpContentKeysResolve(in language: AppLanguage) {
        LocalizationManager.shared.setLanguage(language)

        let keys: [LocalizationKey] = [
            .helpHotkeyUsageTitle,
            .helpFeatureNotesTitle,
            .hotkeyGuideTitle,
            .hotkeyGuideDismiss,
        ] + AppHelpContent.hotkeyUsageKeys +
            AppHelpContent.featureNotes.flatMap { [$0.titleKey, $0.bodyKey] }

        for key in keys {
            let value = LocalizationManager.shared.string(for: key)
            XCTAssertFalse(value.isEmpty, "Expected non-empty localization for \(key.rawValue) in \(language.rawValue)")
            XCTAssertNotEqual(value, key.rawValue, "Expected localized value for \(key.rawValue) in \(language.rawValue)")
        }
    }
}
