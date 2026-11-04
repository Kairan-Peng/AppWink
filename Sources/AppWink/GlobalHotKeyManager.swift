import AppKit
import Carbon
import Foundation
import AppWinkCore

/// 描述一次需要注册到系统层的全局热键业务动作。
enum HotKeyRegistrationAction: Hashable, Sendable {
    case binding(UUID)
    case activityMonitor
}

/// 描述一次需要注册到系统层的全局热键请求。
struct HotKeyRegistrationRequest {
    let action: HotKeyRegistrationAction
    let shortcut: AppShortcut
}

/// 全局热键注册管理器的最小抽象，便于 AppModel 注入测试替身。
protocol GlobalHotKeyManaging {
    func updateRegistrations(
        requests: [HotKeyRegistrationRequest],
        actionHandler: @escaping @MainActor (HotKeyRegistrationAction, AppShortcut, pid_t?) -> Void
    ) -> [HotKeyRegistrationAction]

    func unregisterAll()
}

/// 统一管理 Carbon 全局热键注册与回调分发。
final class GlobalHotKeyManager: GlobalHotKeyManaging {
    /// 固定签名用于区分 AppWink 自己注册的热键事件。
    private static let signature: OSType = 0x4D59544C

    private var eventHandler: EventHandlerRef?
    private var actionHandler: (@MainActor (HotKeyRegistrationAction, AppShortcut, pid_t?) -> Void)?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var registrationActions: [UInt32: HotKeyRegistrationAction] = [:]
    private var registrationShortcuts: [UInt32: AppShortcut] = [:]
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder
    private let registerHotKey: (
        UInt32,
        UInt32,
        EventHotKeyID,
        UnsafeMutablePointer<EventHotKeyRef?>
    ) -> OSStatus

    init(
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared,
        registerHotKey: @escaping (
            UInt32,
            UInt32,
            EventHotKeyID,
            UnsafeMutablePointer<EventHotKeyRef?>
        ) -> OSStatus = { keyCode, modifiers, hotKeyID, hotKeyReference in
            RegisterEventHotKey(
                keyCode,
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                hotKeyReference)
        },
        installsEventHandler: Bool = true
    ) {
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
        self.registerHotKey = registerHotKey
        if installsEventHandler {
            installEventHandlerIfNeeded()
        }
    }

    deinit {
        for registration in registrations.values {
            UnregisterEventHotKey(registration)
        }

        registrations.removeAll()
        registrationActions.removeAll()
        registrationShortcuts.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// 用新的绑定集合整体替换旧注册，避免增量更新导致状态残留。
    func updateRegistrations(
        requests: [HotKeyRegistrationRequest],
        actionHandler: @escaping @MainActor (HotKeyRegistrationAction, AppShortcut, pid_t?) -> Void
    ) -> [HotKeyRegistrationAction] {
        return performanceDiagnosticsRecorder.measure(
            category: .registration,
            name: "updateRegistrations",
            metadata: ["requestCount": String(requests.count)]
        ) {
            self.actionHandler = actionHandler
            unregisterAll()

            appendDecisionTrace("hotkeys update start count=\(requests.count)")

            var failures: [HotKeyRegistrationAction] = []
            var nextRegistrationID: UInt32 = 1

            for request in requests {
                let registrationStatus = register(request.shortcut, for: nextRegistrationID)
                if registrationStatus == noErr {
                    registrationActions[nextRegistrationID] = request.action
                    registrationShortcuts[nextRegistrationID] = request.shortcut
                    appendDecisionTrace(
                        "hotkeys register success id=\(nextRegistrationID) action=\(traceDescription(for: request.action)) keyCode=\(request.shortcut.keyCode) modifiers=\(request.shortcut.modifiers.rawValue)"
                    )
                    nextRegistrationID += 1
                } else {
                    appendDecisionTrace(
                        "hotkeys register failure action=\(traceDescription(for: request.action)) keyCode=\(request.shortcut.keyCode) modifiers=\(request.shortcut.modifiers.rawValue)"
                    )
                    recordRegistrationFailure(status: registrationStatus)
                    failures.append(request.action)
                }
            }

            appendDecisionTrace("hotkeys update done successes=\(registrationActions.count) failures=\(failures.count)")

            return failures
        }
    }

    /// 统一清理所有系统热键句柄，供重新注册和析构两条路径复用。
    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration)
        }

        registrations.removeAll()
        registrationActions.removeAll()
        registrationShortcuts.removeAll()
    }

    /// 收到 Carbon 事件后，根据注册 ID 找回业务绑定并回传当前前台进程。
    fileprivate func handleHotKeyPressed(_ hotKeyID: UInt32) {
        performanceDiagnosticsRecorder.recordEvent(
            category: .hotkey,
            name: "carbonCallback",
            metadata: ["hotKeyID": String(hotKeyID)]
        )

        guard
            let action = registrationActions[hotKeyID],
            let shortcut = registrationShortcuts[hotKeyID]
        else {
            appendDecisionTrace("hotkeys pressed unresolved id=\(hotKeyID)")
            return
        }

        let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
        appendDecisionTrace(
            "hotkeys pressed id=\(hotKeyID) action=\(traceDescription(for: action)) keyCode=\(shortcut.keyCode) modifiers=\(shortcut.modifiers.rawValue) frontmostPid=\(frontmostProcessIdentifier ?? -1)"
        )
        Task { @MainActor [actionHandler] in
            actionHandler?(action, shortcut, frontmostProcessIdentifier)
        }
    }

    /// 直接向 Carbon 注册热键，失败时交由上层汇总成用户提示。
    private func register(_ shortcut: AppShortcut, for registrationID: UInt32) -> OSStatus {
        var hotKeyReference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: registrationID)

        let status = registerHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            &hotKeyReference)

        guard status == noErr, let hotKeyReference else {
            let effectiveStatus = status == noErr ? OSStatus(eventNotHandledErr) : status
            appendDecisionTrace(
                "hotkeys carbonRegister status=\(effectiveStatus) id=\(registrationID) keyCode=\(shortcut.keyCode) carbonModifiers=\(shortcut.carbonModifiers)"
            )
            return effectiveStatus
        }

        registrations[registrationID] = hotKeyReference
        return noErr
    }

    private func recordRegistrationFailure(status: OSStatus) {
        performanceDiagnosticsRecorder.recordEvent(
            category: .registration,
            name: "carbonRegistrationFailure",
            metadata: [
                "statusCode": String(status),
            ]
        )
    }

    /// 应用级事件处理器只需要安装一次，后续复用内部映射表即可。
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)
    }

    private func traceDescription(for action: HotKeyRegistrationAction) -> String {
        switch action {
        case .binding(let bindingID):
            return "binding=\(bindingID.uuidString)"
        case .activityMonitor:
            return "activityMonitor"
        }
    }
}

private func globalHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID)

    guard status == noErr else {
        return status
    }

    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    // Carbon 回调层只负责解包事件，具体业务逻辑仍回到对象方法中处理。
    manager.handleHotKeyPressed(hotKeyID.id)

    return noErr
}
