import AppKit
import SwiftUI

enum AppWindowChromeIdentifier {
    static let main = "AppWinkMainTitlebar"
    static let settings = "AppWinkSettingsTitlebar"
}

@MainActor
enum AppWindowForegroundController {
    private static var isPromotingWindow = false
    private static var visiblePrimaryWindows: Set<ObjectIdentifier> = []

    nonisolated static func normalizedCollectionBehavior(
        _ collectionBehavior: NSWindow.CollectionBehavior
    ) -> NSWindow.CollectionBehavior {
        var normalized = collectionBehavior
        normalized.insert(.managed)
        normalized.insert(.participatesInCycle)
        normalized.remove(.transient)
        normalized.remove(.ignoresCycle)
        normalized.remove(.stationary)
        return normalized
    }

    static func configurePrimaryWindowBehavior(_ window: NSWindow) {
        window.level = .normal
        let normalizedBehavior = normalizedCollectionBehavior(window.collectionBehavior)
        if window.collectionBehavior != normalizedBehavior {
            window.collectionBehavior = normalizedBehavior
        }
    }

    static func registerPrimaryWindow(_ window: NSWindow) {
        configurePrimaryWindowBehavior(window)
        visiblePrimaryWindows.insert(ObjectIdentifier(window))
        refreshActivationPolicy()
    }

    static func unregisterPrimaryWindow(_ window: NSWindow) {
        visiblePrimaryWindows.remove(ObjectIdentifier(window))
        refreshActivationPolicy()
    }

    static func refreshActivationPolicy() {
        NSApp.setActivationPolicy(visiblePrimaryWindows.isEmpty ? .accessory : .regular)
    }

    static func schedulePromotion(windowIdentifier: String) {
        DispatchQueue.main.async {
            Task { @MainActor in
                promoteWindow(withIdentifier: windowIdentifier)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Task { @MainActor in
                promoteWindow(withIdentifier: windowIdentifier)
            }
        }
    }

    static func promoteWindow(withIdentifier windowIdentifier: String) {
        activateApp()

        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == windowIdentifier }) else {
            return
        }

