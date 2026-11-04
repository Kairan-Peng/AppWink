import AppKit
import SwiftUI
import AppWinkCore

/// 热键设置主页，承载与绑定编辑直接相关的内容。
struct SettingsHomeView: View {
    private struct BindingsContentHeightPreferenceKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct BindingRowFramesPreferenceKey: PreferenceKey {
        static let defaultValue: [UUID: CGRect] = [:]

        static func reduce(
            value: inout [UUID: CGRect],
            nextValue: () -> [UUID: CGRect]
        ) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.settingsBottomBannerAvoidance) private var bottomBannerAvoidance

    @State private var isAddButtonHovered = false
    @State private var bindingReorderState: BindingReorderState?
    @State private var recentlyDroppedBindingID: UUID?
    @State private var hoveredBindingID: UUID?
    @State private var hoveredDeleteButtonID: UUID?
    @State private var bindingsContentHeight: CGFloat = 0
    @State private var bindingRowFrames: [UUID: CGRect] = [:]
    @State private var dropHighlightDismissWorkItem: DispatchWorkItem?

    let onOpenSettings: () -> Void

    private var layoutAnimation: Animation {
        .easeInOut(duration: SettingsDesignTokens.Motion.layoutDuration)
    }

    private var reorderAnimation: Animation {
        .interactiveSpring(response: 0.22, dampingFraction: 0.88)
    }

