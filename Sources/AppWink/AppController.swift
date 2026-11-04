import AppKit
import AppWinkCore

@MainActor
/// 协调全局运行时组件，把窗口切换、覆盖层和系统通知串起来。
final class AppController: ObservableObject {
    let model: AppModel

    private let overlayPanelController: QuickSwitchOverlayPanelController
    private let pressedKeysOverlayPanelController: PressedKeysOverlayPanelController
    private let appIconFlashOverlayPanelController: AppIconFlashOverlayPanelController
    private let pressedKeysMonitorController: PressedKeysMonitorController
    private let hiddenBarController: HiddenBarController
    private let networkStatusItemController: NetworkStatusItemController
    private let mouseWheelScrollService: MouseWheelScrollService
    private let optionHoldController: OptionKeyHoldController
    private let notificationCenter = NotificationCenter.default
    nonisolated(unsafe) private var appDidBecomeActiveObserver: NSObjectProtocol?
    nonisolated(unsafe) private var appWillTerminateObserver: NSObjectProtocol?

    /// 在应用启动时一次性装配控制器、事件观察者和初始焦点历史。
    init(model: AppModel? = nil) {
        let resolvedModel = model ?? AppModel()
        self.model = resolvedModel

        let performanceDiagnosticsRecorder = resolvedModel.performanceDiagnosticsRecorder
        let overlayPanelController = QuickSwitchOverlayPanelController(
            model: resolvedModel,
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder
        )
        self.overlayPanelController = overlayPanelController
        let pressedKeysOverlayPanelController = PressedKeysOverlayPanelController(
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder
        )
        self.pressedKeysOverlayPanelController = pressedKeysOverlayPanelController
        let appIconFlashOverlayPanelController = AppIconFlashOverlayPanelController(
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder
        )
        self.appIconFlashOverlayPanelController = appIconFlashOverlayPanelController
        let hiddenBarController = HiddenBarController()
        self.hiddenBarController = hiddenBarController
        let networkStatusItemController = NetworkStatusItemController(
            reader: SystemNetworkInterfaceByteReader(),
            display: AppKitNetworkStatusItemDisplay(),
            timerScheduler: FoundationNetworkStatusTimerScheduler()
        ) { upload, download in
            LocalizationManager.shared.string(
                for: .networkMonitorAccessibilityValue,
                arguments: upload,
                download
            )
        }
        self.networkStatusItemController = networkStatusItemController
        self.pressedKeysMonitorController = PressedKeysMonitorController(
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder
        ) { text in
            if let text {
                pressedKeysOverlayPanelController.show(text: text)
            } else {
                pressedKeysOverlayPanelController.hide()
            }
        }
        self.mouseWheelScrollService = MouseWheelScrollService(
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder
        )
        self.optionHoldController = OptionKeyHoldController(
            revealDelay: { resolvedModel.virtualKeyboardRevealDelay },
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder,
            allowsGlobalKeyMonitoring: { AccessibilityPermissionChecker.isGranted() },
            isOverlayAvailable: { resolvedModel.virtualKeyboardRuntimeEnabled && !resolvedModel.overlayBindings.isEmpty },
            onReveal: { overlayPanelController.show() },
            onDismiss: { overlayPanelController.hide() })

        resolvedModel.beforeBindingAction = { [weak optionHoldController] in
            optionHoldController?.suppressOverlayUntilModifierReset()
        }
        resolvedModel.pressedKeysOverlaySettingsDidChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshPressedKeysOverlayRuntime()
            }
        }
        resolvedModel.virtualKeyboardSettingsDidChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshVirtualKeyboardRuntime()
            }
        }
        resolvedModel.hotKeyTargetFlashDidTrigger = { [weak appIconFlashOverlayPanelController] payload in
            appIconFlashOverlayPanelController?.show(payload: payload)
        }
        resolvedModel.hiddenBarSettingsDidChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshHiddenBarRuntime()
            }
        }
        resolvedModel.networkStatusSettingsDidChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshNetworkStatusRuntime()
            }
        }
        resolvedModel.mouseWheelScrollSettingsDidChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshMouseWheelScrollRuntime()
            }
        }

        observeAppActivation()
        observeAppTermination()
        refreshVirtualKeyboardRuntime()
        refreshPressedKeysOverlayRuntime()
        scheduleInitialMenuBarRuntimeRefresh()
        refreshMouseWheelScrollRuntime()

    }

    deinit {
        if let appDidBecomeActiveObserver {
            notificationCenter.removeObserver(appDidBecomeActiveObserver)
        }
        if let appWillTerminateObserver {
            notificationCenter.removeObserver(appWillTerminateObserver)
        }
        Task { @MainActor [optionHoldController] in
            optionHoldController.stop()
        }
        Task { @MainActor [pressedKeysMonitorController, pressedKeysOverlayPanelController] in
            pressedKeysMonitorController.stop()
            pressedKeysOverlayPanelController.hide()
        }
        Task { @MainActor [appIconFlashOverlayPanelController] in
            appIconFlashOverlayPanelController.hide()
        }
        Task { @MainActor [hiddenBarController, networkStatusItemController] in
            hiddenBarController.teardown()
            networkStatusItemController.teardown()
        }
    }

    /// 当 AppWink 自己重新变为激活态时，同步刷新依赖系统状态的 UI 信息。
    private func observeAppActivation() {
        appDidBecomeActiveObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.handleApplicationDidBecomeActive()
                self?.model.refreshLaunchAtLoginStatus()
                self?.refreshVirtualKeyboardRuntime()
                self?.refreshPressedKeysOverlayRuntime()
                self?.refreshMouseWheelScrollRuntime()
            }
        }
    }

    private func observeAppTermination() {
        let hiddenBarController = hiddenBarController
        let networkStatusItemController = networkStatusItemController
        appWillTerminateObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: NSApp,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                hiddenBarController.teardown()
                networkStatusItemController.teardown()
            }
        }
    }

    /// 根据配置开关和辅助功能权限，决定 pressed-keys overlay runtime 是否应该运行。
    private func refreshPressedKeysOverlayRuntime() {
        let shouldRun = model.pressedKeysOverlayRuntimeEnabled && model.accessibilityPermissionGranted

        guard shouldRun else {
            pressedKeysMonitorController.stop()
            pressedKeysOverlayPanelController.hide()
            return
        }

        pressedKeysMonitorController.start()
    }

    /// 根据配置开关决定长按 Option 虚拟键盘监听器是否应该运行。
    private func refreshVirtualKeyboardRuntime() {
        guard model.virtualKeyboardRuntimeEnabled else {
            optionHoldController.stop()
            overlayPanelController.hide()
            return
        }

        optionHoldController.start()
        optionHoldController.refreshGlobalMonitors()
    }

    private func refreshHiddenBarRuntime() {
        hiddenBarController.setEnabled(model.hiddenBarRuntimeEnabled)
    }

    private func refreshNetworkStatusRuntime() {
        networkStatusItemController.setEnabled(model.networkStatusRuntimeEnabled)
    }

    private func scheduleInitialMenuBarRuntimeRefresh() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.refreshHiddenBarRuntime()
            self?.refreshNetworkStatusRuntime()
        }
    }

    /// 根据配置开关和辅助功能权限，决定 mouse-wheel Windows scroll runtime 是否应该运行。
    private func refreshMouseWheelScrollRuntime() {
        mouseWheelScrollService.updateActivation(
            isEnabled: model.mouseWheelWindowsScrollRuntimeEnabled,
            accessibilityGranted: model.accessibilityPermissionGranted)
    }
}
