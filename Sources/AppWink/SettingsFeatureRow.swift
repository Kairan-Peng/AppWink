import AppWinkCore
import SwiftUI

struct SettingsFeatureRow: View {
    @EnvironmentObject private var localizationManager: LocalizationManager

    let row: ToolboxToggleRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsDesignTokens.Space.sixteen) {
                SettingsListRowIcon(systemImage: row.kind.presentation.systemImage)

                Text(localized(row.kind.presentation.titleKey))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                HStack(spacing: SettingsDesignTokens.Space.four) {
                    statusText
                        .layoutPriority(1)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .settingsInteractiveListRowSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(localized(row.kind.presentation.titleKey)))
        .accessibilityValue(Text(localized(row.status.localizationKey)))
        .accessibilityHint(Text(localized(.settingsFeatureOpenHint)))
    }

    private var statusText: some View {
        Text(localized(row.status.localizationKey))
            .font(.callout)
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var statusColor: Color {
        switch row.status {
        case .enabled, .disabled:
            return .secondary
        case .permissionRequired:
            return .orange
        }
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }
}
