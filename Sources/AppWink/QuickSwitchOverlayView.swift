import AppKit
import SwiftUI
import AppWinkCore

private typealias QuickSwitchTokens = SettingsDesignTokens.QuickSwitch

enum QuickSwitchOverlayLegacyStyle {
    enum BoundLabelShadowBase: Equatable {
        case white
        case black

        var color: Color {
            switch self {
            case .white:
                return .white
            case .black:
                return .black
            }
        }
    }

    static let panelCornerRadius: CGFloat = 34
    static let panelStrokeOpacity: Double = 0.40
    static let panelShadowOpacity: Double = 0.10
    static let panelShadowRadius: CGFloat = 30
    static let panelShadowY: CGFloat = 18

    static let keyCornerRadius: CGFloat = 18
    static let boundKeyShadowOpacity: Double = 0.10
    static let boundKeyShadowRadius: CGFloat = 18
    static let boundKeyShadowY: CGFloat = 10
    static let boundKeyGradientStartOpacity: Double = 0.48
    static let boundKeyGradientEndOpacity: Double = 0.24
    static let referenceKeyMaterialOpacity: Double = 0.32
    static let referenceKeyStrokeOpacity: Double = 0.07
    static let shortcutKeyStrokeOpacity: Double = 0.28
    static let boundKeyStrokeOpacity: Double = 0.46

    static let shortcutLabelOpacity: Double = 0.82
    static let boundLabelOpacity: Double = 0.95
    static let boundLabelPrimaryShadowOpacity: Double = 1.00
    static let boundLabelSecondaryShadowOpacity: Double = 0.32
    static let boundLabelTertiaryShadowOpacity: Double = 0.96

    static func boundLabelShadowBase(for colorScheme: ColorScheme) -> BoundLabelShadowBase {
        colorScheme == .dark ? .black : .white
    }
}

