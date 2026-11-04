import Foundation

struct BindingsListLayoutResult: Equatable {
    let visibleHeight: CGFloat
    let shouldScroll: Bool
}

enum BindingsListLayout {
    static func resolve(contentHeight: CGFloat, availableHeight: CGFloat) -> BindingsListLayoutResult {
        let safeContentHeight = max(contentHeight, 0)
        let safeAvailableHeight = max(availableHeight, 0)
        let visibleHeight = min(safeContentHeight, safeAvailableHeight)
        let shouldScroll = safeContentHeight > safeAvailableHeight && safeAvailableHeight > 0

        return BindingsListLayoutResult(
            visibleHeight: visibleHeight,
            shouldScroll: shouldScroll)
    }
}
