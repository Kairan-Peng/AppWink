import AppKit
import AppWinkCore
import SwiftUI

enum BindingOpenModeSegment: Equatable {
    case open
    case menu
}

struct BindingOpenModeMenu: View {
    let binding: HotkeyBinding
    let presentation: HotkeyTargetPresentation
    let openTarget: () -> Void
    let selectFolderMode: (FolderOpenMode) -> Void
    let selectFileMode: (FileOpenMode) -> Void
    let chooseOtherApplication: () -> Void

    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var hoveredSegment: BindingOpenModeSegment?

    var body: some View {
        if let openingMode = presentation.openingMode {
            controlLabel(openingMode: openingMode)
                .overlay {
                    BindingOpenModeSplitHitTarget(
                        binding: binding,
                        presentation: presentation,
                        finderTitle: localized(.finderNewTab),
                        chooseOtherApplicationTitle: localized(.chooseOtherApplication),
                        openingApplicationUnavailableTitle: localized(.openingApplicationUnavailable),
                        openAccessibilityLabel: localized(
                            .openTargetWithApplication,
                            openingMode.label,
                            presentation.displayName
                        ),
                        menuAccessibilityLabel: localized(.openWith),
                        menuAccessibilityValue: openingMode.label,
                        openTarget: openTarget,
                        selectFolderMode: selectFolderMode,
                        selectFileMode: selectFileMode,
                        chooseOtherApplication: chooseOtherApplication,
                        onHover: updateHover
                    )
                }
        }
    }

    private func controlLabel(
        openingMode: HotkeyTargetPresentation.OpeningMode
    ) -> some View {
        ZStack {
            Color.clear
                .frame(
                    width: SettingsDesignTokens.BindingOpenMode.width,
                    height: SettingsDesignTokens.BindingOpenMode.height
                )
                .settingsRecorderChrome(
                    shape: controlShape,
                    isHovered: false
                )

            hoveredSegmentChrome

            HStack(spacing: 0) {
                icon(
                    image: openingMode.image,
                    fallbackSymbolName: openingMode.fallbackSymbolName,
                    size: SettingsDesignTokens.BindingOpenMode.iconSize
                )
                .frame(
                    width: SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
                    height: SettingsDesignTokens.BindingOpenMode.height
                )

                Rectangle()
                    .fill(.primary.opacity(hoveredSegment == nil ? 0.11 : 0.16))
                    .frame(
                        width: SettingsDesignTokens.BindingOpenMode.dividerWidth,
                        height: SettingsDesignTokens.BindingOpenMode.dividerHeight
                    )

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: SettingsDesignTokens.BindingOpenMode.chevronRegionWidth,
                        height: SettingsDesignTokens.BindingOpenMode.height
                    )
            }
        }
        .frame(
            width: SettingsDesignTokens.BindingOpenMode.width,
            height: SettingsDesignTokens.BindingOpenMode.height
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var hoveredSegmentChrome: some View {
        switch hoveredSegment {
        case .open:
            segmentChrome(
                width: SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
                shape: UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: SettingsDesignTokens.BindingOpenMode.radius,
                        bottomLeading: SettingsDesignTokens.BindingOpenMode.radius
                    ),
                    style: .continuous
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case .menu:
            segmentChrome(
                width: SettingsDesignTokens.BindingOpenMode.width -
                    SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
                shape: UnevenRoundedRectangle(
                    cornerRadii: .init(
                        bottomTrailing: SettingsDesignTokens.BindingOpenMode.radius,
                        topTrailing: SettingsDesignTokens.BindingOpenMode.radius
                    ),
                    style: .continuous
                )
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        case nil:
            EmptyView()
        }
    }

    private func segmentChrome<S: InsettableShape>(
        width: CGFloat,
        shape: S
    ) -> some View {
        Color.clear
            .frame(
                width: width,
                height: SettingsDesignTokens.BindingOpenMode.height
            )
            .settingsRecorderChrome(shape: shape, isHovered: true)
    }

    private var controlShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SettingsDesignTokens.BindingOpenMode.radius,
            style: .continuous
        )
    }

