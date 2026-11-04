import AppKit
import SwiftUI
import AppWinkCore

/// 菜单栏弹出面板，提供快速回到设置页和手动触发目标的入口。
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.MenuBar.spacing) {
            menuActionButton(
                title: localized(.menuConfigureHotkeys),
                systemImage: "keyboard"
            ) {
                openWindow(id: AppScene.mainWindowID)
                AppWindowForegroundController.schedulePromotion(
                    windowIdentifier: AppWindowChromeIdentifier.main
                )
            }

            menuActionButton(
                title: localized(.menuOpenSettings),
                systemImage: "gearshape"
            ) {
                model.showSettingsWindowHome()
                openWindow(id: AppScene.settingsWindowID)
                AppWindowForegroundController.schedulePromotion(
                    windowIdentifier: AppWindowChromeIdentifier.settings
                )
            }

            if !model.bindings.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: SettingsDesignTokens.MenuBar.rowSpacing) {
                    ForEach(model.bindings) { binding in
                        bindingActionButton(for: binding)
                    }
                }
            }

            Divider()

            menuActionButton(
                title: localized(.menuQuitApp, AppBrand.displayName),
                systemImage: "power"
            ) {
                NSApp.terminate(nil)
            }
        }
        .padding(SettingsDesignTokens.MenuBar.padding)
        .frame(width: SettingsDesignTokens.MenuBar.width, alignment: .leading)
        .id(localizationManager.currentLanguage)
    }

    @ViewBuilder
    private func menuActionButton(
        title: String,
        systemImage: String,
        role: SettingsInteractiveSurfaceRole = .standard,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SettingsDesignTokens.Space.ten) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(role == .accent ? Color.accentColor : Color.secondary)
                    .frame(
                        width: SettingsDesignTokens.MenuBar.appIconSize,
                        height: SettingsDesignTokens.MenuBar.appIconSize
                    )

                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .menuRowChrome(role: role, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func bindingActionButton(for binding: HotkeyBinding) -> some View {
        let canPerform = model.canPerformAction(for: binding.id)
        let actionState = bindingActionState(for: binding.id)
        let presentation = model.targetPresentation(for: binding)
        let accessibility = MenuBarBindingAccessibility(
            presentation: presentation,
            shortcut: shortcutSubtitle(for: binding.id),
            state: bindingActionStateTitle(actionState)
        )

        if canPerform {
            Button {
                model.performAction(for: binding.id, source: .manual)
            } label: {
                bindingActionLabel(
                    for: binding,
                    presentation: presentation,
                    actionState: actionState
                )
                    .menuRowChrome(role: .compactMenu, isEnabled: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibility.label))
            .accessibilityValue(Text(accessibility.value))
        } else {
            bindingActionLabel(
                for: binding,
                presentation: presentation,
                actionState: actionState
            )
                .menuRowChrome(role: .compactMenu, isEnabled: canPerform)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibility.label))
                .accessibilityValue(Text(accessibility.value))
        }
    }

    private func bindingActionLabel(
        for binding: HotkeyBinding,
        presentation: HotkeyTargetPresentation,
        actionState: MenuBarBindingActionState
    ) -> some View {
        HStack(spacing: SettingsDesignTokens.Space.ten) {
            menuBarIcon(presentation)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    bindingActionPrimaryTitle(
                        for: binding,
                        presentation: presentation,
                        actionState: actionState
                    )
                )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if actionState == .enabled {
                    Text(shortcutSubtitle(for: binding.id))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            bindingActionAccessory(actionState)
        }
    }

    private func bindingActionPrimaryTitle(
        for binding: HotkeyBinding,
        presentation: HotkeyTargetPresentation,
        actionState: MenuBarBindingActionState
    ) -> String {
        let targetDisplayName = presentation.displayName

        switch actionState {
        case .enabled:
            return targetDisplayName

        case .unavailable:
            return [
                targetDisplayName,
                shortcutSubtitle(for: binding.id),
                bindingActionStateTitle(actionState)
            ].joined(separator: "  ")
        }
    }

    private func bindingActionState(for bindingID: UUID) -> MenuBarBindingActionState {
        return model.canPerformAction(for: bindingID) ? .enabled : .unavailable
    }

    private func bindingActionStateTitle(_ state: MenuBarBindingActionState) -> String {
        switch state {
        case .enabled:
            return localized(.enabled)

        case .unavailable:
            return localized(.unavailable)
        }
    }

    @ViewBuilder
    private func bindingActionAccessory(_ state: MenuBarBindingActionState) -> some View {
        switch state {
        case .enabled:
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)

        case .unavailable:
            bindingStateBadge(
                title: localized(.unavailable),
                systemImage: "exclamationmark.triangle.fill",
                foregroundStyle: Color.secondary
            )
        }
    }

    private func bindingStateBadge(
        title: String,
        systemImage: String,
        foregroundStyle: Color
    ) -> some View {
        HStack(spacing: SettingsDesignTokens.Space.four) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, SettingsDesignTokens.Space.eight)
        .padding(.vertical, SettingsDesignTokens.Space.four)
        .background(
            .thinMaterial,
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 与主界面保持一致，优先展示已物化图标，缺失时按目标类型降级。
    private func menuBarIcon(
        _ presentation: HotkeyTargetPresentation
    ) -> some View {
        Group {
            if let image = presentation.targetImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: presentation.fallbackSymbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: SettingsDesignTokens.MenuBar.appIconSize,
            height: SettingsDesignTokens.MenuBar.appIconSize
        )
        .frame(
            width: SettingsDesignTokens.MenuBar.iconTileSize,
            height: SettingsDesignTokens.MenuBar.iconTileSize
        )
        .background(
            .quaternary.opacity(0.35),
            in: RoundedRectangle(cornerRadius: SettingsDesignTokens.Radius.keycap, style: .continuous)
        )
    }

    private func shortcutSubtitle(for bindingID: UUID) -> String {
        model.shortcut(for: bindingID)?.displayString ?? localized(.notConfigured)
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }

    private func localized(_ key: LocalizationKey, _ argument: CVarArg) -> String {
        localizationManager.string(for: key, arguments: argument)
    }
}

struct MenuBarBindingAccessibility: Equatable {
    let label: String
    let value: String

    init(
        presentation: HotkeyTargetPresentation,
        shortcut: String,
        state: String
    ) {
        label = presentation.accessibilityValue
        value = [shortcut, state]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private struct MenuBarRowChromeModifier: ViewModifier {
    let role: SettingsInteractiveSurfaceRole
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, SettingsDesignTokens.MenuBar.rowPaddingX)
            .padding(.vertical, SettingsDesignTokens.MenuBar.rowPaddingY)
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsDesignTokens.MenuBar.rowMinHeight,
                alignment: .leading
            )
            .opacity(isEnabled ? 1 : 0.68)
            .settingsInteractiveChrome(
                role: role,
                shape: RoundedRectangle(
                    cornerRadius: SettingsDesignTokens.MenuBar.rowRadius,
                    style: .continuous
                )
            )
    }
}

private extension View {
    func menuRowChrome(role: SettingsInteractiveSurfaceRole, isEnabled: Bool) -> some View {
        modifier(MenuBarRowChromeModifier(role: role, isEnabled: isEnabled))
    }
}

private enum MenuBarBindingActionState {
    case enabled
    case unavailable
}
