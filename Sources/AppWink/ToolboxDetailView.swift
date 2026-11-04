import SwiftUI
import AppWinkCore

/// Settings 详情页现在只承载帮助内容。
struct ToolboxDetailView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.settingsBottomBannerAvoidance) private var bottomBannerAvoidance

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.ten) {
                helpContent
            }
            .padding(.top, SettingsDesignTokens.SettingsWindow.sectionContentTopPadding)
            .padding(.bottom, max(SettingsDesignTokens.Window.edgePadding, bottomBannerAvoidance))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .compositingGroup()
        .mask(alignment: .top) {
            SettingsScrollMask()
        }
    }

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.ten) {
            helpSection(title: localized(.helpHotkeyUsageTitle)) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AppHelpContent.hotkeyUsageKeys, id: \.self) { key in
                        helpParagraph(localized(key))
                    }
                }
            }

            helpSection(title: localized(.helpFeatureNotesTitle)) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AppHelpContent.featureNotes, id: \.titleKey) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localized(note.titleKey))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            helpParagraph(localized(note.bodyKey))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.ten) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, SettingsDesignTokens.SettingsList.sectionTitlePaddingX)

            content()
                .padding(.horizontal, SettingsDesignTokens.SettingsList.rowPaddingX)
                .padding(.vertical, SettingsDesignTokens.Space.sixteen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsPanelBackground(cornerRadius: SettingsDesignTokens.SettingsList.containerRadius))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: SettingsDesignTokens.SettingsList.containerRadius,
                        style: .continuous
                    )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpParagraph(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }
}
