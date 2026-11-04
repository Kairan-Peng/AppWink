import SwiftUI

/// 轻量级按键浮层，只负责把当前按键文本渲染成胶囊样式。
struct PressedKeysOverlayView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, SettingsDesignTokens.PressedKeysPill.paddingX)
            .padding(.vertical, SettingsDesignTokens.PressedKeysPill.paddingY)
            .frame(minHeight: SettingsDesignTokens.PressedKeysPill.minHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: SettingsDesignTokens.PressedKeysPill.radius,
                    style: .continuous
                )
                    .fill(Color.black.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: SettingsDesignTokens.PressedKeysPill.radius,
                    style: .continuous
                )
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            .fixedSize()
    }
}
