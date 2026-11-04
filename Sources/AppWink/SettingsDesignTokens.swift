import SwiftUI

/// SwiftUI-facing numeric bridge for the repo design token contract.
///
/// Keep this namespace intentionally small. It mirrors only the reusable values
/// needed by the approved AppWink settings, menu, sheet, and overlay slice.
enum SettingsDesignTokens {
    enum Space {
        static let four: CGFloat = 4
        static let six: CGFloat = 6
        static let eight: CGFloat = 8
        static let ten: CGFloat = 10
        static let twelve: CGFloat = 12
        static let fourteen: CGFloat = 14
        static let sixteen: CGFloat = 16
        static let eighteen: CGFloat = 18
        static let twenty: CGFloat = 20
        static let twentyFour: CGFloat = 24
        static let twentyEight: CGFloat = 28
        static let thirtyTwo: CGFloat = 32
    }

    enum Radius {
        static let keycap: CGFloat = 8
        static let control: CGFloat = 10
        static let compactControl: CGFloat = 12
        static let row: CGFloat = 14
        static let panel: CGFloat = 20
        static let shell: CGFloat = 24
        static let pill: CGFloat = 999
    }

    enum WindowChrome {
        static let titlebarHeight: CGFloat = 52
        static let contentTopPadding: CGFloat = 32
    }

    enum Window {
        static let minWidth: CGFloat = 615
        static let minHeight: CGFloat = minWidth
        static let edgePadding = Space.fourteen
        static let contentTopPadding = WindowChrome.contentTopPadding
    }

    enum SettingsWindow {
        static let minWidth: CGFloat = 465
        static let minHeight: CGFloat = 434
        static let windowFrameHeight: CGFloat = minHeight
        static let titlebarHeight = WindowChrome.titlebarHeight
        static let edgePadding = Space.fourteen
        static let contentTopPadding = WindowChrome.contentTopPadding
        static let sectionContentTopPadding: CGFloat = 44
        static let topFadeHeight: CGFloat = titlebarHeight
    }

    enum SettingsList {
        static let sectionSpacing = Space.twenty
        static let rowSpacing: CGFloat = 0
        static let rowMinHeight: CGFloat = 38.4
        static let rowPaddingX = Space.sixteen
        static let rowPaddingY: CGFloat = 5.2
        static let rowIconSize: CGFloat = 24
        static let rowRadius = Radius.row
        static let containerRadius = Radius.panel
        static let sectionTitlePaddingX = Space.four
        static let separatorLeadingInset = rowPaddingX
        static let separatorTrailingInset = Space.twenty
    }

    enum WorkbenchHeader {
        static let radius = Radius.shell
        static let paddingX = Space.six
        static let paddingY = Space.sixteen
        static let iconTileSize: CGFloat = 64
        static let iconImageSize: CGFloat = 44
    }

    enum BindingRow {
        static let radius = Radius.row
        static let listRadius = Radius.panel
        static let listSpacing: CGFloat = 0
        static let minHeight: CGFloat = 46.4
        static let paddingX = Space.eighteen
        static let paddingY: CGFloat = 2.2
        static let separatorLeadingInset = paddingX
        static let separatorTrailingInset = Space.eighteen
        static let iconSize: CGFloat = 40
        static let iconImageSize: CGFloat = 38
        static let toggleWidth: CGFloat = 64
        static let toggleHeight: CGFloat = 42
        static let reorderHandleVisualWidth = Space.twelve
        static let reorderHandleHitWidth = paddingX + reorderHandleVisualWidth + Space.twelve
    }

    enum ShortcutRecorder {
        static let width: CGFloat = 88
        static let height: CGFloat = 38
        static let radius = Radius.compactControl
    }

