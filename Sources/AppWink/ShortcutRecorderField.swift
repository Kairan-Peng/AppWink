import AppKit
import SwiftUI
import AppWinkCore

/// 让文本在胶囊型输入框中保持视觉垂直居中。
private final class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let defaultRect = super.drawingRect(forBounds: rect)
        let titleSize = cellSize(forBounds: rect)
        let delta = max(0, defaultRect.height - titleSize.height)

        guard delta > 0 else {
            return defaultRect
        }

        var adjustedRect = defaultRect
        adjustedRect.origin.y += floor(delta / 2)
        adjustedRect.size.height = titleSize.height
        return adjustedRect
    }
}

/// 用 AppKit 文本框承载热键录制，供 SwiftUI 设置页复用。
struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: AppShortcut?
    let allowsAdvancedHotkeys: Bool
    let onRecordingChanged: (Bool) -> Void
    let placeholder: String
    let controlHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> RecorderTextField {
        let field = RecorderTextField()
        field.coordinator = context.coordinator
        field.allowsAdvancedHotkeys = allowsAdvancedHotkeys
        field.recordingStateDidChange = onRecordingChanged
        field.placeholderText = placeholder
        field.preferredHeight = controlHeight
        field.currentShortcut = shortcut
        field.refreshDisplay()
        return field
    }

    func updateNSView(_ nsView: RecorderTextField, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.allowsAdvancedHotkeys = allowsAdvancedHotkeys
        nsView.recordingStateDidChange = onRecordingChanged
        nsView.placeholderText = placeholder
        if nsView.preferredHeight != controlHeight {
            nsView.preferredHeight = controlHeight
        }
        nsView.currentShortcut = shortcut
        nsView.refreshDisplay()
    }

    @MainActor
    /// 在 SwiftUI `Binding` 与 AppKit 视图之间同步快捷键值。
    final class Coordinator: NSObject {
        private var parent: ShortcutRecorderField

        init(parent: ShortcutRecorderField) {
            self.parent = parent
        }

        func update(shortcut: AppShortcut?) {
            parent.shortcut = shortcut
        }
    }
}

/// 自定义热键录制输入框，只接受字母/数字并屏蔽不受支持的组合键。
final class RecorderTextField: NSTextField {
    weak var coordinator: ShortcutRecorderField.Coordinator?

