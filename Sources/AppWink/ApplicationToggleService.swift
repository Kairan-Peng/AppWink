import AppKit
import ApplicationServices
import AppWinkCore

private let axWindowNumberAttribute = "AXWindowNumber"
private let hideConfirmationDelay: TimeInterval = 0.05
private let hideConfirmationAttempts = 6

func appendDecisionTrace(_ line: String) {
    guard let path = ProcessInfo.processInfo.environment["APPWINK_DECISION_TRACE_FILE"],
          !path.isEmpty,
          let data = "\(line)\n".data(using: .utf8) else {
        return
    }

    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    guard let fileHandle = FileHandle(forWritingAtPath: path) else {
        return
    }

    defer {
        try? fileHandle.close()
    }

    do {
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: data)
    } catch {
        return
    }
}

private func describeApplicationToggleDecisionSnapshot(_ snapshot: ApplicationToggleDecisionSnapshot) -> String {
    switch snapshot {
    case .backgroundTarget:
        return "backgroundTarget"
    case .frontmostImmersive:
        return "frontmostImmersive"
    case .frontmostNormalWithVisibleRegularWindow:
        return "frontmostNormalWithVisibleRegularWindow"
    case .frontmostNormalWithoutVisibleRegularWindow:
        return "frontmostNormalWithoutVisibleRegularWindow"
    }
}

private func describeApplicationToggleDecision(_ decision: ApplicationToggleDecision) -> String {
    switch decision {
    case .hide:
        return "hide"
    case .noOpFrontmostImmersiveWindow:
        return "noOpFrontmostImmersiveWindow"
    case .systemEquivalentActivate:
        return "systemEquivalentActivate"
    }
}

/// 描述一次应用切换动作最终呈现给用户的结果。
enum ApplicationToggleResult {
    case activated(String)
    case hidden(String)

    var message: String {
        switch self {
        case .activated(let name):
            return LocalizationManager.shared.string(for: .activated).replacingOccurrences(of: "%@", with: name)
        case .hidden(let name):
            return LocalizationManager.shared.string(for: .hidden).replacingOccurrences(of: "%@", with: name)
        }
    }
}

/// 窗口切换过程中可能出现的业务级错误，用于统一给 UI 反馈友好提示。
enum ApplicationToggleError: LocalizedError {
    case applicationUnavailable(String)
    case launchFailed(String)
    case activationFailed(String)
    case hideFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable(let name):
            return LocalizationManager.shared.string(for: .applicationUnavailable).replacingOccurrences(of: "%@", with: name)
        case .launchFailed(let name):
            return LocalizationManager.shared.string(for: .launchFailed).replacingOccurrences(of: "%@", with: name)
        case .activationFailed(let name):
            return LocalizationManager.shared.string(for: .activationFailed).replacingOccurrences(of: "%@", with: name)
        case .hideFailed(let name):
            return LocalizationManager.shared.string(for: .hideFailed).replacingOccurrences(of: "%@", with: name)
        }
    }
}

@MainActor
/// 负责探测应用状态并执行激活、隐藏或沉浸态 no-op 的核心运行时服务。
final class ApplicationToggleService: ApplicationToggleServicing {
    private let decisionPolicy: ApplicationToggleDecisionPolicy
    private let systemEquivalentActivator: SystemEquivalentActivator
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder

    init(
        decisionPolicy: ApplicationToggleDecisionPolicy = ApplicationToggleDecisionPolicy(),
        systemEquivalentActivator: SystemEquivalentActivator? = nil,
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared
    ) {
        self.decisionPolicy = decisionPolicy
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
        self.systemEquivalentActivator = systemEquivalentActivator ?? SystemEquivalentActivator(
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder
        )
    }

    /// 在 trigger 时刻冻结 runtime 决策，供上层选择立即执行还是下一轮 runloop 再执行。
    func prepareToggle(
        application: ManagedApplication,
        frontmostProcessIdentifier: pid_t? = nil,
        invocationSource: ToggleInvocationSource = .manual
    ) -> PreparedApplicationToggle {
        let baseMetadata = toggleMetadata(
            application: application,
            invocationSource: invocationSource
        )

        return performanceDiagnosticsRecorder.measure(
            category: .hotkey,
            name: "prepareToggle",
            metadata: baseMetadata
        ) {
            makePreparedToggle(
                application: application,
                frontmostProcessIdentifier: frontmostProcessIdentifier,
                invocationSource: invocationSource,
                baseMetadata: baseMetadata
            )
        }
    }

