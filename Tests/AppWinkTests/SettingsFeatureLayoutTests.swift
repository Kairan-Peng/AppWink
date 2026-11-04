import Foundation
import XCTest

final class SettingsFeatureLayoutTests: XCTestCase {
    func testFeatureDescriptionPanelCentersIconAndSummaryVertically() throws {
        let source = try source(named: "SettingsFeatureDetailView.swift")
        let descriptionStart = try XCTUnwrap(source.range(of: "private var descriptionPanel"))
        let featureSectionStart = try XCTUnwrap(
            source.range(of: "private var featureSection", range: descriptionStart.upperBound..<source.endIndex)
        )
        let descriptionPanel = String(
            source[descriptionStart.lowerBound..<featureSectionStart.lowerBound]
        )

        XCTAssertTrue(
            descriptionPanel.contains(
                "HStack(alignment: .center, spacing: SettingsDesignTokens.Space.sixteen)"
            )
        )
        XCTAssertFalse(descriptionPanel.contains("HStack(alignment: .top"))
    }

    func testFeatureEnableToggleIsTheTrailingRowAccessory() throws {
        let source = try source(named: "SettingsFeatureDetailView.swift")
        let featureSectionStart = try XCTUnwrap(source.range(of: "private var featureSection"))
        let detailSectionStart = try XCTUnwrap(
            source.range(of: "private var detailSection", range: featureSectionStart.upperBound..<source.endIndex)
        )
        let featureSection = String(source[featureSectionStart.lowerBound..<detailSectionStart.lowerBound])

        let rowStart = try XCTUnwrap(featureSection.range(of: "HStack("))
        let title = try XCTUnwrap(featureSection.range(of: "Text(localized(.settingsFeatureEnable))"))
        let spacer = try XCTUnwrap(
            featureSection.range(of: "Spacer(minLength: SettingsDesignTokens.Space.sixteen)")
        )
        let toggle = try XCTUnwrap(
            featureSection.range(of: "Toggle(localized(.settingsFeatureEnable), isOn: featureBinding)")
        )
        let hiddenLabel = try XCTUnwrap(featureSection.range(of: ".labelsHidden()"))

        XCTAssertLessThan(rowStart.lowerBound, title.lowerBound)
        XCTAssertLessThan(title.lowerBound, spacer.lowerBound)
        XCTAssertLessThan(spacer.lowerBound, toggle.lowerBound)
        XCTAssertLessThan(toggle.lowerBound, hiddenLabel.lowerBound)
    }

    func testFeatureNavigationRowUsesGroupedListTrailingAccessoryStyle() throws {
        let source = try source(named: "SettingsFeatureRow.swift")

        XCTAssertTrue(source.contains(".settingsInteractiveListRowSurface()"))
        XCTAssertFalse(source.contains(".settingsInteractiveChrome("))
        XCTAssertTrue(source.contains("Spacer(minLength: SettingsDesignTokens.Space.sixteen)"))

        let trailingAccessory = try XCTUnwrap(
            source.range(of: "HStack(spacing: SettingsDesignTokens.Space.four)")
        )
        let status = try XCTUnwrap(source.range(of: "statusText", range: trailingAccessory.upperBound..<source.endIndex))
        let chevron = try XCTUnwrap(
            source.range(of: "Image(systemName: \"chevron.right\")", range: status.upperBound..<source.endIndex)
        )
        let fixedSize = try XCTUnwrap(
            source.range(
                of: ".fixedSize(horizontal: true, vertical: false)",
                range: chevron.upperBound..<source.endIndex
            )
        )

        XCTAssertLessThan(trailingAccessory.lowerBound, status.lowerBound)
        XCTAssertLessThan(status.lowerBound, chevron.lowerBound)
        XCTAssertLessThan(chevron.lowerBound, fixedSize.lowerBound)
    }

    private func source(named fileName: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AppWink/\(fileName)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
