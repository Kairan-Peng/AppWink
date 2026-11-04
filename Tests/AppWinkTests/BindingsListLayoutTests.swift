import XCTest
@testable import AppWinkRuntime

final class BindingsListLayoutTests: XCTestCase {
    func testContentFitsReturnsContentHeightAndDoesNotScroll() {
        let result = BindingsListLayout.resolve(contentHeight: 180, availableHeight: 240)

        XCTAssertEqual(result, BindingsListLayoutResult(visibleHeight: 180, shouldScroll: false))
    }

    func testContentOverflowsReturnsAvailableHeightAndScrolls() {
        let compactRowHeight = SettingsDesignTokens.BindingRow.minHeight
        let separatorsHeight: CGFloat = 2
        let mixedContentHeight =
            compactRowHeight +
            compactRowHeight +
            compactRowHeight +
            separatorsHeight

        let result = BindingsListLayout.resolve(
            contentHeight: mixedContentHeight,
            availableHeight: 120
        )

        XCTAssertEqual(result, BindingsListLayoutResult(visibleHeight: 120, shouldScroll: true))
    }

    func testNegativeAndZeroInputsClampToZeroWithoutScrolling() {
        let result = BindingsListLayout.resolve(contentHeight: -50, availableHeight: 0)

        XCTAssertEqual(result, BindingsListLayoutResult(visibleHeight: 0, shouldScroll: false))
    }

    func testBindingRowSeparatorStartsAtRowContentInset() {
        XCTAssertEqual(
            SettingsDesignTokens.BindingRow.separatorLeadingInset,
            SettingsDesignTokens.BindingRow.paddingX
        )
    }

    func testBindingRowReorderHitAreaExtendsToAppIconLeftEdge() {
        XCTAssertEqual(
            SettingsDesignTokens.BindingRow.reorderHandleHitWidth,
            SettingsDesignTokens.BindingRow.paddingX +
            SettingsDesignTokens.BindingRow.reorderHandleVisualWidth +
            SettingsDesignTokens.Space.twelve
        )
    }

    func testBindingRowCompactVisualRefreshTokens() {
        XCTAssertEqual(SettingsDesignTokens.BindingRow.minHeight, 46.4, accuracy: 0.001)
        XCTAssertEqual(SettingsDesignTokens.BindingRow.paddingY, 2.2, accuracy: 0.001)
        XCTAssertEqual(SettingsDesignTokens.BindingRow.iconSize, 40)
        XCTAssertEqual(SettingsDesignTokens.BindingRow.iconImageSize, 38)
        XCTAssertEqual(SettingsDesignTokens.BindingRow.toggleWidth, 64)
        XCTAssertEqual(SettingsDesignTokens.BindingRow.toggleHeight, 42)
        XCTAssertEqual(SettingsDesignTokens.ShortcutRecorder.width, 88)
        XCTAssertEqual(SettingsDesignTokens.BindingOpenMode.width, 72)
        XCTAssertEqual(
            SettingsDesignTokens.BindingOpenMode.height,
            SettingsDesignTokens.ShortcutRecorder.height
        )
        XCTAssertEqual(SettingsDesignTokens.BindingOpenMode.iconRegionWidth, 40)
        XCTAssertEqual(SettingsDesignTokens.BindingOpenMode.dividerWidth, 1)
        XCTAssertEqual(SettingsDesignTokens.BindingOpenMode.chevronRegionWidth, 31)
        XCTAssertEqual(SettingsDesignTokens.BindingOpenMode.iconSize, 28)
        XCTAssertEqual(SettingsDesignTokens.BindingOpenMode.dividerHeight, 22)
    }

    func testPrimaryPageInsetsUseCompactChromeSpacing() {
        XCTAssertEqual(SettingsDesignTokens.Window.minWidth, 615)
        XCTAssertEqual(SettingsDesignTokens.Window.minHeight, 615)
        XCTAssertEqual(SettingsDesignTokens.SettingsWindow.minWidth, 465)
        XCTAssertEqual(SettingsDesignTokens.SettingsWindow.minHeight, 434)
        XCTAssertEqual(SettingsDesignTokens.SettingsWindow.windowFrameHeight, 434)
        XCTAssertEqual(SettingsDesignTokens.Window.edgePadding, SettingsDesignTokens.Space.fourteen)
        XCTAssertEqual(SettingsDesignTokens.SettingsWindow.edgePadding, SettingsDesignTokens.Space.fourteen)
        XCTAssertEqual(SettingsDesignTokens.Window.contentTopPadding, 32)
        XCTAssertEqual(SettingsDesignTokens.SettingsWindow.contentTopPadding, 32)
        XCTAssertEqual(SettingsDesignTokens.SettingsWindow.sectionContentTopPadding, 44)
        XCTAssertEqual(SettingsDesignTokens.WorkbenchHeader.paddingX, SettingsDesignTokens.Space.six)
    }

    func testSettingsListRowsUseCompactEightyPercentHeight() {
        XCTAssertEqual(SettingsDesignTokens.SettingsList.rowMinHeight, 38.4, accuracy: 0.001)
        XCTAssertEqual(SettingsDesignTokens.SettingsList.rowPaddingY, 5.2, accuracy: 0.001)
    }
}
