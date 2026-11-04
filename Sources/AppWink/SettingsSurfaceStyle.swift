import SwiftUI

struct SettingsPageBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.98),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.42),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct SettingsPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        .white.opacity(SettingsDesignTokens.Border.hairlineOpacity(for: colorScheme)),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: .black.opacity(SettingsDesignTokens.Effect.Panel.shadowOpacity),
                radius: SettingsDesignTokens.Effect.Panel.shadowRadius,
                y: SettingsDesignTokens.Effect.Panel.shadowY
            )
    }
}

struct SettingsListPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                shape
                    .fill(
                        (colorScheme == .dark ? Color.white : Color.black)
                            .opacity(colorScheme == .dark ? 0.08 : 0.07)
                    )
            )
            .overlay(
                shape
                    .strokeBorder(
                        .white.opacity(SettingsDesignTokens.Border.hairlineOpacity(for: colorScheme)),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: .black.opacity(SettingsDesignTokens.Effect.Panel.shadowOpacity),
                radius: SettingsDesignTokens.Effect.Panel.shadowRadius,
                y: SettingsDesignTokens.Effect.Panel.shadowY
            )
    }
}

private struct SettingsBottomBannerAvoidanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = SettingsDesignTokens.Window.edgePadding
}

extension EnvironmentValues {
    var settingsBottomBannerAvoidance: CGFloat {
        get { self[SettingsBottomBannerAvoidanceKey.self] }
        set { self[SettingsBottomBannerAvoidanceKey.self] = newValue }
    }
}
