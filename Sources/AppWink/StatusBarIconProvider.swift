import AppKit

/// 绘制纯代码生成的状态栏图标，避免额外资源文件依赖。
enum StatusBarIconProvider {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }()

    /// 用键帽 + 眨眼笑脸组合出 AppWink 的状态栏识别图形。
    private static func draw(in rect: NSRect) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let keyRect = NSRect(
            x: rect.minX + 1.8,
            y: rect.minY + 2.2,
            width: rect.width - 3.6,
            height: rect.height - 4.4)
        let keyPath = NSBezierPath(
            roundedRect: keyRect,
            xRadius: 4.2,
            yRadius: 4.2)
        keyPath.lineWidth = 1.7
        keyPath.stroke()

        let wink = NSBezierPath()
        wink.lineCapStyle = .round
        wink.lineWidth = 1.7
        wink.move(to: NSPoint(x: rect.minX + 5.1, y: rect.minY + 10.8))
        wink.line(to: NSPoint(x: rect.minX + 7.6, y: rect.minY + 11.2))
        wink.stroke()

        let eyeDot = NSBezierPath(ovalIn: NSRect(x: rect.minX + 10.7, y: rect.minY + 9.8, width: 2.2, height: 2.2))
        eyeDot.fill()

        let smile = NSBezierPath()
        smile.lineCapStyle = .round
        smile.lineWidth = 1.45
        smile.move(to: NSPoint(x: rect.minX + 5.1, y: rect.minY + 6.9))
        smile.curve(
            to: NSPoint(x: rect.minX + 11.9, y: rect.minY + 6.9),
            controlPoint1: NSPoint(x: rect.minX + 6.9, y: rect.minY + 5.3),
            controlPoint2: NSPoint(x: rect.minX + 10.1, y: rect.minY + 5.3))
        smile.stroke()
    }
}
