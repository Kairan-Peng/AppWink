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

    /// 将应用图标的圆角外框、键帽和两只眼睛转为菜单栏单色模板。
    private static func draw(in rect: NSRect) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let tilePath = NSBezierPath(
            roundedRect: rect.insetBy(dx: 1, dy: 1),
            xRadius: 4.2,
            yRadius: 4.2)
        let keyRect = NSRect(
            x: rect.minX + 3.3,
            y: rect.minY + 3.5,
            width: rect.width - 6.6,
            height: rect.height - 7)
        let keyPath = NSBezierPath(
            roundedRect: keyRect,
            xRadius: 2.6,
            yRadius: 2.6)
        tilePath.append(keyPath)
        tilePath.windingRule = .evenOdd
        tilePath.fill()

        let wink = NSBezierPath()
        wink.lineCapStyle = .round
        wink.lineWidth = 1.3
        wink.move(to: NSPoint(x: rect.minX + 5.7, y: rect.minY + 9))
        wink.curve(
            to: NSPoint(x: rect.minX + 8, y: rect.minY + 9.8),
            controlPoint1: NSPoint(x: rect.minX + 6.3, y: rect.minY + 9.6),
            controlPoint2: NSPoint(x: rect.minX + 7.1, y: rect.minY + 9.9))
        wink.stroke()

        let eyeDot = NSBezierPath(ovalIn: NSRect(
            x: rect.minX + 10.1,
            y: rect.minY + 9,
            width: 1.9,
            height: 1.9))
        eyeDot.fill()
    }
}
