import Foundation

struct MouseWheelScrollEventFacts: Equatable {
    let isContinuous: Bool
    let scrollPhase: Int64
    let momentumPhase: Int64
    let lineDeltaX: Int
    let lineDeltaY: Int
    let pointDeltaX: Int
    let pointDeltaY: Int
}

struct MouseWheelScrollTarget: Equatable {
    let deltaX: Int
    let deltaY: Int

    var isZero: Bool {
        deltaX == 0 && deltaY == 0
    }
}

struct MouseWheelScrollFrame: Equatable {
    let deltaX: Int
    let deltaY: Int
}

enum MouseWheelScrollPlanner {
    static let defaultPixelsPerLine = 10.0
    static let defaultFrameCount = 6

    static func shouldTransform(_ facts: MouseWheelScrollEventFacts) -> Bool {
        guard !facts.isContinuous else {
            return false
        }

        guard facts.scrollPhase == 0, facts.momentumPhase == 0 else {
            return false
        }

        return facts.lineDeltaX != 0 ||
            facts.lineDeltaY != 0 ||
            facts.pointDeltaX != 0 ||
            facts.pointDeltaY != 0
    }

    static func targetPixels(
        for facts: MouseWheelScrollEventFacts,
        naturalScrollingEnabled: Bool,
        pixelsPerLine: Double = defaultPixelsPerLine
    ) -> MouseWheelScrollTarget? {
        guard shouldTransform(facts) else {
            return nil
        }

        let rawX = facts.pointDeltaX != 0
            ? facts.pointDeltaX
            : Int((Double(facts.lineDeltaX) * pixelsPerLine).rounded())
        let rawY = facts.pointDeltaY != 0
            ? facts.pointDeltaY
            : Int((Double(facts.lineDeltaY) * pixelsPerLine).rounded())
        let multiplier = naturalScrollingEnabled ? -1 : 1
        let target = MouseWheelScrollTarget(deltaX: rawX * multiplier, deltaY: rawY * multiplier)

        return target.isZero ? nil : target
    }

    static func merge(
        existing: MouseWheelScrollTarget,
        incoming: MouseWheelScrollTarget
    ) -> MouseWheelScrollTarget {
        MouseWheelScrollTarget(
            deltaX: existing.deltaX + incoming.deltaX,
            deltaY: existing.deltaY + incoming.deltaY
        )
    }

    static func remainingTarget(from frames: [MouseWheelScrollFrame]) -> MouseWheelScrollTarget {
        MouseWheelScrollTarget(
            deltaX: frames.reduce(0) { $0 + $1.deltaX },
            deltaY: frames.reduce(0) { $0 + $1.deltaY }
        )
    }

    static func easedFrames(
        target: MouseWheelScrollTarget,
        frameCount: Int = defaultFrameCount
    ) -> [MouseWheelScrollFrame] {
        let count = max(1, frameCount)

        return distribute(target: target, frameCount: count)
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        let inverted = 1 - t
        return 1 - inverted * inverted * inverted
    }

    private static func distribute(
        target: MouseWheelScrollTarget,
        frameCount: Int
    ) -> [MouseWheelScrollFrame] {
        var frames: [MouseWheelScrollFrame] = []
        var emittedX = 0
        var emittedY = 0

        for index in 0..<frameCount {
            let isLast = index == frameCount - 1
            let t = Double(index + 1) / Double(frameCount)
            let eased = easeOutCubic(t)
            let targetX = isLast
                ? target.deltaX
                : Int((Double(target.deltaX) * eased).rounded())
            let targetY = isLast
                ? target.deltaY
                : Int((Double(target.deltaY) * eased).rounded())
            let deltaX = targetX - emittedX
            let deltaY = targetY - emittedY

            emittedX = targetX
            emittedY = targetY
            frames.append(MouseWheelScrollFrame(deltaX: deltaX, deltaY: deltaY))
        }

        return frames
    }
}