    private func makePreparedToggle(
        application: ManagedApplication,
        frontmostProcessIdentifier: pid_t?,
        invocationSource: ToggleInvocationSource,
        baseMetadata: [String: String]
    ) -> PreparedApplicationToggle {
        let appName = localizedDisplayName(for: application)

        guard let url = application.resolvedURL() else {
            performanceDiagnosticsRecorder.recordEvent(
                category: .hotkey,
                name: "prepareToggleUnavailable",
                metadata: baseMetadata.merging(["failureCategory": "applicationUnavailable"]) { _, new in new }
            )
            return PreparedApplicationToggle(executionTiming: .immediate) { completion in
                completion(.failure(.applicationUnavailable(appName)))
            }
        }

        let runningApplications: [NSRunningApplication] = performanceDiagnosticsRecorder.measure(
            category: .hotkey,
            name: "runningApplicationLookup",
            metadata: baseMetadata
        ) {
            self.runningApplications(for: application)
        }
        let runningApplication = runningApplications.first
        let isTargetRunning = runningApplication != nil
        let bundleIdentifier = windowHistoryBundleIdentifier(
            for: application,
            runningApplication: runningApplication
        )
        let isFinder = isFinderApplication(
            application: application,
            runningApplication: runningApplication
        )
        var runtimeMetadata = baseMetadata
        runtimeMetadata["bundleIdentifier"] = bundleIdentifier ?? "nil"
        runtimeMetadata["isFinder"] = String(isFinder)
        runtimeMetadata["isTargetRunning"] = String(isTargetRunning)
        runtimeMetadata["runningApplicationCount"] = String(runningApplications.count)

        let presentationSnapshot: AppPresentationSnapshot = performanceDiagnosticsRecorder.measure(
            category: .hotkey,
            name: "presentationProbeSnapshot",
            metadata: runtimeMetadata
        ) {
            makePresentationProbe(
                application: application,
                runningApplications: runningApplications,
                runningApplication: runningApplication,
                frontmostProcessIdentifier: frontmostProcessIdentifier,
                bundleIdentifier: bundleIdentifier
            ).snapshot(
                isTargetRunning: isTargetRunning,
                isFinder: isFinder
            )
        }
        let decisionSnapshot = presentationSnapshot.applicationToggleDecisionSnapshot
        var decisionPolicyMetadata = runtimeMetadata
        decisionPolicyMetadata["decisionSnapshot"] = describeApplicationToggleDecisionSnapshot(decisionSnapshot)
        let decision: ApplicationToggleDecision = performanceDiagnosticsRecorder.measure(
            category: .hotkey,
            name: "decisionPolicy",
            metadata: decisionPolicyMetadata
        ) {
            decisionPolicy.decision(for: decisionSnapshot)
        }
        let executionTiming: PreparedApplicationToggleExecutionTiming =
            decision == .systemEquivalentActivate ? .nextRunLoop : .immediate
        var decisionMetadata = decisionPolicyMetadata
        decisionMetadata["decision"] = describeApplicationToggleDecision(decision)

        appendDecisionTrace(
            "toggleDecision app=\(appName) bundle=\(bundleIdentifier ?? "nil") invocation=\(String(describing: invocationSource)) running=\(presentationSnapshot.isTargetRunning) frontmost=\(presentationSnapshot.isTargetFrontmost) isFinder=\(presentationSnapshot.isFinder) presentation=\(presentationSnapshot.frontmostPresentation) visibleRegularCurrentSpace=\(presentationSnapshot.hasVisibleRegularWindowOnCurrentSpace) snapshot=\(describeApplicationToggleDecisionSnapshot(decisionSnapshot)) decision=\(describeApplicationToggleDecision(decision))"
        )

        return PreparedApplicationToggle(executionTiming: executionTiming) { completion in
            switch decision {
            case .noOpFrontmostImmersiveWindow:
                self.performanceDiagnosticsRecorder.recordEvent(
                    category: .hotkey,
                    name: "noOpResult",
                    metadata: decisionMetadata.merging(["result": "frontmostImmersive"]) { _, new in new }
                )
                completion(.success(.activated(appName)))
            case .hide:
                self.hideFrontmostApplication(
                    runningApplications: runningApplications,
                    application: application,
                    invocationSource: invocationSource,
                    completion: completion
                )
            case .systemEquivalentActivate:
                self.performSystemEquivalentActivation(
                    applicationURL: url,
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    invocationSource: invocationSource,
                    wasRunning: isTargetRunning,
                    completion: completion
                )
            }
        }
    }

