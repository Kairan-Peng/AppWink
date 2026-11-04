import AppWinkCore
import Darwin
import Foundation
import XCTest

@testable import AppWinkRuntime

final class NetworkInterfaceByteReaderTests: XCTestCase {
    private enum TestError: Error {
        case primaryInterface
        case routingTable
    }

    func testNoPrimaryInterfaceReturnsNilWithoutReadingRoutes() throws {
        var routeReadCount = 0
        let reader = SystemNetworkInterfaceByteReader(
            primaryInterfaceName: { nil },
            interfaceIndex: { _ in
                XCTFail("Unexpected interface index lookup")
                return 0
            },
            routingTableData: {
                routeReadCount += 1
                return Data()
            },
            now: { ContinuousClock().now }
        )

        XCTAssertNil(try reader.readSnapshot())
        XCTAssertEqual(routeReadCount, 0)
    }

    func testMatchingIfInfo2ReturnsFull64BitCounters() throws {
        let timestamp = ContinuousClock().now
        let reader = makeReader(
            data: routeMessage(
                index: 7,
                received: 5_000_000_000,
                sent: 6_000_000_000
            ),
            now: timestamp
        )

        XCTAssertEqual(
            try reader.readSnapshot(),
            NetworkInterfaceByteSnapshot(
                interfaceName: "en0",
                receivedBytes: 5_000_000_000,
                sentBytes: 6_000_000_000,
                timestamp: timestamp
            )
        )
    }

    func testZeroInterfaceIndexThrows() {
        let reader = SystemNetworkInterfaceByteReader(
            primaryInterfaceName: { "en0" },
            interfaceIndex: { _ in 0 },
            routingTableData: {
                XCTFail("Unexpected route table read")
                return Data()
            },
            now: { ContinuousClock().now }
        )

        assertReaderError(.interfaceIndexUnavailable("en0"), from: reader)
    }

    func testValidNonmatchingRecordIsSkippedBeforeMatchingRecord() throws {
        var data = routeMessage(index: 8, received: 1, sent: 2)
        data.append(routeMessage(index: 7, received: 3, sent: 4))

        let snapshot = try makeReader(data: data).readSnapshot()

        XCTAssertEqual(snapshot?.receivedBytes, 3)
        XCTAssertEqual(snapshot?.sentBytes, 4)
    }

    func testOnlyNonmatchingRecordThrowsCountersMissing() {
        let reader = makeReader(
            data: routeMessage(index: 8, received: 1, sent: 2)
        )

        assertReaderError(.interfaceCountersMissing("en0"), from: reader)
    }

    func testTruncatedIfInfo2RecordThrows() {
        let length = MemoryLayout<if_msghdr2>.size - 1
        let reader = makeReader(
            data: routingMessage(length: length, type: UInt8(RTM_IFINFO2))
        )

        assertReaderError(.malformedRoutingMessage, from: reader)
    }

    func testUnknownMessageTypeWithValidLengthIsSkipped() throws {
        var data = routingMessage(length: 4, type: 0xff)
        data.append(routeMessage(index: 7, received: 11, sent: 12))

        let snapshot = try makeReader(data: data).readSnapshot()

        XCTAssertEqual(snapshot?.receivedBytes, 11)
        XCTAssertEqual(snapshot?.sentBytes, 12)
    }

    func testZeroDeclaredLengthThrows() {
        let reader = makeReader(data: routingMessage(length: 0, type: 0xff))

        assertReaderError(.malformedRoutingMessage, from: reader)
    }

    func testDeclaredLengthBelowHeaderThrowsBeforeParsingOverlappingMessages() {
        var data = Data(repeating: 0, count: 257)
        data[0] = 1
        data[1] = 0
        data[2] = 1
        data[4] = 0xff
        data.append(routeMessage(index: 7, received: 11, sent: 12))
        let reader = makeReader(data: data)

        assertReaderError(.malformedRoutingMessage, from: reader)
    }

    func testIfInfo2WithUnexpectedVersionThrows() {
        let reader = makeReader(
            data: routeMessage(
                index: 7,
                received: 11,
                sent: 12,
                version: UInt8(RTM_VERSION) &+ 1
            )
        )

        assertReaderError(.malformedRoutingMessage, from: reader)
    }

