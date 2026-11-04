import AppKit
import Carbon
import Foundation
import AppWinkCore

/// 在 Finder 中拦截 `⌘X` / `⌘V`，模拟 Windows 风格的文件剪切与移动。
final class FinderWindowsCutPasteService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cutState = WindowsStyleCutState()
    private var isEnabled = false
    private var isPostingSyntheticShortcut = false
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder

    init(performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared) {
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
    }

    func updateActivation(isEnabled: Bool, accessibilityGranted: Bool) {
        let shouldRun = isEnabled && accessibilityGranted

        if shouldRun {
            startIfNeeded()
        } else {
            stop()
        }

        self.isEnabled = shouldRun
    }

    deinit {
        stop()
    }

    private func startIfNeeded() {
        guard eventTap == nil else {
            return
        }

        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "finderCutPasteStart"
        )
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let service = Unmanaged<FinderWindowsCutPasteService>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return service.handleEvent(proxy: proxy, type: type, event: event)
        }

        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "finderCutPasteEventTapInstallFailed"
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
            name: "finderCutPasteEventTapInstallSucceeded"
        )
    }

    private func stop() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "finderCutPasteStop"
        )
        cutState.reset()

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
        isEnabled = false
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "finderCutPasteEventTapReenabled",
                metadata: [
                    "reason": type == .tapDisabledByTimeout ? "timeout" : "userInput",
                ]
            )
            return Unmanaged.passUnretained(event)
        }

        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .eventListener,
            name: "finderCutPasteCallback"
        )
        defer {
            performanceDiagnosticsRecorder.endInterval(intervalToken)
        }

        guard type == .keyDown,
              isEnabled,
              !isPostingSyntheticShortcut,
              let command = command(for: event) else {
            return Unmanaged.passUnretained(event)
        }

        let outcome = cutState.handle(
            command: command,
            isFinderFrontmost: Self.isFinderFrontmost
        )

        switch outcome {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .interceptAsCopy:
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "finderCutPasteIntercepted"
            )
            postSyntheticShortcut(keyCode: CGKeyCode(kVK_ANSI_C), flags: [.maskCommand])
            return nil
        case .interceptAsMovePaste:
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "finderCutPasteIntercepted"
            )
            postSyntheticShortcut(
                keyCode: CGKeyCode(kVK_ANSI_V),
                flags: [.maskCommand, .maskAlternate]
            )
            return nil
        }
    }

    /// 只处理 Finder 中纯 `⌘X / ⌘C / ⌘V`，避免影响用户主动输入 `⌥⌘V` 等原生组合。
    private func command(for event: CGEvent) -> WindowsStyleCutCommand? {
        let relevantFlags = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        guard relevantFlags == [.maskCommand],
              let characters = event.keyboardUnicodeString()?.lowercased() else {
            return nil
        }

        switch characters {
        case "x":
            return .cut
        case "c":
            return .copy
        case "v":
            return .paste
        default:
            return .other
        }
    }

    private static var isFinderFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    private func postSyntheticShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "finderCutPasteSyntheticEvent"
        )
        isPostingSyntheticShortcut = true
        defer { isPostingSyntheticShortcut = false }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

private extension CGEvent {
    func keyboardUnicodeString() -> String? {
        let maxLength = 4
        var characters = [UniChar](repeating: 0, count: maxLength)
        var actualLength = 0

        keyboardGetUnicodeString(
            maxStringLength: maxLength,
            actualStringLength: &actualLength,
            unicodeString: &characters
        )

        guard actualLength > 0 else {
            return nil
        }

        return String(utf16CodeUnits: characters, count: actualLength)
    }
}
