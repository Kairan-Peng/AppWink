import XCTest
@testable import AppWinkRuntime

final class SettingsInteractiveControlStyleTests: XCTestCase {
    func testAllRolesPreserveFillStyleAndIncreaseHoverAffordances() {
        for role in [SettingsInteractiveSurfaceRole.standard, .accent, .compactMenu] {
            let idle = SettingsInteractiveSurfaceResolver.tokens(for: role, isHovered: false)
            let hovered = SettingsInteractiveSurfaceResolver.tokens(for: role, isHovered: true)

            XCTAssertEqual(idle.fillStyle, hovered.fillStyle)
            XCTAssertLessThanOrEqual(idle.overlayOpacity, hovered.overlayOpacity)
            XCTAssertLessThanOrEqual(idle.strokeOpacity, hovered.strokeOpacity)
            XCTAssertLessThanOrEqual(idle.shadowOpacity, hovered.shadowOpacity)
        }
    }

    func testStandardHoverStrengthensMaterialFillAndStroke() {
        let idle = SettingsInteractiveSurfaceResolver.tokens(for: .standard, isHovered: false)
        let hovered = SettingsInteractiveSurfaceResolver.tokens(for: .standard, isHovered: true)

        XCTAssertEqual(idle.fillStyle, .material)
        XCTAssertLessThan(idle.fillOpacity, hovered.fillOpacity)
        XCTAssertLessThan(idle.overlayOpacity, hovered.overlayOpacity)
        XCTAssertLessThan(idle.strokeOpacity, hovered.strokeOpacity)
        XCTAssertLessThan(idle.shadowOpacity, hovered.shadowOpacity)
    }

    func testAccentHoverKeepsSolidFillAndOnlyLiftsOverlayAndStroke() {
        let idle = SettingsInteractiveSurfaceResolver.tokens(for: .accent, isHovered: false)
        let hovered = SettingsInteractiveSurfaceResolver.tokens(for: .accent, isHovered: true)

        XCTAssertEqual(idle.fillStyle, .accentColor)
        XCTAssertEqual(hovered.fillStyle, .accentColor)
        XCTAssertEqual(idle.fillOpacity, 1.0)
        XCTAssertEqual(hovered.fillOpacity, 1.0)
        XCTAssertEqual(idle.overlayOpacity, 0.0)
        XCTAssertLessThan(idle.overlayOpacity, hovered.overlayOpacity)
        XCTAssertLessThan(idle.strokeOpacity, hovered.strokeOpacity)
        XCTAssertLessThan(idle.shadowOpacity, hovered.shadowOpacity)
    }

    func testCompactMenuHoverUsesMaterialTokensWithoutShadowLift() {
        let idle = SettingsInteractiveSurfaceResolver.tokens(for: .compactMenu, isHovered: false)
        let hovered = SettingsInteractiveSurfaceResolver.tokens(for: .compactMenu, isHovered: true)

        XCTAssertEqual(idle.fillStyle, .material)
        XCTAssertLessThan(idle.fillOpacity, hovered.fillOpacity)
        XCTAssertLessThan(idle.overlayOpacity, hovered.overlayOpacity)
        XCTAssertLessThan(idle.strokeOpacity, hovered.strokeOpacity)
        XCTAssertEqual(idle.shadowOpacity, 0.0)
        XCTAssertEqual(hovered.shadowOpacity, 0.0)
    }

    func testRecorderRecordingStateOverridesPlainHoverTokens() {
        let hovered = SettingsInteractiveSurfaceResolver.recorderMetrics(isHovered: true, isRecording: false)
        let recording = SettingsInteractiveSurfaceResolver.recorderMetrics(isHovered: false, isRecording: true)
        let recordingWhileHovered = SettingsInteractiveSurfaceResolver.recorderMetrics(isHovered: true, isRecording: true)

        XCTAssertEqual(recording, recordingWhileHovered)
        XCTAssertEqual(recording.emphasisMetrics.shadowOpacity, 0.05)
        XCTAssertEqual(recording.backgroundStartOpacity, 0.54)
        XCTAssertGreaterThan(recording.emphasisMetrics.strokeOpacity, hovered.emphasisMetrics.strokeOpacity)
        XCTAssertGreaterThan(recording.backgroundStartOpacity, hovered.backgroundStartOpacity)
        XCTAssertEqual(recording.shadowTone, .black)
        XCTAssertEqual(hovered.shadowTone, .white)
    }

    func testOpeningModeControlUsesShortcutRecorderIdleAndHoverTokens() {
        for isHovered in [false, true] {
            XCTAssertEqual(
                SettingsInteractiveSurfaceResolver.openingModeMetrics(isHovered: isHovered),
                SettingsInteractiveSurfaceResolver.recorderMetrics(
                    isHovered: isHovered,
                    isRecording: false
                )
            )
        }
    }
}