    @ViewBuilder
    private func icon(
        image: NSImage?,
        fallbackSymbolName: String,
        size: CGFloat
    ) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSymbolName)
                .frame(width: size, height: size)
        }
    }

    private func updateHover(
        segment: BindingOpenModeSegment,
        isHovered: Bool
    ) {
        if isHovered {
            hoveredSegment = segment
        } else if hoveredSegment == segment {
            hoveredSegment = nil
        }
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }

    private func localized(
        _ key: LocalizationKey,
        _ arguments: CVarArg...
    ) -> String {
        localizationManager.string(for: key, arguments: arguments)
    }
}

struct BindingOpenModeSplitHitTarget: NSViewRepresentable {
    let binding: HotkeyBinding
    let presentation: HotkeyTargetPresentation
    let finderTitle: String
    let chooseOtherApplicationTitle: String
    let openingApplicationUnavailableTitle: String
    let openAccessibilityLabel: String
    let menuAccessibilityLabel: String
    let menuAccessibilityValue: String
    let openTarget: () -> Void
    let selectFolderMode: (FolderOpenMode) -> Void
    let selectFileMode: (FileOpenMode) -> Void
    let chooseOtherApplication: () -> Void
    let onHover: (BindingOpenModeSegment, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectFolderMode: selectFolderMode,
            selectFileMode: selectFileMode,
            chooseOtherApplication: chooseOtherApplication
        )
    }

    func makeNSView(context: Context) -> BindingOpenModeSplitHitTargetView {
        let view = BindingOpenModeSplitHitTargetView(frame: .zero)
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(
        _ nsView: BindingOpenModeSplitHitTargetView,
        context: Context
    ) {
        let coordinator = context.coordinator
        coordinator.selectFolderMode = selectFolderMode
        coordinator.selectFileMode = selectFileMode
        coordinator.chooseOtherApplication = chooseOtherApplication
        configure(nsView, coordinator: coordinator)
    }

    private func configure(
        _ view: BindingOpenModeSplitHitTargetView,
        coordinator: Coordinator
    ) {
        coordinator.binding = binding
        coordinator.presentation = presentation
        coordinator.finderTitle = finderTitle
        coordinator.chooseOtherApplicationTitle = chooseOtherApplicationTitle
        coordinator.openingApplicationUnavailableTitle = openingApplicationUnavailableTitle

        view.openButton.activationHandler = openTarget
        view.openButton.hoverHandler = { onHover(.open, $0) }
        view.openButton.setAccessibilityElement(true)
        view.openButton.setAccessibilityRole(.button)
        view.openButton.setAccessibilityLabel(openAccessibilityLabel)
        view.openButton.toolTip = openAccessibilityLabel

        view.menuButton.coordinator = coordinator
        view.menuButton.hoverHandler = { onHover(.menu, $0) }
        view.menuButton.setAccessibilityElement(true)
        view.menuButton.setAccessibilityRole(.popUpButton)
        view.menuButton.setAccessibilityLabel(menuAccessibilityLabel)
        view.menuButton.setAccessibilityValue(menuAccessibilityValue)
        view.menuButton.toolTip = "\(menuAccessibilityLabel): \(menuAccessibilityValue)"
    }

    final class Coordinator: NSObject {
        var binding: HotkeyBinding?
        var presentation: HotkeyTargetPresentation?
        var finderTitle = ""
        var chooseOtherApplicationTitle = ""
        var openingApplicationUnavailableTitle = ""
        var selectFolderMode: (FolderOpenMode) -> Void
        var selectFileMode: (FileOpenMode) -> Void
        var chooseOtherApplication: () -> Void

        init(
            selectFolderMode: @escaping (FolderOpenMode) -> Void,
            selectFileMode: @escaping (FileOpenMode) -> Void,
            chooseOtherApplication: @escaping () -> Void
        ) {
            self.selectFolderMode = selectFolderMode
            self.selectFileMode = selectFileMode
            self.chooseOtherApplication = chooseOtherApplication
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            guard let binding, let presentation else {
                return menu
            }

            switch binding.target {
            case .application:
                return menu
            case .folder(_, let selectedMode):
                menu.addItem(
                    item(
                        title: finderTitle,
                        image: presentation.finderOpeningMode?.image,
                        fallbackSymbolName: "folder",
                        state: selectedMode == .finderNewTab ? .on : .off,
                        action: #selector(selectFolderDefault(_:))
                    )
                )
            case .file(_, let selectedMode):
                menu.addItem(
                    item(
                        title: presentation.systemDefaultOpeningMode?.label ??
                            openingApplicationUnavailableTitle,
                        image: presentation.systemDefaultOpeningMode?.image,
                        fallbackSymbolName: "app.fill",
                        state: selectedMode == .systemDefault ? .on : .off,
                        action: #selector(selectFileDefault(_:))
                    )
                )
            }

            if !presentation.applicationCandidates.isEmpty {
                menu.addItem(.separator())
            }

            for option in presentation.applicationCandidates {
                let menuItem = item(
                    title: option.displayName,
                    image: option.image,
                    fallbackSymbolName: "app.fill",
                    state: option.isSelected ? .on : .off,
                    action: #selector(selectApplication(_:))
                )
                menuItem.representedObject = option.application
                menu.addItem(menuItem)
            }

            menu.addItem(.separator())
            menu.addItem(
                item(
                    title: chooseOtherApplicationTitle,
                    image: nil,
                    fallbackSymbolName: "ellipsis",
                    state: .off,
                    action: #selector(chooseOther(_:))
                )
            )
            return menu
        }

        @objc func selectFolderDefault(_ sender: NSMenuItem) {
            selectFolderMode(.finderNewTab)
        }

        @objc func selectFileDefault(_ sender: NSMenuItem) {
            selectFileMode(.systemDefault)
        }

        @objc func selectApplication(_ sender: NSMenuItem) {
            guard let application = sender.representedObject as? ManagedApplication,
                  let binding else {
                return
            }

            switch binding.target {
            case .application:
                return
            case .folder:
                selectFolderMode(.application(application))
            case .file:
                selectFileMode(.application(application))
            }
        }

        @objc func chooseOther(_ sender: NSMenuItem) {
            chooseOtherApplication()
        }

        private func item(
            title: String,
            image: NSImage?,
            fallbackSymbolName: String,
            state: NSControl.StateValue,
            action: Selector
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = state
            item.isEnabled = true
            item.image = menuImage(image, fallbackSymbolName: fallbackSymbolName)
            return item
        }

        private func menuImage(
            _ image: NSImage?,
            fallbackSymbolName: String
        ) -> NSImage? {
            let resolved = image?.copy() as? NSImage ??
                NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: nil)
            resolved?.size = NSSize(width: 16, height: 16)
            return resolved
        }
    }
}

