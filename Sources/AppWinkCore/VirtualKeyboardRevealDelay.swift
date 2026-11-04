import Foundation

public enum VirtualKeyboardRevealDelay: Sendable {
    public static let allowedValues: [TimeInterval] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.75, 1, 1.5, 2]
    public static let defaultValue: TimeInterval = 0.5

    public static func normalized(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else {
            return defaultValue
        }

        return allowedValues.min { lhs, rhs in
            abs(lhs - value) < abs(rhs - value)
        } ?? defaultValue
    }

    public static func index(for value: TimeInterval) -> Int {
        guard let index = allowedValues.firstIndex(of: normalized(value)) else {
            return allowedValues.firstIndex(of: defaultValue) ?? 0
        }

        return index
    }

    public static func value(at index: Int) -> TimeInterval {
        let clampedIndex = min(max(index, 0), allowedValues.count - 1)
        return allowedValues[clampedIndex]
    }

    public static func displayString(for value: TimeInterval) -> String {
        let normalizedValue = normalized(value)
        if normalizedValue.rounded() == normalizedValue {
            return String(Int(normalizedValue))
        }

        return String(format: "%g", normalizedValue)
    }
}