    func testDeclaredLengthBeyondRemainingBytesThrows() {
        var data = routingMessage(length: 4, type: 0xff)
        data.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: UInt16(5), toByteOffset: 0, as: UInt16.self)
        }
        let reader = makeReader(data: data)

        assertReaderError(.malformedRoutingMessage, from: reader)
    }

    func testTrailingBytesShorterThanHeaderThrow() {
        var data = routingMessage(length: 4, type: 0xff)
        data.append(contentsOf: [0x01, 0x02, 0x03])
        let reader = makeReader(data: data)

        assertReaderError(.malformedRoutingMessage, from: reader)
    }

    func testPrimaryInterfaceErrorPropagates() {
        let reader = SystemNetworkInterfaceByteReader(
            primaryInterfaceName: { throw TestError.primaryInterface },
            interfaceIndex: { _ in
                XCTFail("Unexpected interface index lookup")
                return 0
            },
            routingTableData: {
                XCTFail("Unexpected route table read")
                return Data()
            },
            now: { ContinuousClock().now }
        )

        XCTAssertThrowsError(try reader.readSnapshot()) { error in
            XCTAssertEqual(error as? TestError, .primaryInterface)
        }
    }

    func testRoutingTableErrorPropagates() {
        let reader = SystemNetworkInterfaceByteReader(
            primaryInterfaceName: { "en0" },
            interfaceIndex: { _ in 7 },
            routingTableData: { throw TestError.routingTable },
            now: { ContinuousClock().now }
        )

        XCTAssertThrowsError(try reader.readSnapshot()) { error in
            XCTAssertEqual(error as? TestError, .routingTable)
        }
    }

    func testRoutingTableLoaderRetriesAfterSizeRace() throws {
        let expected = routeMessage(index: 7, received: 11, sent: 12)
        var queryCount = 0

        let data = try SystemNetworkInterfaceByteReader.routingTableData(
            query: { (buffer: UnsafeMutableRawPointer?, length: inout Int) -> Int32? in
                defer { queryCount += 1 }
                switch queryCount {
                case 0:
                    XCTAssertNil(buffer)
                    length = 4
                    return nil
                case 1:
                    XCTAssertNotNil(buffer)
                    XCTAssertEqual(length, 4)
                    length = expected.count
                    return ENOMEM
                case 2:
                    XCTAssertNotNil(buffer)
                    XCTAssertEqual(length, expected.count)
                    expected.withUnsafeBytes { source in
                        buffer?.copyMemory(
                            from: source.baseAddress!,
                            byteCount: expected.count
                        )
                    }
                    length = expected.count
                    return nil
                default:
                    XCTFail("Unexpected extra routing table query")
                    return EINVAL
                }
            }
        )

        XCTAssertEqual(data, expected)
        XCTAssertEqual(queryCount, 3)
    }

    func testRoutingTableLoaderPropagatesNonMemoryErrorWithoutRetrying() {
        var queryCount = 0

        XCTAssertThrowsError(
            try SystemNetworkInterfaceByteReader.routingTableData(
                query: { (buffer: UnsafeMutableRawPointer?, length: inout Int) -> Int32? in
                    defer { queryCount += 1 }
                    if buffer == nil {
                        length = 4
                        return nil
                    }
                    return EACCES
                }
            )
        ) { error in
            XCTAssertEqual(
                error as? NetworkInterfaceByteReaderError,
                .routingTableQueryFailed(EACCES)
            )
        }
        XCTAssertEqual(queryCount, 2)
    }

    private func makeReader(
        data: Data,
        now: ContinuousClock.Instant = ContinuousClock().now
    ) -> SystemNetworkInterfaceByteReader {
        SystemNetworkInterfaceByteReader(
            primaryInterfaceName: { "en0" },
            interfaceIndex: { $0 == "en0" ? 7 : 0 },
            routingTableData: { data },
            now: { now }
        )
    }

    private func assertReaderError(
        _ expected: NetworkInterfaceByteReaderError,
        from reader: SystemNetworkInterfaceByteReader,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try reader.readSnapshot(), file: file, line: line) { error in
            XCTAssertEqual(error as? NetworkInterfaceByteReaderError, expected, file: file, line: line)
        }
    }

    private func routeMessage(
        index: UInt16,
        received: UInt64,
        sent: UInt64,
        version: UInt8 = UInt8(RTM_VERSION)
    ) -> Data {
        var message = if_msghdr2()
        message.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        message.ifm_version = version
        message.ifm_type = UInt8(RTM_IFINFO2)
        message.ifm_index = index
        message.ifm_data.ifi_ibytes = received
        message.ifm_data.ifi_obytes = sent
        return withUnsafeBytes(of: &message) { Data($0) }
    }

    private func routingMessage(length: Int, type: UInt8) -> Data {
        var data = Data(repeating: 0, count: max(length, 4))
        data.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: UInt16(length), toByteOffset: 0, as: UInt16.self)
            bytes.storeBytes(of: type, toByteOffset: 3, as: UInt8.self)
        }
        return data
    }
}