final class BindingOpenModeSplitHitTargetView: NSView {
    let openButton = BindingOpenModeOpenHitTargetView(frame: .zero)
    let menuButton = BindingOpenModeMenuHitTargetView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureButtons()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureButtons()
    }

    override func layout() {
        super.layout()
        let openWidth = min(
            SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
            bounds.width
        )
        openButton.frame = NSRect(
            x: 0,
            y: 0,
            width: openWidth,
            height: bounds.height
        )
        menuButton.frame = NSRect(
            x: openWidth,
            y: 0,
            width: max(0, bounds.width - openWidth),
            height: bounds.height
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }
        return point.x < openButton.frame.maxX ? openButton : menuButton
    }

    private func configureButtons() {
        configure(openButton)
        configure(menuButton)
        addSubview(openButton)
        addSubview(menuButton)
        openButton.nextKeyView = menuButton
        setAccessibilityElement(false)
    }

    private func configure(_ button: NSButton) {
        button.isBordered = false
        button.title = ""
        button.imagePosition = .noImage
        button.setButtonType(.momentaryChange)
    }
}

class BindingOpenModeHitTargetView: NSButton {
    var hoverHandler: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .none
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var canBecomeKeyView: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverHandler?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverHandler?(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            hoverHandler?(false)
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

final class BindingOpenModeOpenHitTargetView: BindingOpenModeHitTargetView {
    var activationHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        activate()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76:
            activate()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    func activate() {
        activationHandler?()
    }
}

final class BindingOpenModeMenuHitTargetView: BindingOpenModeHitTargetView {
    weak var coordinator: BindingOpenModeSplitHitTarget.Coordinator?
    var menuPresentationHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        showMenu()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76, 125, 126:
            showMenu()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        showMenu()
        return true
    }

    func showMenu() {
        if let menuPresentationHandler {
            menuPresentationHandler()
            return
        }

        guard let coordinator else {
            return
        }

        let menu = coordinator.makeMenu()
        let selectedItem = menu.items.first { $0.state == .on }
        menu.popUp(
            positioning: selectedItem,
            at: NSPoint(x: 0, y: bounds.height),
            in: self
        )
    }
}
