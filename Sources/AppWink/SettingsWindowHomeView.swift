import SwiftUI
import AppKit
import AppWinkCore

/// Settings window home renders non-hotkey settings as a compact grouped list.
struct SettingsWindowHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updateCoordinator: AppUpdateCoordinator
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.settingsBottomBannerAvoidance) private var bottomBannerAvoidance

    let onOpenFeature: (ToolboxToggleKind) -> Void
    let onOpenHelp: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.twenty) {
                SettingsListSection(title: localized(.settingsSectionGeneral)) {
                    rows(toolboxSnapshot.generalRows)
                }

                SettingsListSection(title: localized(.settingsSectionFeatures)) {
                    ForEach(Array(toolboxSnapshot.featureRows.enumerated()), id: \.element.id) { index, row in
                        SettingsFeatureRow(row: row) {
                            onOpenFeature(row.kind)
                        }
                        if index < toolboxSnapshot.featureRows.count - 1 {
                            SettingsListSeparator()
                        }
                    }
                }

                SettingsListSection(title: localized(.settingsSectionAboutUpdates)) {
                    rows(toolboxSnapshot.aboutAndUpdateRows)
                }
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

    private var toolboxSnapshot: ToolboxCatalogSnapshot {
        model.toolboxSnapshot(
            automaticUpdateChecksEnabled: updateCoordinator.automaticallyChecksForUpdates,
            showsAutomaticUpdateChecksControl: updateCoordinator.showsAutomaticUpdateChecksControl,
            canCheckForUpdates: updateCoordinator.canCheckForUpdates,
            showsCheckForUpdatesAction: updateCoordinator.showsCheckForUpdatesAction
        )
    }

    @ViewBuilder
    private func rows(_ rows: [ToolboxOtherRow]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            otherRow(row)
            if index < rows.count - 1 {
                SettingsListSeparator()
            }
        }
    }

    @ViewBuilder
    private func otherRow(_ row: ToolboxOtherRow) -> some View {
        switch row.kind {
        case .language:
            HStack(spacing: SettingsDesignTokens.Space.sixteen) {
                SettingsListRowIcon(systemImage: "globe")

                Text(localized(.language))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                languageSelectorLabel
                    .overlay {
                        LanguageMenuHitTarget(
                            currentLanguage: model.currentLanguage,
                            localizationBundle: localizationManager.bundle,
                            onSelect: model.setLanguage
                        )
                }
                .fixedSize()
            }
            .settingsListRowSurface()

        case .appearanceMode:
            HStack(spacing: SettingsDesignTokens.Space.sixteen) {
                SettingsListRowIcon(systemImage: "circle.lefthalf.filled")

                Text(localized(.appearanceMode))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                appearanceModeSelectorLabel
                    .overlay {
                        AppearanceModeMenuHitTarget(
                            currentAppearanceMode: model.appearanceMode,
                            localizationBundle: localizationManager.bundle,
                            onSelect: model.setAppearanceMode
                        )
                    }
                .fixedSize()
            }
            .settingsListRowSurface()

        case .launchAtLogin:
            HStack(spacing: SettingsDesignTokens.Space.sixteen) {
                SettingsListRowIcon(systemImage: "power")

                Text(localized(.launchAtLogin))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                Toggle(localized(.launchAtLogin), isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!row.isEnabled)
            }
            .settingsListRowSurface(isEnabled: row.isEnabled)
            .delayedHoverTooltip(
                row.isEnabled ? nil : launchAtLoginUnavailableTooltip,
                delay: 1.5,
                maxWidth: 320
            )

        case .automaticallyCheckForUpdates:
            HStack(alignment: .center, spacing: SettingsDesignTokens.Space.sixteen) {
                SettingsListRowIcon(systemImage: "arrow.triangle.2.circlepath")

                Text(localized(.automaticallyCheckForUpdates))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                Toggle(localized(.automaticallyCheckForUpdates), isOn: automaticallyCheckForUpdatesBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .settingsListRowSurface(isEnabled: row.isEnabled)

        case .checkForUpdates:
            Button {
                updateCoordinator.checkForUpdates()
            } label: {
                HStack(spacing: SettingsDesignTokens.Space.sixteen) {
                    SettingsListRowIcon(systemImage: "arrow.clockwise")

                    Text(localized(.toolboxCheckForUpdates))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .settingsInteractiveListRowSurface(isEnabled: row.isEnabled)
            }
            .buttonStyle(.plain)
            .disabled(!row.isEnabled)

        case .help:
            Button(action: onOpenHelp) {
                HStack(spacing: SettingsDesignTokens.Space.sixteen) {
                    SettingsListRowIcon(systemImage: "questionmark.circle")

                    Text(localized(.toolboxAboutHelp))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .settingsInteractiveListRowSurface()
            }
            .buttonStyle(.plain)

        case .currentVersion:
            HStack(spacing: SettingsDesignTokens.Space.sixteen) {
                SettingsListRowIcon(systemImage: "info.circle")

                Text(localized(.toolboxCurrentVersion))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: SettingsDesignTokens.Space.sixteen)

                Text(displayVersionText(row.valueText ?? model.currentVersionText))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .settingsListRowSurface()
            .overlay {
                OptionClickHitTarget {
                    model.openPerformanceDiagnosticsFromVersionRow()
                }
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { isEnabled in
                guard model.launchAtLoginEnabled != isEnabled else {
                    return
                }

                model.setLaunchAtLoginEnabled(isEnabled)
            }
        )
    }

    private var automaticallyCheckForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updateCoordinator.automaticallyChecksForUpdates },
            set: { updateCoordinator.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var launchAtLoginUnavailableTooltip: String? {
        guard !model.canEditLaunchAtLogin else {
            return nil
        }

        return model.launchAtLoginHelpText
    }

    private var languageSelectorLabel: some View {
        HStack(spacing: SettingsDesignTokens.Space.ten) {
            Text(model.currentLanguage.displayName(in: localizationManager.bundle))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .contentShape(Rectangle())
        .accessibilityLabel(Text(localized(.language)))
        .accessibilityValue(Text(model.currentLanguage.displayName(in: localizationManager.bundle)))
    }

    private var appearanceModeSelectorLabel: some View {
        HStack(spacing: SettingsDesignTokens.Space.ten) {
            Text(model.appearanceMode.displayName(in: localizationManager.bundle))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .contentShape(Rectangle())
        .accessibilityLabel(Text(localized(.appearanceMode)))
        .accessibilityValue(Text(model.appearanceMode.displayName(in: localizationManager.bundle)))
    }

    private func displayVersionText(_ value: String) -> String {
        value == "Development Build" ? localized(.developmentBuild) : value
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }

}

private struct LanguageMenuHitTarget: NSViewRepresentable {
    let currentLanguage: AppLanguage
    let localizationBundle: Bundle
    let onSelect: (AppLanguage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> LanguageMenuHitTargetView {
        let view = LanguageMenuHitTargetView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: LanguageMenuHitTargetView, context: Context) {
        context.coordinator.currentLanguage = currentLanguage
        context.coordinator.localizationBundle = localizationBundle
        context.coordinator.onSelect = onSelect
        nsView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject {
        var currentLanguage: AppLanguage = .system
        var localizationBundle: Bundle = .main
        var onSelect: (AppLanguage) -> Void

        init(onSelect: @escaping (AppLanguage) -> Void) {
            self.onSelect = onSelect
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            for language in AppLanguage.allCases {
                let item = NSMenuItem(
                    title: language.displayName(in: localizationBundle),
                    action: #selector(selectLanguage(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = language
                item.state = language == currentLanguage ? .on : .off
                menu.addItem(item)
            }
            return menu
        }

        @objc private func selectLanguage(_ sender: NSMenuItem) {
            guard let language = sender.representedObject as? AppLanguage else {
                return
            }
            onSelect(language)
        }
    }
}

private final class LanguageMenuHitTargetView: NSView {
    weak var coordinator: LanguageMenuHitTarget.Coordinator?

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let coordinator else {
            return
        }

        let menu = coordinator.makeMenu()
        let selectedItem = menu.items.first { $0.state == .on }
        menu.popUp(positioning: selectedItem, at: NSPoint(x: 0, y: bounds.height), in: self)
    }
}

private struct OptionClickHitTarget: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> OptionClickHitTargetView {
        let view = OptionClickHitTargetView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: OptionClickHitTargetView, context: Context) {
        context.coordinator.action = action
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }
    }
}

private final class OptionClickHitTargetView: NSView {
    weak var coordinator: OptionClickHitTarget.Coordinator?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point),
              NSApp.currentEvent?.modifierFlags.contains(.option) == true else {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else {
            return
        }

        coordinator?.action()
    }
}

private struct AppearanceModeMenuHitTarget: NSViewRepresentable {
    let currentAppearanceMode: AppAppearanceMode
    let localizationBundle: Bundle
    let onSelect: (AppAppearanceMode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> AppearanceModeMenuHitTargetView {
        let view = AppearanceModeMenuHitTargetView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AppearanceModeMenuHitTargetView, context: Context) {
        context.coordinator.currentAppearanceMode = currentAppearanceMode
        context.coordinator.localizationBundle = localizationBundle
        context.coordinator.onSelect = onSelect
        nsView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject {
        var currentAppearanceMode: AppAppearanceMode = .system
        var localizationBundle: Bundle = .main
        var onSelect: (AppAppearanceMode) -> Void

        init(onSelect: @escaping (AppAppearanceMode) -> Void) {
            self.onSelect = onSelect
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            for appearanceMode in AppAppearanceMode.allCases {
                let item = NSMenuItem(
                    title: appearanceMode.displayName(in: localizationBundle),
                    action: #selector(selectAppearanceMode(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = appearanceMode
                item.state = appearanceMode == currentAppearanceMode ? .on : .off
                menu.addItem(item)
            }
            return menu
        }

        @objc private func selectAppearanceMode(_ sender: NSMenuItem) {
            guard let appearanceMode = sender.representedObject as? AppAppearanceMode else {
                return
            }
            onSelect(appearanceMode)
        }
    }
}

private final class AppearanceModeMenuHitTargetView: NSView {
    weak var coordinator: AppearanceModeMenuHitTarget.Coordinator?

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let coordinator else {
            return
        }

        let menu = coordinator.makeMenu()
        let selectedItem = menu.items.first { $0.state == .on }
        menu.popUp(positioning: selectedItem, at: NSPoint(x: 0, y: bounds.height), in: self)
    }
}
