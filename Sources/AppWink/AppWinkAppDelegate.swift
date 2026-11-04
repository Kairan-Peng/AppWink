import AppKit

/// 配置应用生命周期，让 AppWink 以常驻菜单栏工具的方式运行。
public final class AppWinkAppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 关闭自动标签页，确保设置窗口始终保持单实例体验。
        NSWindow.allowsAutomaticWindowTabbing = false
        // 使用 accessory 模式隐藏 Dock 图标，只保留菜单栏入口。
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppWindowForegroundController.refreshActivationPolicy()
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
