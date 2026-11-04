import XCTest

import AppWinkCore

final class NetworkThroughputTests: XCTestCase {
    private let clock = ContinuousClock()

    func testFirstSnapshotEstablishesBaselineAndReturnsZero() {
        var calculator = NetworkThroughputCalculator()

        let result = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: clock.now)
        )

        XCTAssertEqual(result, .zero)
    }

    func testComparableSnapshotUsesActualElapsedTimeAndDirectionMapping() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        let result = calculator.consume(
            snapshot(
                name: "en0",
                received: 16_000,
                sent: 22_000,
                at: start.advanced(by: .seconds(2))
            )
        )

        XCTAssertEqual(result.uploadBytesPerSecond, 1_000, accuracy: 0.001)
        XCTAssertEqual(result.downloadBytesPerSecond, 3_000, accuracy: 0.001)
    }

    func testFractionalElapsedTimeIncludesAttoseconds() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        let result = calculator.consume(
            snapshot(
                name: "en0",
                received: 15_000,
                sent: 22_500,
                at: start.advanced(by: .milliseconds(2_500))
            )
        )

        XCTAssertEqual(result.uploadBytesPerSecond, 1_000, accuracy: 0.001)
        XCTAssertEqual(result.downloadBytesPerSecond, 2_000, accuracy: 0.001)
    }

    func testInterfaceChangeReturnsZeroAndRebuildsBaseline() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en1",
                    received: 1_000_000,
                    sent: 2_000_000,
                    at: start.advanced(by: .seconds(2))
                )
            ),
            .zero
        )

        let result = calculator.consume(
            snapshot(
                name: "en1",
                received: 1_003_000,
                sent: 2_001_000,
                at: start.advanced(by: .seconds(3))
            )
        )
        XCTAssertEqual(
            result,
            NetworkThroughput(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 3_000)
        )
    }

    func testReceivedCounterRegressionReturnsZeroAndRebuildsBaseline() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 9_000,
                    sent: 21_000,
                    at: start.advanced(by: .seconds(2))
                )
            ),
            .zero
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 10_000,
                    sent: 22_000,
                    at: start.advanced(by: .seconds(3))
                )
            ),
            NetworkThroughput(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 1_000)
        )
    }

    func testSentCounterRegressionReturnsZeroAndRebuildsBaseline() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 11_000,
                    sent: 19_000,
                    at: start.advanced(by: .seconds(2))
                )
            ),
            .zero
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 12_000,
                    sent: 20_000,
                    at: start.advanced(by: .seconds(3))
                )
            ),
            NetworkThroughput(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 1_000)
        )
    }

    func testNonPositiveElapsedTimeReturnsZeroAndRebuildsBaseline() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(name: "en0", received: 11_000, sent: 21_000, at: start)
            ),
            .zero
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 12_000,
                    sent: 22_000,
                    at: start.advanced(by: .seconds(1))
                )
            ),
            NetworkThroughput(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 1_000)
        )
    }

    func testNegativeElapsedTimeReturnsZeroAndRebuildsBaseline() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 11_000,
                    sent: 21_000,
                    at: start.advanced(by: .seconds(-1))
                )
            ),
            .zero
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(name: "en0", received: 12_000, sent: 22_000, at: start)
            ),
            NetworkThroughput(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 1_000)
        )
    }

    func testIntervalEqualToMaximumSampleGapRemainsValid() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        let result = calculator.consume(
            snapshot(
                name: "en0",
                received: 40_000,
                sent: 30_000,
                at: start.advanced(by: .seconds(10))
            )
        )

        XCTAssertEqual(
            result,
            NetworkThroughput(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 3_000)
        )
    }

    func testIntervalAboveMaximumSampleGapReturnsZeroAndRebuildsBaseline() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 110_000,
                    sent: 120_000,
                    at: start.advanced(by: .seconds(11))
                )
            ),
            .zero
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 113_000,
                    sent: 121_000,
                    at: start.advanced(by: .seconds(12))
                )
            ),
            NetworkThroughput(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 3_000)
        )
    }

    func testResetClearsBaseline() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )
        calculator.reset()

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 50_000,
                    sent: 80_000,
                    at: start.advanced(by: .seconds(2))
                )
            ),
            .zero
        )
    }

    func testZeroCounterDeltasReturnZero() {
        var calculator = NetworkThroughputCalculator()
        let start = clock.now
        _ = calculator.consume(
            snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)
        )

        XCTAssertEqual(
            calculator.consume(
                snapshot(
                    name: "en0",
                    received: 10_000,
                    sent: 20_000,
                    at: start.advanced(by: .seconds(2))
                )
            ),
            .zero
        )
    }

    func testFormatterUsesApprovedUnitsAndRounding() {
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 0), "0 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 511), "0 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 512), "1 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 860), "1 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 21_200), "21 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 1_572_864), "1.5 MB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 134_217_728), "128 MB/s")
    }

    func testFormatterUsesBinaryUnitBoundaries() {
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 1_024), "1 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 1_048_576), "1.0 MB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 104_857_599), "100.0 MB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: 104_857_600), "100 MB/s")
    }

    func testFormatterNormalizesInvalidValuesToZero() {
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: -1), "0 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: .nan), "0 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.string(bytesPerSecond: .infinity), "0 KB/s")
    }

    func testFormatterHandlesGreatestFiniteMagnitudeAsMegabytes() {
        XCTAssertTrue(
            NetworkSpeedFormatter.string(bytesPerSecond: .greatestFiniteMagnitude)
                .hasSuffix(" MB/s")
        )
    }

    private func snapshot(
        name: String,
        received: UInt64,
        sent: UInt64,
        at timestamp: ContinuousClock.Instant
    ) -> NetworkInterfaceByteSnapshot {
        NetworkInterfaceByteSnapshot(
            interfaceName: name,
            receivedBytes: received,
            sentBytes: sent,
            timestamp: timestamp
        )
    }
}
