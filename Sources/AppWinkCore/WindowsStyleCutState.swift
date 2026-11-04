import Foundation

/// 抽象出 Windows 风格 Finder 剪切功能关心的命令集合，便于事件层和测试共用同一套状态机。
public enum WindowsStyleCutCommand: Sendable {
    case cut
    case copy
    case paste
    case other
}

/// 描述一次命令处理后，运行时层应该让事件继续传播还是改发 Finder 的替代快捷键。
public enum WindowsStyleCutOutcome: Equatable, Sendable {
    case passThrough
    case interceptAsCopy
    case interceptAsMovePaste
}

/// 维护 Finder `⌘X -> ⌘C`、`⌘V -> ⌥⌘V` 所需的最小状态。
public struct WindowsStyleCutState: Equatable, Sendable {
    public private(set) var hasPendingCut = false

    public init(hasPendingCut: Bool = false) {
        self.hasPendingCut = hasPendingCut
    }

    /// 在 Finder 中按下 `⌘X` 时进入待移动状态；显式复制或其它应用内的剪切会清掉该状态。
    public mutating func handle(
        command: WindowsStyleCutCommand,
        isFinderFrontmost: Bool
    ) -> WindowsStyleCutOutcome {
        switch command {
        case .cut:
            guard isFinderFrontmost else {
                hasPendingCut = false
                return .passThrough
            }

            hasPendingCut = true
            return .interceptAsCopy
        case .copy:
            hasPendingCut = false
            return .passThrough
        case .paste:
            guard isFinderFrontmost, hasPendingCut else {
                return .passThrough
            }

            hasPendingCut = false
            return .interceptAsMovePaste
        case .other:
            return .passThrough
        }
    }

    public mutating func reset() {
        hasPendingCut = false
    }
}
