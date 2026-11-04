import AppKit
import QuartzCore
import SwiftUI

@MainActor
/// Manages the passive target-icon flash overlay shown after accepted hotkey actions.
final class AppIconFlashOverlayPanelController {
    private static let postActivationReorderDelay: TimeInterval = 0.06

    private var panel: AppIconFlashOverlayPanel?
    private var fadeWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?
    private var animationSessionID = 0
    private let performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder

    init(performanceDiagnosticsRecorder: PerformanceDiagnosticsRecorder = .shared) {
        self.performanceDiagnosticsRecorder = performanceDiagnosticsRecorder
    }

    func show(payload: HotKeyTargetFlashPayload) {
        guard let image = payload.targetImage ??
                NSImage(
                    systemSymbolName: payload.fallbackSymbolName,
                    accessibilityDescription: nil
                ) else {
            return
        }
        show(image: image, screenFrame: payload.screenFrame)
    }

    func hide() {
        cancelPendingAnimation()
        hidePanel(panel)
    }

    private func show(image: NSImage, screenFrame: CGRect) {
        let intervalToken = performanceDiagnosticsRecorder.beginInterval(
            category: .overlay,
            name: "appIconFlashShow"
        )
        defer {
            performanceDiagnosticsRecorder.endInterval(intervalToken)
        }

        cancelPendingAnimation()

        let frame = centeredFrame(in: screenFrame)
        let sessionID = animationSessionID
        let panel = panel ?? makePanel(contentFrame: frame)
        self.panel = panel

        stopAlphaAnimation(on: panel)
        panel.alphaValue = 1
        panel.contentView = NSHostingView(
            rootView: AppIconFlashOverlayView(
                image: image,
                opacity: SettingsDesignTokens.AppIconFlash.peakOpacity,
                iconSize: min(SettingsDesignTokens.AppIconFlash.iconSize, frame.width, frame.height)
            )
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        schedulePostActivationReorder(panel, sessionID: sessionID)
        scheduleFadeAndHide(panel, sessionID: sessionID)
        performanceDiagnosticsRecorder.recordEvent(
            category: .overlay,
            name: "appIconFlashShow"
        )
    }

    private func makePanel(contentFrame: NSRect) -> AppIconFlashOverlayPanel {
        let panel = AppIconFlashOverlayPanel(
            contentRect: contentFrame,
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        return panel
    }

    private func centeredFrame(in screenFrame: CGRect) -> NSRect {
        let visibleFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: screenFrame.height
        )
        let size = SettingsDesignTokens.AppIconFlash.iconSize
        let inset = SettingsDesignTokens.AppIconFlash.edgeInset
        let width = min(size, max(1, visibleFrame.width - (inset * 2)))
        let height = min(size, max(1, visibleFrame.height - (inset * 2)))
        let horizontalInset = min(inset, max(0, (visibleFrame.width - width) / 2))
        let verticalInset = min(inset, max(0, (visibleFrame.height - height) / 2))
        let originX = min(
            max(visibleFrame.midX - (width / 2), visibleFrame.minX + horizontalInset),
            visibleFrame.maxX - width - horizontalInset
        )
        let originY = min(
            max(visibleFrame.midY - (height / 2), visibleFrame.minY + verticalInset),
            visibleFrame.maxY - height - verticalInset
        )

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func schedulePostActivationReorder(_ panel: NSPanel, sessionID: Int) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.postActivationReorderDelay
        ) { [weak self, weak panel] in
            guard self?.animationSessionID == sessionID else {
                return
            }

            panel?.orderFrontRegardless()
        }
    }

    private func scheduleFadeAndHide(_ panel: NSPanel, sessionID: Int) {
        let fadeWorkItem = DispatchWorkItem { [weak self, weak panel] in
            guard self?.animationSessionID == sessionID else {
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = SettingsDesignTokens.AppIconFlash.fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel?.animator().alphaValue = 0
            }
        }
        self.fadeWorkItem = fadeWorkItem

        let hideWorkItem = DispatchWorkItem { [weak self, weak panel] in
            guard self?.animationSessionID == sessionID else {
                return
            }

            self?.hidePanel(panel)
            panel?.alphaValue = 1
            if self?.panel === panel {
                self?.fadeWorkItem = nil
                self?.hideWorkItem = nil
            }
        }
        self.hideWorkItem = hideWorkItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + SettingsDesignTokens.AppIconFlash.holdDuration,
            execute: fadeWorkItem
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SettingsDesignTokens.AppIconFlash.holdDuration + SettingsDesignTokens.AppIconFlash.fadeOutDuration,
            execute: hideWorkItem
        )
    }

    private func cancelPendingAnimation() {
        animationSessionID += 1
        fadeWorkItem?.cancel()
        hideWorkItem?.cancel()
        fadeWorkItem = nil
        hideWorkItem = nil
        if let panel {
            stopAlphaAnimation(on: panel)
            panel.alphaValue = 1
        }
    }

    private func stopAlphaAnimation(on panel: NSPanel) {
        panel.animations[NSAnimatablePropertyKey("alphaValue")] = nil
        panel.contentView?.layer?.removeAllAnimations()
    }

    private func hidePanel(_ panel: NSPanel?) {
        panel?.orderOut(nil)
        performanceDiagnosticsRecorder.recordEvent(
            category: .overlay,
            name: "appIconFlashHide"
        )
    }
}

private final class AppIconFlashOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: backing,
            defer: flag
        )
    }
}
