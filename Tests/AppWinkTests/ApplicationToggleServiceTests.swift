import XCTest
import AppWinkCore
@testable import AppWinkRuntime

@MainActor
final class ApplicationToggleServiceTests: XCTestCase {
    func testPrepareToggleRecordsDiagnosticsForUnavailableApplication() {
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        recorder.startSampling(round: .core)
        let service = ApplicationToggleService(performanceDiagnosticsRecorder: recorder)
        let application = ManagedApplication(
            displayName: "Missing App",
            bundleIdentifier: "com.example.missing",
            fallbackPath: "/tmp/AppWinkTests/Missing-\(UUID().uuidString).app",
            bookmarkData: Data()
        )

        let preparedToggle = service.prepareToggle(
            application: application,
            frontmostProcessIdentifier: nil,
            invocationSource: .hotKey
        )
        var capturedResult: Result<ApplicationToggleResult, ApplicationToggleError>?
        preparedToggle.execute { result in
            capturedResult = result
        }

        guard case .failure(.applicationUnavailable("Missing App")) = capturedResult else {
            XCTFail("Expected unavailable application result")
            return
        }

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.counters["hotkey.prepareToggle"], 1)
        XCTAssertEqual(snapshot.counters["hotkey.prepareToggleUnavailable"], 1)
        let metadata = snapshot.durationSamples["hotkey.prepareToggle"]?.first?.metadata ?? [:]
        XCTAssertEqual(metadata["appDisplayName"], "Missing App")
        XCTAssertEqual(metadata["bundleIdentifier"], "com.example.missing")
        XCTAssertEqual(metadata["invocationSource"], "hotKey")
    }
}
