import AppKit

enum HiddenBarCollapsePolicy: Equatable {
    /// macOS 26 and earlier clamp an oversized pusher, so the collapsed item
    /// can still use the widest display width to push icons off-screen.
    case legacyOversized
    /// macOS 27 MenuBarAgent discards a status item that reaches half the
    /// display width. Stay under that cliff and let the system overflow
    /// chevron absorb displaced icons.
    case macOS27Capped
}

enum HiddenBarPresentationMetrics {
    static let collapsedArrowSystemName = "chevron.left"
    static let expandedArrowSystemName = "chevron.right"
    static let settingsRowIconSystemName = collapsedArrowSystemName
    static let boundaryAccessibilityDescription = "Hidden Bar managed area starts here"
    static let arrowLength: CGFloat = 18
    static let expandedBoundaryLength: CGFloat = 12
    static let boundaryImageSize = NSSize(width: 8, height: 18)
    static let boundaryLineRect = NSRect(x: 3, y: 2.5, width: 2, height: 13)
    static let minimumCollapsedPusherLength: CGFloat = 1_600
    static let maximumCollapsedPusherLength: CGFloat = 4_096
    static let macOS27CollapsedLengthRatio: CGFloat = 0.45
    static let macOS27DiscardThresholdRatio: CGFloat = 0.5

    static func collapsePolicy(
        majorOperatingSystemVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) -> HiddenBarCollapsePolicy {
        majorOperatingSystemVersion >= 27 ? .macOS27Capped : .legacyOversized
    }

    static func collapsedPusherLength(for screenWidths: [CGFloat]) -> CGFloat {
        collapsedPusherLength(for: screenWidths, policy: collapsePolicy())
    }

    static func collapsedPusherLength(
        for screenWidths: [CGFloat],
        policy: HiddenBarCollapsePolicy
    ) -> CGFloat {
        let validWidths = screenWidths.filter { $0.isFinite && $0 > 0 }

        switch policy {
        case .legacyOversized:
            let widestScreen = validWidths.max() ?? minimumCollapsedPusherLength
            return min(
                max(widestScreen.rounded(.up), minimumCollapsedPusherLength),
                maximumCollapsedPusherLength
            )
        case .macOS27Capped:
            let fallbackWidth = validWidths.min() ?? minimumCollapsedPusherLength
            let preferredLength = (fallbackWidth * macOS27CollapsedLengthRatio).rounded(.down)
            let discardCliffs = validWidths.map { width in
                (width * macOS27DiscardThresholdRatio).rounded(.down) - 1
            }
            let safestCliff = discardCliffs.min() ?? preferredLength
            return max(min(preferredLength, safestCliff, maximumCollapsedPusherLength), 1)
        }
    }
}

struct HiddenBarBoundaryMarkerPresentation {
    let image: NSImage
    let isEnabled: Bool
    let appearsDisabled: Bool
    let contentTintColor: NSColor?

    static func make() -> HiddenBarBoundaryMarkerPresentation {
        let image = NSImage(size: HiddenBarPresentationMetrics.boundaryImageSize)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(
            roundedRect: HiddenBarPresentationMetrics.boundaryLineRect,
            xRadius: HiddenBarPresentationMetrics.boundaryLineRect.width / 2,
            yRadius: HiddenBarPresentationMetrics.boundaryLineRect.width / 2
        ).fill()
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = HiddenBarPresentationMetrics.boundaryAccessibilityDescription

        return HiddenBarBoundaryMarkerPresentation(
            image: image,
            isEnabled: true,
            appearsDisabled: false,
            contentTintColor: nil
        )
    }
}

@MainActor
final class HiddenBarController: NSObject {
    private enum State {
        case collapsed
        case expanded
    }

    private enum Constants {
        static let arrowAutosaveName = "com.kairanpeng.appwink.hidden-bar.arrow"
        static let pusherAutosaveName = "com.kairanpeng.appwink.hidden-bar.pusher"
        static let autoCollapseDelay: TimeInterval = 30
    }

