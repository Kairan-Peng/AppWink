import SwiftUI

struct SettingsScrollMask: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .black.opacity(0.40), location: 0.36),
                    .init(color: .black, location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: SettingsDesignTokens.SettingsWindow.topFadeHeight)

            Rectangle()
                .fill(.black)
        }
    }
}

struct SettingsListSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.ten) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, SettingsDesignTokens.SettingsList.sectionTitlePaddingX)

            VStack(spacing: SettingsDesignTokens.SettingsList.rowSpacing) {
                content
            }
            .background(SettingsListPanelBackground(cornerRadius: SettingsDesignTokens.SettingsList.containerRadius))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: SettingsDesignTokens.SettingsList.containerRadius,
                    style: .continuous
                )
            )
        }
    }
}

struct SettingsListSeparator: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
            .padding(.leading, SettingsDesignTokens.SettingsList.separatorLeadingInset)
            .padding(.trailing, SettingsDesignTokens.SettingsList.separatorTrailingInset)
    }
}

struct SettingsListRowIcon: View {
    let systemImage: String
    var role: SettingsInteractiveSurfaceRole = .standard

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(role == .accent ? Color.accentColor : Color.secondary)
            .frame(
                width: SettingsDesignTokens.SettingsList.rowIconSize,
                height: SettingsDesignTokens.SettingsList.rowIconSize
            )
            .accessibilityHidden(true)
    }
}

struct SettingsListRowSurfaceModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, SettingsDesignTokens.SettingsList.rowPaddingX)
            .padding(.vertical, SettingsDesignTokens.SettingsList.rowPaddingY)
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsDesignTokens.SettingsList.rowMinHeight,
                alignment: .leading
            )
            .opacity(isEnabled ? 1 : 0.58)
    }
}

struct SettingsInteractiveListRowSurfaceModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, SettingsDesignTokens.SettingsList.rowPaddingX)
            .padding(.vertical, SettingsDesignTokens.SettingsList.rowPaddingY)
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsDesignTokens.SettingsList.rowMinHeight,
                alignment: .leading
            )
            .opacity(isEnabled ? 1 : 0.58)
            .contentShape(Rectangle())
    }
}

extension View {
    func settingsListRowSurface(isEnabled: Bool = true) -> some View {
        modifier(SettingsListRowSurfaceModifier(isEnabled: isEnabled))
    }

    func settingsInteractiveListRowSurface(isEnabled: Bool = true) -> some View {
        modifier(SettingsInteractiveListRowSurfaceModifier(isEnabled: isEnabled))
    }
}
