import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AppWinkCore

@MainActor
/// 设置页和运行时共享的主模型，负责配置持久化、校验、热键注册和状态提示。
final class AppModel: ObservableObject {
    private struct ConfigurationDiagnosticsCounts {
        let bindingCount: Int
        let invalidBindingCount: Int
        let duplicateConflictCount: Int
        let registerableShortcutCount: Int
    }

    private struct HotKeyDiagnosticsContext {
        let intervalToken: PerformanceDiagnosticsIntervalToken?
        let metadata: [String: String]
    }

    private struct RuntimeInvalidBinding {
        let target: HotkeyTarget
        let availability: HotkeyTargetAvailability
    }

    private struct TargetPresentationCacheKey: Hashable {
        let target: HotkeyTarget
        let languageRawValue: String
        let availability: HotkeyTargetAvailability
    }

    private struct CachedTargetPresentation {
        let key: TargetPresentationCacheKey
        let presentation: HotkeyTargetPresentation
    }

    private struct CachedBindingAvailability: Equatable {
        let target: HotkeyTarget
        let availability: HotkeyTargetAvailability
    }

    @Published private(set) var configuration: AppConfiguration
    @Published private(set) var validationMessages: [String] = []
    @Published private(set) var shortcutConflictMessages: [String] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var accessibilityPermissionGranted: Bool
    @Published private(set) var settingsWindowRoute: SettingsWindowRoute = .settings
    @Published private(set) var launchAtLoginState: LaunchAtLoginState
    @Published private(set) var hotkeyGuideIsRequested: Bool = false
    @Published private(set) var isPerformanceDiagnosticsPresented = false

    var currentLanguage: AppLanguage {
        configuration.language
    }

    var appearanceMode: AppAppearanceMode {
        configuration.appearanceMode
    }

    private let localizationManager: LocalizationManager
    private let store: UserDefaultsAppConfigurationStore
    private let hotKeyManager: any GlobalHotKeyManaging
    private let applicationToggleService: any ApplicationToggleServicing
    private let bindingActionExecutor: any BindingActionExecuting
    private let activityMonitorApplicationProvider: @MainActor () -> ManagedApplication?
    private let finderWindowsCutPasteService: FinderWindowsCutPasteService
    private let launchAtLoginController: LaunchAtLoginControlling
    private let accessibilityPermissionStatusProvider: @MainActor () -> Bool
    private let hotkeyGuideStore: any HotkeyGuideStateStoring
    private let bindingOpenModeCatalog: BindingOpenModeCatalog
    private let targetPresentationResolver: HotkeyTargetPresentationResolver
    private let staticBindingAvailabilityProvider:
        ((HotkeyBinding) -> HotkeyTargetAvailability)?
    private let configurationSaver: (AppConfiguration) throws -> Void
    let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder
    var beforeBindingAction: (() -> Void)?
    var hotKeyTargetFlashDidTrigger: ((HotKeyTargetFlashPayload) -> Void)?
    var pressedKeysOverlaySettingsDidChange: (() -> Void)?
    var virtualKeyboardSettingsDidChange: (() -> Void)?
    var hiddenBarSettingsDidChange: (() -> Void)?
    var networkStatusSettingsDidChange: (() -> Void)?
    var mouseWheelScrollSettingsDidChange: (() -> Void)?
    private var mainWindowPresenter: (() -> Void)?
    private var settingsWindowPresenter: (() -> Void)?

    private var invalidBindingIDs: Set<UUID> = []
    private var runtimeInvalidBindingByBindingID:
        [UUID: RuntimeInvalidBinding] = [:]
    private var targetPresentationCache:
        [UUID: CachedTargetPresentation] = [:]
    private var bindingAvailabilityCache:
        [UUID: CachedBindingAvailability] = [:]
    private var bindingActionGenerationByBindingID: [UUID: UUID] = [:]
    private var duplicateShortcutBindingIDs: Set<UUID> = []
    private var conflictingBindingIDsByBindingID: [UUID: Set<UUID>] = [:]
    private var pendingStatusDismissWorkItem: DispatchWorkItem?
    private var isShortcutRecordingActive = false
    /// 启动时加载配置，并同步初始化校验结果、权限状态和热键注册。
    init(
        store: UserDefaultsAppConfigurationStore = UserDefaultsAppConfigurationStore(),
        hotKeyManager: any GlobalHotKeyManaging = GlobalHotKeyManager(),
        applicationToggleService: any ApplicationToggleServicing = ApplicationToggleService(),
        bindingActionExecutor: (any BindingActionExecuting)? = nil,
        activityMonitorApplicationProvider: @escaping @MainActor () -> ManagedApplication? = {
            ActivityMonitorHotKeyFeature.makeManagedApplication()
        },
        finderWindowsCutPasteService: FinderWindowsCutPasteService? = nil,
        launchAtLoginController: LaunchAtLoginControlling = LaunchAtLoginController(),
        hotkeyGuideStore: any HotkeyGuideStateStoring = UserDefaultsHotkeyGuideStateStore(),
        performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared,
        localizationManager: LocalizationManager = .shared,
        accessibilityPermissionStatusProvider: @escaping @MainActor () -> Bool = AccessibilityPermissionChecker.isGranted,
        bindingOpenModeCatalog: BindingOpenModeCatalog = BindingOpenModeCatalog(),
        targetPresentationResolver: HotkeyTargetPresentationResolver? = nil,
        staticBindingAvailabilityProvider:
            ((HotkeyBinding) -> HotkeyTargetAvailability)? = nil,
        configurationSaver: ((AppConfiguration) throws -> Void)? = nil
    ) {
        self.localizationManager = localizationManager
        self.store = store
        self.hotKeyManager = hotKeyManager
        self.applicationToggleService = applicationToggleService
        self.bindingActionExecutor = bindingActionExecutor ??
            BindingActionExecutor(
                applicationToggleService: applicationToggleService
            )
        self.activityMonitorApplicationProvider = activityMonitorApplicationProvider
        self.finderWindowsCutPasteService = finderWindowsCutPasteService ?? FinderWindowsCutPasteService(
            performanceDiagnosticsRecorder: performanceDiagnosticsRecorder
        )
        self.launchAtLoginController = launchAtLoginController
        self.accessibilityPermissionStatusProvider = accessibilityPermissionStatusProvider
        self.hotkeyGuideStore = hotkeyGuideStore
        self.bindingOpenModeCatalog = bindingOpenModeCatalog
        self.targetPresentationResolver = targetPresentationResolver ??
            HotkeyTargetPresentationResolver(catalog: bindingOpenModeCatalog)
        self.staticBindingAvailabilityProvider =
            staticBindingAvailabilityProvider
        self.configurationSaver = configurationSaver ?? {
            try store.save($0)
        }
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
        self.accessibilityPermissionGranted = accessibilityPermissionStatusProvider()
        self.launchAtLoginState = launchAtLoginController.status()

        let loadErrorMessage: String?
        let loadIntervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .configuration,
            name: "load"
        )
        do {
            let loadedConfiguration = try store.load()
            self.configuration = loadedConfiguration
            performanceDiagnosticsRecorder.endInterval(
                loadIntervalToken,
                metadata: loadIntervalToken == nil
                    ? [:]
                    : configurationDiagnosticsMetadata(for: loadedConfiguration)
            )
            loadErrorMessage = nil
        } catch {
            self.configuration = AppConfiguration()
            performanceDiagnosticsRecorder.endInterval(
                loadIntervalToken,
                metadata: loadIntervalToken == nil
                    ? [:]
                    : configurationDiagnosticsMetadata(for: configuration)
            )
            loadErrorMessage = localizationManager.string(
                for: .configurationLoadFailed,
                arguments: error.localizedDescription
            )
        }

        // 初始化语言设置
        localizationManager.setLanguage(configuration.language)
        persistNormalizedConfigurationIfNeeded()
        applyApplicationAppearance()

        refreshAccessibilityPermissionStatus()