    private func makePresentationProbe(
        application: ManagedApplication,
        runningApplications: [NSRunningApplication],
        runningApplication: NSRunningApplication?,
        frontmostProcessIdentifier: pid_t?,
        bundleIdentifier: String?
    ) -> AppPresentationProbe {
        AppPresentationProbe(
            isTargetFrontmost: { [self] in
                isFrontmost(
                    application: application,
                    runningApplications: runningApplications,
                    frontmostProcessIdentifier: frontmostProcessIdentifier
                )
            },
            frontmostPresentation: { [self] in
                guard let runningApplication else {
                    return .normal
                }

                return frontmostPresentation(
                    for: runningApplication,
                    bundleIdentifier: bundleIdentifier
                )
            },
            nonFinderVisibleRegularWindowOnCurrentSpace: { [self] in
                guard let runningApplication else {
                    return false
                }

                return hasVisibleRegularWindowOnCurrentSpaceForNonFinder(
                    for: runningApplication,
                    bundleIdentifier: bundleIdentifier,
                    currentSpaceID: WindowSpaceBridge.live.currentSpaceID()
                )
            },
            finderVisibleRegularWindowOnCurrentSpace: { [self] in
                guard let runningApplication else {
                    return false
                }

                return hasVisibleRegularWindowOnCurrentSpaceForFinder(
                    for: runningApplication,
                    bundleIdentifier: bundleIdentifier,
                    currentSpaceID: WindowSpaceBridge.live.currentSpaceID()
                )
            }
        )
    }

    private func isFinderApplication(
        application: ManagedApplication,
        runningApplication: NSRunningApplication?
    ) -> Bool {
        (runningApplication?.bundleIdentifier ?? application.bundleIdentifier) == "com.apple.finder"
    }

    private func performSystemEquivalentActivation(
        applicationURL: URL,
        appName: String,
        bundleIdentifier: String?,
        invocationSource: ToggleInvocationSource,
        wasRunning: Bool,
        completion: @escaping @MainActor (Result<ApplicationToggleResult, ApplicationToggleError>) -> Void
    ) {
        let metadata = toggleMetadata(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            invocationSource: invocationSource
        ).merging([
            "wasRunning": String(wasRunning),
        ]) { _, new in new }
        performanceDiagnosticsRecorder.recordEvent(
            category: .hotkey,
            name: "systemEquivalentActivationRequest",
            metadata: metadata
        )
        systemEquivalentActivator.activate(applicationURL: applicationURL) { result in
            Task { @MainActor in
                switch result {
                case .activated:
                    completion(.success(.activated(appName)))
                case .failed:
                    completion(.failure(wasRunning ? .activationFailed(appName) : .launchFailed(appName)))
                }
            }
        }
    }

    /// 优先通过 bundle identifier 查找运行实例，找不到时再退化到 bundle URL 比对。
    func runningApplications(for application: ManagedApplication) -> [NSRunningApplication] {
        if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            if !apps.isEmpty {
                return apps
            }
        }

        guard let resolvedURL = application.resolvedURL()?.standardizedFileURL else {
            return []
        }

