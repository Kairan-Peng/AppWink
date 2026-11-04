import AppKit
import SwiftUI

@MainActor
/// 管理 pressed-keys overlay 对应的无边框面板生命周期。
final class PressedKeysOverlayPanelController {
    private var panel: PressedKeysOverlayPanel?
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder

    init(performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared) {
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
    }

    /// 显示当前按键文本，并根据内容大小与鼠标所在屏幕重新定位。
    func show(text: String) {
        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .overlay,
            name: "pressedKeysShow"
        )
        defer {
            performanceDiagnosticsRecorder.endInterval(intervalToken)
        }

        let panel = panel ?? makePanel()
        self.panel = panel

        let hostingView = NSHostingView(rootView: PressedKeysOverlayView(text: text))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        panel.contentView = hostingView

        let contentSize = hostingView.fittingSize
        let frame = frame(for: contentSize)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        panel.contentView?.displayIfNeeded()
        panel.displayIfNeeded()
        performanceDiagnosticsRecorder.recordEvent(
            category: .overlay,
            name: "pressedKeysShow"
        )
    }

    /// 隐藏面板但保留实例，避免每次显示都重新创建窗口。
    func hide() {
        panel?.orderOut(nil)
        performanceDiagnosticsRecorder.recordEvent(
            category: .overlay,
            name: "pressedKeysHide"
        )
    }

    private func makePanel() -> PressedKeysOverlayPanel {
        let panel = PressedKeysOverlayPanel(
            contentRect: activeScreen()?.frame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 900, height: 700),
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

    private func frame(for contentSize: CGSize) -> NSRect {
        let screen = activeScreen()
        let visibleFrame = screen?.visibleFrame ?? screen?.frame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let horizontalInset: CGFloat = 16
        let bottomInset: CGFloat = 44

        let width = min(contentSize.width, max(1, visibleFrame.width - (horizontalInset * 2)))
        let height = min(contentSize.height, max(1, visibleFrame.height - bottomInset - horizontalInset))

        let maxX = visibleFrame.maxX - width - horizontalInset
        let maxY = visibleFrame.maxY - height - horizontalInset
        let minX = visibleFrame.minX + horizontalInset
        let minY = visibleFrame.minY + bottomInset

        let originX = min(max(visibleFrame.midX - (width / 2), minX), maxX)
        let originY = min(max(minY, visibleFrame.minY + horizontalInset), maxY)

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    /// 优先使用鼠标所在屏幕，保证多显示器时浮层出现在当前活动显示器。
    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    }
}

/// 自定义 NSPanel，让浮层保持最上层但不抢焦点。
private final class PressedKeysOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: backing,
            defer: flag)
    }
}
