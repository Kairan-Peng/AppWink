import AppKit
import CoreGraphics

struct HotKeyTargetFlashPayload: Equatable {
    let targetDisplayName: String
    let targetImage: NSImage?
    let fallbackSymbolName: String
    let screenFrame: CGRect

    static func == (
        lhs: HotKeyTargetFlashPayload,
        rhs: HotKeyTargetFlashPayload
    ) -> Bool {
        lhs.targetDisplayName == rhs.targetDisplayName &&
            lhs.fallbackSymbolName == rhs.fallbackSymbolName &&
            lhs.screenFrame == rhs.screenFrame &&
            imagesAreEqual(lhs.targetImage, rhs.targetImage)
    }

    private static func imagesAreEqual(
        _ lhs: NSImage?,
        _ rhs: NSImage?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case (let lhs?, let rhs?):
            lhs.isEqual(rhs)
        case (nil, _), (_, nil):
            false
        }
    }
}
