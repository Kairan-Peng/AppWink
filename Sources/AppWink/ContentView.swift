import AppKit
import SwiftUI
import AppWinkCore

/// AppWink main hotkey window shell, responsible for hotkey setup and bottom runtime banners.
struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    /// 让底部常驻 banner 把自身高度回传给主布局，用于给页面内容让出空间。
    private struct BottomBannerHeightPreferenceKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var bottomBannerHeight: CGFloat = 0

    private var layoutAnimation: Animation {
        .easeInOut(duration: SettingsDesignTokens.Motion.layoutDuration)
    }

    var body: some View {
        ZStack {
            SettingsPageBackground()

            pageContent
                .padding(.horizontal, SettingsDesignTokens.Window.edgePadding)
                .padding(.top, SettingsDesignTokens.Window.contentTopPadding)

            AppWindowTitlebarFade()
                .frame(height: SettingsDesignTokens.WindowChrome.titlebarHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(
            minWidth: SettingsDesignTokens.Window.minWidth,
            minHeight: SettingsDesignTokens.Window.minHeight
        )
        .id(localizationManager.currentLanguage)
        .environment(\.settingsBottomBannerAvoidance, pageBottomBannerAvoidance)
        .overlay(alignment: .bottom) {
            VStack(spacing: SettingsDesignTokens.Space.ten) {
                if let statusMessage = model.statusMessage {
                    SettingsStatusBanner(message: statusMessage)
                        .transition(.opacity)
                }

                if let shortcutConflictReminder = model.shortcutConflictReminder {
                    conflictBanner(shortcutConflictReminder)
                        .background { measureBottomBannerHeight }
                        .transition(.opacity)
                } else if model.shouldShowHotkeyGuideBanner {
                    hotkeyGuideBanner
                        .background { measureBottomBannerHeight }
                        .transition(.opacity)
                }
            }
            .padding(.bottom, SettingsDesignTokens.Space.twelve)
            .onPreferenceChange(BottomBannerHeightPreferenceKey.self) { bottomBannerHeight = $0 }
            .animation(layoutAnimation, value: model.statusMessage != nil)
            .animation(layoutAnimation, value: model.shortcutConflictReminder != nil)
            .animation(layoutAnimation, value: model.shouldShowHotkeyGuideBanner)
        }
        .background(
            AppWindowChromeConfigurator(
                toolbarIdentifier: AppWindowChromeIdentifier.main,
                minWidth: SettingsDesignTokens.Window.minWidth,
                minHeight: SettingsDesignTokens.Window.minHeight,
                preferredFrameWidth: SettingsDesignTokens.Window.minWidth,
                fixedFrameHeight: SettingsDesignTokens.Window.minHeight,
                titlebarHelpAction: model.toggleHotkeyGuideFromHelpButton,
                titlebarHelpAccessibilityLabel: localized(.help)
            )
        )
        .onAppear {
            model.setMainWindowPresenter {
                openWindow(id: AppScene.mainWindowID)
                AppWindowForegroundController.schedulePromotion(
                    windowIdentifier: AppWindowChromeIdentifier.main
                )
            }
            model.setSettingsWindowPresenter {
                openWindow(id: AppScene.settingsWindowID)
                AppWindowForegroundController.schedulePromotion(
                    windowIdentifier: AppWindowChromeIdentifier.settings
                )
            }
            model.handleMainHotkeyWindowAppeared()
        }
    }

    /// 底部常驻 banner 出现时，按实际高度给页面底部加出一段动态留白。
    private var pageBottomBannerAvoidance: CGFloat {
        guard model.shortcutConflictReminder != nil || model.shouldShowHotkeyGuideBanner else {
            return SettingsDesignTokens.Window.edgePadding
        }

        return max(
            SettingsDesignTokens.Window.edgePadding,
            bottomBannerHeight + SettingsDesignTokens.Space.thirtyTwo
        )
    }

    @ViewBuilder
    private var pageContent: some View {
        SettingsHomeView(onOpenSettings: model.openSettingsWindow)
    }

    private var measureBottomBannerHeight: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: BottomBannerHeightPreferenceKey.self,
                value: proxy.size.height
            )
        }
    }

    /// 冲突提示与普通状态提示分层展示，避免用户忽略热键冲突这一类长期问题。
    private func conflictBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: SettingsDesignTokens.Space.twelve) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: SettingsDesignTokens.Space.twentyFour, height: SettingsDesignTokens.Space.twentyFour)
                .background(
                    Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.keycap, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.keycap, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
                )
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsDesignTokens.Space.fourteen)
        .padding(.vertical, SettingsDesignTokens.Space.twelve)
        .frame(maxWidth: SettingsDesignTokens.Banner.maxWidth, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(
                cornerRadius: SettingsDesignTokens.Banner.conflictRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesignTokens.Banner.conflictRadius, style: .continuous)
                .strokeBorder(.orange.opacity(0.22), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.pill, style: .continuous)
                .fill(Color.orange.opacity(0.72))
                .frame(width: 3)
                .padding(.vertical, SettingsDesignTokens.Space.twelve)
                .padding(.leading, SettingsDesignTokens.Space.four)
        }
        .shadow(color: .black.opacity(0.1), radius: 18, y: 10)
        .padding(.horizontal, SettingsDesignTokens.Space.twentyFour)
        .accessibilityLabel(message)
    }

    private var hotkeyGuideBanner: some View {
        HStack(alignment: .top, spacing: SettingsDesignTokens.Space.twelve) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: SettingsDesignTokens.Space.twentyFour, height: SettingsDesignTokens.Space.twentyFour)
                .background(
                    Color.blue.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.keycap, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.keycap, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.22), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.six) {
                Text(localized(.hotkeyGuideTitle))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.four) {
                    ForEach(AppHelpContent.hotkeyUsageKeys, id: \.self) { key in
                        Text(localized(key))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
            }
            .layoutPriority(1)
        }
        .padding(.trailing, SettingsDesignTokens.Space.thirtyTwo)
        .padding(.horizontal, SettingsDesignTokens.Space.fourteen)
        .padding(.vertical, SettingsDesignTokens.Space.twelve)
        .frame(maxWidth: SettingsDesignTokens.Banner.maxWidth, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(
                cornerRadius: SettingsDesignTokens.Banner.conflictRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesignTokens.Banner.conflictRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.34), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                model.dismissHotkeyGuide()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsDesignTokens.Space.twentyFour, height: SettingsDesignTokens.Space.twentyFour)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localized(.hotkeyGuideDismiss))
            .accessibilityLabel(localized(.hotkeyGuideDismiss))
            .padding(.top, SettingsDesignTokens.Space.twelve)
            .padding(.trailing, SettingsDesignTokens.Space.fourteen)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.pill, style: .continuous)
                .fill(Color.blue.opacity(0.62))
                .frame(width: 3)
                .padding(.vertical, SettingsDesignTokens.Space.twelve)
                .padding(.leading, SettingsDesignTokens.Space.four)
        }
        .shadow(color: .black.opacity(0.1), radius: 18, y: 10)
        .padding(.horizontal, SettingsDesignTokens.Space.twentyFour)
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }
}