/// 长按 `Option` 时展示的快捷切换面板，只渲染已启用且已注册的字母/数字热键。
struct QuickSwitchOverlayView: View {
    let bindings: [HotkeyBinding]
    let targetPresentation: (HotkeyBinding) -> HotkeyTargetPresentation

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                overlayCard
                    .scaleEffect(scaleFactor(for: geometry.size), anchor: .center)
            }
            .padding(QuickSwitchTokens.viewportPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var overlayCard: some View {
        VStack(alignment: .leading, spacing: QuickSwitchTokens.titleSpacing) {
            Text(AppBrand.displayName)
                .font(.system(size: QuickSwitchTokens.titleFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary.opacity(0.72))
                .frame(width: visibleKeyboardWidth, alignment: .center)

            keyboardRows
        }
        .padding(QuickSwitchTokens.panelPadding)
        .background(.ultraThinMaterial, in: panelShape)
        .overlay(
            panelShape.strokeBorder(
                .white.opacity(QuickSwitchOverlayLegacyStyle.panelStrokeOpacity),
                lineWidth: 1
            )
        )
        .shadow(
            color: .black.opacity(QuickSwitchOverlayLegacyStyle.panelShadowOpacity),
            radius: QuickSwitchOverlayLegacyStyle.panelShadowRadius,
            y: QuickSwitchOverlayLegacyStyle.panelShadowY
        )
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: QuickSwitchOverlayLegacyStyle.panelCornerRadius,
            style: .continuous
        )
    }

    private var keyboardRows: some View {
        VStack(alignment: .leading, spacing: QuickSwitchTokens.rowSpacing) {
            ForEach(Array(QuickSwitchKeyboardLayout.rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: QuickSwitchTokens.keySpacing) {
                    ForEach(row) { key in
                        QuickSwitchOverlayKeyView(
                            key: key,
                            binding: binding(for: key),
                            targetPresentation: targetPresentation,
                            width: keyWidth(for: key.widthUnits),
                            height: rowHeight(for: rowIndex))
                    }
                }
            }
        }
        .frame(width: visibleKeyboardWidth, alignment: .leading)
        .compositingGroup()
        .mask(keyboardFadeMask)
    }

    private var keyboardFadeMask: some View {
        let start = fadeStartLocation
        let midpoint = min(max(start + ((1 - start) * QuickSwitchTokens.fadeMidpointProgress), start), 1)

        return LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: start),
                .init(color: .white.opacity(QuickSwitchTokens.fadeDimOpacity), location: midpoint),
                .init(color: .clear, location: 1),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing)
    }

    private var fadeStartLocation: CGFloat {
        normalizedMaskLocation(for: centerX(of: "letter-n") ?? visibleKeyboardWidth * 0.9)
    }

    private var bindingsByKeyCode: [UInt16: HotkeyBinding] {
        Dictionary(uniqueKeysWithValues: bindings.compactMap { binding in
            guard let keyCode = QuickSwitchKeyboardLayout.key(for: binding.shortcut)?.keyCode else {
                return nil
            }

            return (keyCode, binding)
        })
    }

    private var contentWidth: CGFloat {
        visibleKeyboardWidth
    }

    private var fullKeyboardWidth: CGFloat {
        QuickSwitchKeyboardLayout.rows
            .map { rowWidth(for: $0) }
            .max() ?? 0
    }

    private var visibleKeyboardWidth: CGFloat {
        trailingEdge(of: "letter-n") ?? fullKeyboardWidth
    }

    private var contentHeight: CGFloat {
        let rows = CGFloat(QuickSwitchKeyboardLayout.rows.count)
        let verticalSpacing = QuickSwitchTokens.rowSpacing * max(rows - 1, 0)
        let titleBlockHeight = QuickSwitchTokens.titleFontSize + QuickSwitchTokens.titleSpacing
        let rowHeights = QuickSwitchKeyboardLayout.rows.indices.reduce(CGFloat.zero) { partialResult, index in
            partialResult + rowHeight(for: index)
        }
        return (QuickSwitchTokens.panelPadding * 2) + titleBlockHeight + rowHeights + verticalSpacing
    }

    private func binding(for key: QuickSwitchKeyboardLayout.Key) -> HotkeyBinding? {
        guard let keyCode = key.keyCode else {
            return nil
        }

        return bindingsByKeyCode[keyCode]
    }

    private func keyWidth(for widthUnits: Double) -> CGFloat {
        let units = CGFloat(widthUnits)
        return (units * QuickSwitchTokens.keyUnitWidth) + (max(0, units - 1) * QuickSwitchTokens.keySpacing)
    }

    private func rowHeight(for rowIndex: Int) -> CGFloat {
        rowIndex == 0 ? QuickSwitchTokens.compactReferenceRowHeight : QuickSwitchTokens.keyHeight
    }

    private func rowWidth(for row: [QuickSwitchKeyboardLayout.Key]) -> CGFloat {
        let content = row.reduce(CGFloat.zero) { partialResult, key in
            partialResult + keyWidth(for: key.widthUnits)
        }

        let spacing = CGFloat(max(0, row.count - 1)) * QuickSwitchTokens.keySpacing
        return content + spacing
    }

    private func trailingEdge(of keyID: String) -> CGFloat? {
        for row in QuickSwitchKeyboardLayout.rows {
            var cursorX: CGFloat = 0

            for (index, key) in row.enumerated() {
                if index > 0 {
                    cursorX += QuickSwitchTokens.keySpacing
                }

                let trailingX = cursorX + keyWidth(for: key.widthUnits)
                if key.id == keyID {
                    return trailingX
                }

                cursorX = trailingX
            }
        }

        return nil
    }

    private func centerX(of keyID: String) -> CGFloat? {
        for row in QuickSwitchKeyboardLayout.rows {
            var cursorX: CGFloat = 0

            for (index, key) in row.enumerated() {
                if index > 0 {
                    cursorX += QuickSwitchTokens.keySpacing
                }

                let width = keyWidth(for: key.widthUnits)
                let centerX = cursorX + (width / 2)
                if key.id == keyID {
                    return centerX
                }

                cursorX += width
            }
        }

        return nil
    }

    private func normalizedMaskLocation(for x: CGFloat) -> CGFloat {
        let normalized = x / max(visibleKeyboardWidth, 1)
        return min(max(normalized, 0), 1)
    }

    /// 大屏保持原始尺寸，小屏按比例缩放，避免覆盖层超出屏幕。
    private func scaleFactor(for availableSize: CGSize) -> CGFloat {
        let horizontalScale = max(
            QuickSwitchTokens.minimumScale,
            min(1, (availableSize.width - QuickSwitchTokens.scaleSafeInset) / max(contentWidth, 1))
        )
        let verticalScale = max(
            QuickSwitchTokens.minimumScale,
            min(1, (availableSize.height - QuickSwitchTokens.scaleSafeInset) / max(contentHeight, 1))
        )
        return min(horizontalScale, verticalScale)
    }
}

private struct QuickSwitchOverlayKeyView: View {
    @Environment(\.colorScheme) private var colorScheme

    let key: QuickSwitchKeyboardLayout.Key
    let binding: HotkeyBinding?
    let targetPresentation: (HotkeyBinding) -> HotkeyTargetPresentation
    let width: CGFloat
    let height: CGFloat

    private var isReferenceKey: Bool {
        key.role == .reference
    }

    private var hasBinding: Bool {
        binding != nil
    }

    private var isFunctionReferenceKey: Bool {
        key.id.hasPrefix("f") && key.id != "fn"
    }

    private var isBottomRowReferenceKey: Bool {
        ["fn", "control", "option", "command", "space"].contains(key.id)
    }

    private var isBottomModifierReferenceKey: Bool {
        ["fn", "control", "option", "command"].contains(key.id)
    }

    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: QuickSwitchOverlayLegacyStyle.keyCornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            if let binding {
                bindingContent(binding)
            } else if isReferenceKey {
                referenceKeyContent
            } else {
                shortcutPlaceholder
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(keyBackground, in: keyShape)
        .overlay(keyShape.strokeBorder(keyBorderColor, lineWidth: 1))
        .shadow(
            color: hasBinding
                ? .black.opacity(QuickSwitchOverlayLegacyStyle.boundKeyShadowOpacity)
                : .clear,
            radius: QuickSwitchOverlayLegacyStyle.boundKeyShadowRadius,
            y: QuickSwitchOverlayLegacyStyle.boundKeyShadowY
        )
    }