        if let loadErrorMessage {
            setStatusMessage(loadErrorMessage)
        }
    }

    var bindings: [HotkeyBinding] {
        configuration.bindings
    }

    var hasBindings: Bool {
        !bindings.isEmpty
    }

    func localizedDisplayName(for application: ManagedApplication) -> String {
        application.localizedDisplayName(for: currentLanguage)
    }

    func targetDisplayName(for binding: HotkeyBinding) -> String {
        switch binding.target {
        case .application(let application):
            if binding.source == .activityMonitorFeature {
                return localized(.activityMonitor)
            }

            return localizedDisplayName(for: application)
        case .folder(let item, _), .file(let item, _):
            return item.displayName
        }
    }

    var shouldShowAccessibilityPermissionCallout: Bool {
        usesAccessibilityRuntimeFeatures && !accessibilityPermissionGranted
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginState.isEnabled
    }

    var currentVersionText: String {
        let infoDictionary = Bundle.main.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String

        guard let version, !version.isEmpty else {
            return "Development Build"
        }

        return version
    }

    var windowsStyleCutEnabled: Bool {
        configuration.windowsStyleCutEnabled
    }

    var mouseWheelWindowsScrollEnabled: Bool {
        configuration.mouseWheelWindowsScrollEnabled
    }

    var pressedKeysOverlayEnabled: Bool {
        configuration.pressedKeysOverlayEnabled
    }

    var advancedHotkeysEnabled: Bool {
        configuration.advancedHotkeysEnabled
    }

    var virtualKeyboardEnabled: Bool {
        configuration.virtualKeyboardEnabled
    }

    var virtualKeyboardRevealDelay: TimeInterval {
        configuration.virtualKeyboardRevealDelay
    }

    var hotKeyIconFlashEnabled: Bool {
        configuration.hotKeyIconFlashEnabled
    }

    var hiddenBarEnabled: Bool {
        configuration.hiddenBarEnabled
    }

    var networkStatusEnabled: Bool {
        configuration.networkStatusEnabled
    }

    var activityMonitorHotKeyEnabled: Bool {
        configuration.activityMonitorHotKeyEnabled
    }

    var windowsStyleCutRuntimeEnabled: Bool {
        configuration.windowsStyleCutEnabled
    }

    var mouseWheelWindowsScrollRuntimeEnabled: Bool {
        configuration.mouseWheelWindowsScrollEnabled
    }

    var pressedKeysOverlayRuntimeEnabled: Bool {
        configuration.pressedKeysOverlayEnabled
    }

    var virtualKeyboardRuntimeEnabled: Bool {
        configuration.virtualKeyboardEnabled
    }

    var hotKeyIconFlashRuntimeEnabled: Bool {
        configuration.hotKeyIconFlashEnabled
    }

    var hiddenBarRuntimeEnabled: Bool {
        configuration.hiddenBarEnabled
    }

    var networkStatusRuntimeEnabled: Bool {
        configuration.networkStatusEnabled
    }

    var activityMonitorHotKeyRuntimeEnabled: Bool {
        configuration.activityMonitorHotKeyEnabled
    }

    var canEditLaunchAtLogin: Bool {
        launchAtLoginState != .unavailable
    }

    var launchAtLoginHelpText: String {
        switch launchAtLoginState {
        case .enabled:
            return localized(.launchAtLoginDescription, AppBrand.displayName)
        case .disabled:
            return localized(.launchAtLoginDescription, AppBrand.displayName)
        case .requiresApproval:
            return localized(.launchAtLoginRequiresApproval, AppBrand.displayName)
        case .unavailable:
            return localized(.launchAtLoginUnavailable)
        }
    }

    func toolboxSnapshot(
        automaticUpdateChecksEnabled: Bool,
        showsAutomaticUpdateChecksControl: Bool,
        canCheckForUpdates: Bool,
        showsCheckForUpdatesAction: Bool
    ) -> ToolboxCatalogSnapshot {
        ToolboxCatalog.build(
            from: ToolboxCatalogInput(
                windowsStyleCutEnabled: configuration.windowsStyleCutEnabled,
                mouseWheelWindowsScrollEnabled: configuration.mouseWheelWindowsScrollEnabled,
                pressedKeysOverlayEnabled: configuration.pressedKeysOverlayEnabled,
                virtualKeyboardEnabled: configuration.virtualKeyboardEnabled,
                hiddenBarEnabled: configuration.hiddenBarEnabled,
                networkStatusEnabled: configuration.networkStatusEnabled,
                hotKeyIconFlashEnabled: configuration.hotKeyIconFlashEnabled,
                advancedHotkeysEnabled: configuration.advancedHotkeysEnabled,
                automaticUpdateChecksEnabled: automaticUpdateChecksEnabled,
                showsAutomaticUpdateChecksControl: showsAutomaticUpdateChecksControl,
                accessibilityPermissionGranted: accessibilityPermissionGranted,
                canEditLaunchAtLogin: canEditLaunchAtLogin,
                canCheckForUpdates: canCheckForUpdates,
                showsCheckForUpdatesAction: showsCheckForUpdatesAction,
                currentVersionText: currentVersionText
            ))
    }

    private var usesAccessibilityRuntimeFeatures: Bool {
        configuration.bindings.contains {
            $0.target.requiredPermissions.contains(.accessibility)
        } || windowsStyleCutRuntimeEnabled || activityMonitorHotKeyRuntimeEnabled
    }

    private func diagnosticsRuntimeMetadata() -> [String: String] {
        [
            "bindingCount": String(configuration.bindings.count),
            "windowsStyleCutRuntimeEnabled": String(windowsStyleCutRuntimeEnabled),
            "mouseWheelWindowsScrollRuntimeEnabled": String(mouseWheelWindowsScrollRuntimeEnabled),
            "pressedKeysOverlayRuntimeEnabled": String(pressedKeysOverlayRuntimeEnabled),
            "virtualKeyboardRuntimeEnabled": String(virtualKeyboardRuntimeEnabled),
            "hiddenBarRuntimeEnabled": String(hiddenBarRuntimeEnabled),
            "hotKeyIconFlashRuntimeEnabled": String(hotKeyIconFlashRuntimeEnabled),
            "activityMonitorHotKeyRuntimeEnabled": String(activityMonitorHotKeyRuntimeEnabled),
        ]
    }

    private func currentPerformanceDiagnosticsResourceMetadata() -> [String: String] {
        let snapshot = SystemPerformanceDiagnosticsResourceSampler().sample()
        return [
            "residentMemoryBytes": String(snapshot.residentMemoryBytes),
            "cpuTimeSeconds": String(snapshot.cpuTimeSeconds),
            "threadCount": String(snapshot.threadCount),
            "processIdentifier": String(snapshot.processIdentifier),
        ]
    }

    private func configurationDiagnosticsMetadata(
        registerableShortcutCount: Int? = nil,
        registrationFailureCount: Int = 0
    ) -> [String: String] {
        configurationDiagnosticsMetadata(
            for: configuration,
            registerableShortcutCount: registerableShortcutCount,
            registrationFailureCount: registrationFailureCount
        )
    }

    private func configurationDiagnosticsMetadata(
        for configuration: AppConfiguration,
        registerableShortcutCount: Int? = nil,
        registrationFailureCount: Int = 0
    ) -> [String: String] {
        let counts = configurationDiagnosticsCounts(for: configuration)
        return [
            "bindingCount": String(counts.bindingCount),
            "invalidBindingCount": String(counts.invalidBindingCount),
            "duplicateConflictCount": String(counts.duplicateConflictCount),
            "registerableShortcutCount": String(registerableShortcutCount ?? counts.registerableShortcutCount),
            "registrationFailureCount": String(registrationFailureCount),
        ]
    }

    private func configurationDiagnosticsCounts(for configuration: AppConfiguration) -> ConfigurationDiagnosticsCounts {
        let invalidBindingIDs = Set(
            configuration.bindings
                .filter(isBindingTargetInvalid)
                .map(\.id)
        )
        let enabledShortcutBindings = configuration.bindings.filter {
            $0.isEnabled &&
            $0.shortcut != nil &&
            !invalidBindingIDs.contains($0.id) &&
            bindingParticipatesInRuntime($0, configuration: configuration)
        }
        let duplicateShortcutGroups = Dictionary(grouping: enabledShortcutBindings) { binding in
            binding.shortcut!
        }
            .values
            .filter { $0.count > 1 }
        let duplicateBindingIDs = Set(duplicateShortcutGroups.flatMap { $0.map(\.id) })
        let registerableBindingCount = enabledShortcutBindings.filter {
            !duplicateBindingIDs.contains($0.id) &&
                requiredPermissionsAreGranted(for: $0.target)
        }.count

        return ConfigurationDiagnosticsCounts(
            bindingCount: configuration.bindings.count,
            invalidBindingCount: invalidBindingIDs.count,
            duplicateConflictCount: duplicateBindingIDs.count,
            registerableShortcutCount: registerableBindingCount
        )
    }

    func setMainWindowPresenter(_ presenter: @escaping () -> Void) {
        mainWindowPresenter = presenter
    }

    func setSettingsWindowPresenter(_ presenter: @escaping () -> Void) {
        settingsWindowPresenter = presenter
    }

    func openHotkeyConfiguration(
        showsRegistrationFailureBanner: Bool = true
    ) {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "hotkeyWindowOpenRequested"
        )
        refreshAccessibilityPermissionStatus(
            showsRegistrationFailureBanner:
                showsRegistrationFailureBanner
        )
        mainWindowPresenter?()
    }

    func openSettingsWindow() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "settingsWindowOpenRequested"
        )
        refreshAccessibilityPermissionStatus()
        settingsWindowRoute = .settings
        settingsWindowPresenter?()
    }

    func showSettingsWindowHome() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "settingsHomeOpened"
        )
        refreshAccessibilityPermissionStatus()
        settingsWindowRoute = .settings
    }

    func showSettingsFeature(_ kind: ToolboxToggleKind) {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "settingsFeatureOpened.\(kind.rawValue)"
        )
        refreshAccessibilityPermissionStatus()
        settingsWindowRoute = .feature(kind)
    }

    func showSettingsWindowHelp() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "settingsHelpOpened"
        )
        refreshAccessibilityPermissionStatus()
        settingsWindowRoute = .help
    }

    func openPerformanceDiagnostics() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "diagnosticsSurfaceOpened"
        )
        isPerformanceDiagnosticsPresented = true
    }

    func openPerformanceDiagnosticsFromVersionRow() {
        performanceDiagnosticsRecorder.recordSessionEvent(
            category: .uiTransition,
            name: "diagnosticsOpenedFromVersionRow"
        )
        openPerformanceDiagnostics()
    }

    func dismissPerformanceDiagnostics() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "diagnosticsSurfaceClosed"
        )
        isPerformanceDiagnosticsPresented = false
    }

    func startPerformanceDiagnosticsSampling(round: PerformanceDiagnosticsRound) {
        performanceDiagnosticsRecorder.startSampling(round: round)
        performanceDiagnosticsRecorder.recordEvent(
            category: .resource,
            name: "samplingStart",
            metadata: currentPerformanceDiagnosticsResourceMetadata()
        )
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "diagnosticsSamplingStarted",
            metadata: diagnosticsRuntimeMetadata()
        )
        objectWillChange.send()
    }

    func stopPerformanceDiagnosticsSampling() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .resource,
            name: "samplingStop",
            metadata: currentPerformanceDiagnosticsResourceMetadata()
        )
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "diagnosticsSamplingStopped"
        )
        performanceDiagnosticsRecorder.stopSampling()
        objectWillChange.send()
    }

    func clearPerformanceDiagnosticsSession() {
        performanceDiagnosticsRecorder.clearSession()
        objectWillChange.send()
    }

    func updatePerformanceDiagnosticsNotes(_ notes: String) {
        performanceDiagnosticsRecorder.updateNotes(notes)
        objectWillChange.send()
    }

    func performanceDiagnosticsSnapshot() -> PerformanceDiagnosticsSnapshot {
        performanceDiagnosticsRecorder.snapshot()
    }

    func recordPerformanceDiagnosticsReportExportSucceeded() {
        performanceDiagnosticsRecorder.recordSessionEvent(
            category: .report,
            name: "exportSucceeded"
        )
        objectWillChange.send()
    }

    func recordPerformanceDiagnosticsReportExportFailed(errorType: String) {
        performanceDiagnosticsRecorder.recordSessionEvent(
            category: .report,
            name: "exportFailed",
            metadata: ["errorType": errorType]
        )
        objectWillChange.send()
    }

    /// 叠层只展示“已启用、已注册、可触发”的绑定，并保留用户配置顺序。
    var overlayBindings: [HotkeyBinding] {
        guard virtualKeyboardRuntimeEnabled else {
            return []
        }

        return configuration.bindings
            .filter { $0.shortcut != nil && isBindingRegistered($0.id) }
    }

    var shortcutConflictReminder: String? {
        guard !shortcutConflictMessages.isEmpty else {
            return nil
        }

        return localized(
            .shortcutConflictReminder,
            shortcutConflictMessages.joined(separator: localizationManager.clauseSeparator)
        )
    }

    var shouldShowHotkeyGuideBanner: Bool {
        hotkeyGuideIsRequested && shortcutConflictReminder == nil
    }

    func handleMainHotkeyWindowAppeared() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "hotkeyWindowAppeared"
        )
        guard !hotkeyGuideStore.isDismissed else {
            return
        }

        hotkeyGuideIsRequested = true
    }

    func handleSettingsWindowAppeared() {
        performanceDiagnosticsRecorder.recordEvent(
            category: .uiTransition,
            name: "settingsWindowAppeared"
        )
        targetPresentationCache.removeAll()
    }

    func toggleHotkeyGuideFromHelpButton() {
        if shouldShowHotkeyGuideBanner {
            dismissHotkeyGuide()
        } else {
            hotkeyGuideIsRequested = true
        }
    }

    func dismissHotkeyGuide() {
        hotkeyGuideStore.isDismissed = true
        hotkeyGuideIsRequested = false
    }

    /// 通过系统面板选择应用、文件夹或文件，并创建一个等待配置快捷键的新绑定。
    func chooseTarget() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.title = localized(.chooseTarget)
        panel.message = localized(.chooseTargetMessage)
        panel.prompt = localized(.addTarget)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        addTarget(at: url)
    }

    func addTarget(at url: URL) {
        do {
            let target = try HotkeyTargetFactory.makeTarget(for: url)
            let binding = HotkeyBinding(target: target)
            let displayName = targetDisplayName(for: binding)
            guard !configuration.containsBinding(matching: target) else {
                setStatusMessage(localized(.targetAlreadyExists, displayName))
                return
            }

            let previousConfiguration = configuration
            configuration.bindings.append(binding)

            guard persistConfiguration(
                revertingTo: previousConfiguration,
                successMessage: localized(.targetAdded, displayName)
            ) else {
                return
            }

        } catch {
            setStatusMessage(localized(.addTargetFailed, error.localizedDescription))
        }
    }

    func setFolderOpenMode(_ mode: FolderOpenMode, for bindingID: UUID) {
        guard let binding = binding(for: bindingID),
              case .folder(let item, _) = binding.target else {
            return
        }

        updateTarget(.folder(item, mode), for: bindingID)
    }

    func setFileOpenMode(_ mode: FileOpenMode, for bindingID: UUID) {
        guard let binding = binding(for: bindingID),
              case .file(let item, _) = binding.target else {
            return
        }

        updateTarget(.file(item, mode), for: bindingID)
    }

    func setOpeningApplication(_ applicationURL: URL, for bindingID: UUID) {
        guard let binding = binding(for: bindingID),
              let application = bindingOpenModeCatalog.application(at: applicationURL) else {
            return
        }

        switch binding.target {
        case .folder(let item, _):
            updateTarget(
                .folder(item, .application(application)),
                for: bindingID
            )
        case .file(let item, _):
            updateTarget(
                .file(item, .application(application)),
                for: bindingID
            )
        case .application:
            return
        }
    }

    func chooseOpeningApplication(for bindingID: UUID) {
        guard let binding = binding(for: bindingID),
              binding.target.kind != .application else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = localized(.chooseOtherApplication)
        panel.prompt = localized(.open)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        setOpeningApplication(url, for: bindingID)
    }

    func targetPresentation(
        for binding: HotkeyBinding
    ) -> HotkeyTargetPresentation {
        let cachedAvailability = bindingAvailabilityCache[binding.id]
            .flatMap { cached in
                cached.target == binding.target ? cached.availability : nil
            }
        if let cached = targetPresentationCache[binding.id],
           cached.key.target == binding.target,
           cached.key.languageRawValue == currentLanguage.rawValue,
           cached.key.availability == cachedAvailability {
            return cached.presentation
        }

        let availability = cachedAvailability ??
            cachedBindingAvailability(for: binding)
        let key = TargetPresentationCacheKey(
            target: binding.target,
            languageRawValue: currentLanguage.rawValue,
            availability: availability
        )

        let presentation = targetPresentationResolver.resolve(
            binding: binding,
            availability: availability,
            language: currentLanguage,
            localizationBundle: localizationManager.bundle
        )
        targetPresentationCache[binding.id] = CachedTargetPresentation(
            key: key,
            presentation: presentation
        )
        return presentation
    }

    func bindingAvailability(
        for bindingID: UUID
    ) -> HotkeyTargetAvailability {
        guard let binding = binding(for: bindingID) else {
            return .targetUnavailable
        }
        return cachedBindingAvailability(for: binding)
    }

    func hasRuntimeInvalidBindingState(for bindingID: UUID) -> Bool {
        runtimeInvalidBindingByBindingID[bindingID] != nil
    }

    func hasCachedBindingAvailability(for bindingID: UUID) -> Bool {
        bindingAvailabilityCache[bindingID] != nil
    }

    /// 删除绑定后立即持久化，确保菜单栏和热键状态同步收敛。
    func removeBinding(_ bindingID: UUID) {
        guard let binding = binding(for: bindingID) else {
            return
        }
        guard canEditShortcut(for: bindingID) else {
            return
        }

        discardBindingRuntimeState(for: bindingID)
        configuration.bindings.removeAll { $0.id == bindingID }
        persistConfiguration(
            successMessage: localized(
                .targetRemoved,
                targetDisplayName(for: binding)
            )
        )
    }

    func shortcut(for bindingID: UUID) -> AppShortcut? {
        binding(for: bindingID)?.shortcut
    }

    func canEditShortcut(for bindingID: UUID) -> Bool {
        guard let binding = binding(for: bindingID) else {
            return false
        }

        return binding.source != .activityMonitorFeature
    }

    func setShortcut(_ shortcut: AppShortcut?, for bindingID: UUID) {
        guard let index = configuration.bindings.firstIndex(where: { $0.id == bindingID }) else {
            return
        }
        guard canEditShortcut(for: bindingID) else {
            return
        }

        configuration.bindings[index].shortcut = shortcut
        persistConfiguration()
    }

    /// 录制期间暂时注销全局热键，确保已有组合不会抢先消费用户输入。
    func setShortcutRecordingActive(_ isActive: Bool) {
        guard isShortcutRecordingActive != isActive else {
            return
        }

        isShortcutRecordingActive = isActive
        if isActive {
            hotKeyManager.unregisterAll()
        } else {
            refreshHotKeyRegistration(showsFailureBanner: false)
        }
    }

    func isBindingEnabled(_ bindingID: UUID) -> Bool {
        binding(for: bindingID)?.isEnabled ?? false
    }

    func setBindingEnabled(_ isEnabled: Bool, for bindingID: UUID) {
        guard let index = configuration.bindings.firstIndex(where: { $0.id == bindingID }) else {
            return
        }
        guard canEditShortcut(for: bindingID) else {
            return
        }

        configuration.bindings[index].isEnabled = isEnabled
        persistConfiguration()
    }

    /// 设置页拖拽排序结束后一次性提交最终顺序，避免拖动过程反复落盘造成卡顿。
    func moveBinding(withID bindingID: UUID, toOffset destination: Int) {
        let previousBindingOrder = configuration.bindings.map(\.id)
        configuration.moveBinding(withID: bindingID, toOffset: destination)

        guard configuration.bindings.map(\.id) != previousBindingOrder else {
            return
        }

        persistBindingOrder()
    }

    /// 允许 UI 在本地预览拖拽顺序后统一提交最终结果，减少拖动阶段的同步 IO。
    func setBindingOrder(_ orderedBindingIDs: [UUID]) {
        let previousBindingOrder = configuration.bindings.map(\.id)
        configuration.setBindingOrder(orderedBindingIDs)

        guard configuration.bindings.map(\.id) != previousBindingOrder else {
            return
        }

        persistBindingOrder()
    }

    /// 热键和菜单栏动作最终都会汇聚到这里，统一处理执行前准备和结果提示。
    func performAction(
        for bindingID: UUID,
        frontmostProcessIdentifier: pid_t? = nil,
        source: ToggleInvocationSource = .manual
    ) {
        let diagnosticsContext = beginHotKeyDiagnostics(
            actionType: "binding",
            invocationSource: source
        )
        _ = performAction(
            for: bindingID,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            source: source,
            shouldRunBeforeBindingAction: true,
            hotKeyDiagnosticsContext: diagnosticsContext
        )
    }

    private func performAction(
        for bindingID: UUID,
        frontmostProcessIdentifier: pid_t?,
        source: ToggleInvocationSource,
        shouldRunBeforeBindingAction: Bool,
        acceptedAction: (() -> Void)? = nil,
        hotKeyDiagnosticsContext: HotKeyDiagnosticsContext? = nil
    ) -> Bool {
        guard let binding = binding(for: bindingID) else {
            recordHotKeyStage(
                "bindingResolution",
                context: hotKeyDiagnosticsContext,
                metadata: ["result": "missing"]
            )
            _ = completeHotKeyDiagnostics(
                hotKeyDiagnosticsContext,
                metadata: [
                    "result": "failure",
                    "failureCategory": "missingBinding",
                ]
            )
            if source.showsStatusBanner {
                setStatusMessage(localized(.bindingNotFound))
            }
            return false
        }

        recordHotKeyStage(
            "bindingResolution",
            context: hotKeyDiagnosticsContext,
            metadata: hotKeyMetadata(for: binding).merging(["result": "success"]) { _, new in new }
        )

        return performAction(
            for: binding,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            source: source,
            shouldRunBeforeBindingAction: shouldRunBeforeBindingAction,
            acceptedAction: acceptedAction,
            hotKeyDiagnosticsContext: hotKeyDiagnosticsContext
        )
    }

    private func performAction(
        for binding: HotkeyBinding,
        frontmostProcessIdentifier: pid_t?,
        source: ToggleInvocationSource,
        shouldRunBeforeBindingAction: Bool,
        acceptedAction: (() -> Void)? = nil,
        hotKeyDiagnosticsContext: HotKeyDiagnosticsContext? = nil
    ) -> Bool {
        let actionMetadata = hotKeyMetadata(for: binding)

        let requiredPermissions = binding.target.requiredPermissions
        if requiredPermissions.contains(.accessibility) {
            measureHotKeyStage(
                "accessibilityRefresh",
                context: hotKeyDiagnosticsContext,
                metadata: actionMetadata
            ) {
                refreshAccessibilityPermissionStatus(
                    showsRegistrationFailureBanner: source.showsStatusBanner
                )
            }
        }
        if shouldRunBeforeBindingAction {
            recordHotKeyStage(
                "beforeBindingAction",
                context: hotKeyDiagnosticsContext,
                metadata: actionMetadata
            )
            beforeBindingAction?()
        }
        recordHotKeyStage(
            "prepareActionRequested",
            context: hotKeyDiagnosticsContext,
            metadata: actionMetadata
        )
        let preparedAction = bindingActionExecutor.prepareAction(
            for: binding,
            authorization: BindingActionAuthorizationContext(
                accessibilityGranted: accessibilityPermissionGranted
            ),
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            source: source
        )
        if preparedAction.isAccepted {
            acceptedAction?()
        }
        let actionGeneration = UUID()
        bindingActionGenerationByBindingID[binding.id] = actionGeneration
        executePreparedAction(
            preparedAction,
            binding: binding,
            source: source,
            actionGeneration: actionGeneration,
            hotKeyDiagnosticsContext: hotKeyDiagnosticsContext,
            hotKeyCompletionMetadata: actionMetadata
        )
        return preparedAction.isAccepted
    }

    /// 统一处理系统热键触发，让 runtime 层能拿到被 Carbon 吃掉的主键信息。
    func handleHotKeyTrigger(
        for action: HotKeyRegistrationAction,
        shortcut: AppShortcut,
        frontmostProcessIdentifier: pid_t?
    ) {
        handleHotKeyAction(
            action,
            shortcut: shortcut,
            frontmostProcessIdentifier: frontmostProcessIdentifier
        )
    }

    /// 统一处理系统热键触发，让 runtime 层能拿到被 Carbon 吃掉的主键信息。
    func handleHotKeyTrigger(
        for bindingID: UUID,
        shortcut: AppShortcut,
        frontmostProcessIdentifier: pid_t?
    ) {
        let hotKeyDiagnosticsContext = beginHotKeyDiagnostics(actionType: "binding")
        appendDecisionTrace(
            "hotkeyTrigger binding=\(bindingID.uuidString) keyCode=\(shortcut.keyCode) modifiers=\(shortcut.modifiers.rawValue) frontmostPid=\(frontmostProcessIdentifier ?? -1)"
        )

        guard let binding = binding(for: bindingID) else {
            recordHotKeyStage(
                "bindingResolution",
                context: hotKeyDiagnosticsContext,
                metadata: ["result": "missing"]
            )
            _ = completeHotKeyDiagnostics(
                hotKeyDiagnosticsContext,
                metadata: [
                    "result": "failure",
                    "failureCategory": "missingBinding",
                ]
            )
            appendDecisionTrace("hotkeyTrigger missingBinding binding=\(bindingID.uuidString)")
            return
        }

        recordHotKeyStage(
            "bindingResolution",
            context: hotKeyDiagnosticsContext,
            metadata: hotKeyMetadata(for: binding).merging(["result": "success"]) { _, new in new }
        )

        appendDecisionTrace(
            "hotkeyTrigger resolvedBinding binding=\(binding.id.uuidString) targetKind=\(binding.target.kind.rawValue) enabled=\(binding.isEnabled)"
        )

        var targetFlashPayload: HotKeyTargetFlashPayload?
        let didStartAction = performAction(
            for: binding,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            source: .hotKey,
            shouldRunBeforeBindingAction: true,
            acceptedAction: {
                targetFlashPayload =
                    self.makeHotKeyTargetFlashPayloadIfNeeded(for: binding)
                self.recordHotKeyStage(
                    "appIconFlashPayload",
                    context: hotKeyDiagnosticsContext,
                    metadata: self.hotKeyMetadata(for: binding).merging([
                        "result": targetFlashPayload == nil
                            ? "skipped"
                            : "created",
                    ]) { _, new in new }
                )
            },
            hotKeyDiagnosticsContext: hotKeyDiagnosticsContext
        )

        if didStartAction {
            publishHotKeyTargetFlash(targetFlashPayload)
        }
    }

    private func makeHotKeyTargetFlashPayloadIfNeeded(
        for binding: HotkeyBinding
    ) -> HotKeyTargetFlashPayload? {
        guard hotKeyIconFlashRuntimeEnabled else {
            return nil
        }

        let presentation = targetPresentation(for: binding)
        guard presentation.availability != .targetUnavailable else {
            return nil
        }

        return HotKeyTargetFlashPayload(
            targetDisplayName: presentation.displayName,
            targetImage: presentation.targetImage,
            fallbackSymbolName: presentation.fallbackSymbolName,
            screenFrame: hotKeyTargetFlashScreenFrame()
        )
    }

    private func publishHotKeyTargetFlash(
        _ payload: HotKeyTargetFlashPayload?
    ) {
        guard let payload else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.hotKeyTargetFlashDidTrigger?(payload)
        }
    }

    private func hotKeyTargetFlashScreenFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        return screen?.visibleFrame
            ?? screen?.frame
            ?? CGRect(x: 0, y: 0, width: 900, height: 700)
    }

    private func executePreparedAction(
        _ preparedAction: PreparedBindingAction,
        binding: HotkeyBinding,
        source: ToggleInvocationSource,
        actionGeneration: UUID,
        hotKeyDiagnosticsContext: HotKeyDiagnosticsContext? = nil,
        hotKeyCompletionMetadata: [String: String] = [:]
    ) {
        let execute: @MainActor @Sendable () -> Void = {
            preparedAction.execute { [weak self] result in
                guard let self else {
                    return
                }

                let completionMetadata =
                    hotKeyCompletionMetadata.merging(
                        self.hotKeyCompletionMetadata(for: result)
                    ) { _, new in new }
                let didCompleteDiagnostics =
                    self.completeHotKeyDiagnostics(
                        hotKeyDiagnosticsContext,
                        metadata: completionMetadata
                    )
                if didCompleteDiagnostics {
                    self.recordHotKeyStage(
                        "completion",
                        context: hotKeyDiagnosticsContext,
                        metadata: completionMetadata
                    )
                }

                guard self.bindingActionGenerationByBindingID[binding.id] ==
                        actionGeneration else {
                    return
                }
                self.bindingActionGenerationByBindingID.removeValue(
                    forKey: binding.id
                )

                if case .success(.opened(let refreshedItem)) = result,
                   let refreshedItem {
                    self.persistRefreshedItem(
                        refreshedItem,
                        for: binding.id,
                        executedTarget: binding.target,
                        showsRegistrationFailureBanner:
                            source.showsStatusBanner
                    )
                }
                switch result {
                case .failure(.targetUnavailable):
                    self.runtimeInvalidBindingByBindingID[binding.id] =
                        RuntimeInvalidBinding(
                            target: binding.target,
                            availability: .targetUnavailable
                        )
                    self.targetPresentationCache.removeValue(
                        forKey: binding.id
                    )
                    self.refreshValidation()
                    self.refreshHotKeyRegistration(
                        showsFailureBanner: source.showsStatusBanner
                    )
                case .failure(.selectedHandlerUnavailable):
                    self.runtimeInvalidBindingByBindingID[binding.id] =
                        RuntimeInvalidBinding(
                            target: binding.target,
                            availability: .openingApplicationUnavailable
                        )
                    self.targetPresentationCache.removeValue(
                        forKey: binding.id
                    )
                    self.refreshValidation()
                    self.refreshHotKeyRegistration(
                        showsFailureBanner: source.showsStatusBanner
                    )
                case .success
                    where self.runtimeInvalidBindingByBindingID[binding.id]?
                        .target == binding.target:
                    self.runtimeInvalidBindingByBindingID.removeValue(
                        forKey: binding.id
                    )
                    self.targetPresentationCache.removeValue(
                        forKey: binding.id
                    )
                    self.refreshValidation()
                    self.refreshHotKeyRegistration(
                        showsFailureBanner: source.showsStatusBanner
                    )
                case .failure, .success:
                    break
                }

                guard source.showsStatusBanner else {
                    return
                }
                switch result {
                case .success(.application(let toggleResult)):
                    self.setStatusMessage(toggleResult.message)
                case .success(.opened):
                    self.setStatusMessage(
                        "Opened \(self.targetDisplayName(for: binding))"
                    )
                case .failure(let error):
                    self.setStatusMessage(error.errorDescription)
                }
            }
        }

        switch preparedAction.executionTiming {
        case .immediate:
            execute()
        case .nextRunLoop:
            DispatchQueue.main.async(execute: execute)
        }
    }

    private func persistRefreshedItem(
        _ refreshedItem: ManagedFileSystemItem,
        for bindingID: UUID,
        executedTarget: HotkeyTarget,
        showsRegistrationFailureBanner: Bool
    ) {
        guard let index = configuration.bindings.firstIndex(where: {
            $0.id == bindingID
        }) else {
            return
        }

        let currentTarget = configuration.bindings[index].target
        let refreshedTarget: HotkeyTarget
        switch (executedTarget, currentTarget) {
        case let (
            .folder(executedItem, executedMode),
            .folder(currentItem, currentMode)
        ) where executedItem == currentItem &&
                executedMode == currentMode:
            refreshedTarget = .folder(refreshedItem, currentMode)
        case let (
            .file(executedItem, executedMode),
            .file(currentItem, currentMode)
        ) where executedItem == currentItem &&
                executedMode == currentMode:
            refreshedTarget = .file(refreshedItem, currentMode)
        default:
            return
        }

        let previousConfiguration = configuration
        configuration.bindings[index].target = refreshedTarget
        do {
            try configurationSaver(configuration)
            runtimeInvalidBindingByBindingID.removeValue(forKey: bindingID)
            targetPresentationCache.removeValue(forKey: bindingID)
            bindingAvailabilityCache.removeValue(forKey: bindingID)
        } catch {
            configuration = previousConfiguration
        }
        refreshValidation()
        refreshHotKeyRegistration(
            showsFailureBanner: showsRegistrationFailureBanner
        )
    }

    private func executePreparedToggle(
        _ preparedToggle: PreparedApplicationToggle,
        source: ToggleInvocationSource,
        hotKeyDiagnosticsContext: HotKeyDiagnosticsContext? = nil,
        hotKeyCompletionMetadata: [String: String] = [:]
    ) {
        preparedToggle.execute { [weak self] result in
            guard let self else {
                return
            }

            let completionMetadata = hotKeyCompletionMetadata.merging(
                self.hotKeyCompletionMetadata(for: result)
            ) { _, new in new }
            let didCompleteDiagnostics = self.completeHotKeyDiagnostics(
                hotKeyDiagnosticsContext,
                metadata: completionMetadata
            )
            if didCompleteDiagnostics {
                self.recordHotKeyStage(
                    "completion",
                    context: hotKeyDiagnosticsContext,
                    metadata: completionMetadata
                )
            }

            switch result {
            case .success(let toggleResult):
                guard source.showsStatusBanner else {
                    return
                }

                self.setStatusMessage(toggleResult.message)
            case .failure(let error):
                guard source.showsStatusBanner else {
                    return
                }

                self.setStatusMessage(error.errorDescription)
            }
        }
    }

    /// 让界面上的权限提醒和运行时真实状态保持同步。
    func refreshAccessibilityPermissionStatus(
        showsRegistrationFailureBanner: Bool = true
    ) {
        accessibilityPermissionGranted = accessibilityPermissionStatusProvider()
        refreshFinderWindowsCutPasteService()
        refreshValidation()
        refreshHotKeyRegistration(
            showsFailureBanner: showsRegistrationFailureBanner
        )
    }

    func handleApplicationDidBecomeActive() {
        targetPresentationCache.removeAll()
        refreshAccessibilityPermissionStatus()
    }

    /// 权限页打开失败时给出手动路径，避免用户被静默失败卡住。
    func openAccessibilitySystemSettings() {
        guard AccessibilityPermissionChecker.openSystemSettings() else {
            setStatusMessage(localized(.openSystemSettingsFailed))
            return
        }

        setStatusMessage(localized(.openSystemSettingsSucceeded, AppBrand.displayName))
    }

    /// 从 `SMAppService` 回读状态，避免仅依赖本地缓存。
    func refreshLaunchAtLoginStatus() {
        launchAtLoginState = launchAtLoginController.status()
    }

    /// 对登录项开关结果做统一状态刷新和用户提示。
    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(isEnabled)
        } catch {
            refreshLaunchAtLoginStatus()

            if isEnabled && launchAtLoginState == .requiresApproval {
                setStatusMessage(localized(.launchAtLoginRequiresApproval, AppBrand.displayName))
                return
            }

            setStatusMessage(localized(.launchAtLoginUpdateFailed, error.localizedDescription))
            return
        }

        refreshLaunchAtLoginStatus()

        switch launchAtLoginState {
        case .enabled:
            setStatusMessage(localized(.launchAtLoginEnabled))
        case .disabled:
            setStatusMessage(localized(.launchAtLoginDisabled))
        case .requiresApproval:
            setStatusMessage(localized(.launchAtLoginRequiresApproval, AppBrand.displayName))
        case .unavailable:
            setStatusMessage(localized(.launchAtLoginUnavailable))
        }
    }

    func setWindowsStyleCutEnabled(_ isEnabled: Bool) {
        guard configuration.windowsStyleCutEnabled != isEnabled else {
            return
        }

        refreshAccessibilityPermissionStatus()
        configuration.windowsStyleCutEnabled = isEnabled

        let statusMessage: String?
        if isEnabled {
            statusMessage = accessibilityPermissionGranted
                ? localized(.windowsStyleCutEnabled)
                : localized(.windowsStyleCutPermissionRequired)
        } else {
            statusMessage = localized(.windowsStyleCutDisabled)
        }

        persistConfiguration(successMessage: statusMessage)
    }

    func setPressedKeysOverlayEnabled(_ isEnabled: Bool) {
        guard configuration.pressedKeysOverlayEnabled != isEnabled else {
            return
        }

        refreshAccessibilityPermissionStatus()
        configuration.pressedKeysOverlayEnabled = isEnabled

        let statusMessage: String?
        if isEnabled {
            statusMessage = accessibilityPermissionGranted
                ? localized(.pressedKeysOverlayEnabled)
                : localized(.pressedKeysOverlayPermissionRequired)
        } else {
            statusMessage = localized(.pressedKeysOverlayDisabled)
        }

        let didPersist = persistConfiguration(successMessage: statusMessage)
        if didPersist {
            pressedKeysOverlaySettingsDidChange?()
        }
    }

    func setVirtualKeyboardEnabled(_ isEnabled: Bool) {
        guard configuration.virtualKeyboardEnabled != isEnabled else {
            return
        }

        configuration.virtualKeyboardEnabled = isEnabled

        let didPersist = persistConfiguration(
            successMessage: isEnabled
                ? localized(.virtualKeyboardEnabled)
                : localized(.virtualKeyboardDisabled)
        )
        if didPersist {
            virtualKeyboardSettingsDidChange?()
        }
    }

    func setVirtualKeyboardRevealDelay(_ revealDelay: TimeInterval) {
        let normalizedRevealDelay = VirtualKeyboardRevealDelay.normalized(revealDelay)
        guard configuration.virtualKeyboardRevealDelay != normalizedRevealDelay else {
            return
        }

        configuration.virtualKeyboardRevealDelay = normalizedRevealDelay

        let didPersist = persistConfiguration()
        if didPersist {
            virtualKeyboardSettingsDidChange?()
        }
    }

    func setHotKeyIconFlashEnabled(_ isEnabled: Bool) {
        guard configuration.hotKeyIconFlashEnabled != isEnabled else {
            return
        }

        let previousConfiguration = configuration
        configuration.hotKeyIconFlashEnabled = isEnabled
        persistConfigurationWithoutRuntimeRefresh(
            revertingTo: previousConfiguration,
            successMessage: isEnabled
                ? localized(.hotKeyIconFlashEnabled)
                : localized(.hotKeyIconFlashDisabled)
        )
    }

    func setHiddenBarEnabled(_ isEnabled: Bool) {
        guard configuration.hiddenBarEnabled != isEnabled else {
            return
        }

        configuration.hiddenBarEnabled = isEnabled

        let statusMessage = isEnabled
            ? localized(.hiddenBarEnabled)
            : localized(.hiddenBarDisabled)

        let didPersist = persistConfiguration(successMessage: statusMessage)
        if didPersist {
            hiddenBarSettingsDidChange?()
        }
    }

    func setNetworkStatusEnabled(_ isEnabled: Bool) {
        guard configuration.networkStatusEnabled != isEnabled else {
            return
        }

        configuration.networkStatusEnabled = isEnabled

        let statusMessage = isEnabled
            ? localized(.networkMonitorEnabled)
            : localized(.networkMonitorDisabled)

        let didPersist = persistConfiguration(successMessage: statusMessage)
        if didPersist {
            networkStatusSettingsDidChange?()
        }
    }

    func setMouseWheelWindowsScrollEnabled(_ isEnabled: Bool) {
        guard configuration.mouseWheelWindowsScrollEnabled != isEnabled else {
            return
        }

        refreshAccessibilityPermissionStatus()
        configuration.mouseWheelWindowsScrollEnabled = isEnabled

        let statusMessage: String?
        if isEnabled {
            statusMessage = accessibilityPermissionGranted
                ? localized(.mouseWheelWindowsScrollEnabled)
                : localized(.mouseWheelWindowsScrollPermissionRequired)
        } else {
            statusMessage = localized(.mouseWheelWindowsScrollDisabled)
        }

        let didPersist = persistConfiguration(successMessage: statusMessage)
        if didPersist {
            mouseWheelScrollSettingsDidChange?()
        }
    }

    func setAdvancedHotkeysEnabled(_ isEnabled: Bool) {
        guard configuration.advancedHotkeysEnabled != isEnabled else {
            return
        }

        let previousConfiguration = configuration
        configuration.advancedHotkeysEnabled = isEnabled
        persistConfigurationWithoutRuntimeRefresh(
            revertingTo: previousConfiguration,
            successMessage: localized(
                isEnabled ? .advancedHotkeysEnabled : .advancedHotkeysDisabled
            )
        )
    }

    func setActivityMonitorHotKeyEnabled(_ isEnabled: Bool) {
        guard configuration.activityMonitorHotKeyEnabled != isEnabled else {
            return
        }

        refreshAccessibilityPermissionStatus()
        configuration.activityMonitorHotKeyEnabled = isEnabled
        _ = reconcileActivityMonitorFeatureBinding()

        let statusMessage: String
        if isEnabled {
            statusMessage = accessibilityPermissionGranted
                ? localized(.activityMonitorHotKeyEnabled)
                : localized(.activityMonitorHotKeyPermissionRequired)
        } else {
            statusMessage = localized(.activityMonitorHotKeyDisabled)
        }

        persistConfiguration(successMessage: statusMessage)
    }

    /// 设置应用语言
    func setLanguage(_ language: AppLanguage) {
        guard configuration.language != language else { return }

        var updatedConfiguration = configuration
        updatedConfiguration.language = language

        do {
            try store.save(updatedConfiguration)
            configuration = updatedConfiguration
            localizationManager.setLanguage(language)
            targetPresentationCache.removeAll()
            refreshValidation()
            setStatusMessage(localized(.languageUpdated, language.displayName(in: localizationManager.bundle)))
        } catch {
            setStatusMessage(localized(.configurationSaveFailed, error.localizedDescription))
        }
    }

    /// 设置 AppWink 自身界面外观。
    func setAppearanceMode(_ appearanceMode: AppAppearanceMode) {
        guard configuration.appearanceMode != appearanceMode else {
            return
        }

        let previousConfiguration = configuration
        configuration.appearanceMode = appearanceMode
        applyApplicationAppearance()

        do {
            try store.save(configuration)
            setStatusMessage(localized(.appearanceModeUpdated, appearanceMode.displayName(in: localizationManager.bundle)))
        } catch {
            configuration = previousConfiguration
            applyApplicationAppearance()
            setStatusMessage(localized(.configurationSaveFailed, error.localizedDescription))
        }
    }

    func canPerformAction(for bindingID: UUID) -> Bool {
        guard let binding = binding(for: bindingID) else {
            return false
        }

        guard invalidBindingIDs.contains(bindingID) else {
            return true
        }

        return runtimeInvalidBindingByBindingID[bindingID]?.target ==
            binding.target &&
            staticBindingAvailability(for: binding) == .available
    }

    func canPerformMenuBarSwitchAction(for bindingID: UUID) -> Bool {
        canPerformAction(for: bindingID)
    }

    func isBindingRegistered(_ bindingID: UUID) -> Bool {
        hotKeyRegistrationRequests().contains {
            if case .binding(let requestBindingID) = $0.action {
                return requestBindingID == bindingID
            }

            return false
        }
    }

    func isBindingDuplicateShortcut(_ bindingID: UUID) -> Bool {
        duplicateShortcutBindingIDs.contains(bindingID)
    }

    func isBindingInvalid(_ bindingID: UUID) -> Bool {
        invalidBindingIDs.contains(bindingID)
    }

    func conflictingTargetNames(for bindingID: UUID) -> [String] {
        guard let conflictingBindingIDs = conflictingBindingIDsByBindingID[bindingID] else {
            return []
        }

        return conflictingBindingIDs
            .compactMap { binding(for: $0) }
            .map { targetDisplayName(for: $0) }
            .sorted()
    }

    /// 所有绑定查找统一走这里，减少散落的数组索引逻辑。
    private func binding(for bindingID: UUID) -> HotkeyBinding? {
        configuration.bindings.first { $0.id == bindingID }
    }

    private func application(for binding: HotkeyBinding) -> ManagedApplication? {
        switch binding.target {
        case .application(let application):
            return application
        case .folder, .file:
            return nil
        }
    }

    private func cachedBindingAvailability(
        for binding: HotkeyBinding
    ) -> HotkeyTargetAvailability {
        if let cached = bindingAvailabilityCache[binding.id],
           cached.target == binding.target {
            return cached.availability
        }

        let availability = resolvedBindingAvailability(for: binding)
        bindingAvailabilityCache[binding.id] = CachedBindingAvailability(
            target: binding.target,
            availability: availability
        )
        return availability
    }

    private func resolvedBindingAvailability(
        for binding: HotkeyBinding
    ) -> HotkeyTargetAvailability {
        if let runtimeInvalidBinding =
            runtimeInvalidBindingByBindingID[binding.id],
           runtimeInvalidBinding.target == binding.target {
            return runtimeInvalidBinding.availability
        }
        return staticBindingAvailability(for: binding)
    }

    private func staticBindingAvailability(
        for binding: HotkeyBinding
    ) -> HotkeyTargetAvailability {
        if let staticBindingAvailabilityProvider {
            return staticBindingAvailabilityProvider(binding)
        }

        switch binding.target {
        case .application(let application):
            return application.resolvedURL() == nil
                ? .targetUnavailable
                : .available
        case .folder(let item, .finderNewTab),
             .file(let item, .systemDefault):
            return item.resolve() == nil
                ? .targetUnavailable
                : .available
        case .folder(let item, .application(let application)),
             .file(let item, .application(let application)):
            if item.resolve() == nil {
                return .targetUnavailable
            }
            return application.resolvedURL() == nil
                ? .openingApplicationUnavailable
                : .available
        }
    }

    private func isBindingTargetInvalid(_ binding: HotkeyBinding) -> Bool {
        staticBindingAvailability(for: binding) != .available
    }

    private func updateTarget(_ target: HotkeyTarget, for bindingID: UUID) {
        let previousConfiguration = configuration
        guard configuration.updateTarget(
            target,
            forBindingID: bindingID
        ) == .updated else {
            return
        }

        bindingActionGenerationByBindingID.removeValue(forKey: bindingID)
        if persistConfiguration(revertingTo: previousConfiguration) {
            discardBindingRuntimeState(for: bindingID)
        }
    }

    private func discardBindingRuntimeState(for bindingID: UUID) {
        bindingActionGenerationByBindingID.removeValue(forKey: bindingID)
        runtimeInvalidBindingByBindingID.removeValue(forKey: bindingID)
        targetPresentationCache.removeValue(forKey: bindingID)
        bindingAvailabilityCache.removeValue(forKey: bindingID)
    }

    private func persistNormalizedConfigurationIfNeeded() {
        let retiredFeatureWasEnabled = configuration.activityMonitorHotKeyEnabled
        configuration.activityMonitorHotKeyEnabled = false
        let removedRetiredBindings = removeManagedActivityMonitorBindings()

        guard retiredFeatureWasEnabled || removedRetiredBindings else {
            return
        }

        do {
            try store.save(configuration)
        } catch {
            setStatusMessage(localized(.configurationSaveFailed, error.localizedDescription))
        }
    }

    @discardableResult
    private func reconcileActivityMonitorFeatureBinding() -> Bool {
        if configuration.activityMonitorHotKeyEnabled {
            return ensureActivityMonitorFeatureBinding()
        }

        return removeManagedActivityMonitorBindings()
    }

    @discardableResult
    private func removeManagedActivityMonitorBindings() -> Bool {
        let removedBindingIDs = configuration.bindings.compactMap { binding in
            binding.source == .activityMonitorFeature ? binding.id : nil
        }
        for bindingID in removedBindingIDs {
            discardBindingRuntimeState(for: bindingID)
        }
        let previousCount = configuration.bindings.count
        configuration.bindings.removeAll {
            $0.source == .activityMonitorFeature
        }
        return configuration.bindings.count != previousCount
    }

    @discardableResult
    private func ensureActivityMonitorFeatureBinding() -> Bool {
        let preferredApplication = activityMonitorApplicationProvider()
        var didChange = false
        let managedApplicationIndex = configuration.bindings.firstIndex {
            $0.source == .activityMonitorFeature && application(for: $0) != nil
        }
        let activityMonitorApplicationIndex = configuration.bindings.firstIndex {
            guard let application = application(for: $0) else {
                return false
            }

            return isActivityMonitorApplication(application)
        }
        let repairableManagedIndex = preferredApplication.flatMap { _ in
            configuration.bindings.firstIndex {
                $0.source == .activityMonitorFeature
            }
        }
        let existingIndex = managedApplicationIndex ??
            activityMonitorApplicationIndex ??
            repairableManagedIndex

        if let existingIndex,
           let application = preferredApplication ??
               application(for: configuration.bindings[existingIndex]) {
            let existingBinding = configuration.bindings[existingIndex]
            let updatedBinding = HotkeyBinding(
                id: existingBinding.id,
                target: .application(application),
                shortcut: ActivityMonitorHotKeyFeature.shortcut,
                isEnabled: true,
                source: .activityMonitorFeature
            )

            if configuration.bindings[existingIndex] != updatedBinding {
                discardBindingRuntimeState(for: existingBinding.id)
                configuration.bindings[existingIndex] = updatedBinding
                didChange = true
            }

            let keptBindingID = updatedBinding.id
            let removedBindingIDs = configuration.bindings.compactMap {
                binding -> UUID? in
                guard binding.id != keptBindingID,
                      binding.source == .activityMonitorFeature ||
                        isActivityMonitorTarget(binding) else {
                    return nil
                }
                return binding.id
            }
            for bindingID in removedBindingIDs {
                discardBindingRuntimeState(for: bindingID)
            }
            let previousCount = configuration.bindings.count
            configuration.bindings.removeAll { binding in
                return binding.id != keptBindingID &&
                    (binding.source == .activityMonitorFeature ||
                        isActivityMonitorTarget(binding))
            }
            didChange = didChange || configuration.bindings.count != previousCount
        } else if let preferredApplication {
            configuration.bindings.append(
                HotkeyBinding(
                    target: .application(preferredApplication),
                    shortcut: ActivityMonitorHotKeyFeature.shortcut,
                    isEnabled: true,
                    source: .activityMonitorFeature
                )
            )
            didChange = true
        } else {
            didChange = removeManagedActivityMonitorBindings()
        }

        return didChange
    }

    private func isActivityMonitorApplication(_ application: ManagedApplication) -> Bool {
        if application.bundleIdentifier == ActivityMonitorHotKeyFeature.bundleIdentifier {
            return true
        }

        return application.fallbackPath == ActivityMonitorHotKeyFeature.fallbackPath
    }

    private func isActivityMonitorTarget(_ binding: HotkeyBinding) -> Bool {
        guard let application = application(for: binding) else {
            return false
        }

        return isActivityMonitorApplication(application)
    }

    private func bindingParticipatesInRuntime(
        _ binding: HotkeyBinding,
        configuration: AppConfiguration
    ) -> Bool {
        guard binding.source == .activityMonitorFeature else {
            return true
        }

        guard case .application = binding.target else {
            return false
        }

        return configuration.activityMonitorHotKeyEnabled
    }

    /// 配置变更后统一执行保存、状态提示、校验和热键刷新，避免遗漏收尾动作。
    @discardableResult
    private func persistConfiguration(
        revertingTo previousConfiguration: AppConfiguration? = nil,
        successMessage: String? = nil
    ) -> Bool {
        return performanceDiagnosticsRecorder.measure(
            category: .configuration,
            name: "persistConfiguration",
            metadata: configurationDiagnosticsMetadata()
        ) {
            let didPersist: Bool
            do {
                try configurationSaver(configuration)
                didPersist = true
                if let successMessage {
                    setStatusMessage(successMessage)
                }
            } catch {
                didPersist = false
                if let previousConfiguration {
                    configuration = previousConfiguration
                }
                setStatusMessage(localized(.configurationSaveFailed, error.localizedDescription))
            }

            refreshValidation()
            refreshHotKeyRegistration()
            refreshFinderWindowsCutPasteService()
            return didPersist
        }
    }

    /// 仅保存纯偏好项，不刷新权限、热键或运行时监听器。
    private func persistConfigurationWithoutRuntimeRefresh(
        revertingTo previousConfiguration: AppConfiguration,
        successMessage: String
    ) {
        performanceDiagnosticsRecorder.measure(
            category: .configuration,
            name: "persistConfigurationWithoutRuntimeRefresh",
            metadata: configurationDiagnosticsMetadata()
        ) {
            do {
                try store.save(configuration)
                setStatusMessage(successMessage)
            } catch {
                configuration = previousConfiguration
                setStatusMessage(localized(.configurationSaveFailed, error.localizedDescription))
            }
        }
    }

    /// 排序只影响显示顺序，不影响热键注册结果，因此只保存配置即可。
    private func persistBindingOrder() {
        let configurationSnapshot = configuration
        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .configuration,
            name: "persistBindingOrder",
            metadata: configurationDiagnosticsMetadata(for: configurationSnapshot)
        )

        store.saveAsync(configurationSnapshot) { [weak self] error in
            guard let self else {
                return
            }

            self.performanceDiagnosticsRecorder.endInterval(
                intervalToken,
                metadata: ["result": error == nil ? "success" : "failure"]
            )

            if let error {
                self.setStatusMessage(self.localized(.configurationSaveFailed, error.localizedDescription))
            }
        }
    }

    /// 刷新路径有效性和快捷键冲突状态，供 UI 提示和热键注册共同使用。
    private func refreshValidation() {
        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .configuration,
            name: "refreshValidation"
        )

        let currentBindingIDs = Set(configuration.bindings.map(\.id))
        let currentTargetsByBindingID = Dictionary(
            uniqueKeysWithValues: configuration.bindings.map {
                ($0.id, $0.target)
            }
        )
        runtimeInvalidBindingByBindingID = runtimeInvalidBindingByBindingID
            .filter {
                currentTargetsByBindingID[$0.key] == $0.value.target
            }
        targetPresentationCache = targetPresentationCache
            .filter { currentBindingIDs.contains($0.key) }
        let previousAvailabilityCache = bindingAvailabilityCache
        var refreshedAvailabilityCache:
            [UUID: CachedBindingAvailability] = [:]
        for binding in configuration.bindings {
            let refreshed = CachedBindingAvailability(
                target: binding.target,
                availability: resolvedBindingAvailability(for: binding)
            )
            refreshedAvailabilityCache[binding.id] = refreshed
            if previousAvailabilityCache[binding.id] != refreshed {
                targetPresentationCache.removeValue(forKey: binding.id)
            }
        }
        bindingAvailabilityCache = refreshedAvailabilityCache
        invalidBindingIDs = Set(
            refreshedAvailabilityCache.compactMap { bindingID, cached in
                cached.availability == .available ? nil : bindingID
            }
        )

        // 只有“已启用 + 已配置 + 路径有效”的绑定才参与冲突检测。
        let enabledShortcutGroups = Dictionary(
            grouping: configuration.bindings.filter {
                $0.isEnabled &&
                $0.shortcut != nil &&
                !invalidBindingIDs.contains($0.id) &&
                bindingParticipatesInRuntime($0, configuration: configuration)
            }
        ) { binding in
            binding.shortcut!
        }

        let conflictingShortcutGroups = Dictionary(
            uniqueKeysWithValues: enabledShortcutGroups.filter { $0.value.count > 1 }
        )

        duplicateShortcutBindingIDs = Set(
            conflictingShortcutGroups.values
                .flatMap { $0.map(\.id) })

        conflictingBindingIDsByBindingID = conflictingShortcutGroups.values.reduce(into: [:]) { result, bindings in
            let groupedBindingIDs = Set(bindings.map(\.id))
            for binding in bindings {
                result[binding.id] = groupedBindingIDs.subtracting([binding.id])
            }
        }

        var messages: [String] = []

        // 目标不可用属于配置问题，需要优先暴露出来，避免用户以为热键注册故障。
        let invalidApps = configuration.bindings
            .filter { invalidBindingIDs.contains($0.id) }
            .map { targetDisplayName(for: $0) }
            .sorted()
        if !invalidApps.isEmpty {
            messages.append(
                localized(
                    .targetsUnavailable,
                    invalidApps.joined(separator: localizationManager.listSeparator)
                )
            )
        }

        shortcutConflictMessages = conflictingShortcutGroups
            .map { shortcut, bindings in
                let appNames = bindings
                    .map { targetDisplayName(for: $0) }
                    .sorted()
                    .joined(separator: localizationManager.listSeparator)
                return "\(shortcut.displayString)\(localizationManager.colonSeparator)\(appNames)"
            }
            .sorted()

        validationMessages = messages

        performanceDiagnosticsRecorder.endInterval(
            intervalToken,
            metadata: intervalToken == nil ? [:] : configurationDiagnosticsMetadata()
        )
    }

    /// 仅把可注册绑定提交给系统热键层，失败项再回填为用户可读提示。
    private func refreshHotKeyRegistration(
        showsFailureBanner: Bool = true
    ) {
        let requests = hotKeyRegistrationRequests()

        var failures: [HotKeyRegistrationAction] = []
        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .registration,
            name: "refreshHotKeys"
        )
        failures = hotKeyManager.updateRegistrations(requests: requests) { [weak self] action, shortcut, frontmostProcessIdentifier in
            self?.handleHotKeyAction(
                action,
                shortcut: shortcut,
                frontmostProcessIdentifier: frontmostProcessIdentifier)
        }
        let refreshMetadata = intervalToken == nil
            ? [:]
            : configurationDiagnosticsMetadata(
                registerableShortcutCount: requests.count,
                registrationFailureCount: failures.count
            )
        performanceDiagnosticsRecorder.endInterval(intervalToken, metadata: refreshMetadata)
        performanceDiagnosticsRecorder.recordEvent(
            category: .registration,
            name: "refreshHotKeys",
            metadata: refreshMetadata
        )

        if !failures.isEmpty {
            performanceDiagnosticsRecorder.recordEvent(
                category: .registration,
                name: "refreshHotKeyFailures",
                metadata: configurationDiagnosticsMetadata(
                    registerableShortcutCount: requests.count,
                    registrationFailureCount: failures.count
                )
            )
        }

        if showsFailureBanner, !failures.isEmpty {
            let appNames = failures
                .compactMap { targetDisplayName(for: $0) }
                .sorted()
                .joined(separator: localizationManager.listSeparator)
            setStatusMessage(localized(.hotKeyRegistrationFailed, appNames))
        }
    }

    private func hotKeyRegistrationRequests() -> [HotKeyRegistrationRequest] {
        guard !isShortcutRecordingActive else {
            return []
        }

        return registerableBindings().compactMap { binding -> HotKeyRegistrationRequest? in
            guard let shortcut = binding.shortcut else {
                return nil
            }

            return HotKeyRegistrationRequest(action: .binding(binding.id), shortcut: shortcut)
        }
    }

    private func beginHotKeyDiagnostics(
        actionType: String,
        invocationSource: ToggleInvocationSource = .hotKey
    ) -> HotKeyDiagnosticsContext? {
        let metadata = [
            "actionType": actionType,
            "invocationSource": invocationSourceName(invocationSource),
        ]
        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .hotkey,
            name: "handleHotKeyAction",
            metadata: metadata
        )
        guard let intervalToken else {
            return nil
        }

        performanceDiagnosticsRecorder.recordEvent(
            category: .hotkey,
            name: "handleHotKeyAction",
            metadata: metadata
        )
        return HotKeyDiagnosticsContext(
            intervalToken: intervalToken,
            metadata: metadata
        )
    }

    private func invocationSourceName(
        _ source: ToggleInvocationSource
    ) -> String {
        switch source {
        case .hotKey:
            "hotKey"
        case .manual:
            "manual"
        }
    }

    private func recordHotKeyStage(
        _ name: String,
        context: HotKeyDiagnosticsContext?,
        metadata: [String: String] = [:]
    ) {
        guard let context else {
            return
        }

        performanceDiagnosticsRecorder.recordEvent(
            category: .hotkey,
            name: name,
            metadata: context.metadata
                .merging(["stage": name]) { _, new in new }
                .merging(metadata) { _, new in new }
        )
    }

    private func measureHotKeyStage<T>(
        _ name: String,
        context: HotKeyDiagnosticsContext?,
        metadata: [String: String] = [:],
        _ work: () throws -> T
    ) rethrows -> T {
        guard let context else {
            return try work()
        }

        return try performanceDiagnosticsRecorder.measure(
            category: .hotkey,
            name: name,
            metadata: context.metadata.merging(metadata) { _, new in new },
            work
        )
    }

    private func completeHotKeyDiagnostics(
        _ context: HotKeyDiagnosticsContext?,
        metadata: [String: String] = [:]
    ) -> Bool {
        guard let context else {
            return false
        }

        return performanceDiagnosticsRecorder.endInterval(
            context.intervalToken,
            metadata: context.metadata.merging(metadata) { _, new in new }
        )
    }

    private func hotKeyMetadata(for application: ManagedApplication) -> [String: String] {
        var metadata = ["appDisplayName": application.displayName]
        if let bundleIdentifier = application.bundleIdentifier,
           !bundleIdentifier.isEmpty {
            metadata["bundleIdentifier"] = bundleIdentifier
        }
        return metadata
    }

    private func hotKeyMetadata(for binding: HotkeyBinding) -> [String: String] {
        var metadata = [
            "bindingID": binding.id.uuidString,
            "targetKind": binding.target.kind.rawValue,
            "openModeKind": openModeKind(for: binding.target),
        ]
        switch binding.target {
        case .application(let application):
            metadata.merge(hotKeyMetadata(for: application)) { _, new in new }
        case .folder, .file:
            break
        }
        return metadata
    }

    private func openModeKind(for target: HotkeyTarget) -> String {
        switch target {
        case .application:
            "applicationToggle"
        case .folder(_, .finderNewTab):
            "systemDefault"
        case .folder(_, .application), .file(_, .application):
            "selectedApplication"
        case .file(_, .systemDefault):
            "systemDefault"
        }
    }

    private func hotKeyCompletionMetadata(
        for result: Result<ApplicationToggleResult, ApplicationToggleError>
    ) -> [String: String] {
        switch result {
        case .success(let toggleResult):
            return [
                "result": "success",
                "toggleResult": hotKeyResultName(toggleResult),
            ]
        case .failure(let error):
            return [
                "result": "failure",
                "failureCategory": hotKeyFailureCategory(error),
            ]
        }
    }

    private func hotKeyCompletionMetadata(
        for result: Result<BindingActionResult, BindingActionError>
    ) -> [String: String] {
        switch result {
        case .success(.application(let toggleResult)):
            [
                "stage": "completion",
                "result": "success",
                "toggleResult": hotKeyResultName(toggleResult),
            ]
        case .success(.opened(let refreshedItem)):
            [
                "stage": "completion",
                "result": "success",
                "bookmarkRefreshed": String(refreshedItem != nil),
            ]
        case .failure(let error):
            [
                "stage": "completion",
                "result": "failure",
                "failureCategory": bindingActionFailureCategory(error),
                "errorDomain": error.diagnosticDomain,
                "errorCode": String(error.diagnosticCode),
            ]
        }
    }

    private func bindingActionFailureCategory(
        _ error: BindingActionError
    ) -> String {
        switch error {
        case .accessibilityPermissionRequired:
            "accessibilityPermissionRequired"
        case .targetUnavailable:
            "targetUnavailable"
        case .selectedHandlerUnavailable:
            "selectedHandlerUnavailable"
        case .applicationFailed:
            "applicationFailed"
        case .openFailed:
            "openFailed"
        }
    }

    private func hotKeyResultName(_ result: ApplicationToggleResult) -> String {
        switch result {
        case .activated:
            return "activated"
        case .hidden:
            return "hidden"
        }
    }

    private func hotKeyFailureCategory(_ error: ApplicationToggleError) -> String {
        switch error {
        case .applicationUnavailable:
            return "applicationUnavailable"
        case .launchFailed:
            return "launchFailed"
        case .activationFailed:
            return "activationFailed"
        case .hideFailed:
            return "hideFailed"
        }
    }

    func handleHotKeyAction(
        _ action: HotKeyRegistrationAction,
        shortcut: AppShortcut,
        frontmostProcessIdentifier: pid_t?
    ) {
        guard !isShortcutRecordingActive else {
            appendDecisionTrace("hotkeyTrigger ignored while shortcut recorder is active")
            return
        }

        switch action {
        case .binding(let bindingID):
            handleHotKeyTrigger(
                for: bindingID,
                shortcut: shortcut,
                frontmostProcessIdentifier: frontmostProcessIdentifier
            )
        case .activityMonitor:
            handleActivityMonitorHotKey(
                shortcut: shortcut,
                frontmostProcessIdentifier: frontmostProcessIdentifier,
                hotKeyDiagnosticsContext: beginHotKeyDiagnostics(actionType: "activityMonitor")
            )
        }
    }

    private func handleActivityMonitorHotKey(
        shortcut: AppShortcut,
        frontmostProcessIdentifier: pid_t?,
        hotKeyDiagnosticsContext: HotKeyDiagnosticsContext? = nil
    ) {
        appendDecisionTrace(
            "hotkeyTrigger activityMonitor keyCode=\(shortcut.keyCode) modifiers=\(shortcut.modifiers.rawValue) frontmostPid=\(frontmostProcessIdentifier ?? -1)"
        )

        guard let application = activityMonitorApplicationProvider() else {
            recordHotKeyStage(
                "fixedActionResolution",
                context: hotKeyDiagnosticsContext,
                metadata: ["result": "missing"]
            )
            _ = completeHotKeyDiagnostics(
                hotKeyDiagnosticsContext,
                metadata: [
                    "result": "failure",
                    "failureCategory": "missingFixedAction",
                ]
            )
            appendDecisionTrace("hotkeyTrigger activityMonitor unresolved")
            return
        }

        let applicationMetadata = hotKeyMetadata(for: application)
        recordHotKeyStage(
            "fixedActionResolution",
            context: hotKeyDiagnosticsContext,
            metadata: applicationMetadata.merging(["result": "success"]) { _, new in new }
        )

        measureHotKeyStage(
            "accessibilityRefresh",
            context: hotKeyDiagnosticsContext,
            metadata: applicationMetadata
        ) {
            refreshAccessibilityPermissionStatus(
                showsRegistrationFailureBanner: false
            )
        }
        recordHotKeyStage(
            "beforeBindingAction",
            context: hotKeyDiagnosticsContext,
            metadata: applicationMetadata
        )
        beforeBindingAction?()
        recordHotKeyStage(
            "prepareToggleRequested",
            context: hotKeyDiagnosticsContext,
            metadata: applicationMetadata
        )
        let preparedToggle = applicationToggleService.prepareToggle(
            application: application,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            invocationSource: .hotKey
        )
        let activityMonitorBinding = configuration.bindings.first {
            $0.source == .activityMonitorFeature
        } ?? HotkeyBinding(
            target: .application(application),
            shortcut: shortcut,
            source: .activityMonitorFeature
        )
        let targetFlashPayload = makeHotKeyTargetFlashPayloadIfNeeded(
            for: activityMonitorBinding
        )
        recordHotKeyStage(
            "appIconFlashPayload",
            context: hotKeyDiagnosticsContext,
            metadata: applicationMetadata.merging([
                "result": targetFlashPayload == nil ? "skipped" : "created",
            ]) { _, new in new }
        )
        executePreparedToggle(
            preparedToggle,
            source: .hotKey,
            hotKeyDiagnosticsContext: hotKeyDiagnosticsContext,
            hotKeyCompletionMetadata: applicationMetadata
        )
        publishHotKeyTargetFlash(targetFlashPayload)
    }

    private func targetDisplayName(
        for action: HotKeyRegistrationAction
    ) -> String? {
        switch action {
        case .binding(let bindingID):
            return binding(for: bindingID).map { targetDisplayName(for: $0) }
        case .activityMonitor:
            return localized(.activityMonitor)
        }
    }

    private func refreshFinderWindowsCutPasteService() {
        finderWindowsCutPasteService.updateActivation(
            isEnabled: windowsStyleCutRuntimeEnabled,
            accessibilityGranted: accessibilityPermissionGranted
        )
    }

    /// 这是热键注册和覆盖层展示的共同准入规则，必须保持一致。
    private func registerableBindings() -> [HotkeyBinding] {
        configuration.bindings.filter { binding in
            !invalidBindingIDs.contains(binding.id) &&
            !duplicateShortcutBindingIDs.contains(binding.id) &&
            binding.isEnabled &&
            binding.shortcut != nil &&
            requiredPermissionsAreGranted(for: binding.target) &&
            bindingParticipatesInRuntime(binding, configuration: configuration)
        }
    }

    private func requiredPermissionsAreGranted(
        for target: HotkeyTarget
    ) -> Bool {
        let permissions = target.requiredPermissions
        if permissions.contains(.accessibility),
           !accessibilityPermissionGranted {
            return false
        }
        return true
    }

    /// 所有临时提示统一走这里，顺带处理自动消失和重复任务取消。
    private func setStatusMessage(
        _ message: String?,
        autoDismissAfter duration: TimeInterval? = 3
    ) {
        pendingStatusDismissWorkItem?.cancel()
        pendingStatusDismissWorkItem = nil
        statusMessage = message

        guard message != nil, let duration else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.clearStatusMessage()
        }
        pendingStatusDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    /// 显式清理挂起任务，避免旧提示把新提示提前清掉。
    private func clearStatusMessage() {
        pendingStatusDismissWorkItem?.cancel()
        pendingStatusDismissWorkItem = nil
        statusMessage = nil
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }

    private func localized(_ key: LocalizationKey, _ argument: CVarArg) -> String {
        localizationManager.string(for: key, arguments: argument)
    }

    private func applyApplicationAppearance() {
        NSApplication.shared.appearance = configuration.appearanceMode.nsAppearance
    }
}

private extension AppAppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}