        promote(window)
    }

    static func promote(_ window: NSWindow) {
        guard !isPromotingWindow,
              window.isVisible else {
            return
        }

        isPromotingWindow = true
        orderPromotedWindow(window)

        DispatchQueue.main.async {
            Task { @MainActor in
                orderPromotedWindow(window)
                isPromotingWindow = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                orderPromotedWindow(window)
            }
        }
    }

    private static func activateApp() {
        NSRunningApplication.current.activate(options: [
            .activateAllWindows
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func orderPromotedWindow(_ window: NSWindow) {
        guard window.isVisible else {
            return
        }

        configurePrimaryWindowBehavior(window)
        activateApp()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        // Mission Control can make an accessory-app window key before the old
        // foreground app has fully yielded. Re-ordering regardless preserves
        // the user's explicit window selection across that transition.
        window.orderFrontRegardless()
    }
}

/// Shared AppKit titlebar chrome used by AppWink's primary desktop windows.
struct AppWindowChromeConfigurator: NSViewRepresentable {
    let toolbarIdentifier: String
    let minWidth: CGFloat
    let minHeight: CGFloat
    let preferredFrameWidth: CGFloat?
    let fixedFrameHeight: CGFloat?
    let titlebarHeight: CGFloat
    let titleOverride: String?
    let titlebarBackAction: (() -> Void)?
    let titlebarBackAccessibilityLabel: String
    let titlebarHelpAction: (() -> Void)?
    let titlebarHelpAccessibilityLabel: String

    init(
        toolbarIdentifier: String,
        minWidth: CGFloat,
        minHeight: CGFloat,
        preferredFrameWidth: CGFloat? = nil,
        fixedFrameHeight: CGFloat? = nil,
        titlebarHeight: CGFloat = SettingsDesignTokens.WindowChrome.titlebarHeight,
        titleOverride: String? = nil,
        titlebarBackAction: (() -> Void)? = nil,
        titlebarBackAccessibilityLabel: String = "Back",
        titlebarHelpAction: (() -> Void)? = nil,
        titlebarHelpAccessibilityLabel: String = "Help"
    ) {
        self.toolbarIdentifier = toolbarIdentifier
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.preferredFrameWidth = preferredFrameWidth
        self.fixedFrameHeight = fixedFrameHeight
        self.titlebarHeight = titlebarHeight
        self.titleOverride = titleOverride
        self.titlebarBackAction = titlebarBackAction
        self.titlebarBackAccessibilityLabel = titlebarBackAccessibilityLabel
        self.titlebarHelpAction = titlebarHelpAction
        self.titlebarHelpAccessibilityLabel = titlebarHelpAccessibilityLabel
    }

    func makeNSView(context: Context) -> ConfiguringView {
        ConfiguringView(
            toolbarIdentifier: toolbarIdentifier,
            minWidth: minWidth,
            minHeight: minHeight,
            preferredFrameWidth: preferredFrameWidth,
            fixedFrameHeight: fixedFrameHeight,
            titlebarHeight: titlebarHeight,
            titleOverride: titleOverride,
            titlebarBackAction: titlebarBackAction,
            titlebarBackAccessibilityLabel: titlebarBackAccessibilityLabel,
            titlebarHelpAction: titlebarHelpAction,
            titlebarHelpAccessibilityLabel: titlebarHelpAccessibilityLabel
        )
    }

    func updateNSView(_ nsView: ConfiguringView, context: Context) {
        nsView.toolbarIdentifier = toolbarIdentifier
        nsView.minWidth = minWidth
        nsView.minHeight = minHeight
        nsView.preferredFrameWidth = preferredFrameWidth
        nsView.fixedFrameHeight = fixedFrameHeight
        nsView.titlebarHeight = titlebarHeight
        nsView.titleOverride = titleOverride
        nsView.titlebarBackAction = titlebarBackAction
        nsView.titlebarBackAccessibilityLabel = titlebarBackAccessibilityLabel
        nsView.titlebarHelpAction = titlebarHelpAction
        nsView.titlebarHelpAccessibilityLabel = titlebarHelpAccessibilityLabel
        nsView.configureWindow()
    }

    final class ConfiguringView: NSView {
        var toolbarIdentifier: String
        var minWidth: CGFloat
        var minHeight: CGFloat
        var preferredFrameWidth: CGFloat?
        var fixedFrameHeight: CGFloat?
        var titlebarHeight: CGFloat
        var titleOverride: String?
        var titlebarBackAction: (() -> Void)?
        var titlebarBackAccessibilityLabel: String
        var titlebarHelpAction: (() -> Void)?
        var titlebarHelpAccessibilityLabel: String

        private var didScheduleInitialWindowResize = false
        private weak var observedWindow: NSWindow?
        private var windowLayoutObserverTokens: [NSObjectProtocol] = []
        private weak var titlebarBackAccessoryWindow: NSWindow?
        private var titlebarBackAccessoryController: NSTitlebarAccessoryViewController?
        private weak var titlebarHelpAccessoryWindow: NSWindow?
        private var titlebarHelpAccessoryController: NSTitlebarAccessoryViewController?

        init(
            toolbarIdentifier: String,
            minWidth: CGFloat,
            minHeight: CGFloat,
            preferredFrameWidth: CGFloat?,
            fixedFrameHeight: CGFloat?,
            titlebarHeight: CGFloat,
            titleOverride: String?,
            titlebarBackAction: (() -> Void)?,
            titlebarBackAccessibilityLabel: String,
            titlebarHelpAction: (() -> Void)?,
            titlebarHelpAccessibilityLabel: String
        ) {
            self.toolbarIdentifier = toolbarIdentifier
            self.minWidth = minWidth
            self.minHeight = minHeight
            self.preferredFrameWidth = preferredFrameWidth
            self.fixedFrameHeight = fixedFrameHeight
            self.titlebarHeight = titlebarHeight
            self.titleOverride = titleOverride
            self.titlebarBackAction = titlebarBackAction
            self.titlebarBackAccessibilityLabel = titlebarBackAccessibilityLabel
            self.titlebarHelpAction = titlebarHelpAction
            self.titlebarHelpAccessibilityLabel = titlebarHelpAccessibilityLabel
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeTitlebarHelpAccessory()
            }
            configureWindow()
        }

        func configureWindow() {
            guard let window else {
                return
            }

            window.styleMask.insert(.fullSizeContentView)
            window.identifier = NSUserInterfaceItemIdentifier(toolbarIdentifier)
            AppWindowForegroundController.registerPrimaryWindow(window)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: minWidth, height: minHeight)

            configureTitlebarToolbar(for: window)
            configureContentSafeArea(for: window)
            configureContentFrame(for: window)
            configureTitleOverlay(for: window)
            configureWindowLayoutObservers(for: window)
            scheduleInitialWindowResizeIfNeeded(for: window)
        }

        deinit {
            MainActor.assumeIsolated {
                removeTitlebarBackAccessory()
                removeTitlebarHelpAccessory()
                removeWindowLayoutObservers()
            }
        }

        private func configureTitlebarToolbar(for window: NSWindow) {
            let identifier = NSToolbar.Identifier(toolbarIdentifier)
            let toolbar = window.toolbar ?? NSToolbar(identifier: identifier)
            toolbar.showsBaselineSeparator = false
            toolbar.displayMode = .iconOnly
            toolbar.sizeMode = .small
            window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact
        }

        private func configureContentSafeArea(for window: NSWindow) {
            guard let contentView = window.contentView else {
                return
            }

            contentView.additionalSafeAreaInsets.top = -resolvedTitlebarHeight(for: window)
        }

        private func configureContentFrame(for window: NSWindow) {
            guard let contentView = window.contentView,
                  let frameView = contentView.superview else {
                return
            }

            contentView.frame = frameView.bounds
            contentView.autoresizingMask = [.width, .height]
        }

        private func configureTitleOverlay(for window: NSWindow) {
            guard let contentView = window.contentView,
                  let frameView = contentView.superview else {
                return
            }

            let titlebarLayoutHeight = max(resolvedTitlebarHeight(for: window), titlebarHeight)
            let titlebarCenterY = titlebarControlCenterY(
                for: window,
                frameView: frameView,
                titlebarLayoutHeight: titlebarLayoutHeight
            )

            if let titlebarBackAction {
                configureTitlebarBackAccessory(
                    for: window,
                    action: titlebarBackAction,
                    accessibilityLabel: titlebarBackAccessibilityLabel
                )
            } else {
                removeTitlebarBackAccessory()
            }

            if let titlebarHelpAction {
                configureTitlebarHelpAccessory(
                    for: window,
                    action: titlebarHelpAction,
                    accessibilityLabel: titlebarHelpAccessibilityLabel
                )
            } else {
                removeTitlebarHelpAccessory()
            }

            removeLegacyTitlebarBackSubviews(from: frameView)

            let titleView = frameView.subviews.compactMap { $0 as? AppWindowTitleOverlayView }.first
                ?? AppWindowTitleOverlayView()
            titleView.stringValue = titleOverride ?? window.title
            let titleX: CGFloat = titlebarBackAction == nil ? 104 : 156
            let titleRightInset: CGFloat = titlebarHelpAction == nil ? 104 : 156
            let titleHeight: CGFloat = 20
            let titleOpticalYOffset: CGFloat = -2
            titleView.frame = NSRect(
                x: titleX,
                y: titlebarCenterY - (titleHeight / 2) + titleOpticalYOffset,
                width: max(160, frameView.bounds.width - titleX - titleRightInset),
                height: titleHeight
            )
            titleView.autoresizingMask = [.width, .minYMargin]

            if titleView.superview == nil {
                frameView.addSubview(titleView, positioned: .above, relativeTo: nil)
            }
        }

        private func configureTitlebarBackAccessory(
            for window: NSWindow,
            action: @escaping () -> Void,
            accessibilityLabel: String
        ) {
            if titlebarBackAccessoryWindow !== window {
                removeTitlebarBackAccessory()
            }

            let buttonSize = NSSize(width: 44, height: 30)
            let container: AppWindowTitlebarAccessoryContainer
            if let existingContainer = titlebarBackAccessoryController?.view as? AppWindowTitlebarAccessoryContainer {
                container = existingContainer
            } else {
                container = AppWindowTitlebarAccessoryContainer(
                    button: AppWindowTitlebarAccessoryButton(
                        frame: NSRect(origin: .zero, size: buttonSize),
                        symbolName: "chevron.left",
                        symbolPointSize: 16,
                        symbolWeight: .semibold,
                        imageSize: NSSize(width: 18, height: 18),
                        backgroundVerticalInset: 3,
                        defaultAccessibilityLabel: "Back"
                    ),
                    buttonSize: buttonSize
                )

                let controller = NSTitlebarAccessoryViewController()
                controller.view = container
                controller.layoutAttribute = .left
                titlebarBackAccessoryController = controller
                window.addTitlebarAccessoryViewController(controller)
                titlebarBackAccessoryWindow = window
            }

            container.button.actionHandler = action
            container.button.accessibilityLabel = accessibilityLabel
        }

        private func removeTitlebarBackAccessory() {
            if let controller = titlebarBackAccessoryController,
               let accessoryWindow = titlebarBackAccessoryWindow,
               let index = accessoryWindow.titlebarAccessoryViewControllers.firstIndex(where: { $0 === controller }) {
                accessoryWindow.removeTitlebarAccessoryViewController(at: index)
            }

            titlebarBackAccessoryController = nil
            titlebarBackAccessoryWindow = nil
        }

        private func configureTitlebarHelpAccessory(
            for window: NSWindow,
            action: @escaping () -> Void,
            accessibilityLabel: String
        ) {
            if titlebarHelpAccessoryWindow !== window {
                removeTitlebarHelpAccessory()
            }

            let buttonSize = NSSize(width: 18, height: 18)
            let containerSize = NSSize(width: 44, height: 30)
            let container: AppWindowTitlebarAccessoryContainer
            if let existingContainer = titlebarHelpAccessoryController?.view as? AppWindowTitlebarAccessoryContainer {
                container = existingContainer
            } else {
                container = AppWindowTitlebarAccessoryContainer(
                    button: AppWindowTitlebarAccessoryButton(
                        frame: NSRect(origin: .zero, size: buttonSize),
                        symbolName: "questionmark.circle",
                        symbolPointSize: 15,
                        symbolWeight: .regular,
                        imageSize: buttonSize,
                        backgroundVerticalInset: 0,
                        defaultAccessibilityLabel: "Help"
                    ),
                    buttonSize: buttonSize,
                    containerSize: containerSize
                )

                let controller = NSTitlebarAccessoryViewController()
                controller.view = container
                controller.layoutAttribute = .right
                titlebarHelpAccessoryController = controller
                window.addTitlebarAccessoryViewController(controller)
                titlebarHelpAccessoryWindow = window
            }

            container.button.actionHandler = action
            container.button.accessibilityLabel = accessibilityLabel
        }

        private func removeTitlebarHelpAccessory() {
            if let controller = titlebarHelpAccessoryController,
               let accessoryWindow = titlebarHelpAccessoryWindow,
               let index = accessoryWindow.titlebarAccessoryViewControllers.firstIndex(where: { $0 === controller }) {
                accessoryWindow.removeTitlebarAccessoryViewController(at: index)
            }

            titlebarHelpAccessoryController = nil
            titlebarHelpAccessoryWindow = nil
        }

        private func removeLegacyTitlebarBackSubviews(from frameView: NSView) {
            for backButton in frameView.subviews.compactMap({ $0 as? AppWindowTitlebarAccessoryButton }) {
                backButton.removeFromSuperview()
            }
        }

        private func titlebarControlCenterY(
            for window: NSWindow,
            frameView: NSView,
            titlebarLayoutHeight: CGFloat
        ) -> CGFloat {
            if let closeButton = window.standardWindowButton(.closeButton),
               let buttonSuperview = closeButton.superview {
                return buttonSuperview.convert(
                    NSPoint(x: closeButton.frame.midX, y: closeButton.frame.midY),
                    to: frameView
                ).y
            }

            return frameView.bounds.height - (titlebarLayoutHeight / 2)
        }

        private func configureWindowLayoutObservers(for window: NSWindow) {
            guard observedWindow !== window else {
                return
            }

            removeWindowLayoutObservers()
            observedWindow = window

            let layoutNotificationNames: [NSNotification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didMoveNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ]

            windowLayoutObserverTokens = layoutNotificationNames.map { name in
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor [weak self, weak window] in
                        guard let self, let window else {
                            return
                        }
                        self.scheduleWindowLayoutRefresh(for: window)
                    }
                }
            }

            let didBecomeKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                Task { @MainActor [weak window] in
                    guard let window else {
                        return
                    }
                    AppWindowForegroundController.promote(window)
                }
            }
            windowLayoutObserverTokens.append(didBecomeKeyObserver)

            let willCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                Task { @MainActor [weak window] in
                    guard let window else {
                        return
                    }
                    AppWindowForegroundController.unregisterPrimaryWindow(window)
                }
            }
            windowLayoutObserverTokens.append(willCloseObserver)
        }

        private func removeWindowLayoutObservers() {
            if let observedWindow {
                AppWindowForegroundController.unregisterPrimaryWindow(observedWindow)
            }

            for token in windowLayoutObserverTokens {
                NotificationCenter.default.removeObserver(token)
            }
            windowLayoutObserverTokens.removeAll()
            observedWindow = nil
        }

        private func scheduleWindowLayoutRefresh(for window: NSWindow) {
            refreshWindowLayout(for: window)

            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else {
                    return
                }
                self.refreshWindowLayout(for: window)
            }
        }

        private func refreshWindowLayout(for window: NSWindow) {
            configureContentSafeArea(for: window)
            configureContentFrame(for: window)
            configureTitleOverlay(for: window)
        }

        private func resolvedTitlebarHeight(for window: NSWindow) -> CGFloat {
            let computedHeight = window.frame.height - window.contentLayoutRect.height
            if computedHeight > 1 {
                return computedHeight
            }

            return titlebarHeight
        }

        private func scheduleInitialWindowResizeIfNeeded(for window: NSWindow) {
            guard (preferredFrameWidth != nil || fixedFrameHeight != nil),
                  !didScheduleInitialWindowResize else {
                return
            }

            didScheduleInitialWindowResize = true
            resizeWindow(window)

            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else {
                    return
                }
                self.resizeWindow(window)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak window] in
                guard let self, let window else {
                    return
                }
                self.resizeWindow(window)
            }
        }

        private func resizeWindow(_ window: NSWindow) {
            let targetWidth = preferredFrameWidth.map { max($0, minWidth) }
            let targetHeight = fixedFrameHeight
            let needsWidthUpdate = targetWidth.map { abs(window.frame.width - $0) > 1 } ?? false
            let needsHeightUpdate = targetHeight.map { abs(window.frame.height - $0) > 1 } ?? false

            guard needsWidthUpdate || needsHeightUpdate else {
                return
            }

            var frame = window.frame
            let oldMaxY = frame.maxY
            if let targetWidth {
                let oldMidX = frame.midX
                frame.size.width = targetWidth
                frame.origin.x = oldMidX - (frame.width / 2)
            } else {
                frame.size.width = max(frame.width, minWidth)
            }
            if let targetHeight {
                frame.size.height = targetHeight
                frame.origin.y = oldMaxY - frame.height
            }
            window.setFrame(frame, display: true)
            configureContentSafeArea(for: window)
            configureContentFrame(for: window)
            configureTitleOverlay(for: window)
        }
    }
}