    private var keyHeader: some View {
        Text(key.label)
            .font(.system(size: referenceKeyFontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(isReferenceKey ? Color.secondary.opacity(0.42) : Color.secondary)
            .opacity(isReferenceKey ? 0.48 : 1)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var referenceKeyFontSize: CGFloat {
        if isFunctionReferenceKey {
            return QuickSwitchTokens.functionReferenceFontSize
        }

        if isReferenceKey {
            return QuickSwitchTokens.standardReferenceFontSize
        }

        return 12
    }

    private var referenceKeyContent: AnyView {
        if isBottomRowReferenceKey {
            return AnyView(bottomRowReferenceContent)
        } else {
            return AnyView(standardReferenceKeyContent)
        }
    }

    private var standardReferenceKeyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            keyHeader

            Spacer(minLength: 0)
            referencePlaceholder
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bottomRowReferenceContent: some View {
        ZStack(alignment: .bottomLeading) {
            if key.id == "space" {
                Text(key.label)
                    .font(.system(size: QuickSwitchTokens.bottomReferenceFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.34))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.bottom, 8)
            } else if isBottomModifierReferenceKey {
                bottomModifierLegend
                    .padding(.leading, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var bottomModifierLegend: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            if let symbol = bottomModifierSymbol {
                Text(symbol)
                    .font(.system(size: QuickSwitchTokens.bottomReferenceFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }

            Text(bottomModifierTitle)
                .font(.system(size: QuickSwitchTokens.bottomReferenceFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary.opacity(0.34))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
    }

    private var bottomModifierSymbol: String? {
        switch key.id {
        case "control":
            return "⌃"
        case "option":
            return "⌥"
        case "command":
            return "⌘"
        default:
            return nil
        }
    }

    private var bottomModifierTitle: String {
        switch key.id {
        case "fn":
            return "fn"
        case "control":
            return "control"
        case "option":
            return "option"
        case "command":
            return "command"
        default:
            return key.label
        }
    }

    private var keyBackground: AnyShapeStyle {
        if hasBinding {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(QuickSwitchOverlayLegacyStyle.boundKeyGradientStartOpacity),
                        Color.white.opacity(QuickSwitchOverlayLegacyStyle.boundKeyGradientEndOpacity),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
        }

        if isReferenceKey {
            return AnyShapeStyle(.ultraThinMaterial.opacity(QuickSwitchOverlayLegacyStyle.referenceKeyMaterialOpacity))
        }

        return AnyShapeStyle(.thinMaterial)
    }

    private var keyBorderColor: Color {
        if hasBinding {
            return .white.opacity(QuickSwitchOverlayLegacyStyle.boundKeyStrokeOpacity)
        }

        return .white.opacity(isReferenceKey
            ? QuickSwitchOverlayLegacyStyle.referenceKeyStrokeOpacity
            : QuickSwitchOverlayLegacyStyle.shortcutKeyStrokeOpacity)
    }

    private var referencePlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(0.03))
            .frame(width: min(width * 0.58, 74), height: 12)
            .blur(radius: 7.4)
            .opacity(0.3)
    }

    private var shortcutPlaceholder: some View {
        Text(key.label)
            .font(.system(size: QuickSwitchTokens.shortcutLabelFontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(QuickSwitchOverlayLegacyStyle.shortcutLabelOpacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var boundLabelShadowColor: Color {
        QuickSwitchOverlayLegacyStyle.boundLabelShadowBase(for: colorScheme).color
    }

    private func bindingContent(_ binding: HotkeyBinding) -> some View {
        ZStack(alignment: .topLeading) {
            overlayIcon(for: binding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.06)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            Text(key.label)
                .font(.system(size: QuickSwitchTokens.boundLabelFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(QuickSwitchOverlayLegacyStyle.boundLabelOpacity))
                .shadow(
                    color: boundLabelShadowColor.opacity(QuickSwitchOverlayLegacyStyle.boundLabelPrimaryShadowOpacity),
                    radius: 14.4,
                    y: 0
                )
                .shadow(
                    color: boundLabelShadowColor.opacity(QuickSwitchOverlayLegacyStyle.boundLabelSecondaryShadowOpacity),
                    radius: 14.4,
                    y: 0
                )
                .shadow(
                    color: boundLabelShadowColor.opacity(QuickSwitchOverlayLegacyStyle.boundLabelTertiaryShadowOpacity),
                    radius: 3.2,
                    y: 0
                )
                .padding(.top, 7)
                .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    /// 绑定键帽优先展示安全作用域内已物化的目标图标。
    private func overlayIcon(for binding: HotkeyBinding) -> some View {
        let presentation = targetPresentation(binding)
        Group {
            if let image = presentation.targetImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: presentation.fallbackSymbolName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(keyShape)
    }
}