    var body: some View {
        VStack(spacing: 0) {
            heroPanel

            scrollContent
                .padding(.top, 24)
                .padding(.bottom, scrollContentBottomPadding)
                .animation(layoutAnimation, value: scrollContentBottomPadding)
                .animation(layoutAnimation, value: model.shouldShowAccessibilityPermissionCallout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(layoutAnimation, value: model.shouldShowAccessibilityPermissionCallout)
    }

    /// 绑定列表单独放在滚动区，底部 banner 避让由外层环境控制。
    private var scrollContent: some View {
        GeometryReader { proxy in
            Group {
                if model.hasBindings {
                    bindingsScrollContainer(availableHeight: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 壳层会把底部 banner 的避让高度通过环境值传入主页。
    private var scrollContentBottomPadding: CGFloat {
        max(SettingsDesignTokens.Window.edgePadding, bottomBannerAvoidance)
    }

    /// 顶部英雄区承载品牌、Settings 入口和新增应用主操作。
    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.twelve) {
            HStack(alignment: .center, spacing: SettingsDesignTokens.Space.sixteen) {
                headerIcon

                VStack(alignment: .leading, spacing: SettingsDesignTokens.Space.four) {
                    Text(AppBrand.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(2)

                    Text(AppBrand.tagline)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }

                Spacer(minLength: SettingsDesignTokens.Space.twelve)

                headerActions
            }

            if !model.validationMessages.isEmpty {
                issuesPanel
            }
        }
        .padding(.horizontal, SettingsDesignTokens.WorkbenchHeader.paddingX)
        .padding(.vertical, SettingsDesignTokens.Space.six)
    }

    private var headerIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(
                width: SettingsDesignTokens.WorkbenchHeader.iconImageSize,
                height: SettingsDesignTokens.WorkbenchHeader.iconImageSize
            )
            .accessibilityHidden(true)
    }

    private var headerActions: some View {
        HStack(alignment: .center, spacing: SettingsDesignTokens.Space.ten) {
            if model.shouldShowAccessibilityPermissionCallout {
                headerUtilityButton(
                    title: localized(.addAccessibilityPermission),
                    systemImage: "hand.raised.fill",
                    iconColor: .orange,
                    action: model.openAccessibilitySystemSettings
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            settingsHeaderButton
            addTargetHeaderButton
        }
        .animation(layoutAnimation, value: model.shouldShowAccessibilityPermissionCallout)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(3)
    }

    private func headerUtilityButton(
        title: String,
        systemImage: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SettingsDesignTokens.Space.six) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, SettingsDesignTokens.Space.twelve)
            .padding(.vertical, SettingsDesignTokens.Space.ten)
            .settingsInteractiveChrome(
                role: .standard,
                shape: RoundedRectangle(
                    cornerRadius: SettingsDesignTokens.Radius.row,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var settingsHeaderButton: some View {
        Button {
            onOpenSettings()
        } label: {
            Label(localized(.settings), systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, SettingsDesignTokens.Space.fourteen)
                .padding(.vertical, SettingsDesignTokens.Space.ten)
                .settingsInteractiveChrome(
                    role: .standard,
                    shape: RoundedRectangle(
                        cornerRadius: SettingsDesignTokens.Radius.row,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var addTargetHeaderButton: some View {
        Button {
            model.chooseTarget()
        } label: {
            Label(localized(.addTarget), systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, SettingsDesignTokens.Space.fourteen)
                .padding(.vertical, SettingsDesignTokens.Space.ten)
                .settingsInteractiveChrome(
                    role: .accent,
                    shape: RoundedRectangle(
                        cornerRadius: SettingsDesignTokens.Radius.row,
                        style: .continuous
                    )
                )
                .scaleEffect(isAddButtonHovered ? 1.02 : 1)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: SettingsDesignTokens.Radius.row,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: SettingsDesignTokens.Motion.stateDuration), value: isAddButtonHovered)
        .onHover { isHovering in
            isAddButtonHovered = isHovering
        }
    }

    /// 滚动视图内部恢复为一体式绑定列表，行分隔线负责扫描节奏。
    private var bindingsListContent: some View {
        VStack(spacing: SettingsDesignTokens.BindingRow.listSpacing) {
            ForEach(Array(displayedBindings.enumerated()), id: \.element.id) { index, binding in
                reorderableBindingRow(binding)

                if index < displayedBindings.count - 1 {
                    bindingRowSeparator
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BindingsContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    private var bindingRowSeparator: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
            .padding(.leading, SettingsDesignTokens.BindingRow.separatorLeadingInset)
            .padding(.trailing, SettingsDesignTokens.BindingRow.separatorTrailingInset)
    }

    /// 整行保留统一命中形状；排序拖拽只能从左侧 handle 发起。
    private func reorderableBindingRow(_ binding: HotkeyBinding) -> some View {
        bindingRow(binding)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: SettingsDesignTokens.BindingRow.radius,
                    style: .continuous
                )
            )
    }

    /// 拖拽过程中先按本地顺序渲染列表，避免每次跨行都把模型和持久化链路拉起来。
    private var displayedBindings: [HotkeyBinding] {
        guard let bindingReorderState else {
            return model.bindings
        }

        let bindingsByID = Dictionary(uniqueKeysWithValues: model.bindings.map { ($0.id, $0) })
        let reorderedBindings = bindingReorderState.orderedBindingIDs.compactMap { bindingsByID[$0] }

        guard reorderedBindings.count == model.bindings.count else {
            return model.bindings
        }

        return reorderedBindings
    }

    /// 绑定列表在内容较少时贴合实际高度，超出可用区域后再退化为内部滚动。
    private func bindingsScrollContainer(availableHeight: CGFloat) -> some View {
        let layout = BindingsListLayout.resolve(
            contentHeight: bindingsContentHeight,
            availableHeight: availableHeight
        )

        return ScrollView(.vertical, showsIndicators: layout.shouldScroll) {
            bindingsListContent
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: layout.visibleHeight, alignment: .top)
        .clipShape(
            RoundedRectangle(
                cornerRadius: SettingsDesignTokens.BindingRow.listRadius,
                style: .continuous
            )
        )
        .background(SettingsPanelBackground(cornerRadius: SettingsDesignTokens.BindingRow.listRadius))
        .onPreferenceChange(BindingsContentHeightPreferenceKey.self) { bindingsContentHeight = $0 }
        .onPreferenceChange(BindingRowFramesPreferenceKey.self) { bindingRowFrames = $0 }
    }

    /// 仅展示需要用户处理的配置问题，避免在列表里散落多处重复提示。
    private var issuesPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(localized(.issuesTitle), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            ForEach(model.validationMessages, id: \.self) { message in
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.orange.opacity(0.18), lineWidth: 1)
        )
    }

    /// 每一行同时承载目标信息、打开方式、快捷键录制、启停开关和删除操作。
    private func bindingRow(_ binding: HotkeyBinding) -> some View {
        let presentation = targetPresentation(for: binding)

        return HStack(alignment: .center, spacing: SettingsDesignTokens.Space.twelve) {
            dragHandle(for: binding)
            targetIcon(
                presentation: presentation,
                bindingID: binding.id
            )

            HStack(alignment: .center, spacing: SettingsDesignTokens.Space.ten) {
                Text(presentation.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if presentation.availability == .targetUnavailable {
                    issueBadge(title: localized(.targetUnavailable))
                } else if presentation.availability ==
                            .openingApplicationUnavailable {
                    issueBadge(
                        title: localized(.openingApplicationUnavailable)
                    )
                } else if model.isBindingDuplicateShortcut(binding.id) {
                    issueBadge(title: conflictBadgeTitle(for: binding.id))
                }
            }
            .layoutPriority(1)

            Spacer()

            HStack(alignment: .center, spacing: SettingsDesignTokens.Space.sixteen) {
                if presentation.openingMode != nil {
                    // 文件系统目标的打开方式紧邻热键，保持整行单层扫描。
                    BindingOpenModeMenu(
                        binding: binding,
                        presentation: presentation,
                        openTarget: {
                            model.performAction(for: binding.id, source: .manual)
                        },
                        selectFolderMode: {
                            model.setFolderOpenMode($0, for: binding.id)
                        },
                        selectFileMode: {
                            model.setFileOpenMode($0, for: binding.id)
                        },
                        chooseOtherApplication: {
                            model.chooseOpeningApplication(for: binding.id)
                        }
                    )
                }
                shortcutField(for: binding.id)
                bindingToggleControl(for: binding.id)
                deleteBindingButton(for: binding.id)
            }
            .padding(.trailing, SettingsDesignTokens.Space.four)
        }
        .padding(.horizontal, SettingsDesignTokens.BindingRow.paddingX)
        .padding(.vertical, SettingsDesignTokens.BindingRow.paddingY)
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsDesignTokens.BindingRow.minHeight,
            alignment: .center
        )
        .scaleEffect(rowScale(for: binding.id))
        .background(rowBackground(for: binding.id))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BindingRowFramesPreferenceKey.self,
                    value: [binding.id: proxy.frame(in: .global)]
                )
            }
        }
        .overlay(alignment: .leading) {
            bindingReorderHitArea(for: binding)
        }
        .animation(.easeOut(duration: 0.18), value: rowScale(for: binding.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.displayName)
        .accessibilityValue(presentation.accessibilityValue)
        .onHover { isHovering in
            if isHovering {
                hoveredBindingID = binding.id
            } else if hoveredBindingID == binding.id {
                hoveredBindingID = nil
            }
        }
    }

    private func dragHandle(for binding: HotkeyBinding) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(
                width: SettingsDesignTokens.BindingRow.reorderHandleVisualWidth,
                height: SettingsDesignTokens.BindingRow.iconSize
            )
            .accessibilityHidden(true)
    }

    private func bindingReorderHitArea(for binding: HotkeyBinding) -> some View {
        Color.clear
            .frame(width: SettingsDesignTokens.BindingRow.reorderHandleHitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(bindingReorderGesture(for: binding))
            .accessibilityHidden(true)
    }

    private func bindingReorderGesture(for binding: HotkeyBinding) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                updateBindingReorderPreview(for: binding, translationHeight: value.translation.height)
            }
            .onEnded { _ in
                commitBindingReorderPreview()
            }
    }

    private func updateBindingReorderPreview(for binding: HotkeyBinding, translationHeight: CGFloat) {
        var state = bindingReorderState ?? BindingReorderState(
            draggedBindingID: binding.id,
            orderedBindingIDs: model.bindings.map(\.id),
            rowFrames: bindingRowFrames
        )

        guard state.draggedBindingID == binding.id else {
            return
        }

        let reorderedBindingIDs = BindingReorderPreview.orderedBindingIDs(
            initialOrderedBindingIDs: state.initialOrderedBindingIDs,
            draggedBindingID: binding.id,
            translationHeight: translationHeight,
            initialRowFrames: state.initialRowFrames
        )

        if reorderedBindingIDs == state.orderedBindingIDs {
            if bindingReorderState == nil {
                bindingReorderState = state
            }
            return
        }

        state.orderedBindingIDs = reorderedBindingIDs

        withAnimation(reorderAnimation) {
            bindingReorderState = state
        }
    }

    private func commitBindingReorderPreview() {
        guard let bindingReorderState else {
            return
        }

        model.setBindingOrder(bindingReorderState.orderedBindingIDs)
        triggerDropSettleAnimation(for: bindingReorderState.draggedBindingID)

        withAnimation(reorderAnimation) {
            self.bindingReorderState = nil
        }
    }

    private func targetPresentation(
        for binding: HotkeyBinding
    ) -> HotkeyTargetPresentation {
        model.targetPresentation(for: binding)
    }

    /// 解析成功时使用系统真实图标；不可用时按目标类型显示通用图标。
    private func targetIcon(
        presentation: HotkeyTargetPresentation,
        bindingID: UUID
    ) -> some View {
        Group {
            if let image = presentation.targetImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: presentation.fallbackSymbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: SettingsDesignTokens.BindingRow.iconImageSize,
            height: SettingsDesignTokens.BindingRow.iconImageSize
        )
        .frame(width: SettingsDesignTokens.BindingRow.iconSize, height: SettingsDesignTokens.BindingRow.iconSize)
        .saturation(model.isBindingEnabled(bindingID) ? 1 : 0)
        .brightness(model.isBindingEnabled(bindingID) ? 0 : -0.03)
        .opacity(model.isBindingEnabled(bindingID) ? 1 : 0.5)
        .animation(.easeOut(duration: 0.2), value: model.isBindingEnabled(bindingID))
    }

    /// 冲突 badge 在悬停时扩展出对端应用名，帮助用户快速定位问题来源。
    private func issueBadge(title: String) -> some View {
        Label(title, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .lineLimit(1)
            .padding(.horizontal, SettingsDesignTokens.Space.eight)
            .padding(.vertical, SettingsDesignTokens.Space.four)
            .background(Color.orange.opacity(0.12), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
            )
    }

    private func conflictBadgeTitle(for bindingID: UUID) -> String {
        guard isBindingHovered(bindingID) else {
            return localized(.shortcutConflict)
        }

        let conflictingTargetNames = model.conflictingTargetNames(for: bindingID)
        guard !conflictingTargetNames.isEmpty else {
            return localized(.shortcutConflict)
        }

        return localized(
            .shortcutConflictWith,
            conflictingTargetNames.joined(
                separator: localizationManager.listSeparator
            )
        )
    }

    private func updateDeleteButtonHoverState(_ isHovering: Bool, bindingID: UUID) {
        if isHovering {
            hoveredDeleteButtonID = bindingID
        } else if hoveredDeleteButtonID == bindingID {
            hoveredDeleteButtonID = nil
        }
    }

    /// 录制控件只负责单项绑定的快捷键编辑，业务逻辑仍留在 `AppModel`。
    private func shortcutField(for bindingID: UUID) -> some View {
        Group {
            if model.canEditShortcut(for: bindingID) {
                ShortcutRecorderField(
                    shortcut: Binding(
                        get: { model.shortcut(for: bindingID) },
                        set: { model.setShortcut($0, for: bindingID) }),
                    allowsAdvancedHotkeys: model.advancedHotkeysEnabled,
                    onRecordingChanged: model.setShortcutRecordingActive,
                    placeholder: localized(.notConfigured),
                    controlHeight: SettingsDesignTokens.ShortcutRecorder.height
                )
            } else {
                readOnlyShortcutField(for: bindingID)
            }
        }
        .frame(
            width: SettingsDesignTokens.ShortcutRecorder.width,
            height: SettingsDesignTokens.ShortcutRecorder.height
        )
    }

    private func readOnlyShortcutField(for bindingID: UUID) -> some View {
        Text(model.shortcut(for: bindingID)?.displayString ?? localized(.notConfigured))
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
            )
            .accessibilityLabel(model.shortcut(for: bindingID)?.displayString ?? localized(.notConfigured))
    }

    /// 生效开关保持原生外观，不再额外叠加 hover 提示。
    private func bindingToggleControl(for bindingID: UUID) -> some View {
        Group {
            if model.canEditShortcut(for: bindingID) {
                Toggle(
                    model.isBindingEnabled(bindingID) ? localized(.enabled) : localized(.disabled),
                    isOn: bindingEnabledState(for: bindingID)
                )
                .toggleStyle(.switch)
                .controlSize(.regular)
                .labelsHidden()
                .help(model.isBindingEnabled(bindingID) ? localized(.disableHotkey) : localized(.enableHotkey))
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: SettingsDesignTokens.BindingRow.toggleWidth,
            height: SettingsDesignTokens.BindingRow.toggleHeight
        )
    }

    /// 删除按钮同样通过外层包装层展示 hover，确保高光和 glow 有明确载体。
    private func deleteBindingButton(for bindingID: UUID) -> some View {
        Group {
            if model.canEditShortcut(for: bindingID) {
                Button(role: .destructive) {
                    model.removeBinding(bindingID)
                } label: {
                    ZStack {
                        deleteButtonBackground(for: bindingID)
                        deleteButtonIcon(for: bindingID)
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onHover { isHovering in
                    updateDeleteButtonHoverState(isHovering, bindingID: bindingID)
                }
            } else {
                Color.clear
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
            }
        }
    }

    /// 行背景只保留 hover 和拖拽落点高亮；启停开关不再叠加额外行级反馈。
    private func rowBackground(for bindingID: UUID) -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsDesignTokens.BindingRow.radius, style: .continuous)

        return shape
            .fill(Color.white.opacity(rowBaseFillOpacity(for: bindingID)))
            .overlay(
                shape
                    .strokeBorder(Color.white.opacity(rowStrokeOpacity(for: bindingID)), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.16), value: isBindingHovered(bindingID))
            .animation(.easeOut(duration: 0.18), value: recentlyDroppedBindingID == bindingID)
    }

    /// 删除按钮 hover 时直接做颜色反相，避免再叠加高光或 glow。
    private func deleteButtonBackground(for bindingID: UUID) -> some View {
        let isHovered = hoveredDeleteButtonID == bindingID
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return shape
            .fill(isHovered ? Color.red : Color.clear)
            .background(.thinMaterial, in: shape)
            .overlay(
                shape.strokeBorder(isHovered ? Color.red : Color.white.opacity(0.25), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    /// 红白两层图标交叉淡变，和背景一起完成 hover 反相过渡。
    private func deleteButtonIcon(for bindingID: UUID) -> some View {
        let isHovered = hoveredDeleteButtonID == bindingID

        return ZStack {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
                .opacity(isHovered ? 0 : 1)

            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .opacity(isHovered ? 1 : 0)
        }
        .frame(width: 30, height: 30)
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    /// 包装 Toggle 的双向绑定，保持原生开关反馈并直接落业务状态。
    private func bindingEnabledState(for bindingID: UUID) -> Binding<Bool> {
        Binding(
            get: { model.isBindingEnabled(bindingID) },
            set: { isEnabled in
                guard model.isBindingEnabled(bindingID) != isEnabled else {
                    return
                }

                model.setBindingEnabled(isEnabled, for: bindingID)
            }
        )
    }

    private func rowBaseFillOpacity(for bindingID: UUID) -> Double {
        (isBindingHovered(bindingID) ? 0.115 : 0) +
        (isBindingRecentlyDropped(bindingID) ? 0.075 : 0)
    }

    private func rowStrokeOpacity(for bindingID: UUID) -> Double {
        (isBindingHovered(bindingID) ? 0.22 : 0) +
        (isBindingRecentlyDropped(bindingID) ? 0.14 : 0)
    }

    private func isBindingHovered(_ bindingID: UUID) -> Bool {
        hoveredBindingID == bindingID
    }

    private func isBindingRecentlyDropped(_ bindingID: UUID) -> Bool {
        recentlyDroppedBindingID == bindingID
    }

    private func rowScale(for bindingID: UUID) -> CGFloat {
        if isBindingRecentlyDropped(bindingID) {
            return 1.008
        }

        return 1
    }

    private func triggerDropSettleAnimation(for bindingID: UUID) {
        dropHighlightDismissWorkItem?.cancel()

        withAnimation(reorderAnimation) {
            recentlyDroppedBindingID = bindingID
        }

        let dismissWorkItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.22)) {
                if recentlyDroppedBindingID == bindingID {
                    recentlyDroppedBindingID = nil
                }
            }
        }

        dropHighlightDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: dismissWorkItem)
    }

    private func localized(_ key: LocalizationKey) -> String {
        localizationManager.string(for: key)
    }

    private func localized(_ key: LocalizationKey, _ argument: CVarArg) -> String {
        localizationManager.string(for: key, arguments: argument)
    }
}

/// 拖拽期间只维护本地顺序快照，等 drop 完成后再统一提交最终顺序。
struct BindingReorderState: Equatable {
    let draggedBindingID: UUID
    let initialOrderedBindingIDs: [UUID]
    let initialRowFrames: [UUID: CGRect]
    var orderedBindingIDs: [UUID]

    init(
        draggedBindingID: UUID,
        orderedBindingIDs: [UUID],
        rowFrames: [UUID: CGRect]
    ) {
        self.draggedBindingID = draggedBindingID
        self.initialOrderedBindingIDs = orderedBindingIDs
        self.initialRowFrames = rowFrames
        self.orderedBindingIDs = orderedBindingIDs
    }
}

enum BindingReorderPreview {
    static func orderedBindingIDs(
        initialOrderedBindingIDs: [UUID],
        draggedBindingID: UUID,
        translationHeight: CGFloat,
        initialRowFrames: [UUID: CGRect]
    ) -> [UUID] {
        guard let sourceIndex = initialOrderedBindingIDs.firstIndex(of: draggedBindingID),
              let sourceFrame = initialRowFrames[draggedBindingID],
              initialOrderedBindingIDs.allSatisfy({ initialRowFrames[$0] != nil }) else {
            return initialOrderedBindingIDs
        }

        let projectedCenter = sourceFrame.midY + translationHeight
        let destinationIndex = initialOrderedBindingIDs
            .filter { $0 != draggedBindingID }
            .filter { initialRowFrames[$0]!.midY < projectedCenter }
            .count
        let destinationOffset = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        return movedBindingIDs(initialOrderedBindingIDs, from: sourceIndex, toOffset: destinationOffset)
    }
}

/// 复用与配置模型相同的 move 语义，让本地预览和最终提交保持一致。
private func movedBindingIDs(_ orderedBindingIDs: [UUID], from sourceIndex: Int, toOffset destination: Int) -> [UUID] {
    guard orderedBindingIDs.indices.contains(sourceIndex) else {
        return orderedBindingIDs
    }

    let clampedDestination = min(max(destination, 0), orderedBindingIDs.count)
    guard sourceIndex != clampedDestination, sourceIndex + 1 != clampedDestination else {
        return orderedBindingIDs
    }

    var reorderedBindingIDs = orderedBindingIDs
    let bindingID = reorderedBindingIDs.remove(at: sourceIndex)
    let adjustedDestination = clampedDestination > sourceIndex ? clampedDestination - 1 : clampedDestination
    reorderedBindingIDs.insert(bindingID, at: adjustedDestination)
    return reorderedBindingIDs
}