    private var arrowItem: NSStatusItem?
    private var pusherItem: NSStatusItem?
    private var state: State = .collapsed
    private var collapseTimer: Timer?
    private var timerGeneration = 0

    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            installIfNeeded()
        } else {
            removeItems()
        }
    }

    func teardown() {
        removeItems()
    }

    private func installIfNeeded() {
        guard arrowItem == nil || pusherItem == nil else {
            updatePresentation()
            return
        }

        removeItems()

        // macOS 27 can restore the old pusher to the arrow's right, hiding
        // our own control. Fresh, stable names reset only this pair's layout.
        let placementSuffix = HiddenBarPresentationMetrics.collapsePolicy() == .macOS27Capped
            ? ".layout-v2" : ""
        let statusBar = NSStatusBar.system
        let arrowItem = statusBar.statusItem(withLength: HiddenBarPresentationMetrics.arrowLength)
        arrowItem.autosaveName = NSStatusItem.AutosaveName(Constants.arrowAutosaveName + placementSuffix)
        guard let arrowButton = arrowItem.button else {
            statusBar.removeStatusItem(arrowItem)
            return
        }

        let pusherItem = statusBar.statusItem(withLength: HiddenBarPresentationMetrics.expandedBoundaryLength)
        pusherItem.autosaveName = NSStatusItem.AutosaveName(Constants.pusherAutosaveName + placementSuffix)
        pusherItem.button?.title = ""
        pusherItem.button?.image = nil
        pusherItem.button?.imagePosition = .noImage
        pusherItem.button?.isEnabled = false
        pusherItem.button?.appearsDisabled = true

        arrowButton.target = self
        arrowButton.action = #selector(toggleHiddenBar)
        arrowButton.toolTip = "AppWink Hidden Bar"

        self.pusherItem = pusherItem
        self.arrowItem = arrowItem
        state = .expanded
        updatePresentation()

        // Register both compact items before applying menu-bar layout pressure.
        let generation = timerGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.timerGeneration == generation,
                  self.arrowItem === arrowItem,
                  self.pusherItem === pusherItem else {
                return
            }
            self.collapse()
        }
    }

    @objc private func toggleHiddenBar() {
        switch state {
        case .collapsed:
            expand()
        case .expanded:
            collapse()
        }
    }

    private func expand() {
        state = .expanded
        updatePresentation()
        scheduleAutoCollapse()
    }

    private func collapse() {
        state = .collapsed
        updatePresentation()
        cancelAutoCollapse()
    }

    private func updatePresentation() {
        switch state {
        case .collapsed:
            arrowItem?.isVisible = true
            pusherItem?.isVisible = true
            resetPusherButton(pusherItem?.button)
            setPusherLength(collapsedPusherLength())
            setArrowImage(
                systemName: HiddenBarPresentationMetrics.collapsedArrowSystemName,
                accessibilityDescription: "Show hidden menu bar icons"
            )
        case .expanded:
            arrowItem?.isVisible = true
            pusherItem?.isVisible = true
            setPusherLength(HiddenBarPresentationMetrics.expandedBoundaryLength)
            showBoundaryMarker(on: pusherItem?.button)
            setArrowImage(
                systemName: HiddenBarPresentationMetrics.expandedArrowSystemName,
                accessibilityDescription: "Hide menu bar icons"
            )
        }
    }

    private func setArrowImage(systemName: String, accessibilityDescription: String) {
        let image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: accessibilityDescription
        )
        image?.isTemplate = true
        arrowItem?.button?.image = image
        arrowItem?.button?.imagePosition = .imageOnly
        arrowItem?.button?.setAccessibilityLabel(accessibilityDescription)
    }

    private func resetPusherButton(_ pusherButton: NSStatusBarButton?) {
        guard let pusherButton else {
            return
        }
        pusherButton.target = nil
        pusherButton.action = nil
        pusherButton.title = ""
        pusherButton.image = nil
        pusherButton.imagePosition = .noImage
        pusherButton.isEnabled = false
        pusherButton.appearsDisabled = true
        pusherButton.toolTip = nil
        pusherButton.setAccessibilityLabel(nil)
    }

    private func setPusherLength(_ length: CGFloat) {
        guard let pusherItem else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            pusherItem.length = length
        }
    }

    private func showBoundaryMarker(on boundaryButton: NSStatusBarButton?) {
        guard let boundaryButton else {
            return
        }
        let presentation = HiddenBarBoundaryMarkerPresentation.make()

        boundaryButton.target = nil
        boundaryButton.action = nil
        boundaryButton.title = ""
        boundaryButton.image = presentation.image
        boundaryButton.imagePosition = .imageOnly
        boundaryButton.imageScaling = .scaleNone
        boundaryButton.contentTintColor = presentation.contentTintColor
        boundaryButton.isEnabled = presentation.isEnabled
        boundaryButton.appearsDisabled = presentation.appearsDisabled
        boundaryButton.toolTip = HiddenBarPresentationMetrics.boundaryAccessibilityDescription
        boundaryButton.setAccessibilityLabel(HiddenBarPresentationMetrics.boundaryAccessibilityDescription)
    }

    private func collapsedPusherLength() -> CGFloat {
        HiddenBarPresentationMetrics.collapsedPusherLength(
            for: NSScreen.screens.map { $0.frame.width }
        )
    }

    private func scheduleAutoCollapse() {
        cancelAutoCollapse()
        timerGeneration += 1
        let generation = timerGeneration
        let timer = Timer(timeInterval: Constants.autoCollapseDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.timerGeneration == generation else {
                    return
                }
                self?.collapse()
            }
        }
        collapseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelAutoCollapse() {
        timerGeneration += 1
        collapseTimer?.invalidate()
        collapseTimer = nil
    }

    private func removeItems() {
        cancelAutoCollapse()
        if let arrowItem {
            NSStatusBar.system.removeStatusItem(arrowItem)
        }
        if let pusherItem {
            NSStatusBar.system.removeStatusItem(pusherItem)
        }
        arrowItem = nil
        pusherItem = nil
        state = .collapsed
    }
}
