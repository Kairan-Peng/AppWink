import AppKit
import ApplicationServices

/// 统一封装辅助功能授权检查与系统设置跳转，避免调用方分散处理 TCC 细节。
enum AccessibilityPermissionChecker {
    static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 直接跳转到“隐私与安全性 > 辅助功能”页面，减少用户手动查找成本。
    static func openSystemSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }
}
