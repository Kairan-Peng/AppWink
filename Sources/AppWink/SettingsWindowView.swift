import SwiftUI
import AppKit
import AppWinkCore

/// Independent Settings window shell for non-hotkey settings pages.
struct SettingsWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updateCoordinator: AppUpdateCoordinator
    @EnvironmentObject private var localizationManager: LocalizationManager

    private var layoutAnimation: Animation {
        .easeInOut(duration: SettingsDesignTokens.Motion.layoutDuration)
    }

    var body: some View {
        ZStack {
            SettingsPageBackground()

            pageContent
                .padding(.horizontal, SettingsDesignTokens.SettingsWindow.edgePadding)

            AppWindowTitlebarFade()
                .frame(height: SettingsDesignTokens.SettingsWindow.titlebarHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(
            minWidth: SettingsDesignTokens.SettingsWindow.minWidth,
            minHeight: SettingsDesignTokens.SettingsWindow.minHeight
        )
        .id(localizationManager.currentLanguage)
        .environment(
            \.settingsBottomBannerAvoidance,
            SettingsDesignTokens.SettingsWindow.edgePadding
        )
        .sheet(isPresented: performanceDiagnosticsSheetBinding) {
            PerformanceDiagnosticsView()
                .environmentObject(model)
                .environmentObject(localizationManager)
        }
        .overlay(alignment: .bottom) {
            if let statusMessage = model.statusMessage {
                SettingsStatusBanner(message: statusMessage)
                    .padding(.bottom, SettingsDesignTokens.Space.twelve)
                    .transition(.opacity)
            }
        }
        .animation(layoutAnimation, value: model.statusMessage != nil)
        .background(
            AppWindowChromeConfigurator(
                toolbarIdentifier: AppWindowChromeIdentifier.settings,
                minWidth: SettingsDesignTokens.SettingsWindow.minWidth,
                minHeight: SettingsDesignTokens.SettingsWindow.windowFrameHeight,
                preferredFrameWidth: SettingsDesignTokens.SettingsWindow.minWidth,
                fixedFrameHeight: SettingsDesignTokens.SettingsWindow.windowFrameHeight,
                titleOverride: titlebarTitle,
                titlebarBackAction: titlebarBackAction,
                titlebarBackAccessibilityLabel: localized(.settings)
            )
        )
        .onAppear {
            model.setSettingsWindowPresenter {
                openWindow(id: AppScene.settingsWindowID)
                AppWindowForegroundController.schedulePromotion(
                    windowIdentifier: AppWindowChromeIdentifier.settings
                )
            }
            model.handleSettingsWindowAppeared()
        }
    }

    private var performanceDiagnosticsSheetBinding: Binding<Bool> {
        Binding(
            get: { model.isPerformanceDiagnosticsPresented },
            set: { isPresented in
                if !isPresented {
                    model.dismissPerformanceDiagnostics()
                }
            }
        )
    }

    private var toolboxSnapshot: ToolboxCatalogSnapshot {
        model.toolboxSnapshot(
            automaticUpdateChecksEnabled: updateCoordinator.automaticallyChecksForUpdates,
            showsAutomaticUpdateChecksControl: updateCoordinator.showsAutomaticUpdateChecksControl,
            canCheckForUpdates: updateCoordinator.canCheckForUpdates,
            showsCheckForUpdatesAction: updateCoordinator.showsCheckForUpdatesAction
        )
    }

    private var titlebarTitle: String {
        switch model.settingsWindowRoute {
        case .settings:
            return localized(.settings)
        case .feature(let kind):
            return localized(kind.presentation.titleKey)
        case .help:
            return localized(.toolboxAboutHelp)
        }
    }

    private var titlebarBackAction: (() -> Void)? {
        switch model.settingsWindowRoute {
        case .settings:
            return nil
        case .feature, .help:
            return { model.showSettingsWindowHome() }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            SettingsWindowHomeView(
                onOpenFeature: model.showSettingsFeature,
                onOpenHelp: model.showSettingsWindowHelp
            )
                .opacity(model.settingsWindowRoute == .settings ? 1 : 0)
                .allowsHitTesting(model.settingsWindowRoute == .settings)
                .accessibilityHidden(model.settingsWindowRoute != .settings)

            if case .feature(let kind) = model.settingsWindowRoute,
               let row = toolboxSnapshot.featureRows.first(where: { $0.kind == kind }) {
                SettingsFeatureDetailView(row: row)
                    .id(kind)
                    .transition(.opacity)
            }

            if model.settingsWindowRoute == .help {
                ToolboxDetailView()
                    .transition(.opacity)
            }
        }
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }
}

/// All settings shells use the same lightweight bottom status treatment.
struct SettingsStatusBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, SettingsDesignTokens.Space.sixteen)
            .padding(.vertical, SettingsDesignTokens.Space.twelve)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
            .padding(.horizontal, SettingsDesignTokens.Space.twentyFour)
    }
}
