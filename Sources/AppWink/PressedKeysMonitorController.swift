import AppKit
import AppWinkCore

@MainActor
/// 监听系统按键变化，把 pressed-keys overlay 的可见文本去重后发布给上层。
final class PressedKeysMonitorController {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitors: [Any] = []
    private var globalMonitors: [Any] = []
    private var state = PressedKeysOverlayState()
    private var lastPublishedText: String?
    private var didStopForCurrentRun = false
    private var isActive = true
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder
    private let onDisplayTextChange: @MainActor (String?) -> Void

    init(
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared,
        onDisplayTextChange: @escaping @MainActor (String?) -> Void
    ) {
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
        self.onDisplayTextChange = onDisplayTextChange
    }

    /// 启动本地和全局监听器；重复调用不会重复安装。
    func start() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "pressedKeysStart"
        )
        didStopForCurrentRun = false
        isActive = true
        installEventTapIfNeeded()

        if eventTap == nil {
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "pressedKeysFallbackMonitors"
            )
            installLocalMonitorsIfNeeded()
            installGlobalMonitorsIfNeeded()
            return
        }

        removeLocalMonitors()
        removeGlobalMonitors()
    }

    /// 停止监听、清空状态，并只发布一次 `nil`。
    func stop() {
        guard !didStopForCurrentRun else {
            return
        }

        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "pressedKeysStop"
        )
        didStopForCurrentRun = true
        isActive = false
        removeEventTap()
        removeLocalMonitors()
        removeGlobalMonitors()
        state = PressedKeysOverlayState()
        publish(nil, force: true)
    }

    /// 处理 modifier flags 变化，并在可见文本变化时向外发布。
    func handleModifierFlagsChanged(_ modifiers: AppShortcutModifiers) {
        guard isActive else {
            return
        }

        performanceDiagnosticsRecorder.measure(
            category: .eventListener,
            name: "pressedKeysCallback",
            metadata: ["eventType": "flagsChanged"]
        ) {
            state.applyModifierFlags(modifiers)
            publish(state.displayText)
        }
    }

    /// 处理 keyDown，忽略重复 keyDown 和 modifier 虚拟键码。
    func handleKeyDown(keyCode: UInt16, modifiers: AppShortcutModifiers, isARepeat: Bool) {
        guard isActive else {
            return
        }

        performanceDiagnosticsRecorder.measure(
            category: .eventListener,
            name: "pressedKeysCallback",
            metadata: [
                "eventType": "keyDown",
                "isRepeat": String(isARepeat),
            ]
        ) {
            state.handleKeyDown(keyCode: keyCode, modifiers: modifiers, isARepeat: isARepeat)
            publish(state.displayText)
        }
    }

    /// 处理 keyUp，忽略 modifier 虚拟键码。
    func handleKeyUp(keyCode: UInt16, modifiers: AppShortcutModifiers) {
        guard isActive else {
            return
        }

        performanceDiagnosticsRecorder.measure(
            category: .eventListener,
            name: "pressedKeysCallback",
            metadata: ["eventType": "keyUp"]
        ) {
            state.handleKeyUp(keyCode: keyCode, modifiers: modifiers)
            publish(state.displayText)
        }
    }

    func handleCGEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isARepeat: Bool = false
    ) {
        switch type {
        case .flagsChanged:
            handleModifierFlagsChanged(AppShortcutModifiers(eventFlags: flags))
        case .keyDown:
            handleKeyDown(
                keyCode: keyCode,
                modifiers: AppShortcutModifiers(eventFlags: flags),
                isARepeat: isARepeat)
        case .keyUp:
            handleKeyUp(
                keyCode: keyCode,
                modifiers: AppShortcutModifiers(eventFlags: flags))
        default:
            return
        }
    }

    private func installEventTapIfNeeded() {
        guard eventTap == nil else {
            return
        }

        let eventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let controller = Unmanaged<PressedKeysMonitorController>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let isARepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

            Task { @MainActor in
                controller.handleEventTap(
                    type: type,
                    keyCode: keyCode,
                    flags: flags,
                    isARepeat: isARepeat)
            }

            return Unmanaged.passUnretained(event)
        }

        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap else {
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "pressedKeysEventTapInstallFailed"
            )
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "pressedKeysEventTapInstallSucceeded"
        )
    }

    private func installLocalMonitorsIfNeeded() {
        guard localMonitors.isEmpty else {
            return
        }

        installLocalMonitor(matching: [.flagsChanged]) { [weak self] event in
            guard let self else {
                return event
            }

            self.handleModifierFlagsChanged(AppShortcutModifiers(eventFlags: event.modifierFlags))
            return event
        }

        installLocalMonitor(matching: [.keyDown]) { [weak self] event in
            guard let self else {
                return event
            }

            self.handleKeyDown(
                keyCode: event.keyCode,
                modifiers: AppShortcutModifiers(eventFlags: event.modifierFlags),
                isARepeat: event.isARepeat)
            return event
        }

        installLocalMonitor(matching: [.keyUp]) { [weak self] event in
            guard let self else {
                return event
            }

            self.handleKeyUp(
                keyCode: event.keyCode,
                modifiers: AppShortcutModifiers(eventFlags: event.modifierFlags))
            return event
        }
    }

    private func installGlobalMonitorsIfNeeded() {
        guard globalMonitors.isEmpty else {
            return
        }

        installGlobalMonitor(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.handleModifierFlagsChanged(AppShortcutModifiers(eventFlags: event.modifierFlags))
            }
        }

        installGlobalMonitor(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.handleKeyDown(
                    keyCode: event.keyCode,
                    modifiers: AppShortcutModifiers(eventFlags: event.modifierFlags),
                    isARepeat: event.isARepeat)
            }
        }

        installGlobalMonitor(matching: [.keyUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.handleKeyUp(
                    keyCode: event.keyCode,
                    modifiers: AppShortcutModifiers(eventFlags: event.modifierFlags))
            }
        }
    }

    private func installLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> NSEvent
    ) {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            return handler(event)
        }) {
            localMonitors.append(monitor)
        }
    }

    private func handleEventTap(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        isARepeat: Bool
    ) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "pressedKeysEventTapReenabled",
                metadata: [
                    "reason": type == .tapDisabledByTimeout ? "timeout" : "userInput",
                ]
            )
            return
        }

        handleCGEvent(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isARepeat: isARepeat)
    }

    private func installGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> Void
    ) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
        }) {
            globalMonitors.append(monitor)
        }
    }

    private func removeLocalMonitors() {
        for monitor in localMonitors {
            NSEvent.removeMonitor(monitor)
        }

        localMonitors.removeAll()
    }

    private func removeEventTap() {
        if let eventTap {
            if CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }

            CFMachPortInvalidate(eventTap)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    private func removeGlobalMonitors() {
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }

        globalMonitors.removeAll()
    }

    private func publish(_ text: String?, force: Bool = false) {
        guard force || text != lastPublishedText else {
            return
        }

        lastPublishedText = text
        onDisplayTextChange(text)
    }
}