    var currentShortcut: AppShortcut?
    var allowsAdvancedHotkeys = false
    var recordingStateDidChange: ((Bool) -> Void)?
    var placeholderText = ""
    var preferredHeight: CGFloat = 38 {
        didSet {
            guard preferredHeight != oldValue else {
                return
            }

            invalidateIntrinsicContentSize()
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

    private let backgroundGradientLayer = CAGradientLayer()
    private let highlightGradientLayer = CAGradientLayer()
    private var isRecordingShortcut = false
    private var isHovered = false
    private var outsideClickMonitor: Any?
    private var hoverTrackingArea: NSTrackingArea?
    private var windowResignKeyObserver: NSObjectProtocol?

    #if DEBUG
    var currentHoverStateForTesting: Bool {
        isHovered
    }
    #endif

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: preferredHeight)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            updateRecordingState(true)
            // 录制状态下监听外部点击，用于模拟“点击空白处退出录制”的原生体验。
            installOutsideClickMonitor()
        }
        refreshDisplay()
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            updateRecordingState(false)
            removeOutsideClickMonitor()
        }
        refreshDisplay()
        return didResignFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        if isRecordingShortcut {
            window?.makeFirstResponder(nil)
        } else {
            window?.makeFirstResponder(self)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHoverState(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateHoverState(false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        reconcileHoverStateWithCurrentMouseLocation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        removeWindowObservers()
        guard window != nil else {
            updateRecordingState(false)
            removeOutsideClickMonitor()
            updateHoverState(false)
            return
        }

        installWindowObservers()
        reconcileHoverStateWithCurrentMouseLocation()
    }

    override func removeFromSuperview() {
        updateHoverState(false)
        removeWindowObservers()
        super.removeFromSuperview()
    }

    override func layout() {
        super.layout()

        guard let layer else {
            return
        }

        // 录制框完全由图层驱动视觉效果，因此在布局阶段同步圆角、阴影和渐变尺寸。
        installSublayersIfNeeded()
        layer.cornerRadius = bounds.height / 2
        layer.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: bounds.height / 2,
            cornerHeight: bounds.height / 2,
            transform: nil
        )

        backgroundGradientLayer.frame = bounds
        backgroundGradientLayer.cornerRadius = bounds.height / 2
        highlightGradientLayer.frame = bounds.insetBy(dx: 1, dy: 1)
        highlightGradientLayer.cornerRadius = max(0, (bounds.height - 2) / 2)
        reconcileHoverStateWithCurrentMouseLocation()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecordingShortcut else {
            return super.performKeyEquivalent(with: event)
        }

        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }

        // Delete / Backspace 被定义为“清空快捷键”，避免要求用户额外点按钮。
        if event.keyCode == 51 || event.keyCode == 117 {
            currentShortcut = nil
            coordinator?.update(shortcut: nil)
            window?.makeFirstResponder(nil)
            return
        }

        let supportsKeyCode = allowsAdvancedHotkeys
            ? QuickSwitchShortcutPalette.isAdvancedSupportedKeyCode(event.keyCode)
            : QuickSwitchShortcutPalette.isSupportedKeyCode(event.keyCode)
        guard supportsKeyCode else {
            NSSound.beep()
            return
        }

        let eventModifiers = event.modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift,
        ])
        let modifiers: AppShortcutModifiers
        if allowsAdvancedHotkeys {
            modifiers = eventModifiers.isEmpty
                ? QuickSwitchShortcutPalette.defaultModifiers
                : AppShortcutModifiers(eventFlags: eventModifiers)
        } else {
            guard eventModifiers.isEmpty else {
                NSSound.beep()
                return
            }
            modifiers = QuickSwitchShortcutPalette.defaultModifiers
        }

        let shortcut = AppShortcut(keyCode: event.keyCode, modifiers: modifiers)
        currentShortcut = shortcut
        coordinator?.update(shortcut: shortcut)
        window?.makeFirstResponder(nil)
    }

    /// 根据录制态、已配置值和占位文案刷新显示文本与外观。
    func refreshDisplay() {
        if isRecordingShortcut {
            applyDisplayText(
                LocalizationManager.shared.string(for: .recordShortcut),
                color: .labelColor
            )
            updateAppearance()
            return
        }

        if let currentShortcut {
            applyDisplayText(currentShortcut.displayString, color: .labelColor)
        } else {
            applyDisplayText(placeholderText, color: .secondaryLabelColor)
        }

        updateAppearance()
    }

    /// 一次性设置文本框的交互模式和图层样式，让它表现得更像一个轻量级录制按钮。
    private func configure() {
        cell = CenteredTextFieldCell(textCell: "")
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        backgroundColor = .clear
        lineBreakMode = .byTruncatingTail
        alignment = .center
        font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        cell?.wraps = false
        cell?.isScrollable = true
        cell?.usesSingleLineMode = true
        cell?.alignment = .center
        installSublayersIfNeeded()
        updateAppearance()
    }

    /// 所有状态文本都走富文本渲染，保证字距、截断和阴影效果一致。
    private func applyDisplayText(_ text: String, color: NSColor, shadowColor: NSColor? = nil) {
        let textShadow = NSShadow()
        textShadow.shadowOffset = CGSize(width: 0, height: -1)
        textShadow.shadowBlurRadius = shadowColor == nil ? 0 : 2
        textShadow.shadowColor = shadowColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: font ?? .monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
                .shadow: textShadow,
            ]
        )
    }

    /// 渐变层按需安装，避免在多次 layout 中重复创建子图层。
    private func installSublayersIfNeeded() {
        guard let layer else {
            return
        }

        if backgroundGradientLayer.superlayer == nil {
            backgroundGradientLayer.startPoint = CGPoint(x: 0.12, y: 1)
            backgroundGradientLayer.endPoint = CGPoint(x: 0.88, y: 0)
            layer.insertSublayer(backgroundGradientLayer, at: 0)
        }

        if highlightGradientLayer.superlayer == nil {
            highlightGradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
            highlightGradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
            layer.insertSublayer(highlightGradientLayer, above: backgroundGradientLayer)
        }
    }

    /// 录制时点击输入框外部应立即退出，避免焦点残留导致后续输入误写入。
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else {
            return
        }

        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self,
                  self.isRecordingShortcut,
                  let window = self.window,
                  event.window === window else {
                return event
            }

            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)
            if self.bounds.contains(locationInView) {
                return event
            }

            window.makeFirstResponder(nil)
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else {
            return
        }

        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func updateRecordingState(_ isRecording: Bool) {
        guard isRecordingShortcut != isRecording else {
            return
        }

        isRecordingShortcut = isRecording
        recordingStateDidChange?(isRecording)
    }

    private func installWindowObservers() {
        guard let window, windowResignKeyObserver == nil else {
            return
        }

        windowResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.updateHoverState(false)
                if self.isRecordingShortcut {
                    self.window?.makeFirstResponder(nil)
                }
            }
        }
    }

    private func removeWindowObservers() {
        if let windowResignKeyObserver {
            NotificationCenter.default.removeObserver(windowResignKeyObserver)
            self.windowResignKeyObserver = nil
        }
    }

    private func reconcileHoverStateWithCurrentMouseLocation() {
        guard let window, !isHiddenOrHasHiddenAncestor, !bounds.isEmpty, !visibleRect.isEmpty else {
            updateHoverState(false)
            return
        }

        let locationInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateHoverState(bounds.contains(locationInView) && visibleRect.contains(locationInView))
    }

    private func updateHoverState(_ isHovered: Bool) {
        guard self.isHovered != isHovered else {
            return
        }

        self.isHovered = isHovered
        updateAppearance()
    }

    /// 录制态和普通态使用不同高光、边框和阴影，让用户一眼看出当前是否正在等待按键。
    private func updateAppearance() {
        guard let layer else {
            return
        }

        installSublayersIfNeeded()
        layer.borderWidth = 1
        if isRecordingShortcut {
            applyAppearance(
                SettingsInteractiveSurfaceResolver.recorderMetrics(
                    isHovered: isHovered,
                    isRecording: true
                ),
                to: layer
            )
        } else if isHovered {
            applyAppearance(
                SettingsInteractiveSurfaceResolver.recorderMetrics(
                    isHovered: true,
                    isRecording: false
                ),
                to: layer
            )
        } else {
            applyAppearance(
                SettingsInteractiveSurfaceResolver.recorderMetrics(
                    isHovered: false,
                    isRecording: false
                ),
                to: layer
            )
        }
    }

    private func applyAppearance(_ metrics: SettingsInteractiveRecorderTokens, to layer: CALayer) {
        backgroundGradientLayer.colors = [
            NSColor.white.withAlphaComponent(metrics.backgroundStartOpacity).cgColor,
            NSColor.white.withAlphaComponent(metrics.backgroundEndOpacity).cgColor,
        ]
        highlightGradientLayer.startPoint = CGPoint(x: metrics.highlightStartPointX, y: 1)
        highlightGradientLayer.endPoint = CGPoint(x: metrics.highlightEndPointX, y: 0)
        highlightGradientLayer.locations = metrics.highlightLocations.map(NSNumber.init(value:))
        highlightGradientLayer.colors = metrics.highlightOpacities.map { opacity in
            NSColor.white.withAlphaComponent(opacity).cgColor
        }
        layer.backgroundColor = NSColor.clear.cgColor
        layer.borderColor = NSColor.white.withAlphaComponent(metrics.emphasisMetrics.strokeOpacity).cgColor
        layer.shadowColor = shadowColor(for: metrics.shadowTone, opacity: metrics.emphasisMetrics.shadowOpacity).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = metrics.shadowRadius
        layer.shadowOffset = metrics.shadowOffset
    }

    private func shadowColor(for tone: SettingsInteractiveRecorderShadowTone, opacity: Double) -> NSColor {
        switch tone {
        case .black:
            return NSColor.black.withAlphaComponent(opacity)
        case .white:
            return NSColor.white.withAlphaComponent(opacity)
        }
    }
}
