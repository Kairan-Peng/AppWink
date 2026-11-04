import Foundation

protocol PerformanceDiagnosticsClock: Sendable {
    var nowDate: Date { get }
    var nowNanoseconds: UInt64 { get }
}

struct SystemPerformanceDiagnosticsClock: PerformanceDiagnosticsClock {
    var nowDate: Date {
        Date()
    }

    var nowNanoseconds: UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

final class ManualPerformanceDiagnosticsClock: PerformanceDiagnosticsClock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentDate: Date
    private var currentNanoseconds: UInt64

    init(nowDate: Date = Date(timeIntervalSince1970: 0), nowNanoseconds: UInt64 = 0) {
        currentDate = nowDate
        currentNanoseconds = nowNanoseconds
    }

    var nowDate: Date {
        lock.lock()
        defer { lock.unlock() }

        return currentDate
    }

    var nowNanoseconds: UInt64 {
        lock.lock()
        defer { lock.unlock() }

        return currentNanoseconds
    }

    func advance(nanoseconds: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        currentNanoseconds += nanoseconds
        currentDate = currentDate.addingTimeInterval(Double(nanoseconds) / 1_000_000_000)
    }
}
