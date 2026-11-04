import CoreGraphics
import Foundation

final class MouseWheelScrollService {
    private static let naturalScrollPreferenceKey = "com.apple.swipescrolldirection"
    private static let syntheticEventMarker: Int64 = 0x41707057696E6B53
    private static let frameInterval: TimeInterval = 0.020

    private struct ScrollEventContext {
        let location: CGPoint
        let flags: CGEventFlags
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventSource: CGEventSource?
    private var timer: DispatchSourceTimer?
    private var pendingFrames: [MouseWheelScrollFrame] = []
    private var pendingContext: ScrollEventContext?
    private var isEnabled = false
    private var isPostingSyntheticScroll = false
    private let naturalScrollPreferenceProvider: () -> Bool
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder

    init(
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared,
        naturalScrollPreferenceProvider: @escaping () -> Bool =
            MouseWheelScrollService.readNaturalScrollPreference
    ) {
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
        self.naturalScrollPreferenceProvider = naturalScrollPreferenceProvider
    }

    func updateActivation(isEnabled: Bool, accessibilityGranted: Bool) {
        let shouldRun = isEnabled && accessibilityGranted

        if shouldRun {
            self.isEnabled = true
            startIfNeeded()
        } else {
            stop()
        }
    }

    func stop() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "mouseWheelStop"
        )
        timer?.cancel()
        timer = nil
        pendingFrames.removeAll()
        pendingContext = nil

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
        eventSource = nil
        isEnabled = false
        isPostingSyntheticScroll = false
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
            name: "mouseWheelStart"
        )
        guard let source = CGEventSource(stateID: .privateState) else {
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "mouseWheelEventSourceFailed"
            )
            return
        }

        source.userData = Self.syntheticEventMarker
        source.pixelsPerLine = MouseWheelScrollPlanner.defaultPixelsPerLine
        eventSource = source

        let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let service = Unmanaged<MouseWheelScrollService>
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
            eventSource = nil
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "mouseWheelEventTapInstallFailed"
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
            name: "mouseWheelEventTapInstallSucceeded"
        )
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
                name: "mouseWheelEventTapReenabled",
                metadata: [
                    "reason": type == .tapDisabledByTimeout ? "timeout" : "userInput",
                ]
            )
            return Unmanaged.passUnretained(event)
        }

        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .eventListener,
            name: "mouseWheelCallback"
        )
        defer {
            performanceDiagnosticsRecorder.endInterval(intervalToken)
        }

        guard type == .scrollWheel,
              isEnabled,
              !isPostingSyntheticScroll,
              !isSyntheticEvent(event),
              let target = MouseWheelScrollPlanner.targetPixels(
                for: facts(from: event),
                naturalScrollingEnabled: naturalScrollPreferenceProvider()
              ) else {
            return Unmanaged.passUnretained(event)
        }

        enqueue(
            target,
            context: ScrollEventContext(location: event.location, flags: event.flags)
        )
        return nil
    }

    private func enqueue(
        _ incomingTarget: MouseWheelScrollTarget,
        context: ScrollEventContext
    ) {
        let hadPendingFrames = !pendingFrames.isEmpty
        let remainingTarget = MouseWheelScrollPlanner.remainingTarget(from: pendingFrames)
        let mergedTarget = MouseWheelScrollPlanner.merge(
            existing: remainingTarget,
            incoming: incomingTarget
        )
        pendingFrames = MouseWheelScrollPlanner.easedFrames(target: mergedTarget)
        pendingContext = context
        if hadPendingFrames {
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "mouseWheelBurstMerged"
            )
        }

        installTimerIfNeeded()
    }

    private func installTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: Self.frameInterval)
        timer.setEventHandler { [weak self] in
            self?.postNextFrame()
        }
        timer.resume()
        self.timer = timer
        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "mouseWheelTimerStart"
        )
    }

    private func postNextFrame() {
        guard isEnabled, !pendingFrames.isEmpty, let pendingContext else {
            pendingFrames.removeAll()
            self.pendingContext = nil
            cancelTimer()
            return
        }

        let frame = pendingFrames.removeFirst()
        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "mouseWheelGeneratedFrame"
        )
        postSyntheticScroll(frame, context: pendingContext)

        if pendingFrames.isEmpty {
            self.pendingContext = nil
            cancelTimer()
        }
    }

    private func cancelTimer() {
        if timer != nil {
            performanceDiagnosticsRecorder.recordEvent(
                category: .eventListener,
                name: "mouseWheelTimerStop"
            )
        }
        timer?.cancel()
        timer = nil
    }

    private func postSyntheticScroll(
        _ frame: MouseWheelScrollFrame,
        context: ScrollEventContext
    ) {
        guard let eventSource,
              let event = CGEvent(
                scrollWheelEvent2Source: eventSource,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(frame.deltaY),
                wheel2: Int32(frame.deltaX),
                wheel3: 0
              ) else {
            return
        }

        performanceDiagnosticsRecorder.recordEvent(
            category: .eventListener,
            name: "mouseWheelSyntheticEvent"
        )
        event.location = context.location
        event.flags = context.flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)

        isPostingSyntheticScroll = true
        defer { isPostingSyntheticScroll = false }

        event.post(tap: .cgSessionEventTap)
    }

    private func facts(from event: CGEvent) -> MouseWheelScrollEventFacts {
        MouseWheelScrollEventFacts(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            lineDeltaX: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            lineDeltaY: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
            pointDeltaX: Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
            pointDeltaY: Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        )
    }

    private func isSyntheticEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker
    }

    private static func readNaturalScrollPreference() -> Bool {
        let value = UserDefaults.standard.object(forKey: Self.naturalScrollPreferenceKey)

        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        return true
    }
}
