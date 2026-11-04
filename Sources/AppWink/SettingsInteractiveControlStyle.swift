import SwiftUI

enum SettingsInteractiveSurfaceRole: Equatable {
    case standard
    case accent
    case compactMenu
}

enum SettingsInteractiveSurfaceFillStyle: Equatable {
    case material
    case accentColor
}

struct SettingsInteractiveEmphasisMetrics: Equatable {
    let strokeOpacity: Double
    let shadowOpacity: Double
}

struct SettingsInteractiveSurfaceTokens: Equatable {
    let fillStyle: SettingsInteractiveSurfaceFillStyle
    let fillOpacity: Double
    let overlayOpacity: Double
    let emphasisMetrics: SettingsInteractiveEmphasisMetrics

    var strokeOpacity: Double {
        emphasisMetrics.strokeOpacity
    }

    var shadowOpacity: Double {
        emphasisMetrics.shadowOpacity
    }
}

enum SettingsInteractiveRecorderShadowTone: Equatable {
    case black
    case white
}

struct SettingsInteractiveRecorderTokens: Equatable {
    let emphasisMetrics: SettingsInteractiveEmphasisMetrics
    let backgroundStartOpacity: Double
    let backgroundEndOpacity: Double
    let highlightStartPointX: Double
    let highlightEndPointX: Double
    let highlightLocations: [Double]
    let highlightOpacities: [Double]
    let shadowTone: SettingsInteractiveRecorderShadowTone
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
}

enum SettingsInteractiveSurfaceResolver {
    private typealias StandardTokens = SettingsDesignTokens.Interactive.Standard
    private typealias AccentTokens = SettingsDesignTokens.Interactive.Accent
    private typealias CompactMenuTokens = SettingsDesignTokens.Interactive.CompactMenu
    private typealias RecorderIdleTokens = SettingsDesignTokens.Interactive.Recorder.Idle
    private typealias RecorderHoveredTokens = SettingsDesignTokens.Interactive.Recorder.Hovered
    private typealias RecorderRecordingTokens = SettingsDesignTokens.Interactive.Recorder.Recording

    static func tokens(for role: SettingsInteractiveSurfaceRole, isHovered: Bool) -> SettingsInteractiveSurfaceTokens {
        switch (role, isHovered) {
        case (.standard, false):
            return .init(
                fillStyle: .material,
                fillOpacity: StandardTokens.idleFillOpacity,
                overlayOpacity: StandardTokens.idleOverlayOpacity,
                emphasisMetrics: .init(
                    strokeOpacity: StandardTokens.idleStrokeOpacity,
                    shadowOpacity: StandardTokens.idleShadowOpacity
                )
            )
        case (.standard, true):
            return .init(
                fillStyle: .material,
                fillOpacity: StandardTokens.hoveredFillOpacity,
                overlayOpacity: StandardTokens.hoveredOverlayOpacity,
                emphasisMetrics: .init(
                    strokeOpacity: StandardTokens.hoveredStrokeOpacity,
                    shadowOpacity: StandardTokens.hoveredShadowOpacity
                )
            )
        case (.accent, false):
            return .init(
                fillStyle: .accentColor,
                fillOpacity: AccentTokens.fillOpacity,
                overlayOpacity: AccentTokens.idleOverlayOpacity,
                emphasisMetrics: .init(
                    strokeOpacity: AccentTokens.idleStrokeOpacity,
                    shadowOpacity: AccentTokens.idleShadowOpacity
                )
            )
        case (.accent, true):
            return .init(
                fillStyle: .accentColor,
                fillOpacity: AccentTokens.fillOpacity,
                overlayOpacity: AccentTokens.hoveredOverlayOpacity,
                emphasisMetrics: .init(
                    strokeOpacity: AccentTokens.hoveredStrokeOpacity,
                    shadowOpacity: AccentTokens.hoveredShadowOpacity
                )
            )
        case (.compactMenu, false):
            return .init(
                fillStyle: .material,
                fillOpacity: CompactMenuTokens.idleFillOpacity,
                overlayOpacity: CompactMenuTokens.idleOverlayOpacity,
                emphasisMetrics: .init(
                    strokeOpacity: CompactMenuTokens.idleStrokeOpacity,
                    shadowOpacity: CompactMenuTokens.idleShadowOpacity
                )
            )
        case (.compactMenu, true):
            return .init(
                fillStyle: .material,
                fillOpacity: CompactMenuTokens.hoveredFillOpacity,
                overlayOpacity: CompactMenuTokens.hoveredOverlayOpacity,
                emphasisMetrics: .init(
                    strokeOpacity: CompactMenuTokens.hoveredStrokeOpacity,
                    shadowOpacity: CompactMenuTokens.hoveredShadowOpacity
                )
            )
        }
    }