        return NSWorkspace.shared.runningApplications.filter { runningApplication in
            runningApplication.bundleURL?.standardizedFileURL == resolvedURL
        }
    }

    private func toggleMetadata(
        application: ManagedApplication,
        invocationSource: ToggleInvocationSource
    ) -> [String: String] {
        toggleMetadata(
            appName: application.displayName,
            bundleIdentifier: application.bundleIdentifier,
            invocationSource: invocationSource
        )
    }

    private func localizedDisplayName(for application: ManagedApplication) -> String {
        application.localizedDisplayName(for: LocalizationManager.shared.currentLanguage)
    }

    private func toggleMetadata(
        appName: String,
        bundleIdentifier: String?,
        invocationSource: ToggleInvocationSource
    ) -> [String: String] {
        var metadata = [
            "appDisplayName": appName,
            "invocationSource": invocationSource == .hotKey ? "hotKey" : "manual",
        ]
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            metadata["bundleIdentifier"] = bundleIdentifier
        }
        return metadata
    }

    private func copyAXAttribute(
        _ attribute: String,
        from element: AXUIElement,
        visibilityGroup: String? = nil
    ) -> (status: AXError, value: CFTypeRef?) {
        var metadata = ["attribute": attribute]
        if let visibilityGroup {
            metadata["visibilityGroup"] = visibilityGroup
        }

        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .systemQuery,
            name: "axCopyAttribute",
            metadata: metadata
        )
        var rawValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &rawValue)

        if intervalToken != nil, status != .success {
            performanceDiagnosticsRecorder.recordEvent(
                category: .systemQuery,
                name: "axCopyAttribute.failure",
                metadata: metadata.merging(["statusCode": String(status.rawValue)]) { _, new in new }
            )
        }
        performanceDiagnosticsRecorder.endInterval(intervalToken)

        return (status, rawValue)
    }

    private func copyWindowInfo(
        option: CGWindowListOption,
        visibilityGroup: String? = nil
    ) -> [[String: Any]]? {
        var metadata = ["option": String(option.rawValue)]
        if let visibilityGroup {
            metadata["visibilityGroup"] = visibilityGroup
        }

        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .systemQuery,
            name: "windowListCopy",
            metadata: metadata
        )
        let windowInfoList = CGWindowListCopyWindowInfo(
            option,
            kCGNullWindowID
        ) as? [[String: Any]]

        if intervalToken != nil, windowInfoList == nil {
            performanceDiagnosticsRecorder.recordEvent(
                category: .systemQuery,
                name: "windowListCopy.failure",
                metadata: metadata
            )
        }
        performanceDiagnosticsRecorder.endInterval(intervalToken)

        return windowInfoList
    }

    /// 综合回调携带的前台 PID、辅助功能信息和系统前台应用，尽量准确判断目标是否已聚焦。
    private func isFrontmost(
        application: ManagedApplication,
        runningApplications: [NSRunningApplication],
        frontmostProcessIdentifier: pid_t?
    ) -> Bool {
        if let frontmostProcessIdentifier,
           runningApplications.contains(where: { $0.processIdentifier == frontmostProcessIdentifier }) {
            return true
        }

        if runningApplications.contains(where: isAccessibilityFrontmost) {
            return true
        }

        if runningApplications.contains(where: \.isActive) {
            return true
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        if let bundleIdentifier = application.bundleIdentifier,
           !bundleIdentifier.isEmpty,
           frontmostApplication.bundleIdentifier == bundleIdentifier {
            return true
        }

        if let frontmostURL = frontmostApplication.bundleURL?.standardizedFileURL,
           runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == frontmostURL }) {
            return true
        }

        return false
    }

    private func hideFrontmostApplication(
        runningApplications: [NSRunningApplication],
        application: ManagedApplication,
        invocationSource: ToggleInvocationSource,
        completion: @escaping @MainActor (Result<ApplicationToggleResult, ApplicationToggleError>) -> Void
    ) {
        let appName = localizedDisplayName(for: application)

        guard let runningApplication = runningApplications.first else {
            completion(.failure(.applicationUnavailable(appName)))
            return
        }

        let didRequestHide = runningApplication.hide()
        performanceDiagnosticsRecorder.recordEvent(
            category: .hotkey,
            name: "hideRequest",
            metadata: toggleMetadata(
                application: application,
                invocationSource: invocationSource
            ).merging([
                "bundleIdentifier": runningApplication.bundleIdentifier ?? application.bundleIdentifier ?? "nil",
                "hideReturn": String(didRequestHide),
            ]) { _, new in new }
        )

        appendDecisionTrace(
            "hideFrontmostApplication request app=\(appName) pid=\(runningApplication.processIdentifier) hideReturn=\(didRequestHide) hidden=\(runningApplication.isHidden) active=\(runningApplication.isActive)"
        )

        confirmHiddenState(
            runningApplication: runningApplication,
            appName: appName,
            invocationSource: invocationSource,
            didRequestHide: didRequestHide,
            remainingAttempts: hideConfirmationAttempts,
            completion: completion)
    }

    private func confirmHiddenState(
        runningApplication: NSRunningApplication,
        appName: String,
        invocationSource: ToggleInvocationSource,
        didRequestHide: Bool,
        remainingAttempts: Int,
        completion: @escaping @MainActor (Result<ApplicationToggleResult, ApplicationToggleError>) -> Void
    ) {
        performanceDiagnosticsRecorder.recordEvent(
            category: .hotkey,
            name: "hideConfirmationAttempt",
            metadata: toggleMetadata(
                appName: appName,
                bundleIdentifier: runningApplication.bundleIdentifier,
                invocationSource: invocationSource
            ).merging([
                "remainingAttempts": String(remainingAttempts),
                "isHidden": String(runningApplication.isHidden),
            ]) { _, new in new }
        )

        if runningApplication.isHidden {
            appendDecisionTrace(
                "hideFrontmostApplication confirmed app=\(appName) pid=\(runningApplication.processIdentifier) hideReturn=\(didRequestHide) remainingAttempts=\(remainingAttempts)"
            )
            completion(.success(.hidden(appName)))
            return
        }

        guard remainingAttempts > 0 else {
            appendDecisionTrace(
                "hideFrontmostApplication failed app=\(appName) pid=\(runningApplication.processIdentifier) hideReturn=\(didRequestHide) hidden=\(runningApplication.isHidden) active=\(runningApplication.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")"
            )
            completion(.failure(.hideFailed(appName)))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + hideConfirmationDelay) { [weak self] in
            guard let self else {
                return
            }

            self.confirmHiddenState(
                runningApplication: runningApplication,
                appName: appName,
                invocationSource: invocationSource,
                didRequestHide: didRequestHide,
                remainingAttempts: remainingAttempts - 1,
                completion: completion)
        }
    }

    private func windowHistoryBundleIdentifier(
        for application: ManagedApplication,
        runningApplication: NSRunningApplication?
    ) -> String? {
        if let bundleIdentifier = application.bundleIdentifier,
           !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        if let bundleIdentifier = runningApplication?.bundleIdentifier,
           !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        return nil
    }

    private func usableWindowElements(for runningApplication: NSRunningApplication) -> [AXUIElement] {
        if runningApplication.bundleIdentifier == "com.apple.finder" {
            return finderWindowElements(for: runningApplication)
        }

        return preferredWindowElements(for: runningApplication)
    }

    private func windowIdentity(
        for window: AXUIElement?,
        processIdentifier: pid_t,
        bundleIdentifier: String?
    ) -> WindowIdentity? {
        guard let window,
              let bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }

        return windowIdentity(
            for: window,
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier)
    }

    private func windowIdentity(
        for window: AXUIElement,
        processIdentifier: pid_t,
        bundleIdentifier: String
    ) -> WindowIdentity? {
        let directWindowNumber = directWindowNumber(for: window)
        let windowNumber: Int?

        if bundleIdentifier == "com.apple.finder" {
            let title = windowTitle(for: window)
            let bounds = windowFrame(for: window)
            windowNumber = AccessibilityWindowIdentityResolver.resolveWindowNumber(
                directWindowNumber: directWindowNumber,
                title: title,
                bounds: bounds,
                preferredWindowNumbers: currentSpaceWindowServerWindowNumbers(
                    forProcessIdentifier: processIdentifier),
                candidates: accessibilityWindowIdentityCandidates(
                    forProcessIdentifier: processIdentifier))

            if directWindowNumber == nil,
               let windowNumber {
                appendDecisionTrace(
                    "finderWindowIdentity fallback title=\(title ?? "nil") frame=\(bounds.map(NSStringFromRect) ?? "nil") resolved=\(windowNumber)"
                )
            }
        } else {
            windowNumber = directWindowNumber
        }

        guard let windowNumber else {
            return nil
        }

        return WindowIdentity(
            processIdentifier: processIdentifier,
            windowNumber: windowNumber,
            bundleIdentifier: bundleIdentifier)
    }

    private func directWindowNumber(for window: AXUIElement) -> Int? {
        let result = copyAXAttribute(axWindowNumberAttribute, from: window)

        guard result.status == .success,
              let number = result.value as? NSNumber else {
            return nil
        }

        return number.intValue
    }

    private func windowTitle(for window: AXUIElement) -> String? {
        let result = copyAXAttribute(kAXTitleAttribute, from: window)

        guard result.status == .success else {
            return nil
        }

        return result.value as? String
    }

    private func windowFrame(for window: AXUIElement) -> CGRect? {
        let positionResult = copyAXAttribute(kAXPositionAttribute, from: window)
        let sizeResult = copyAXAttribute(kAXSizeAttribute, from: window)

        guard positionResult.status == .success,
              sizeResult.status == .success,
              let positionValue = positionResult.value,
              let sizeValue = sizeResult.value,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            unsafeDowncast(positionValue, to: AXValue.self),
            .cgPoint,
            &origin),
            AXValueGetValue(
                unsafeDowncast(sizeValue, to: AXValue.self),
                .cgSize,
                &size) else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private func accessibilityWindowIdentityCandidates(
        forProcessIdentifier processIdentifier: pid_t
    ) -> [AccessibilityWindowIdentityCandidate] {
        guard let windowInfoList = copyWindowInfo(option: [.optionAll, .excludeDesktopElements]) else {
            return []
        }

        return windowInfoList.compactMap { windowInfo in
            guard let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == processIdentifier,
                  let windowNumber = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.intValue else {
                return nil
            }

            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else {
                return nil
            }

            return AccessibilityWindowIdentityCandidate(
                windowNumber: windowNumber,
                title: windowInfo[kCGWindowName as String] as? String,
                bounds: (windowInfo[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap(CGRect.init(dictionaryRepresentation:)))
        }
    }

    private func currentSpaceWindowServerWindowNumbers(
        forProcessIdentifier processIdentifier: pid_t
    ) -> Set<Int> {
        guard let currentSpaceID = WindowSpaceBridge.live.currentSpaceID(),
              let windowInfoList = copyWindowInfo(option: [.optionAll, .excludeDesktopElements]) else {
            return []
        }

        let windowSpaceBridge = WindowSpaceBridge.live

        return Set(windowInfoList.compactMap { windowInfo in
            guard let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == processIdentifier,
                  let windowNumber = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.intValue else {
                return nil
            }

            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  windowSpaceBridge.spaceIDs(containing: windowNumber).contains(currentSpaceID) else {
                return nil
            }

            return windowNumber
        })
    }

    private func currentSpaceOnScreenWindowServerWindowNumbers(
        forProcessIdentifier processIdentifier: pid_t,
        currentSpaceID: UInt64
    ) -> Set<Int> {
        guard let windowInfoList = copyWindowInfo(
            option: [.optionOnScreenOnly, .excludeDesktopElements],
            visibilityGroup: "nonFinder"
        ) else {
            return []
        }

        let windowSpaceBridge = WindowSpaceBridge.live

        return Set(windowInfoList.compactMap { windowInfo in
            guard let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == processIdentifier,
                  let windowNumber = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.intValue else {
                return nil
            }

            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  windowSpaceBridge.spaceIDs(containing: windowNumber).contains(currentSpaceID) else {
                return nil
            }

            return windowNumber
        })
    }

    /// Finder 在 AX 不可用时，仍可能通过 window-server 暴露当前 Space 的真实浏览器窗口。
    /// 这里把这些当前 Space 命中的 layer-0 窗口保留下来，作为“已有 Finder 窗口”的最后一层证据。
    private func finderCurrentSpaceWindowServerWindowNumbers(for runningApplication: NSRunningApplication) -> [Int] {
        guard let currentSpaceID = WindowSpaceBridge.live.currentSpaceID(),
              let windowInfoList = copyWindowInfo(
                  option: [.optionAll, .excludeDesktopElements],
                  visibilityGroup: "finder"
              ) else {
            return []
        }

        let windowSpaceBridge = WindowSpaceBridge.live
        let windowFilter = FinderWindowServerWindowFilter()

        return windowInfoList.compactMap { windowInfo in
            guard let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == runningApplication.processIdentifier,
                  let windowNumber = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.intValue else {
                return nil
            }

            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  windowSpaceBridge.spaceIDs(containing: windowNumber).contains(currentSpaceID) else {
                return nil
            }

            let bounds = (windowInfo[kCGWindowBounds as String] as? NSDictionary)
                .flatMap(CGRect.init(dictionaryRepresentation:))
            guard windowFilter.isBrowserWindow(bounds: bounds) else {
                return nil
            }

            return windowNumber
        }
    }

    private func hasVisibleRegularWindowOnCurrentSpaceForNonFinder(
        for runningApplication: NSRunningApplication,
        bundleIdentifier: String?,
        currentSpaceID: UInt64?
    ) -> Bool {
        guard let currentSpaceID else {
            return true
        }

        guard isAccessibilityPermissionGranted() else {
            return true
        }

        let currentSpaceWindowServerWindowCount = currentSpaceOnScreenWindowServerWindowNumbers(
            forProcessIdentifier: runningApplication.processIdentifier,
            currentSpaceID: currentSpaceID
        ).count

        let accessibilityDerivedVisibility: Bool? = {
            let windows = usableWindowElements(for: runningApplication)
            guard !windows.isEmpty else {
                return nil
            }

            let effectiveBundleIdentifier = bundleIdentifier ?? runningApplication.bundleIdentifier
            let windowSpaceBridge = WindowSpaceBridge.live

            for window in windows where !isWindowMinimized(window) {
                guard let effectiveBundleIdentifier,
                      !effectiveBundleIdentifier.isEmpty,
                      let identity = windowIdentity(
                          for: window,
                          processIdentifier: runningApplication.processIdentifier,
                          bundleIdentifier: effectiveBundleIdentifier) else {
                    // 无法可靠识别这个可见窗口时，保守地维持旧行为，避免把正常前台窗口误判成“无窗”。
                    return true
                }

                if windowSpaceBridge.spaceIDs(containing: identity.windowNumber).contains(currentSpaceID) {
                    return true
                }
            }

            return false
        }()

        let isVisibleOnCurrentSpace = NonFinderCurrentSpaceVisibilityPolicy().hasVisibleWindowOnCurrentSpace(
            accessibilityDerivedVisibility: accessibilityDerivedVisibility,
            currentSpaceWindowServerWindowCount: currentSpaceWindowServerWindowCount
        )

        appendDecisionTrace(
            "nonFinderCurrentSpaceVisibility axDerived=\(accessibilityDerivedVisibility.map(String.init) ?? "nil") currentSpaceWindowServer=\(currentSpaceWindowServerWindowCount) visible=\(isVisibleOnCurrentSpace)"
        )

        return isVisibleOnCurrentSpace
    }

    private func hasVisibleRegularWindowOnCurrentSpaceForFinder(
        for runningApplication: NSRunningApplication,
        bundleIdentifier: String?,
        currentSpaceID: UInt64?
    ) -> Bool {
        guard let currentSpaceID else {
            return true
        }

        return hasVisibleFinderWindowOnCurrentSpace(
            for: runningApplication,
            bundleIdentifier: bundleIdentifier,
            currentSpaceID: currentSpaceID
        )
    }

    private func hasVisibleFinderWindowOnCurrentSpace(
        for runningApplication: NSRunningApplication,
        bundleIdentifier: String?,
        currentSpaceID: UInt64
    ) -> Bool {
        let currentSpaceWindowServerWindowCount = finderCurrentSpaceWindowServerWindowNumbers(
            for: runningApplication
        ).count

        let accessibilityDerivedVisibility: Bool? = {
            guard isAccessibilityPermissionGranted() else {
                return nil
            }

            let windows = finderWindowElements(for: runningApplication)
            guard !windows.isEmpty else {
                return nil
            }

            let effectiveBundleIdentifier = bundleIdentifier ?? runningApplication.bundleIdentifier
            let windowSpaceBridge = WindowSpaceBridge.live

            for window in windows where !isWindowMinimized(window) {
                guard let effectiveBundleIdentifier,
                      !effectiveBundleIdentifier.isEmpty,
                      let identity = windowIdentity(
                          for: window,
                          processIdentifier: runningApplication.processIdentifier,
                          bundleIdentifier: effectiveBundleIdentifier) else {
                    // Finder 在无法稳定识别 AX 窗口编号时，更适合退回 window-server 当前 Space 信号；
                    // 否则会把“前台桌面但无浏览器窗口”误判成可隐藏的正常窗口。
                    return nil
                }

                if windowSpaceBridge.spaceIDs(containing: identity.windowNumber).contains(currentSpaceID) {
                    return true
                }
            }

            return false
        }()

        let isVisibleOnCurrentSpace = FinderCurrentSpaceVisibilityPolicy().hasVisibleWindowOnCurrentSpace(
            accessibilityDerivedVisibility: accessibilityDerivedVisibility,
            currentSpaceWindowServerWindowCount: currentSpaceWindowServerWindowCount)

        appendDecisionTrace(
            "finderCurrentSpaceVisibility axDerived=\(accessibilityDerivedVisibility.map(String.init) ?? "nil") currentSpaceWindowServer=\(currentSpaceWindowServerWindowCount) visible=\(isVisibleOnCurrentSpace)"
        )

        return isVisibleOnCurrentSpace
    }

    private func frontmostPresentation(
        for runningApplication: NSRunningApplication,
        bundleIdentifier: String?
    ) -> FrontmostWindowPresentation {
        guard let primaryWindow = primaryWindow(for: runningApplication),
              let effectiveBundleIdentifier = bundleIdentifier ?? runningApplication.bundleIdentifier,
              !effectiveBundleIdentifier.isEmpty,
              let frontmostWindow = windowIdentity(
                  for: primaryWindow,
                  processIdentifier: runningApplication.processIdentifier,
                  bundleIdentifier: effectiveBundleIdentifier) else {
            return .normal
        }

        return WindowSpaceBridge.live.currentPresentation(containing: frontmostWindow.windowNumber)
    }

    /// 读取应用暴露的所有窗口元素，供最小化和恢复逻辑复用。
    private func windowElements(for runningApplication: NSRunningApplication) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
        let result = copyAXAttribute(kAXWindowsAttribute, from: appElement)

        guard result.status == .success, let windows = result.value as? [AXUIElement] else {
            return []
        }

        return windows
    }

    /// 优先筛出标准主窗口和对话框，尽量跳过不可恢复的辅助面板。
    private func preferredWindowElements(for runningApplication: NSRunningApplication) -> [AXUIElement] {
        let windows = windowElements(for: runningApplication)
        let preferredWindows = windows.filter(isRestorableWindow)
        return preferredWindows.isEmpty ? windows : preferredWindows
    }

    /// 只把标准窗口和对话框视为"可恢复窗口"，其它子角色默认不拦截，保持兼容性。
    private func isRestorableWindow(_ window: AXUIElement) -> Bool {
        let result = copyAXAttribute(kAXSubroleAttribute, from: window)

        guard result.status == .success else {
            return true
        }

        let subrole = result.value as? String
        return subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
    }

    /// 辅助功能能提供比 `NSRunningApplication.isActive` 更可靠的前台判断。
    private func isAccessibilityFrontmost(_ runningApplication: NSRunningApplication) -> Bool {
        guard isAccessibilityPermissionGranted() else {
            return false
        }

        let appElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
        let result = copyAXAttribute(kAXFrontmostAttribute, from: appElement)

        guard result.status == .success,
              let value = result.value as? NSNumber else {
            return false
        }

        return value.boolValue
    }

    private func finderWindowElements(for runningApplication: NSRunningApplication) -> [AXUIElement] {
        preferredWindowElements(for: runningApplication).filter(isFinderBrowserWindow)
    }

    private func primaryWindow(for runningApplication: NSRunningApplication) -> AXUIElement? {
        let windows = runningApplication.bundleIdentifier == "com.apple.finder"
            ? finderWindowElements(for: runningApplication)
            : preferredWindowElements(for: runningApplication)
        return windows.first(where: isWindowMain)
            ?? windows.first(where: isWindowFocused)
            ?? windows.first(where: { !isWindowMinimized($0) })
            ?? windows.first
    }

    private func isFinderBrowserWindow(_ window: AXUIElement) -> Bool {
        isRestorableWindow(window) && hasWindowCloseButton(window)
    }

    private func hasWindowCloseButton(_ window: AXUIElement) -> Bool {
        let result = copyAXAttribute(kAXCloseButtonAttribute, from: window)

        return result.status == .success && result.value != nil
    }

    private func isWindowMinimized(_ window: AXUIElement) -> Bool {
        let result = copyAXAttribute(kAXMinimizedAttribute, from: window)

        guard result.status == .success,
              let value = result.value as? NSNumber else {
            return false
        }

        return value.boolValue
    }

    private func isWindowFocused(_ window: AXUIElement) -> Bool {
        let result = copyAXAttribute(kAXFocusedAttribute, from: window)

        guard result.status == .success,
              let value = result.value as? NSNumber else {
            return false
        }

        return value.boolValue
    }

    private func isWindowMain(_ window: AXUIElement) -> Bool {
        let result = copyAXAttribute(kAXMainAttribute, from: window)

        guard result.status == .success,
              let value = result.value as? NSNumber else {
            return false
        }

        return value.boolValue
    }

    /// 权限检查封装成单点，便于未来替换为带缓存或埋点的实现。
    private func isAccessibilityPermissionGranted() -> Bool {
        AccessibilityPermissionChecker.isGranted()
    }
}
