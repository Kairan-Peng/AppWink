import AppKit
import SwiftUI

struct AppIconFlashOverlayView: View {
    let image: NSImage
    let opacity: Double
    let iconSize: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(
                width: iconSize,
                height: iconSize
            )
            .opacity(opacity)
            .shadow(
                color: .black.opacity(SettingsDesignTokens.AppIconFlash.shadowOpacity),
                radius: SettingsDesignTokens.AppIconFlash.shadowRadius,
                y: SettingsDesignTokens.AppIconFlash.shadowY
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
