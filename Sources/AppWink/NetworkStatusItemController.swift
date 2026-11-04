import AppKit
import AppWinkCore
import Foundation

enum NetworkStatusItemMetrics {
    static let width: CGFloat = 56
    static let fontSize: CGFloat = 9
    static let columnGap: CGFloat = 2
    static let refreshInterval: TimeInterval = 2
    static let autosaveName = "com.kairanpeng.appwink.network-monitor"
}

struct NetworkStatusItemLineLayout {
    let valueText: String
    let unitText: String?
    let valueRect: NSRect
    let unitRect: NSRect?
    let valueAlignment: NSTextAlignment
    let unitAlignment: NSTextAlignment?

    static func make(text: String, in lineRect: NSRect) -> Self {
        guard let separator = text.lastIndex(of: " "),
              separator != text.startIndex,
              text.index(after: separator) != text.endIndex else {
            return Self(
                valueText: text,
                unitText: nil,
                valueRect: lineRect,
                unitRect: nil,
                valueAlignment: .center,
                unitAlignment: nil
            )
        }

        let unitStart = text.index(after: separator)
        let valueWidth = lineRect.width / 2
        let unitMinX = lineRect.minX + valueWidth + NetworkStatusItemMetrics.columnGap
        return Self(
            valueText: String(text[..<separator]),
            unitText: String(text[unitStart...]),
            valueRect: NSRect(
                x: lineRect.minX,
                y: lineRect.minY,
                width: valueWidth,
                height: lineRect.height
            ),
            unitRect: NSRect(
                x: unitMinX,
                y: lineRect.minY,
                width: max(lineRect.maxX - unitMinX, 0),
                height: lineRect.height
            ),
            valueAlignment: .right,
            unitAlignment: .left
        )
    }
}

struct NetworkStatusItemPresentation: Equatable {
    let topText: String
    let bottomText: String
    let accessibilityText: String

    static func make(
        throughput: NetworkThroughput,
        accessibilityText: (String, String) -> String
    ) -> Self {
        let topText = NetworkSpeedFormatter.string(
            bytesPerSecond: throughput.uploadBytesPerSecond
        )
        let bottomText = NetworkSpeedFormatter.string(
            bytesPerSecond: throughput.downloadBytesPerSecond
        )
        return Self(
            topText: topText,
            bottomText: bottomText,
            accessibilityText: accessibilityText(topText, bottomText)
        )
    }

    static func zero(
        accessibilityText: (String, String) -> String
    ) -> Self {
        let text = NetworkSpeedFormatter.string(bytesPerSecond: 0)
        return Self(
            topText: text,
            bottomText: text,
            accessibilityText: accessibilityText(text, text)
        )
    }

    static func unavailable(
        accessibilityText: (String, String) -> String
    ) -> Self {
        let text = "--"
        return Self(
            topText: text,
            bottomText: text,
            accessibilityText: accessibilityText(text, text)
        )
    }

    private init(
        topText: String,
        bottomText: String,
        accessibilityText: String
    ) {
        self.topText = topText
        self.bottomText = bottomText
        self.accessibilityText = accessibilityText
    }
}

@MainActor
enum NetworkStatusItemRenderer {
    static func image(
        for presentation: NetworkStatusItemPresentation,
        height: CGFloat
    ) -> NSImage {
        image(for: presentation, height: height, drawText: drawText)
    }

    static func image(
        for presentation: NetworkStatusItemPresentation,
        height: CGFloat,
        drawText: @escaping (String, NSRect, NSTextAlignment) -> Void
    ) -> NSImage {
        let size = NSSize(width: NetworkStatusItemMetrics.width, height: height)
        let layouts = lineLayouts(for: presentation, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            draw(layouts.top, using: drawText)
            draw(layouts.bottom, using: drawText)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func lineLayouts(
        for presentation: NetworkStatusItemPresentation,
        height: CGFloat
    ) -> (top: NetworkStatusItemLineLayout, bottom: NetworkStatusItemLineLayout) {
        let rects = textRects(height: height)
        return (
            top: .make(text: presentation.topText, in: rects.top),
            bottom: .make(text: presentation.bottomText, in: rects.bottom)
        )
    }

    static func textRects(height: CGFloat) -> (top: NSRect, bottom: NSRect) {
        let availableHeight = max(height, 0)
        let lineHeight = min(ceil(font.boundingRectForFont.height), availableHeight / 2)
        let bottomOrigin = max((availableHeight - lineHeight * 2) / 2, 0)
        return (
            top: NSRect(
                x: 0,
                y: bottomOrigin + lineHeight,
                width: NetworkStatusItemMetrics.width,
                height: lineHeight
            ),
            bottom: NSRect(
                x: 0,
                y: bottomOrigin,
                width: NetworkStatusItemMetrics.width,
                height: lineHeight
            )
        )
    }

    private static func draw(
        _ layout: NetworkStatusItemLineLayout,
        using drawText: (String, NSRect, NSTextAlignment) -> Void
    ) {
        drawText(layout.valueText, layout.valueRect, layout.valueAlignment)
        if let unitText = layout.unitText,
           let unitRect = layout.unitRect,
           let unitAlignment = layout.unitAlignment {
            drawText(unitText, unitRect, unitAlignment)
        }
    }

    private static func drawText(
        _ text: String,
        in rect: NSRect,
        alignment: NSTextAlignment
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        text.draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ])
    }

    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: NetworkStatusItemMetrics.fontSize,
        weight: .semibold
    )
}

