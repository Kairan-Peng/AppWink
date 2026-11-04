import XCTest
@testable import AppWinkRuntime

final class AccessibilityWindowIdentityResolverTests: XCTestCase {
    func testResolvesWindowNumberFromUniqueFrameMatchWhenDirectAXNumberIsMissing() {
        let result = AccessibilityWindowIdentityResolver.resolveWindowNumber(
            directWindowNumber: nil,
            title: "Applications",
            bounds: CGRect(x: 428, y: 238, width: 913, height: 501),
            preferredWindowNumbers: [],
            candidates: [
                AccessibilityWindowIdentityCandidate(
                    windowNumber: 4948,
                    title: "Applications",
                    bounds: CGRect(x: 428, y: 238, width: 913, height: 501)),
                AccessibilityWindowIdentityCandidate(
                    windowNumber: 22,
                    title: nil,
                    bounds: CGRect(x: 0, y: 0, width: 1680, height: 30)),
            ])

        XCTAssertEqual(result, 4948)
    }

    func testPrefersPreferredWindowNumberWhenFrameMatchesAreAmbiguous() {
        let matchingBounds = CGRect(x: 428, y: 238, width: 913, height: 501)

        let result = AccessibilityWindowIdentityResolver.resolveWindowNumber(
            directWindowNumber: nil,
            title: "Applications",
            bounds: matchingBounds,
            preferredWindowNumbers: [4948],
            candidates: [
                AccessibilityWindowIdentityCandidate(
                    windowNumber: 172,
                    title: "Applications",
                    bounds: matchingBounds),
                AccessibilityWindowIdentityCandidate(
                    windowNumber: 4948,
                    title: "Applications",
                    bounds: matchingBounds),
            ])

        XCTAssertEqual(result, 4948)
    }
}
