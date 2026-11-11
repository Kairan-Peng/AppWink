#!/usr/bin/swift

import AppKit
import ImageIO

enum BrandAssetGenerator {
    static let iconFiles: [(String, Int)] = [
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
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let masterURL = rootURL.appendingPathComponent("Artwork/AppWink-Icon-Source.png")
        let iconsetURL = rootURL.appendingPathComponent("Icon.iconset", isDirectory: true)

        guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
              let master = CGImageSourceCreateImageAtIndex(source, 0, nil),
              master.width == master.height,
              master.width >= 1024 else {
            throw assetError("Artwork/AppWink-Icon-Source.png must be a square PNG of at least 1024 pixels.")
        }

        try FileManager.default.createDirectory(
            at: iconsetURL,
            withIntermediateDirectories: true)

        for (fileName, size) in iconFiles {
            let png = try makePNG(from: master, size: size)
            try png.write(to: iconsetURL.appendingPathComponent(fileName), options: .atomic)
        }

        print("Generated \(iconFiles.count) pixel-exact app icons from Artwork/AppWink-Icon-Source.png")
    }

    private static func makePNG(from master: CGImage, size: Int) throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw assetError("Could not create a \(size)-pixel icon bitmap.")
        }

        // Explicit pixel dimensions avoid inheriting the current screen's Retina scale.
        // The opaque artwork is clipped here so every size has a clean transparent edge.
        let tile = CGRect(x: 0, y: 0, width: size, height: size)
            .insetBy(dx: CGFloat(size) * 0.07, dy: CGFloat(size) * 0.07)
        let outline = CGPath(
            roundedRect: tile,
            cornerWidth: CGFloat(size) * 0.22,
            cornerHeight: CGFloat(size) * 0.22,
            transform: nil)
        context.addPath(outline)
        context.clip()
        context.interpolationQuality = .high
        context.draw(master, in: tile)

        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image)
                .representation(using: .png, properties: [:]) else {
            throw assetError("Could not encode the \(size)-pixel icon.")
        }

        return png
    }

    private static func assetError(_ message: String) -> NSError {
        NSError(domain: "BrandAssetGenerator", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }
}

do {
    try BrandAssetGenerator.run()
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