@MainActor
protocol NetworkStatusItemDisplaying: AnyObject {
    func install()
    func update(_ presentation: NetworkStatusItemPresentation)
    func remove()
}

@MainActor
final class AppKitNetworkStatusItemDisplay: NetworkStatusItemDisplaying {
    private(set) var statusItem: NSStatusItem?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(
            withLength: NetworkStatusItemMetrics.width
        )
        item.autosaveName = NSStatusItem.AutosaveName(
            NetworkStatusItemMetrics.autosaveName
        )
        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleNone
        item.button?.target = nil
        item.button?.action = nil
        item.button?.isEnabled = true
        statusItem = item
    }

    func update(_ presentation: NetworkStatusItemPresentation) {
        guard let button = statusItem?.button else { return }
        let height = button.bounds.height > 0
            ? button.bounds.height
            : NSStatusBar.system.thickness
        button.image = NetworkStatusItemRenderer.image(
            for: presentation,
            height: height
        )
        button.setAccessibilityLabel(presentation.accessibilityText)
        button.toolTip = presentation.accessibilityText
    }

    func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }
}

@MainActor
protocol NetworkStatusTimerToken: AnyObject {
    func invalidate()
}

extension Timer: NetworkStatusTimerToken {}

@MainActor
protocol NetworkStatusTimerScheduling: AnyObject {
    func schedule(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any NetworkStatusTimerToken
}

@MainActor
final class FoundationNetworkStatusTimerScheduler: NetworkStatusTimerScheduling {
    private let addTimer: (Timer, RunLoop.Mode) -> Void

    init(
        addTimer: @escaping (Timer, RunLoop.Mode) -> Void = {
            RunLoop.main.add($0, forMode: $1)
        }
    ) {
        self.addTimer = addTimer
    }

    func schedule(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any NetworkStatusTimerToken {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                action()
            }
        }
        addTimer(timer, .common)
        return timer
    }
}

@MainActor
final class NetworkStatusItemController {
    private let reader: any NetworkInterfaceByteReading
    private let display: any NetworkStatusItemDisplaying
    private let timerScheduler: any NetworkStatusTimerScheduling
    private let accessibilityText: (String, String) -> String
    private var calculator = NetworkThroughputCalculator()
    private var timer: (any NetworkStatusTimerToken)?
    private var isEnabled = false
    private var timerGeneration = 0

    init(
        reader: any NetworkInterfaceByteReading,
        display: any NetworkStatusItemDisplaying,
        timerScheduler: any NetworkStatusTimerScheduling,
        accessibilityText: @escaping (String, String) -> String
    ) {
        self.reader = reader
        self.display = display
        self.timerScheduler = timerScheduler
        self.accessibilityText = accessibilityText
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        timerGeneration += 1
        isEnabled = enabled
        if enabled {
            display.install()
            sample()
            let generation = timerGeneration
            timer = timerScheduler.schedule(
                every: NetworkStatusItemMetrics.refreshInterval
            ) { [weak self] in
                guard self?.timerGeneration == generation else { return }
                self?.sample()
            }
        } else {
            stop()
        }
    }

    func teardown() {
        guard isEnabled else { return }
        timerGeneration += 1
        isEnabled = false
        stop()
    }

    isolated deinit {
        guard isEnabled || timer != nil else { return }
        stop()
    }

    private func sample() {
        guard isEnabled else { return }
        do {
            guard let snapshot = try reader.readSnapshot() else {
                calculator.reset()
                display.update(.zero(accessibilityText: accessibilityText))
                return
            }
            display.update(.make(
                throughput: calculator.consume(snapshot),
                accessibilityText: accessibilityText
            ))
        } catch {
            calculator.reset()
            display.update(.unavailable(accessibilityText: accessibilityText))
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        calculator.reset()
        display.remove()
    }
}