private final class AppWindowTitleOverlayView: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func configure() {
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
        font = .systemFont(ofSize: 14, weight: .semibold)
        textColor = .labelColor
        alignment = .left
        setAccessibilityElement(false)
    }
}

private final class AppWindowTitlebarAccessoryContainer: NSView {
    let button: AppWindowTitlebarAccessoryButton

    private let buttonSize: NSSize
    private let containerSize: NSSize

    init(
        button: AppWindowTitlebarAccessoryButton,
        buttonSize: NSSize,
        containerSize: NSSize? = nil
    ) {
        self.button = button
        self.buttonSize = buttonSize
        self.containerSize = containerSize ?? buttonSize
        super.init(frame: NSRect(origin: .zero, size: self.containerSize))
        addSubview(button)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: containerSize.width, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        button.frame = NSRect(
            x: (bounds.width - buttonSize.width) / 2,
            y: (bounds.height - buttonSize.height) / 2,
            width: buttonSize.width,
            height: buttonSize.height
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let buttonPoint = convert(point, to: button)
        return button.hitTest(buttonPoint)
    }
}

private final class AppWindowTitlebarAccessoryButton: NSButton {
    var actionHandler: (() -> Void)?

    private let glassView = NSVisualEffectView()
    private let hoverOverlayView = NSView()
    private let imageView = NSImageView()
    private let symbolName: String
    private let symbolPointSize: CGFloat
    private let symbolWeight: NSFont.Weight
    private let imageSize: NSSize
    private let backgroundVerticalInset: CGFloat

