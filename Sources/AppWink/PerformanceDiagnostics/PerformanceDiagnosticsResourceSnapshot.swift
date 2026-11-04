import Darwin
import Foundation

struct PerformanceDiagnosticsResourceSnapshot: Codable, Equatable, Sendable {
    let residentMemoryBytes: UInt64
    let cpuTimeSeconds: Double
    let threadCount: Int
    let processIdentifier: Int32
    let timestamp: Date
}

protocol PerformanceDiagnosticsResourceSampling: Sendable {
    func sample() -> PerformanceDiagnosticsResourceSnapshot
}

struct SystemPerformanceDiagnosticsResourceSampler: PerformanceDiagnosticsResourceSampling {
    private let clock: any PerformanceDiagnosticsClock

    init(clock: any PerformanceDiagnosticsClock = SystemPerformanceDiagnosticsClock()) {
        self.clock = clock
    }

    func sample() -> PerformanceDiagnosticsResourceSnapshot {
        let taskMetrics = Self.taskMetrics()
        let threadMetrics = Self.threadMetrics()

        return PerformanceDiagnosticsResourceSnapshot(
            residentMemoryBytes: taskMetrics.residentMemoryBytes,
            cpuTimeSeconds: Self.cpuTimeSeconds(
                terminatedThreadCPUTimeSeconds: taskMetrics.terminatedThreadCPUTimeSeconds,
                liveThreadCPUTimeSeconds: threadMetrics.cpuTimeSeconds
            ),
            threadCount: threadMetrics.threadCount,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            timestamp: clock.nowDate
        )
    }

    static func cpuTimeSeconds(
        terminatedThreadCPUTimeSeconds: Double,
        liveThreadCPUTimeSeconds: Double
    ) -> Double {
        terminatedThreadCPUTimeSeconds + liveThreadCPUTimeSeconds
    }

    private static func taskMetrics() -> (
        residentMemoryBytes: UInt64,
        terminatedThreadCPUTimeSeconds: Double
    ) {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0)
        }

        return (
            UInt64(info.resident_size),
            Self.seconds(from: info.user_time) + Self.seconds(from: info.system_time)
        )
    }

    private static func threadMetrics() -> (cpuTimeSeconds: Double, threadCount: Int) {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threadList else {
            return (0, 0)
        }

        defer {
            for index in 0..<Int(threadCount) {
                mach_port_deallocate(mach_task_self_, threadList[index])
            }

            let byteCount = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threadList), byteCount)
        }

        var cpuTimeSeconds: Double = 0

        for index in 0..<Int(threadCount) {
            var info = thread_basic_info_data_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
            )

            let threadResult = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                    thread_info(
                        threadList[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        reboundPointer,
                        &count
                    )
                }
            }

            guard threadResult == KERN_SUCCESS else {
                continue
            }

            if info.flags & TH_FLAGS_IDLE == 0 {
                cpuTimeSeconds += Self.seconds(from: info.user_time)
                cpuTimeSeconds += Self.seconds(from: info.system_time)
            }
        }

        return (cpuTimeSeconds, Int(threadCount))
    }

    private static func seconds(from time: time_value_t) -> Double {
        Double(time.seconds) + (Double(time.microseconds) / 1_000_000)
    }
}