    static func recorderMetrics(isHovered: Bool, isRecording: Bool) -> SettingsInteractiveRecorderTokens {
        switch state(isHovered: isHovered, isRecording: isRecording) {
        case .idle:
            return .init(
                emphasisMetrics: .init(
                    strokeOpacity: RecorderIdleTokens.strokeOpacity,
                    shadowOpacity: RecorderIdleTokens.shadowOpacity
                ),
                backgroundStartOpacity: RecorderIdleTokens.backgroundStartOpacity,
                backgroundEndOpacity: RecorderIdleTokens.backgroundEndOpacity,
                highlightStartPointX: RecorderIdleTokens.highlightStartPointX,
                highlightEndPointX: RecorderIdleTokens.highlightEndPointX,
                highlightLocations: RecorderIdleTokens.highlightLocations,
                highlightOpacities: RecorderIdleTokens.highlightOpacities,
                shadowTone: .black,
                shadowRadius: RecorderIdleTokens.shadowRadius,
                shadowOffset: RecorderIdleTokens.shadowOffset
            )
        case .hovered:
            return .init(
                emphasisMetrics: .init(
                    strokeOpacity: RecorderHoveredTokens.strokeOpacity,
                    shadowOpacity: RecorderHoveredTokens.shadowOpacity
                ),
                backgroundStartOpacity: RecorderHoveredTokens.backgroundStartOpacity,
                backgroundEndOpacity: RecorderHoveredTokens.backgroundEndOpacity,
                highlightStartPointX: RecorderHoveredTokens.highlightStartPointX,
                highlightEndPointX: RecorderHoveredTokens.highlightEndPointX,
                highlightLocations: RecorderHoveredTokens.highlightLocations,
                highlightOpacities: RecorderHoveredTokens.highlightOpacities,
                shadowTone: .white,
                shadowRadius: RecorderHoveredTokens.shadowRadius,
                shadowOffset: RecorderHoveredTokens.shadowOffset
            )
        case .recording:
            return .init(
                emphasisMetrics: .init(
                    strokeOpacity: RecorderRecordingTokens.strokeOpacity,
                    shadowOpacity: RecorderRecordingTokens.shadowOpacity
                ),
                backgroundStartOpacity: RecorderRecordingTokens.backgroundStartOpacity,
                backgroundEndOpacity: RecorderRecordingTokens.backgroundEndOpacity,
                highlightStartPointX: RecorderRecordingTokens.highlightStartPointX,
                highlightEndPointX: RecorderRecordingTokens.highlightEndPointX,
                highlightLocations: RecorderRecordingTokens.highlightLocations,
                highlightOpacities: RecorderRecordingTokens.highlightOpacities,
                shadowTone: .black,
                shadowRadius: RecorderRecordingTokens.shadowRadius,
                shadowOffset: RecorderRecordingTokens.shadowOffset
            )
        }
    }

    static func openingModeMetrics(isHovered: Bool) -> SettingsInteractiveRecorderTokens {
        recorderMetrics(isHovered: isHovered, isRecording: false)
    }

    private static func state(isHovered: Bool, isRecording: Bool) -> State {
        if isRecording {
            return .recording
        }

        return isHovered ? .hovered : .idle
    }

    private enum State {
        case idle
        case hovered
        case recording
    }
}

