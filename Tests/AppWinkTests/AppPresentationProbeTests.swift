import XCTest
@testable import AppWinkRuntime

final class AppPresentationProbeTests: XCTestCase {
    func testFrontmostFinderUsesFinderSpecificVisibleWindowClassification() {
        var nonFinderCalls = 0
        var finderCalls = 0
        let snapshot = AppPresentationProbe(
            isTargetFrontmost: { true },
            frontmostPresentation: { .normal },
            nonFinderVisibleRegularWindowOnCurrentSpace: {
                nonFinderCalls += 1
                return true
            },
            finderVisibleRegularWindowOnCurrentSpace: {
                finderCalls += 1
                return false
            }
        ).snapshot(
            isTargetRunning: true,
            isFinder: true
        )

        XCTAssertEqual(nonFinderCalls, 0)
        XCTAssertEqual(finderCalls, 1)
        XCTAssertFalse(snapshot.hasVisibleRegularWindowOnCurrentSpace)
        XCTAssertEqual(
            snapshot.applicationToggleDecisionSnapshot,
            .frontmostNormalWithoutVisibleRegularWindow
        )
    }

    func testFrontmostNonFinderUsesNonFinderVisibleWindowClassification() {
        var nonFinderCalls = 0
        var finderCalls = 0
        let snapshot = AppPresentationProbe(
            isTargetFrontmost: { true },
            frontmostPresentation: { .normal },
            nonFinderVisibleRegularWindowOnCurrentSpace: {
                nonFinderCalls += 1
                return true
            },
            finderVisibleRegularWindowOnCurrentSpace: {
                finderCalls += 1
                return false
            }
        ).snapshot(
            isTargetRunning: true,
            isFinder: false
        )

        XCTAssertEqual(nonFinderCalls, 1)
        XCTAssertEqual(finderCalls, 0)
        XCTAssertTrue(snapshot.hasVisibleRegularWindowOnCurrentSpace)
        XCTAssertEqual(
            snapshot.applicationToggleDecisionSnapshot,
            .frontmostNormalWithVisibleRegularWindow
        )
    }

    func testImmersiveFrontmostDoesNotConsultVisibleWindowClassification() {
        var nonFinderCalls = 0
        var finderCalls = 0
        let snapshot = AppPresentationProbe(
            isTargetFrontmost: { true },
            frontmostPresentation: { .immersive },
            nonFinderVisibleRegularWindowOnCurrentSpace: {
                nonFinderCalls += 1
                return true
            },
            finderVisibleRegularWindowOnCurrentSpace: {
                finderCalls += 1
                return true
            }
        ).snapshot(
            isTargetRunning: true,
            isFinder: false
        )

        XCTAssertEqual(nonFinderCalls, 0)
        XCTAssertEqual(finderCalls, 0)
        XCTAssertFalse(snapshot.hasVisibleRegularWindowOnCurrentSpace)
        XCTAssertEqual(snapshot.applicationToggleDecisionSnapshot, .frontmostImmersive)
    }
}