    enum BindingOpenMode {
        static let width: CGFloat = 72
        static let height = ShortcutRecorder.height
        static let radius = Radius.compactControl
        static let iconRegionWidth: CGFloat = 40
        static let dividerWidth: CGFloat = 1
        static let chevronRegionWidth: CGFloat =
            width - iconRegionWidth - dividerWidth
        static let iconSize: CGFloat = 28
        static let dividerHeight: CGFloat = 22
    }

    enum ToolboxRow {
        static let radius = Radius.row
        static let paddingX = Space.sixteen
        static let paddingY = Space.fourteen
        static let minHeight: CGFloat = 52
        static let iconSize: CGFloat = 24
    }

    enum Banner {
        static let maxWidth: CGFloat = 760
        static let radius = Radius.pill
        static let conflictRadius = Radius.panel
    }

    enum QuickSwitch {
        static let panelRadius: CGFloat = 28
        static let keycapRadius = Radius.keycap
        static let panelPadding = Space.twentyEight
        static let viewportPadding = Space.thirtyTwo
        static let titleSpacing = Space.fourteen
        static let keyUnitWidth: CGFloat = 86
        static let keyHeight: CGFloat = 86
        static let compactReferenceRowHeight: CGFloat = 58
        static let keySpacing = Space.twelve
        static let rowSpacing = Space.fourteen
        static let minimumScale: CGFloat = 0.72
        static let scaleSafeInset: CGFloat = 96
        static let fadeMidpointProgress: CGFloat = 0.52
        static let fadeDimOpacity: Double = 0.24
        static let panelFillOpacity: Double = 0.66
        static let panelStrokeOpacity: Double = 0.18
        static let panelShadowOpacity: Double = 0.24
        static let keycapStrokeOpacity: Double = 0.18
        static let referenceKeycapOpacity: Double = 0.06
        static let shortcutKeycapOpacity: Double = 0.12
        static let boundKeyOverlayOpacity: Double = 0.30
        static let boundGlyphShadowOpacity: Double = 0.62
        static let titleFontSize: CGFloat = 21
        static let shortcutLabelFontSize: CGFloat = 36
        static let boundLabelFontSize: CGFloat = 24
        static let functionReferenceFontSize: CGFloat = 11.5
        static let standardReferenceFontSize: CGFloat = 14.5
        static let bottomReferenceFontSize: CGFloat = 14.5
    }

    enum PressedKeysPill {
        static let radius = Radius.pill
        static let paddingX = Space.sixteen
        static let paddingY = Space.ten
        static let minHeight: CGFloat = 48
    }

    enum AppIconFlash {
        static let iconSize: CGFloat = 112
        static let edgeInset: CGFloat = 24
        static let peakOpacity: Double = 1.00
        static let holdDuration: TimeInterval = 0.10
        static let fadeOutDuration: TimeInterval = 0.35
        static let shadowOpacity: Double = 0.00
        static let shadowRadius: CGFloat = 0
        static let shadowY: CGFloat = 0
    }

    enum MenuBar {
        static let width: CGFloat = 320
        static let padding = Space.twelve
        static let spacing = Space.eight
        static let rowSpacing = Space.six
        static let rowRadius = Radius.compactControl
        static let rowPaddingX = Space.ten
        static let rowPaddingY = Space.six
        static let rowMinHeight: CGFloat = 34
        static let iconTileSize: CGFloat = 26
        static let appIconSize: CGFloat = 22
        static let headerIconSize: CGFloat = 22
    }

    enum Motion {
        static let hoverDuration: TimeInterval = 0.14
        static let pressDuration: TimeInterval = 0.09
        static let stateDuration: TimeInterval = 0.18
        static let layoutDuration: TimeInterval = 0.26
        static let overlayInDuration: TimeInterval = 0.18
        static let overlayOutDuration: TimeInterval = 0.12
    }

    enum Border {
        static func hairlineOpacity(for colorScheme: ColorScheme) -> Double {
            colorScheme == .dark ? 0.26 : 0.38
        }
    }

