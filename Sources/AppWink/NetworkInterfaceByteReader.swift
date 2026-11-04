import AppWinkCore
import Darwin
import Foundation
import SystemConfiguration

protocol NetworkInterfaceByteReading {
    func readSnapshot() throws -> NetworkInterfaceByteSnapshot?
}

enum NetworkInterfaceByteReaderError: Error, Equatable {
    case dynamicStoreUnavailable
    case interfaceIndexUnavailable(String)
    case routingTableQueryFailed(Int32)
    case malformedRoutingMessage
    case interfaceCountersMissing(String)
}

struct SystemNetworkInterfaceByteReader: NetworkInterfaceByteReading {
    typealias PrimaryInterfaceName = () throws -> String?
    typealias InterfaceIndex = (String) -> UInt32
    typealias RoutingTableData = () throws -> Data
    typealias RoutingTableQuery = (UnsafeMutableRawPointer?, inout Int) -> Int32?
    typealias Now = () -> ContinuousClock.Instant

    private let primaryInterfaceName: PrimaryInterfaceName
    private let interfaceIndex: InterfaceIndex
    private let routingTableData: RoutingTableData
    private let now: Now

    init(
        primaryInterfaceName: @escaping PrimaryInterfaceName = Self.systemPrimaryInterfaceName,
        interfaceIndex: @escaping InterfaceIndex = { if_nametoindex($0) },
        routingTableData: @escaping RoutingTableData = Self.systemRoutingTableData,
        now: @escaping Now = { ContinuousClock().now }
    ) {
        self.primaryInterfaceName = primaryInterfaceName
        self.interfaceIndex = interfaceIndex
        self.routingTableData = routingTableData
        self.now = now
    }

    func readSnapshot() throws -> NetworkInterfaceByteSnapshot? {
        guard let name = try primaryInterfaceName() else { return nil }
        let index = interfaceIndex(name)
        guard index > 0 else {
            throw NetworkInterfaceByteReaderError.interfaceIndexUnavailable(name)
        }
        guard let counters = try NetworkInterfaceCounterParser.counters(
            for: index,
            in: routingTableData()
        ) else {
            throw NetworkInterfaceByteReaderError.interfaceCountersMissing(name)
        }
        return NetworkInterfaceByteSnapshot(
            interfaceName: name,
            receivedBytes: counters.receivedBytes,
            sentBytes: counters.sentBytes,
            timestamp: now()
        )
    }

    private static func systemPrimaryInterfaceName() throws -> String? {
        guard let store = SCDynamicStoreCreate(
            nil,
            "AppWink.NetworkMonitor" as CFString,
            nil,
            nil
        ) else {
            throw NetworkInterfaceByteReaderError.dynamicStoreUnavailable
        }

        for entity in [kSCEntNetIPv4, kSCEntNetIPv6] {
            let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
                nil,
                kSCDynamicStoreDomainState,
                entity
            )
            guard let value = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                  let name = value[kSCDynamicStorePropNetPrimaryInterface as String] as? String,
                  !name.isEmpty else {
                continue
            }
            return name
        }

        return nil
    }

    private static func systemRoutingTableData() throws -> Data {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        return try routingTableData { buffer, length in
            let result = Darwin.sysctl(
                &mib,
                u_int(mib.count),
                buffer,
                &length,
                nil,
                0
            )
            guard result == 0 else { return errno }
            return nil
        }
    }

    static func routingTableData(query: RoutingTableQuery) throws -> Data {
        var length = 0
        if let error = query(nil, &length) {
            throw NetworkInterfaceByteReaderError.routingTableQueryFailed(error)
        }

        for _ in 0..<3 {
            var data = Data(count: length)
            let error = data.withUnsafeMutableBytes { bytes in
                query(bytes.baseAddress, &length)
            }
            guard let error else {
                if length < data.count {
                    data.removeSubrange(length..<data.count)
                }
                return data
            }
            guard error == ENOMEM else {
                throw NetworkInterfaceByteReaderError.routingTableQueryFailed(error)
            }
        }

        throw NetworkInterfaceByteReaderError.routingTableQueryFailed(ENOMEM)
    }
}

struct NetworkInterfaceCounters: Equatable {
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

enum NetworkInterfaceCounterParser {
    static func counters(
        for interfaceIndex: UInt32,
        in data: Data
    ) throws -> NetworkInterfaceCounters? {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard bytes.count - offset >= 4 else {
                    throw NetworkInterfaceByteReaderError.malformedRoutingMessage
                }
                let messageLength = Int(
                    bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
                )
                let messageType = bytes.loadUnaligned(
                    fromByteOffset: offset + 3,
                    as: UInt8.self
                )
                guard messageLength >= 4,
                      messageLength <= bytes.count - offset else {
                    throw NetworkInterfaceByteReaderError.malformedRoutingMessage
                }

                if messageType == UInt8(RTM_IFINFO2) {
                    let messageVersion = bytes.loadUnaligned(
                        fromByteOffset: offset + 2,
                        as: UInt8.self
                    )
                    guard messageVersion == UInt8(RTM_VERSION),
                          messageLength >= MemoryLayout<if_msghdr2>.size else {
                        throw NetworkInterfaceByteReaderError.malformedRoutingMessage
                    }
                    let message = bytes.loadUnaligned(
                        fromByteOffset: offset,
                        as: if_msghdr2.self
                    )
                    if UInt32(message.ifm_index) == interfaceIndex {
                        return NetworkInterfaceCounters(
                            receivedBytes: message.ifm_data.ifi_ibytes,
                            sentBytes: message.ifm_data.ifi_obytes
                        )
                    }
                }

                offset += messageLength
            }
            return nil
        }
    }
}
