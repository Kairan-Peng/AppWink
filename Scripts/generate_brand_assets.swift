#!/usr/bin/swift

import AppKit

enum BrandAssetGenerator {
    static let iconFiles: [(String, CGFloat)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    static func run() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconsetURL = rootURL.appendingPathComponent("Icon.iconset", isDirectory: true)

        try FileManager.default.createDirectory(
            at: iconsetURL,
            withIntermediateDirectories: true)

        for (fileName, size) in iconFiles {
            let image = makeAppIcon(size: size)
            try writePNG(image: image, to: iconsetURL.appendingPathComponent(fileName))
        }

        print("Generated \(iconFiles.count) app icon assets in \(iconsetURL.path)")
    }

    private static func makeAppIcon(size: CGFloat) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize)

        image.lockFocus()
        defer { image.unlockFocus() }

        let canvas = NSRect(origin: .zero, size: imageSize)
        NSColor.clear.setFill()
        canvas.fill()

        let inset = size * 0.045
        let outerRect = canvas.insetBy(dx: inset, dy: inset)
        let outerPath = NSBezierPath(
            roundedRect: outerRect,
            xRadius: size * 0.24,
            yRadius: size * 0.24)

        let outerShadow = NSShadow()
        outerShadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        outerShadow.shadowBlurRadius = size * 0.08
        outerShadow.shadowOffset = NSSize(width: 0, height: -(size * 0.024))
        outerShadow.set()

        let outerGradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.33, alpha: 1.0), 0.0),
            (NSColor(calibratedRed: 0.99, green: 0.53, blue: 0.28, alpha: 1.0), 0.58),
            (NSColor(calibratedRed: 0.95, green: 0.34, blue: 0.27, alpha: 1.0), 1.0))!
        outerGradient.draw(in: outerPath, angle: -90)

        let glowOne = NSBezierPath(
            ovalIn: NSRect(
                x: size * 0.08,
                y: size * 0.71,
                width: size * 0.26,
                height: size * 0.22))
        NSColor.white.withAlphaComponent(0.18).setFill()
        glowOne.fill()

        let glowTwo = NSBezierPath(
            ovalIn: NSRect(
                x: size * 0.63,
                y: size * 0.17,
                width: size * 0.18,
                height: size * 0.18))
        NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.82, alpha: 0.18).setFill()
        glowTwo.fill()

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.saveGState()
        context.translateBy(x: size * 0.5, y: size * 0.49)
        context.rotate(by: -12 * .pi / 180)

        let capRect = NSRect(
            x: -(size * 0.22),
            y: -(size * 0.19),
            width: size * 0.44,
            height: size * 0.38)
        let capPath = NSBezierPath(
            roundedRect: capRect,
            xRadius: size * 0.105,
            yRadius: size * 0.105)

        let capShadow = NSShadow()
        capShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        capShadow.shadowBlurRadius = size * 0.05
        capShadow.shadowOffset = NSSize(width: 0, height: -(size * 0.018))
        capShadow.set()

        let capGradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.95, alpha: 1.0), 0.0),
            (NSColor(calibratedRed: 0.98, green: 0.93, blue: 0.84, alpha: 1.0), 0.55),
            (NSColor(calibratedRed: 0.95, green: 0.86, blue: 0.72, alpha: 1.0), 1.0))!
        capGradient.draw(in: capPath, angle: -90)

        NSColor.white.withAlphaComponent(0.58).setStroke()
        capPath.lineWidth = max(1.0, size * 0.01)
        capPath.stroke()

        let faceColor = NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.14, alpha: 0.98)
        faceColor.setStroke()
        faceColor.setFill()

        let wink = NSBezierPath()
        wink.lineCapStyle = .round
        wink.lineWidth = max(2.2, size * 0.028)
        wink.move(to: NSPoint(x: -(size * 0.080), y: size * 0.042))
        wink.line(to: NSPoint(x: -(size * 0.018), y: size * 0.060))
        wink.stroke()

        let eyeDot = NSBezierPath(
            ovalIn: NSRect(
                x: size * 0.032,
                y: size * 0.022,
                width: size * 0.048,
                height: size * 0.048))
        eyeDot.fill()

        let smile = NSBezierPath()
        smile.lineCapStyle = .round
        smile.lineWidth = max(1.8, size * 0.022)
        smile.move(to: NSPoint(x: -(size * 0.082), y: -(size * 0.060)))
        smile.curve(
            to: NSPoint(x: size * 0.082, y: -(size * 0.060)),
            controlPoint1: NSPoint(x: -(size * 0.040), y: -(size * 0.108)),
            controlPoint2: NSPoint(x: size * 0.040, y: -(size * 0.108)))
        smile.stroke()

        context.restoreGState()

        drawSpark(
            center: NSPoint(x: size * 0.76, y: size * 0.76),
            radius: size * 0.055,
            lineWidth: max(1.5, size * 0.012))

        return image
    }

    private static func drawSpark(center: NSPoint, radius: CGFloat, lineWidth: CGFloat) {
        NSColor.white.withAlphaComponent(0.95).setStroke()

        let vertical = NSBezierPath()
        vertical.lineCapStyle = .round
        vertical.lineWidth = lineWidth
        vertical.move(to: NSPoint(x: center.x, y: center.y - radius))
        vertical.line(to: NSPoint(x: center.x, y: center.y + radius))
        vertical.stroke()

        let horizontal = NSBezierPath()
        horizontal.lineCapStyle = .round
        horizontal.lineWidth = lineWidth
        horizontal.move(to: NSPoint(x: center.x - radius, y: center.y))
        horizontal.line(to: NSPoint(x: center.x + radius, y: center.y))
        horizontal.stroke()
    }

    private static func writePNG(image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "BrandAssetGenerator", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode PNG for \(url.lastPathComponent)",
            ])
        }

        try pngData.write(to: url)
    }
}

do {
    try BrandAssetGenerator.run()
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
