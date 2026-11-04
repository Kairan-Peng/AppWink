import XCTest
@testable import AppWinkRuntime

final class HiddenBarPresentationMetricsTests: XCTestCase {
    func testHiddenBarStatusItemsUseCompactVisibleWidths() {
        XCTAssertEqual(HiddenBarPresentationMetrics.arrowLength, 18)
        XCTAssertLessThan(HiddenBarPresentationMetrics.expandedBoundaryLength, 22)
        XCTAssertGreaterThanOrEqual(HiddenBarPresentationMetrics.expandedBoundaryLength, 10)
    }

    func testCollapsePolicySwitchesAtMacOS27() {
        XCTAssertEqual(HiddenBarPresentationMetrics.collapsePolicy(majorOperatingSystemVersion: 26), .legacyOversized)
        XCTAssertEqual(HiddenBarPresentationMetrics.collapsePolicy(majorOperatingSystemVersion: 27), .macOS27Capped)
    }

    func testCollapsedPusherLengthTracksDisplayWidthInsteadOfFixedHugeWidth() {
        XCTAssertEqual(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [1_728], policy: .legacyOversized),
            1_728
        )
        XCTAssertEqual(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [900], policy: .legacyOversized),
            HiddenBarPresentationMetrics.minimumCollapsedPusherLength
        )
        XCTAssertEqual(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [10_000], policy: .legacyOversized),
            HiddenBarPresentationMetrics.maximumCollapsedPusherLength
        )
    }

    func testMacOS27CollapsedPusherLengthStaysUnderHalfWidthDiscardCliff() {
        XCTAssertEqual(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [1_728], policy: .macOS27Capped),
            777
        )
        XCTAssertEqual(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [2_056], policy: .macOS27Capped),
            925
        )
        XCTAssertEqual(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [900], policy: .macOS27Capped),
            405
        )
        XCTAssertLessThan(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [1_728], policy: .macOS27Capped),
            1_728 * HiddenBarPresentationMetrics.macOS27DiscardThresholdRatio
        )
    }

    func testMacOS27CollapsedPusherLengthUsesNarrowestScreenToStayUnderEveryDisplayCliff() {
        XCTAssertEqual(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [1_728, 3_440], policy: .macOS27Capped),
            777
        )
        XCTAssertLessThan(
            HiddenBarPresentationMetrics.collapsedPusherLength(for: [1_728, 3_440], policy: .macOS27Capped),
            1_728 * HiddenBarPresentationMetrics.macOS27DiscardThresholdRatio
        )
    }

    func testSettingsIconMatchesCollapsedMenuBarArrow() {
        XCTAssertEqual(
            HiddenBarPresentationMetrics.settingsRowIconSystemName,
            HiddenBarPresentationMetrics.collapsedArrowSystemName
        )
    }

    func testBoundaryMarkerUsesActiveTemplateContrast() {
        let presentation = HiddenBarBoundaryMarkerPresentation.make()

        XCTAssertTrue(presentation.image.isTemplate)
        XCTAssertTrue(presentation.isEnabled)
        XCTAssertFalse(presentation.appearsDisabled)
        XCTAssertNil(presentation.contentTintColor)
    }
}