private struct SettingsRecorderChromeModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let isHovered: Bool

    func body(content: Content) -> some View {
        let metrics = SettingsInteractiveSurfaceResolver.openingModeMetrics(
            isHovered: isHovered
        )

        content
            .contentShape(shape)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(metrics.backgroundStartOpacity),
                            .white.opacity(metrics.backgroundEndOpacity),
                        ],
                        startPoint: UnitPoint(x: 0.12, y: 1),
                        endPoint: UnitPoint(x: 0.88, y: 0)
                    )
                )
            )
            .overlay(
                shape
                    .inset(by: 1)
                    .fill(
                        LinearGradient(
                            stops: zip(
                                metrics.highlightLocations,
                                metrics.highlightOpacities
                            ).map { location, opacity in
                                .init(color: .white.opacity(opacity), location: location)
                            },
                            startPoint: UnitPoint(x: metrics.highlightStartPointX, y: 1),
                            endPoint: UnitPoint(x: metrics.highlightEndPointX, y: 0)
                        )
                    )
                    .allowsHitTesting(false)
            )
            .overlay(
                shape.strokeBorder(
                    .white.opacity(metrics.emphasisMetrics.strokeOpacity),
                    lineWidth: 1
                )
            )
            .shadow(
                color: shadowColor(
                    for: metrics.shadowTone,
                    opacity: metrics.emphasisMetrics.shadowOpacity
                ),
                radius: metrics.shadowRadius,
                x: metrics.shadowOffset.width,
                y: metrics.shadowOffset.height
            )
    }

    private func shadowColor(
        for tone: SettingsInteractiveRecorderShadowTone,
        opacity: Double
    ) -> Color {
        switch tone {
        case .black:
            return .black.opacity(opacity)
        case .white:
            return .white.opacity(opacity)
        }
    }
}

private struct SettingsInteractiveChromeModifier<S: InsettableShape>: ViewModifier {
    let role: SettingsInteractiveSurfaceRole
    let shape: S
    let externallyManagedHover: Bool?

    @State private var isHovered = false

    func body(content: Content) -> some View {
        let effectiveHover = externallyManagedHover ?? isHovered
        let tokens = SettingsInteractiveSurfaceResolver.tokens(for: role, isHovered: effectiveHover)

        content
            .contentShape(shape)
            .background(backgroundStyle(for: tokens), in: shape)
            .overlay(surfaceFillOverlay(for: tokens).allowsHitTesting(false))
            .overlay(shape.fill(.white.opacity(tokens.overlayOpacity)).allowsHitTesting(false))
            .overlay(shape.strokeBorder(.white.opacity(tokens.emphasisMetrics.strokeOpacity), lineWidth: 1))
            .shadow(
                color: .black.opacity(tokens.emphasisMetrics.shadowOpacity),
                radius: shadowRadius(for: tokens.emphasisMetrics),
                y: SettingsDesignTokens.Effect.ControlHover.shadowY
            )
            .onHover { isHovered = $0 }
    }

    private func backgroundStyle(for tokens: SettingsInteractiveSurfaceTokens) -> AnyShapeStyle {
        switch tokens.fillStyle {
        case .accentColor:
            return AnyShapeStyle(Color.accentColor.opacity(tokens.fillOpacity))
        case .material:
            return AnyShapeStyle(.thinMaterial)
        }
    }

    @ViewBuilder
    private func surfaceFillOverlay(for tokens: SettingsInteractiveSurfaceTokens) -> some View {
        switch tokens.fillStyle {
        case .accentColor:
            EmptyView()
        case .material:
            shape.fill(.white.opacity(tokens.fillOpacity))
        }
    }

    private func shadowRadius(for metrics: SettingsInteractiveEmphasisMetrics) -> CGFloat {
        metrics.shadowOpacity == 0 ? 0 : SettingsDesignTokens.Effect.ControlHover.shadowRadius
    }
}

extension View {
    func settingsInteractiveChrome<S: InsettableShape>(
        role: SettingsInteractiveSurfaceRole,
        shape: S,
        isHovered: Bool? = nil
    ) -> some View {
        modifier(
            SettingsInteractiveChromeModifier(
                role: role,
                shape: shape,
                externallyManagedHover: isHovered
            )
        )
    }

    func settingsRecorderChrome<S: InsettableShape>(
        shape: S,
        isHovered: Bool
    ) -> some View {
        modifier(
            SettingsRecorderChromeModifier(
                shape: shape,
                isHovered: isHovered
            )
        )
    }
}
