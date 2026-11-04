import AppWinkCore
import SwiftUI

struct SettingsFeatureControlState: Equatable {
    let subordinateControlsEnabled: Bool
    let showsPermissionCallout: Bool

    init(row: ToolboxToggleRow) {
        subordinateControlsEnabled = row.isOn
        showsPermissionCallout = row.status == .permissionRequired
    }
}

struct SettingsFeatureDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.settingsBottomBannerAvoidance) private var bottomBannerAvoidance

    let row: ToolboxToggleRow

    private static let virtualKeyboardDelaySliderWidth: CGFloat = 96
    private static let virtualKeyboardDelayValueSpacing: CGFloat = 3
    private static let virtualKeyboardDelayValueReservedWidth: CGFloat = 48

    private var presentation: SettingsFeaturePresentation {
        row.kind.presentation
    }

    private var controlState: SettingsFeatureControlState {
        SettingsFeatureControlState(row: row)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.twenty) {
                descriptionPanel
                featureSection
                detailSection
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

    private var descriptionPanel: some View {
        let summary = localized(presentation.summaryKey)
        let attributedSummary = (try? AttributedString(
            markdown: summary,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(summary)

        return HStack(alignment: .center, spacing: SettingsDesignTokens.Space.sixteen) {
            SettingsListRowIcon(systemImage: presentation.systemImage, role: .accent)

            Text(attributedSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SettingsDesignTokens.SettingsList.rowPaddingX)
        .padding(.vertical, SettingsDesignTokens.Space.sixteen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsListPanelBackground(cornerRadius: SettingsDesignTokens.SettingsList.containerRadius))
        .clipShape(
            RoundedRectangle(
                cornerRadius: SettingsDesignTokens.SettingsList.containerRadius,
                style: .continuous
            )
        )
    }

    private var featureSection: some View {
        SettingsListSection(title: localized(.settingsSectionFeatures)) {
            HStack(spacing: SettingsDesignTokens.Space.sixteen) {
                Text(localized(.settingsFeatureEnable))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                Toggle(localized(.settingsFeatureEnable), isOn: featureBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
            }
            .settingsListRowSurface()

            if controlState.showsPermissionCallout,
               let messageKey = row.kind.permissionMessageKey {
                SettingsListSeparator()
                permissionCallout(messageKey: messageKey)
                    .padding(.horizontal, SettingsDesignTokens.SettingsList.rowPaddingX)
                    .padding(.bottom, SettingsDesignTokens.Space.twelve)
            }
        }
    }

    private var detailSection: some View {
        SettingsListSection(title: localized(presentation.sectionKind.titleKey)) {
            ForEach(Array(presentation.rows.enumerated()), id: \.offset) { index, detailRow in
                detailRowView(detailRow)
                if index < presentation.rows.count - 1 {
                    SettingsListSeparator()
                }
            }
        }
    }

    @ViewBuilder
    private func detailRowView(_ detailRow: SettingsFeatureDetailRow) -> some View {
        switch detailRow {
        case let .value(labelKey, value):
            HStack(alignment: .top, spacing: SettingsDesignTokens.Space.sixteen) {
                Text(localized(labelKey))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 112, alignment: .leading)

                Text(detailValue(value))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .settingsListRowSurface()

        case .virtualKeyboardDelay:
            HStack(alignment: .center, spacing: SettingsDesignTokens.Space.sixteen) {
                Text(localized(.settingsFeatureShowAfter))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: SettingsDesignTokens.Space.eight)

                virtualKeyboardDelayControl
            }
            .settingsListRowSurface()
        }
    }

    private func permissionCallout(messageKey: LocalizationKey) -> some View {
        blockerCallout(
            systemImage: "hand.raised.fill",
            title: localized(.accessibilityPermissionRequired),
            description: localized(messageKey),
            actionTitle: localized(.openSystemSettings),
            action: model.openAccessibilitySystemSettings
        )
    }

    private func blockerCallout(
        systemImage: String,
        title: String,
        description: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: SettingsDesignTokens.Space.ten) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(
                    width: SettingsDesignTokens.SettingsList.rowIconSize,
                    height: SettingsDesignTokens.SettingsList.rowIconSize
                )

            VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.eight) {
                HStack(alignment: .center, spacing: SettingsDesignTokens.Space.twelve) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: SettingsDesignTokens.Space.eight)

                    if let actionTitle {
                        blockerAction(title: actionTitle, action: action)
                    }
                }

                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SettingsDesignTokens.Space.twelve)
        .padding(.vertical, SettingsDesignTokens.Space.ten)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: SettingsDesignTokens.Radius.row,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.row, style: .continuous)
                .strokeBorder(.white.opacity(0.30), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.row, style: .continuous)
                .strokeBorder(.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private func blockerAction(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, SettingsDesignTokens.Space.twelve)
                .padding(.vertical, SettingsDesignTokens.Space.eight)
                .settingsInteractiveChrome(
                    role: .accent,
                    shape: RoundedRectangle(
                        cornerRadius: SettingsDesignTokens.Radius.row,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var featureBinding: Binding<Bool> {
        switch row.kind {
        case .windowsStyleCut:
            return Binding(
                get: { model.windowsStyleCutEnabled },
                set: { model.setWindowsStyleCutEnabled($0) }
            )
        case .mouseWheelWindowsScroll:
            return Binding(
                get: { model.mouseWheelWindowsScrollEnabled },
                set: { model.setMouseWheelWindowsScrollEnabled($0) }
            )
        case .pressedKeysOverlay:
            return Binding(
                get: { model.pressedKeysOverlayEnabled },
                set: { model.setPressedKeysOverlayEnabled($0) }
            )
        case .virtualKeyboard:
            return Binding(
                get: { model.virtualKeyboardEnabled },
                set: { model.setVirtualKeyboardEnabled($0) }
            )
        case .hiddenBar:
            return Binding(
                get: { model.hiddenBarEnabled },
                set: { model.setHiddenBarEnabled($0) }
            )
        case .networkMonitor:
            return Binding(
                get: { model.networkStatusEnabled },
                set: { model.setNetworkStatusEnabled($0) }
            )
        case .hotKeyIconFlash:
            return Binding(
                get: { model.hotKeyIconFlashEnabled },
                set: { model.setHotKeyIconFlashEnabled($0) }
            )
        case .advancedHotkeys:
            return Binding(
                get: { model.advancedHotkeysEnabled },
                set: { model.setAdvancedHotkeysEnabled($0) }
            )
        }
    }

    private var virtualKeyboardDelayIndexBinding: Binding<Double> {
        Binding(
            get: {
                Double(VirtualKeyboardRevealDelay.index(for: model.virtualKeyboardRevealDelay))
            },
            set: { value in
                model.setVirtualKeyboardRevealDelay(
                    VirtualKeyboardRevealDelay.value(at: Int(value.rounded()))
                )
            }
        )
    }

    private var virtualKeyboardDelayControl: some View {
        let delayValue = localized(
            .virtualKeyboardDelayValue,
            VirtualKeyboardRevealDelay.displayString(for: model.virtualKeyboardRevealDelay)
        )

        return HStack(spacing: Self.virtualKeyboardDelayValueSpacing) {
            Slider(
                value: virtualKeyboardDelayIndexBinding,
                in: 0...Double(VirtualKeyboardRevealDelay.allowedValues.count - 1),
                step: 1
            ) {
                Text(localized(.settingsFeatureShowAfter))
            }
            .labelsHidden()
            .accessibilityLabel(Text(localized(.settingsFeatureShowAfter)))
            .accessibilityValue(Text(delayValue))
            .frame(width: Self.virtualKeyboardDelaySliderWidth)
            .disabled(!controlState.subordinateControlsEnabled)

            Text(delayValue)
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: Self.virtualKeyboardDelayValueReservedWidth, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func detailValue(_ value: SettingsFeatureDetailValue) -> String {
        switch value {
        case let .localized(key):
            return localized(key)
        case let .verbatim(value):
            return value
        }
    }

    private func localized(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        localizationManager.string(for: key, arguments: arguments)
    }
}