    private var isHovered = false {
        didSet {
            updateVisualState()
        }
    }

    private var isPressed = false {
        didSet {
            updateVisualState()
        }
    }

    var accessibilityLabel: String {
        didSet {
            setAccessibilityLabel(accessibilityLabel)
            toolTip = accessibilityLabel
        }
    }

    init(
        frame frameRect: NSRect,
        symbolName: String,
        symbolPointSize: CGFloat,
        symbolWeight: NSFont.Weight,
        imageSize: NSSize,
        backgroundVerticalInset: CGFloat,
        defaultAccessibilityLabel: String
    ) {
        self.symbolName = symbolName
        self.symbolPointSize = symbolPointSize
        self.symbolWeight = symbolWeight
        self.imageSize = imageSize
        self.backgroundVerticalInset = backgroundVerticalInset
        self.accessibilityLabel = defaultAccessibilityLabel
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
        updateVisualState()
    }

    override func layout() {
        super.layout()
        let backgroundFrame = bounds.insetBy(dx: 0, dy: min(backgroundVerticalInset, bounds.height / 2))
        glassView.frame = backgroundFrame
        hoverOverlayView.frame = backgroundFrame
        let cornerRadius = backgroundFrame.height / 2
        layer?.cornerRadius = cornerRadius
        layer?.shadowPath = CGPath(
            roundedRect: backgroundFrame,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        glassView.layer?.cornerRadius = cornerRadius
        hoverOverlayView.layer?.cornerRadius = cornerRadius

        imageView.frame = NSRect(
            x: (bounds.width - imageSize.width) / 2,
            y: (bounds.height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                owner: self
            )
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func highlight(_ flag: Bool) {
        isPressed = flag
        super.highlight(false)
    }

    @objc private func performAction() {
        actionHandler?()
    }

    private func updateVisualState() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let showsBackground = isHovered || isPressed
        glassView.material = isDark ? .hudWindow : .popover
        glassView.isHidden = !showsBackground
        hoverOverlayView.isHidden = !showsBackground
        hoverOverlayView.layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(isPressed ? 0.16 : 0.10)
            : NSColor.black.withAlphaComponent(isPressed ? 0.10 : 0.06)
        ).cgColor
        layer?.shadowOpacity = showsBackground ? (isHovered ? 0.10 : 0.08) : 0
        layer?.shadowRadius = isHovered ? 11 : 9
    }

    private func configure() {
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        target = self
        action = #selector(performAction)

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: symbolWeight)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(symbolConfiguration)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor

        glassView.material = .popover
        glassView.blendingMode = .withinWindow
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 15
        glassView.layer?.masksToBounds = true

        hoverOverlayView.wantsLayer = true
        hoverOverlayView.layer?.cornerRadius = 15
        hoverOverlayView.layer?.masksToBounds = true

        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.borderWidth = 0
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 9
        layer?.shadowOffset = NSSize(width: 0, height: 4)

        addSubview(glassView)
        addSubview(hoverOverlayView)
        addSubview(imageView)

        glassView.setAccessibilityElement(false)
        hoverOverlayView.setAccessibilityElement(false)
        imageView.setAccessibilityElement(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel)
        toolTip = accessibilityLabel
        updateVisualState()
    }
}

struct AppWindowTitlebarFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(nsColor: .windowBackgroundColor), location: 0.00),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.92), location: 0.24),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.00), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
