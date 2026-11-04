import AppKit

@MainActor
/// 监听长按 `Option` 的手势，在满足条件时显示快捷切换覆盖层。
final class OptionKeyHoldController {
    private var localMonitors: [Any] = []
    private var globalMonitors: [Any] = []
    private var pendingRevealWorkItem: DispatchWorkItem?
    private let revealDelayProvider: @MainActor () -> TimeInterval
    private let allowsGlobalKeyMonitoring: @MainActor () -> Bool
    private let isOverlayAvailable: @MainActor () -> Bool
    private let onReveal: @MainActor () -> Void
    private let onDismiss: @MainActor () -> Void
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder
    private var isRunning = false
    private var isOverlayVisible = false
    private var suppressUntilOptionRelease = false

    init(
        revealDelay: @escaping @MainActor () -> TimeInterval = { 0.5 },
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared,
        allowsGlobalKeyMonitoring: @escaping @MainActor () -> Bool,
        isOverlayAvailable: @escaping @MainActor () -> Bool,
        onReveal: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.revealDelayProvider = revealDelay
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
        self.allowsGlobalKeyMonitoring = allowsGlobalKeyMonitoring
        self.isOverlayAvailable = isOverlayAvailable
        self.onReveal = onReveal
        self.onDismiss = onDismiss
    }

    /// 启动本地监听，并在有权限时补充全局监听以覆盖 AppWink 失焦场景。
    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        performanceDiagnosticsRecorder.recordEvent(category: .eventListener, name: "optionHoldStart")
        installLocalMonitorsIfNeeded()
        refreshGlobalMonitors()
    }

    /// 辅助功能权限变化后，需要重新决定是否安装全局监听器。
    func refreshGlobalMonitors() {
        guard isRunning else {
            removeGlobalMonitors()
            return
        }

        guard allowsGlobalKeyMonitoring() else {
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "optionHoldGlobalMonitorUnavailable"
            )
            removeGlobalMonitors()
            return
        }

        installGlobalMonitorsIfNeeded()
    }

    func stop() {
        guard isRunning ||
              !localMonitors.isEmpty ||
              !globalMonitors.isEmpty ||
              pendingRevealWorkItem != nil ||
              isOverlayVisible ||
              suppressUntilOptionRelease else {
            return
        }

        isRunning = false
        performanceDiagnosticsRecorder.recordEvent(category: .eventListener, name: "optionHoldStop")
        removeLocalMonitors()
        removeGlobalMonitors()
        suppressUntilOptionRelease = false
        dismissOverlay()
    }

    /// 在执行热键切换后暂时抑制覆盖层，避免同一次按键既切换应用又弹出面板。
    func suppressOverlayUntilModifierReset() {
        suppressUntilOptionRelease = true
        dismissOverlay()
    }

    /// 本地监听保证应用自身激活时的行为完整，包括 flagsChanged 和任意交互的收起。
    private func installLocalMonitorsIfNeeded() {
        guard localMonitors.isEmpty else {
            return
        }

        let eventMask: NSEvent.EventTypeMask = [.flagsChanged]
        if let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask, handler: { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }) {
            localMonitors.append(flagsMonitor)
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "optionHoldLocalMonitorInstallSucceeded"
            )
        }

        let dismissalMask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        if let dismissalMonitor = NSEvent.addLocalMonitorForEvents(matching: dismissalMask, handler: { [weak self] event in
            self?.dismissOverlay()
            return event
        }) {
            localMonitors.append(dismissalMonitor)
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "optionHoldLocalMonitorInstallSucceeded"
            )
        }
    }

    /// 全局监听只在有权限时安装，用于覆盖应用不在前台时的长按场景。
    private func installGlobalMonitorsIfNeeded() {
        guard globalMonitors.isEmpty else {
            return
        }

        let eventMask: NSEvent.EventTypeMask = [.flagsChanged]
        if let globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask, handler: { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }) {
            globalMonitors.append(globalFlagsMonitor)
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "optionHoldGlobalMonitorInstallSucceeded"
            )
        }

        let dismissalMask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        if let globalDismissalMonitor = NSEvent.addGlobalMonitorForEvents(matching: dismissalMask, handler: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissOverlay()
            }
        }) {
            globalMonitors.append(globalDismissalMonitor)
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "optionHoldGlobalMonitorInstallSucceeded"
            )
        }
    }

    private func removeLocalMonitors() {
        for monitor in localMonitors {
            NSEvent.removeMonitor(monitor)
        }

        localMonitors.removeAll()
    }

    private func removeGlobalMonitors() {
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }

        globalMonitors.removeAll()
    }

    /// 只有“单独按住 Option”才触发面板，其它组合键或松开都立即收起。
    private func handleFlagsChanged(_ event: NSEvent) {
        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "optionHoldCallback"
        )
        let relevantModifiers = event.modifierFlags.intersection([.option, .command, .control, .shift])

        if suppressUntilOptionRelease {
            if !relevantModifiers.contains(.option) {
                suppressUntilOptionRelease = false
            }
            dismissOverlay()
            return
        }

        if relevantModifiers == [.option] {
            scheduleOverlayReveal()
        } else {
            dismissOverlay()
        }
    }

    /// 使用延迟任务判定“长按”而不是“点按”，避免正常快捷键操作误触覆盖层。
    private func scheduleOverlayReveal() {
        guard isRunning, pendingRevealWorkItem == nil, !isOverlayVisible else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingRevealWorkItem = nil
            guard self.isRunning, self.isOverlayAvailable() else {
                return
            }

            self.isOverlayVisible = true
            self.onReveal()
        }

        let revealDelay = max(0, revealDelayProvider())
        pendingRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay, execute: workItem)
    }

    /// 收起时同时撤销待触发任务，确保状态机不会出现残留展示。
    private func dismissOverlay() {
        pendingRevealWorkItem?.cancel()
        pendingRevealWorkItem = nil

        guard isOverlayVisible else {
            return
        }

        isOverlayVisible = false
        onDismiss()
    }
}
