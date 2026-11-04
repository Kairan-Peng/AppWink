import Carbon
import XCTest
import AppWinkCore
@testable import AppWinkRuntime

final class GlobalHotKeyManagerTests: XCTestCase {
    func testRegistrationFailureDiagnosticsOmitShortcutInputs() {
        let failureStatus = OSStatus(eventHotKeyExistsErr)
        let recorder = PerformanceDiagnosticsRecorder(clock: ManualPerformanceDiagnosticsClock())
        recorder.startSampling(round: .core)
        let manager = GlobalHotKeyManager(
            performanceDiagnosticsRecorder: recorder,
            registerHotKey: { _, _, _, _ in failureStatus },
            installsEventHandler: false
        )
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])

        let failures = manager.updateRegistrations(
            requests: [
                HotKeyRegistrationRequest(action: .activityMonitor, shortcut: shortcut),
            ],
            actionHandler: { _, _, _ in }
        )

        XCTAssertEqual(failures, [.activityMonitor])
        let event = recorder.snapshot().rawEvents.first {
            $0.category == .registration && $0.name == "carbonRegistrationFailure"
        }
        let metadata = event?.metadata ?? [:]
        XCTAssertEqual(metadata, ["statusCode": String(failureStatus)])
        XCTAssertFalse(metadata.keys.contains("keyCode"))
        XCTAssertFalse(metadata.keys.contains("modifierFlags"))
        XCTAssertFalse(metadata.keys.contains("carbonModifierFlags"))
    }
}
