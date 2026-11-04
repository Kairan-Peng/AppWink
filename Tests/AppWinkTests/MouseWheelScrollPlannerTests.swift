import XCTest
@testable import AppWinkRuntime

final class MouseWheelScrollPlannerTests: XCTestCase {
    func testContinuousEventsAreBypassed() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: true,
            scrollPhase: 0,
            momentumPhase: 0,
            lineDeltaX: 0,
            lineDeltaY: 1,
            pointDeltaX: 0,
            pointDeltaY: 0
        )

        XCTAssertFalse(MouseWheelScrollPlanner.shouldTransform(facts))
    }

    func testGesturePhaseEventsAreBypassed() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: false,
            scrollPhase: 1,
            momentumPhase: 0,
            lineDeltaX: 0,
            lineDeltaY: 1,
            pointDeltaX: 0,
            pointDeltaY: 0
        )

        XCTAssertFalse(MouseWheelScrollPlanner.shouldTransform(facts))
    }

    func testMomentumPhaseEventsAreBypassed() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 1,
            lineDeltaX: 0,
            lineDeltaY: 1,
            pointDeltaX: 0,
            pointDeltaY: 0
        )

        XCTAssertFalse(MouseWheelScrollPlanner.shouldTransform(facts))
    }

    func testNaturalScrollingOnInvertsMouseWheelDeltaForWindowsDirection() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            lineDeltaX: 0,
            lineDeltaY: 1,
            pointDeltaX: 0,
            pointDeltaY: 0
        )

        let target = MouseWheelScrollPlanner.targetPixels(
            for: facts,
            naturalScrollingEnabled: true,
            pixelsPerLine: 10
        )

        XCTAssertEqual(target, MouseWheelScrollTarget(deltaX: 0, deltaY: -10))
    }

    func testNaturalScrollingOffKeepsMouseWheelDeltaForWindowsDirection() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            lineDeltaX: 0,
            lineDeltaY: 1,
            pointDeltaX: 0,
            pointDeltaY: 0
        )

        let target = MouseWheelScrollPlanner.targetPixels(
            for: facts,
            naturalScrollingEnabled: false,
            pixelsPerLine: 10
        )

        XCTAssertEqual(target, MouseWheelScrollTarget(deltaX: 0, deltaY: 10))
    }

    func testHorizontalLineDeltaUsesPixelsPerLine() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            lineDeltaX: 2,
            lineDeltaY: 0,
            pointDeltaX: 0,
            pointDeltaY: 0
        )

        let target = MouseWheelScrollPlanner.targetPixels(
            for: facts,
            naturalScrollingEnabled: false,
            pixelsPerLine: 12
        )

        XCTAssertEqual(target, MouseWheelScrollTarget(deltaX: 24, deltaY: 0))
    }

    func testPointDeltaTakesPrecedenceOverLineDeltaForSameAxis() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            lineDeltaX: 3,
            lineDeltaY: 4,
            pointDeltaX: 7,
            pointDeltaY: -9
        )

        let target = MouseWheelScrollPlanner.targetPixels(
            for: facts,
            naturalScrollingEnabled: false,
            pixelsPerLine: 10
        )

        XCTAssertEqual(target, MouseWheelScrollTarget(deltaX: 7, deltaY: -9))
    }

    func testFractionalPixelsPerLineRoundsLineDelta() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            lineDeltaX: 0,
            lineDeltaY: 3,
            pointDeltaX: 0,
            pointDeltaY: 0
        )

        let target = MouseWheelScrollPlanner.targetPixels(
            for: facts,
            naturalScrollingEnabled: false,
            pixelsPerLine: 2.5
        )

        XCTAssertEqual(target, MouseWheelScrollTarget(deltaX: 0, deltaY: 8))
    }

    func testAllZeroFactsReturnNilTarget() {
        let facts = MouseWheelScrollEventFacts(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            lineDeltaX: 0,
            lineDeltaY: 0,
            pointDeltaX: 0,
            pointDeltaY: 0
        )

        let target = MouseWheelScrollPlanner.targetPixels(
            for: facts,
            naturalScrollingEnabled: false,
            pixelsPerLine: 10
        )

        XCTAssertNil(target)
    }

    func testEasedFramesMatchExpectedSequenceAndSumToTarget() {
        let frames = MouseWheelScrollPlanner.easedFrames(
            target: MouseWheelScrollTarget(deltaX: 12, deltaY: -30),
            frameCount: 6
        )

        XCTAssertEqual(frames, [
            MouseWheelScrollFrame(deltaX: 5, deltaY: -13),
            MouseWheelScrollFrame(deltaX: 3, deltaY: -8),
            MouseWheelScrollFrame(deltaX: 3, deltaY: -5),
            MouseWheelScrollFrame(deltaX: 1, deltaY: -3),
            MouseWheelScrollFrame(deltaX: 0, deltaY: -1),
            MouseWheelScrollFrame(deltaX: 0, deltaY: 0),
        ])
        XCTAssertEqual(frames.reduce(0) { $0 + $1.deltaX }, 12)
        XCTAssertEqual(frames.reduce(0) { $0 + $1.deltaY }, -30)
    }

    func testEasedFramesDoNotReverseDirection() {
        let frames = MouseWheelScrollPlanner.easedFrames(
            target: MouseWheelScrollTarget(deltaX: 12, deltaY: -30),
            frameCount: 6
        )

        XCTAssertTrue(frames.allSatisfy { $0.deltaX >= 0 })
        XCTAssertTrue(frames.allSatisfy { $0.deltaY <= 0 })
    }

    func testNonPositiveFrameCountsProduceSingleTargetFrame() {
        let target = MouseWheelScrollTarget(deltaX: 12, deltaY: -30)

        XCTAssertEqual(
            MouseWheelScrollPlanner.easedFrames(target: target, frameCount: 0),
            [MouseWheelScrollFrame(deltaX: 12, deltaY: -30)]
        )
        XCTAssertEqual(
            MouseWheelScrollPlanner.easedFrames(target: target, frameCount: -3),
            [MouseWheelScrollFrame(deltaX: 12, deltaY: -30)]
        )
    }

    func testMergeAddsTargetsWithoutChangingFrameCount() {
        let merged = MouseWheelScrollPlanner.merge(
            existing: MouseWheelScrollTarget(deltaX: 0, deltaY: -12),
            incoming: MouseWheelScrollTarget(deltaX: 0, deltaY: -8)
        )

        XCTAssertEqual(merged, MouseWheelScrollTarget(deltaX: 0, deltaY: -20))
    }

    func testRemainingTargetSumsUnpostedFramesForMerge() {
        let remaining = MouseWheelScrollPlanner.remainingTarget(from: [
            MouseWheelScrollFrame(deltaX: 0, deltaY: -6),
            MouseWheelScrollFrame(deltaX: 0, deltaY: -4),
        ])

        let merged = MouseWheelScrollPlanner.merge(
            existing: remaining,
            incoming: MouseWheelScrollTarget(deltaX: 0, deltaY: -8)
        )

        XCTAssertEqual(merged, MouseWheelScrollTarget(deltaX: 0, deltaY: -18))
    }
}
