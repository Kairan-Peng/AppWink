import AppKit
import SwiftUI

@MainActor
/// 管理快捷切换覆盖层对应的无边框面板生命周期。
final class QuickSwitchOverlayPanelController {
    private weak var model: AppModel?
    private var panel: QuickSwitchOverlayPanel?
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder

    init(
        model: AppModel,
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared
    ) {
        self.model = model
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
    }

    /// 每次展示前重新注入最新模型，确保绑定列表和图标状态实时刷新。
    func show() {
        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .overlay,
            name: "quickSwitchShow"
        )
        defer {
            performanceDiagnosticsRecorder.endInterval(intervalToken)
        }

        guard let model, !model.overlayBindings.isEmpty else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.appearance = NSApp.effectiveAppearance

        panel.contentView = NSHostingView(
            rootView: QuickSwitchOverlayPanelRootView()
                .environmentObject(model)
                .environment(\.colorScheme, currentSystemColorScheme()))

        if let screen = activeScreen() {
            panel.setFrame(screen.frame, display: true)
        }

        panel.orderFrontRegardless()
        performanceDiagnosticsRecorder.recordEvent(
            category: .overlay,
            name: "quickSwitchShow"
        )
    }

    /// 面板常驻复用，只做隐藏不销毁，减少频繁创建窗口的抖动。
    func hide() {
        panel?.orderOut(nil)
        performanceDiagnosticsRecorder.recordEvent(
            category: .overlay,
            name: "quickSwitchHide"
        )
    }

    /// 创建一层不抢焦点、不响应鼠标的全屏浮层，用于纯展示快捷切换 UI。
    private func makePanel() -> QuickSwitchOverlayPanel {
        let screenFrame = activeScreen()?.frame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let panel = QuickSwitchOverlayPanel(
            contentRect: screenFrame,
            backing: .buffered,
            defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        return panel
    }

    /// 优先使用鼠标所在屏幕，避免多显示器下覆盖层出现在错误位置。
    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    private func currentSystemColorScheme() -> ColorScheme {
        let matchedAppearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return matchedAppearance == .darkAqua ? .dark : .light
    }
}

/// 自定义 NSPanel，让覆盖层既可显示在最上层，又不会成为主窗口。
private final class QuickSwitchOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: backing,
            defer: flag)
    }
}

/// 用一个极薄的 SwiftUI 根视图包装遮罩和实际内容，便于直接注入环境对象。
private struct QuickSwitchOverlayPanelRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        QuickSwitchOverlayView(
            bindings: model.overlayBindings,
            targetPresentation: { model.targetPresentation(for: $0) })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
