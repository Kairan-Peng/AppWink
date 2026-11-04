import Foundation

public struct NetworkInterfaceByteSnapshot: Equatable, Sendable {
    public let interfaceName: String
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let timestamp: ContinuousClock.Instant

    public init(
        interfaceName: String,
        receivedBytes: UInt64,
        sentBytes: UInt64,
        timestamp: ContinuousClock.Instant
    ) {
        self.interfaceName = interfaceName
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.timestamp = timestamp
    }
}

public struct NetworkThroughput: Equatable, Sendable {
    public let uploadBytesPerSecond: Double
    public let downloadBytesPerSecond: Double

    public init(
        uploadBytesPerSecond: Double,
        downloadBytesPerSecond: Double
    ) {
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
    }

    public static let zero = NetworkThroughput(
        uploadBytesPerSecond: 0,
        downloadBytesPerSecond: 0
    )
}

public struct NetworkThroughputCalculator: Sendable {
    private var previousSnapshot: NetworkInterfaceByteSnapshot?
    private let maximumSampleGap: Duration

    public init(maximumSampleGap: Duration = .seconds(10)) {
        self.maximumSampleGap = maximumSampleGap
    }

    public mutating func consume(
        _ snapshot: NetworkInterfaceByteSnapshot
    ) -> NetworkThroughput {
        defer { previousSnapshot = snapshot }
        guard let previousSnapshot,
              previousSnapshot.interfaceName == snapshot.interfaceName,
              snapshot.receivedBytes >= previousSnapshot.receivedBytes,
              snapshot.sentBytes >= previousSnapshot.sentBytes else {
            return .zero
        }

        let elapsed = previousSnapshot.timestamp.duration(to: snapshot.timestamp)
        guard elapsed > .zero, elapsed <= maximumSampleGap else {
            return .zero
        }

        let seconds = elapsed / .seconds(1)
        guard seconds.isFinite, seconds > 0 else {
            return .zero
        }

        return NetworkThroughput(
            uploadBytesPerSecond: Double(snapshot.sentBytes - previousSnapshot.sentBytes) / seconds,
            downloadBytesPerSecond: Double(snapshot.receivedBytes - previousSnapshot.receivedBytes) / seconds
        )
    }

    public mutating func reset() {
        previousSnapshot = nil
    }
}

public enum NetworkSpeedFormatter {
    private static let kilo = 1_024.0
    private static let mega = kilo * kilo
    private static let oneDecimalMegabytesLimit = 100.0 * mega
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func string(bytesPerSecond rawValue: Double) -> String {
        let value = rawValue.isFinite && rawValue > 0 ? rawValue : 0
        if value < mega {
            return "\(Int((value / kilo).rounded())) KB/s"
        }
        if value < oneDecimalMegabytesLimit {
            return String(format: "%.1f MB/s", locale: posixLocale, value / mega)
        }
        return String(format: "%.0f MB/s", locale: posixLocale, value / mega)
    }
}
