import XCTest
@testable import AppWinkRuntime

final class BindingReorderPreviewTests: XCTestCase {
    func testDragPreviewMovesCompactRowDownAcrossTallRowUsingMeasuredCenters() {
        let ids = makeIDs()
        let rowFrames = [
            ids[0]: CGRect(x: 0, y: 0, width: 500, height: 46),
            ids[1]: CGRect(x: 0, y: 47, width: 500, height: 72),
            ids[2]: CGRect(x: 0, y: 120, width: 500, height: 46),
            ids[3]: CGRect(x: 0, y: 167, width: 500, height: 72),
        ]

        let reorderedIDs = BindingReorderPreview.orderedBindingIDs(
            initialOrderedBindingIDs: ids,
            draggedBindingID: ids[0],
            translationHeight: 64,
            initialRowFrames: rowFrames
        )

        XCTAssertEqual(reorderedIDs, [ids[1], ids[0], ids[2], ids[3]])
    }

    func testDragPreviewMovesTallRowUpAcrossCompactRowUsingMeasuredCenters() {
        let ids = makeIDs()
        let rowFrames = [
            ids[0]: CGRect(x: 0, y: 0, width: 500, height: 46),
            ids[1]: CGRect(x: 0, y: 47, width: 500, height: 46),
            ids[2]: CGRect(x: 0, y: 94, width: 500, height: 72),
            ids[3]: CGRect(x: 0, y: 167, width: 500, height: 46),
        ]

        let reorderedIDs = BindingReorderPreview.orderedBindingIDs(
            initialOrderedBindingIDs: ids,
            draggedBindingID: ids[2],
            translationHeight: -70,
            initialRowFrames: rowFrames
        )

        XCTAssertEqual(reorderedIDs, [ids[0], ids[2], ids[1], ids[3]])
    }

    func testDragPreviewStateKeepsOriginalOrderStableAfterAnimatedSwap() {
        let ids = makeIDs()
        let rowFrames = [
            ids[0]: CGRect(x: 0, y: 0, width: 500, height: 46),
            ids[1]: CGRect(x: 0, y: 47, width: 500, height: 72),
            ids[2]: CGRect(x: 0, y: 120, width: 500, height: 46),
            ids[3]: CGRect(x: 0, y: 167, width: 500, height: 72),
        ]
        var state = BindingReorderState(
            draggedBindingID: ids[0],
            orderedBindingIDs: ids,
            rowFrames: rowFrames
        )
        state.orderedBindingIDs = BindingReorderPreview.orderedBindingIDs(
            initialOrderedBindingIDs: state.initialOrderedBindingIDs,
            draggedBindingID: state.draggedBindingID,
            translationHeight: 64,
            initialRowFrames: state.initialRowFrames
        )

        let repeatedPreviewIDs = BindingReorderPreview.orderedBindingIDs(
            initialOrderedBindingIDs: state.initialOrderedBindingIDs,
            draggedBindingID: state.draggedBindingID,
            translationHeight: 64,
            initialRowFrames: state.initialRowFrames
        )

        XCTAssertEqual(repeatedPreviewIDs, state.orderedBindingIDs)
        XCTAssertEqual(repeatedPreviewIDs, [ids[1], ids[0], ids[2], ids[3]])
    }

    func testDragPreviewIgnoresInvalidInputs() {
        let ids = makeIDs()
        let rowFrames = [
            ids[0]: CGRect(x: 0, y: 0, width: 500, height: 46),
            ids[1]: CGRect(x: 0, y: 47, width: 500, height: 72),
            ids[2]: CGRect(x: 0, y: 120, width: 500, height: 46),
            ids[3]: CGRect(x: 0, y: 167, width: 500, height: 72),
        ]

        XCTAssertEqual(
            BindingReorderPreview.orderedBindingIDs(
                initialOrderedBindingIDs: ids,
                draggedBindingID: UUID(),
                translationHeight: 64,
                initialRowFrames: rowFrames
            ),
            ids
        )
        XCTAssertEqual(
            BindingReorderPreview.orderedBindingIDs(
                initialOrderedBindingIDs: ids,
                draggedBindingID: ids[0],
                translationHeight: 64,
                initialRowFrames: [:]
            ),
            ids
        )
    }

    private func makeIDs() -> [UUID] {
        [
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        ]
    }
}