    enum Effect {
        enum Panel {
            static let shadowOpacity: Double = 0.06
            static let shadowRadius: CGFloat = 24
            static let shadowY: CGFloat = 10
        }

        enum ControlHover {
            static let shadowOpacity: Double = 0.08
            static let shadowRadius: CGFloat = 10
            static let shadowY: CGFloat = 4
        }

        enum Popover {
            static let shadowOpacity: Double = 0.14
            static let shadowRadius: CGFloat = 36
            static let shadowY: CGFloat = 18
        }

        enum KeycapBound {
            static let shadowOpacity: Double = 0.10
            static let shadowRadius: CGFloat = 16
            static let shadowY: CGFloat = 8
        }
    }

    enum Interactive {
        enum Standard {
            static let idleFillOpacity: Double = 0.06
            static let idleOverlayOpacity: Double = 0.0
            static let idleStrokeOpacity: Double = 0.20
            static let idleShadowOpacity: Double = 0.04

            static let hoveredFillOpacity: Double = 0.10
            static let hoveredOverlayOpacity: Double = 0.02
            static let hoveredStrokeOpacity: Double = 0.30
            static let hoveredShadowOpacity: Double = 0.06
        }

        enum Accent {
            static let fillOpacity: Double = 1.0
            static let idleOverlayOpacity: Double = 0.0
            static let idleStrokeOpacity: Double = 0.18
            static let idleShadowOpacity: Double = 0.05

            static let hoveredOverlayOpacity: Double = 0.07
            static let hoveredStrokeOpacity: Double = 0.24
            static let hoveredShadowOpacity: Double = 0.06
        }

        enum CompactMenu {
            static let idleFillOpacity: Double = 0.05
            static let idleOverlayOpacity: Double = 0.0
            static let idleStrokeOpacity: Double = 0.18
            static let idleShadowOpacity: Double = 0.0

            static let hoveredFillOpacity: Double = 0.08
            static let hoveredOverlayOpacity: Double = 0.02
            static let hoveredStrokeOpacity: Double = 0.28
            static let hoveredShadowOpacity: Double = 0.0
        }

        enum Recorder {
            enum Idle {
                static let strokeOpacity: Double = 0.28
                static let shadowOpacity: Double = 0.05
                static let backgroundStartOpacity: Double = 0.12
                static let backgroundEndOpacity: Double = 0.05
                static let highlightStartPointX: Double = 0.5
                static let highlightEndPointX: Double = 0.5
                static let highlightLocations: [Double] = [0, 0.28, 1]
                static let highlightOpacities: [Double] = [0.18, 0.04, 0]
                static let shadowRadius: CGFloat = 6
                static let shadowOffset = CGSize(width: 0, height: 2)
            }

            enum Hovered {
                static let strokeOpacity: Double = 0.34
                static let shadowOpacity: Double = 0.14
                static let backgroundStartOpacity: Double = 0.16
                static let backgroundEndOpacity: Double = 0.07
                static let highlightStartPointX: Double = 0.32
                static let highlightEndPointX: Double = 0.68
                static let highlightLocations: [Double] = [0, 0.2, 0.72, 1]
                static let highlightOpacities: [Double] = [0.22, 0.1, 0.03, 0]
                static let shadowRadius: CGFloat = 4
                static let shadowOffset = CGSize.zero
            }

            enum Recording {
                static let strokeOpacity: Double = 0.52
                static let shadowOpacity: Double = 0.05
                static let backgroundStartOpacity: Double = 0.54
                static let backgroundEndOpacity: Double = 0.26
                static let highlightStartPointX: Double = 0.38
                static let highlightEndPointX: Double = 0.62
                static let highlightLocations: [Double] = [0, 0.3, 0.72, 1]
                static let highlightOpacities: [Double] = [0.34, 0.16, 0.05, 0]
                static let shadowRadius: CGFloat = 7
                static let shadowOffset = CGSize(width: 0, height: 2)
            }
        }
    }
}
