import AppKit
import AppWinkCore
import XCTest

@testable import AppWinkRuntime

@MainActor
final class NetworkStatusItemControllerTests: XCTestCase {
    func testMetricsUseApprovedFixedValues() {
        XCTAssertEqual(NetworkStatusItemMetrics.width, 56)
        XCTAssertEqual(NetworkStatusItemMetrics.fontSize, 9)
        XCTAssertEqual(NetworkStatusItemMetrics.columnGap, 2)
        XCTAssertEqual(NetworkStatusItemMetrics.refreshInterval, 2)
        XCTAssertEqual(
            NetworkStatusItemMetrics.autosaveName,
            "com.kairanpeng.appwink.network-monitor"
        )
    }

    func testCompactWidthFitsDecimalMegabyteBoundaryValue() {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NetworkStatusItemMetrics.fontSize,
            weight: .semibold
        )
        let textWidth = ceil(
            ("100.0 MB/s" as NSString).size(withAttributes: [.font: font]).width
        )

        XCTAssertLessThanOrEqual(textWidth, NetworkStatusItemMetrics.width)
    }

    func testDecimalMegabyteBoundaryComponentsFitSharedColumns() throws {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NetworkStatusItemMetrics.fontSize,
            weight: .semibold
        )
        let layout = NetworkStatusItemLineLayout.make(
            text: "100.0 MB/s",
            in: NSRect(x: 0, y: 0, width: 56, height: 10)
        )
        let valueWidth = ceil(
            ("100.0" as NSString).size(withAttributes: [.font: font]).width
        )
        let unitWidth = ceil(
            ("MB/s" as NSString).size(withAttributes: [.font: font]).width
        )
        let unitRect = try XCTUnwrap(layout.unitRect)

        XCTAssertLessThanOrEqual(valueWidth, layout.valueRect.width)
        XCTAssertLessThanOrEqual(unitWidth, unitRect.width)
        XCTAssertEqual(layout.valueRect.maxX, 28)
        XCTAssertEqual(unitRect.minX, 30)
    }

    func testFormattedSpeedUsesSharedRightAndLeftAlignedColumns() {
        let lineRect = NSRect(x: 0, y: 3, width: 56, height: 10)
        let singleDigit = NetworkStatusItemLineLayout.make(
            text: "5 KB/s",
            in: lineRect
        )
        let doubleDigit = NetworkStatusItemLineLayout.make(
            text: "24 KB/s",
            in: lineRect
        )

        XCTAssertEqual(singleDigit.valueText, "5")
        XCTAssertEqual(doubleDigit.valueText, "24")
        XCTAssertEqual(singleDigit.unitText, "KB/s")
        XCTAssertEqual(doubleDigit.unitText, "KB/s")
        XCTAssertEqual(singleDigit.valueRect.maxX, 28)
        XCTAssertEqual(doubleDigit.valueRect.maxX, 28)
        XCTAssertEqual(singleDigit.unitRect?.minX, 30)
        XCTAssertEqual(doubleDigit.unitRect?.minX, 30)
        XCTAssertEqual(singleDigit.valueAlignment, NSTextAlignment.right)
        XCTAssertEqual(doubleDigit.valueAlignment, NSTextAlignment.right)
        XCTAssertEqual(singleDigit.unitAlignment, NSTextAlignment.left)
        XCTAssertEqual(doubleDigit.unitAlignment, NSTextAlignment.left)
    }

    func testUnitlessStatusUsesFullWidthCenteredLayout() {
        let lineRect = NSRect(x: 0, y: 3, width: 56, height: 10)
        let layout = NetworkStatusItemLineLayout.make(text: "--", in: lineRect)

        XCTAssertEqual(layout.valueText, "--")
        XCTAssertNil(layout.unitText)
        XCTAssertEqual(layout.valueRect, lineRect)
        XCTAssertNil(layout.unitRect)
        XCTAssertEqual(layout.valueAlignment, NSTextAlignment.center)
        XCTAssertNil(layout.unitAlignment)
    }

    func testPresentationPlacesFormattedUploadAboveFormattedDownload() {
        var accessibilityValues: [(String, String)] = []

        let presentation = NetworkStatusItemPresentation.make(
            throughput: NetworkThroughput(
                uploadBytesPerSecond: 21_200,
                downloadBytesPerSecond: 134_000
            ),
            accessibilityText: {
                accessibilityValues.append(($0, $1))
                return "Upload \($0), Download \($1)"
            }
        )

        XCTAssertEqual(presentation.topText, "21 KB/s")
        XCTAssertEqual(presentation.bottomText, "131 KB/s")
        XCTAssertEqual(presentation.accessibilityText, "Upload 21 KB/s, Download 131 KB/s")
        XCTAssertEqual(accessibilityValues.first?.0, presentation.topText)
        XCTAssertEqual(accessibilityValues.first?.1, presentation.bottomText)
    }

    func testZeroAndUnavailableAccessibilityUseTheirVisibleValues() {
        var accessibilityValues: [(String, String)] = []
        let makeAccessibilityText: (String, String) -> String = {
            accessibilityValues.append(($0, $1))
            return "Upload \($0), Download \($1)"
        }

        let zero = NetworkStatusItemPresentation.zero(
            accessibilityText: makeAccessibilityText
        )
        let unavailable = NetworkStatusItemPresentation.unavailable(
            accessibilityText: makeAccessibilityText
        )

        XCTAssertEqual(zero.topText, "0 KB/s")
        XCTAssertEqual(zero.bottomText, "0 KB/s")
        XCTAssertEqual(zero.accessibilityText, "Upload 0 KB/s, Download 0 KB/s")
        XCTAssertEqual(unavailable.topText, "--")
        XCTAssertEqual(unavailable.bottomText, "--")
        XCTAssertEqual(unavailable.accessibilityText, "Upload --, Download --")
        XCTAssertEqual(accessibilityValues.map(\.0), [zero.topText, unavailable.topText])
        XCTAssertEqual(accessibilityValues.map(\.1), [zero.bottomText, unavailable.bottomText])
        XCTAssertNotEqual(zero, unavailable)
    }

    func testRendererUsesSharedColumnLayoutsForFormattedPresentation() {
        let presentation = NetworkStatusItemPresentation.make(
            throughput: NetworkThroughput(
                uploadBytesPerSecond: 5 * 1024,
                downloadBytesPerSecond: 24 * 1024
            ),
            accessibilityText: accessibilityText
        )
        let layouts = NetworkStatusItemRenderer.lineLayouts(
            for: presentation,
            height: 22
        )

        XCTAssertEqual(layouts.top.valueText, "5")
        XCTAssertEqual(layouts.top.unitText, "KB/s")
        XCTAssertEqual(layouts.top.valueRect.maxX, 28)
        XCTAssertEqual(layouts.top.unitRect?.minX, 30)
        XCTAssertEqual(layouts.top.valueAlignment, NSTextAlignment.right)
        XCTAssertEqual(layouts.top.unitAlignment, NSTextAlignment.left)
        XCTAssertEqual(layouts.bottom.valueText, "24")
        XCTAssertEqual(layouts.bottom.unitText, "KB/s")
        XCTAssertEqual(layouts.bottom.valueRect.maxX, 28)
        XCTAssertEqual(layouts.bottom.unitRect?.minX, 30)
        XCTAssertEqual(layouts.bottom.valueAlignment, NSTextAlignment.right)
        XCTAssertEqual(layouts.bottom.unitAlignment, NSTextAlignment.left)
    }

    func testRendererImageDrawsFormattedValuesAndUnitsInSharedColumns() throws {
        let presentation = NetworkStatusItemPresentation.make(
            throughput: NetworkThroughput(
                uploadBytesPerSecond: 5 * 1024,
                downloadBytesPerSecond: 24 * 1024
            ),
            accessibilityText: accessibilityText
        )
        var operations: [(
            text: String,
            rect: NSRect,
            alignment: NSTextAlignment
        )] = []
        let image = NetworkStatusItemRenderer.image(
            for: presentation,
            height: 22,
            drawText: { (text: String, rect: NSRect, alignment: NSTextAlignment) in
                operations.append((text, rect, alignment))
            }
        )
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 56,
            pixelsHigh: 22,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

        XCTAssertTrue(operations.isEmpty)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 56, height: 22))
        NSGraphicsContext.restoreGraphicsState()

        XCTAssertEqual(operations.count, 4)
        guard operations.count == 4 else { return }

        XCTAssertEqual(operations[0].text, "5")
        XCTAssertEqual(operations[0].rect.maxX, 28)
        XCTAssertEqual(operations[0].alignment, NSTextAlignment.right)
        XCTAssertEqual(operations[1].text, "KB/s")
        XCTAssertEqual(operations[1].rect.minX, 30)
        XCTAssertEqual(operations[1].alignment, NSTextAlignment.left)
        XCTAssertEqual(operations[2].text, "24")
        XCTAssertEqual(operations[2].rect.maxX, 28)
        XCTAssertEqual(operations[2].alignment, NSTextAlignment.right)
        XCTAssertEqual(operations[3].text, "KB/s")
        XCTAssertEqual(operations[3].rect.minX, 30)
        XCTAssertEqual(operations[3].alignment, NSTextAlignment.left)
        XCTAssertGreaterThan(operations[0].rect.minY, operations[2].rect.minY)
    }

    func testRendererUsesFixedWidthRequestedSystemHeightAndUpperTextRect() {
        for systemProvidedHeight: CGFloat in [22, 26, 31] {
            let image = NetworkStatusItemRenderer.image(
                for: .zero(accessibilityText: { "Upload \($0), Download \($1)" }),
                height: systemProvidedHeight
            )
            let rects = NetworkStatusItemRenderer.textRects(
                height: systemProvidedHeight
            )

            XCTAssertEqual(image.size.width, NetworkStatusItemMetrics.width)
            XCTAssertEqual(image.size.height, systemProvidedHeight)
            XCTAssertTrue(image.isTemplate)
            XCTAssertGreaterThan(rects.top.minY, rects.bottom.minY)
            XCTAssertGreaterThanOrEqual(rects.bottom.minY, 0)
            XCTAssertLessThanOrEqual(rects.top.maxY, systemProvidedHeight)
        }
    }

    func testEnableTwiceInstallsSamplesAndSchedulesOnlyOnce() {
        let fixture = makeFixture(results: [.success(nil)])

        fixture.controller.setEnabled(true)
        fixture.controller.setEnabled(true)

        XCTAssertEqual(fixture.display.installCount, 1)
        XCTAssertEqual(fixture.reader.readCount, 1)
        XCTAssertEqual(fixture.timers.intervals, [2])
        XCTAssertEqual(fixture.timers.tokens.count, 1)
        XCTAssertEqual(
            fixture.display.presentations,
            [.zero(accessibilityText: accessibilityText)]
        )
    }

    func testAccessibilityTextUsesCurrentLanguageForEachPresentation() {
        var languageMarker = "en"
        let reader = ReaderStub(results: [.success(nil), .success(nil)])
        let display = DisplaySpy()
        let timers = TimerSchedulerSpy()
        let controller = NetworkStatusItemController(
            reader: reader,
            display: display,
            timerScheduler: timers
        ) { upload, download in
            "\(languageMarker): \(upload), \(download)"
        }

        controller.setEnabled(true)
        XCTAssertEqual(
            display.presentations.last?.accessibilityText,
            "en: 0 KB/s, 0 KB/s"
        )

        languageMarker = "zh"
        timers.fire()

        XCTAssertEqual(
            display.presentations.last?.accessibilityText,
            "zh: 0 KB/s, 0 KB/s"
        )
    }

    func testComparableSnapshotsUseActualElapsedTimeAndDirectionMapping() {
        let start = ContinuousClock().now
        let fixture = makeFixture(results: [
            .success(snapshot(name: "en0", received: 10_000, sent: 20_000, at: start)),
            .success(snapshot(
                name: "en0",
                received: 16_000,
                sent: 22_000,
                at: start.advanced(by: .seconds(2))
            )),
        ])

        fixture.controller.setEnabled(true)
        fixture.timers.fire()

        XCTAssertEqual(fixture.display.presentations.last?.topText, "1 KB/s")
        XCTAssertEqual(fixture.display.presentations.last?.bottomText, "3 KB/s")
        XCTAssertEqual(
            fixture.display.presentations.last?.accessibilityText,
            "Upload 1 KB/s, Download 3 KB/s"
        )
    }

    func testDisableInvalidatesRemovesAndClearsBaselineBeforeReenable() {
        let start = ContinuousClock().now
        let fixture = makeFixture(results: [
            .success(snapshot(name: "en0", received: 1_000, sent: 2_000, at: start)),
            .success(snapshot(
                name: "en0",
                received: 5_096,
                sent: 4_048,
                at: start.advanced(by: .seconds(2))
            )),
            .success(snapshot(
                name: "en0",
                received: 50_000,
                sent: 60_000,
                at: start.advanced(by: .seconds(4))
            )),
        ])
        fixture.controller.setEnabled(true)
        fixture.timers.fire()

        fixture.controller.setEnabled(false)
        fixture.controller.setEnabled(false)
        fixture.controller.setEnabled(true)

        XCTAssertEqual(fixture.timers.tokens.first?.invalidateCount, 1)
        XCTAssertEqual(fixture.display.removeCount, 1)
        XCTAssertEqual(fixture.display.installCount, 2)
        XCTAssertEqual(fixture.display.presentations.last?.topText, "0 KB/s")
        XCTAssertEqual(fixture.display.presentations.last?.bottomText, "0 KB/s")
    }

    func testQueuedTickFromPreviousEnableCycleCannotSampleAfterReenable() {
        let start = ContinuousClock().now
        let fixture = makeFixture(results: [
            .success(snapshot(name: "en0", received: 1_000, sent: 2_000, at: start)),
            .success(snapshot(
                name: "en0",
                received: 10_000,
                sent: 20_000,
                at: start.advanced(by: .seconds(4))
            )),
            .success(snapshot(
                name: "en0",
                received: 14_096,
                sent: 22_048,
                at: start.advanced(by: .seconds(6))
            )),
        ])
        fixture.controller.setEnabled(true)
        fixture.controller.setEnabled(false)
        fixture.controller.setEnabled(true)
        let readCount = fixture.reader.readCount
        let updateCount = fixture.display.presentations.count

        fixture.timers.fire(at: 0)

        XCTAssertEqual(fixture.reader.readCount, readCount)
        XCTAssertEqual(fixture.display.presentations.count, updateCount)
        guard fixture.reader.readCount == readCount else { return }

        fixture.timers.fire(at: 1)

        XCTAssertEqual(fixture.reader.readCount, readCount + 1)
        XCTAssertEqual(fixture.display.presentations.last?.topText, "1 KB/s")
        XCTAssertEqual(fixture.display.presentations.last?.bottomText, "2 KB/s")
    }

    func testReadFailureShowsUnavailableAndNextSuccessRebaselinesAtZero() {
        let start = ContinuousClock().now
        let fixture = makeFixture(results: [
            .success(snapshot(name: "en0", received: 1_000, sent: 2_000, at: start)),
            .failure(.failed),
            .success(snapshot(
                name: "en0",
                received: 20_000,
                sent: 30_000,
                at: start.advanced(by: .seconds(4))
            )),
        ])

        fixture.controller.setEnabled(true)
        fixture.timers.fire()
        fixture.timers.fire()

        XCTAssertEqual(
            fixture.display.presentations.map(\.topText),
            ["0 KB/s", "--", "0 KB/s"]
        )
        XCTAssertEqual(
            fixture.display.presentations.map(\.bottomText),
            ["0 KB/s", "--", "0 KB/s"]
        )
    }

    func testNilPrimaryInterfaceShowsZeroAndResetsExistingBaseline() {
        let start = ContinuousClock().now
        let fixture = makeFixture(results: [
            .success(snapshot(name: "en0", received: 1_000, sent: 2_000, at: start)),
            .success(snapshot(
                name: "en0",
                received: 5_096,
                sent: 4_048,
                at: start.advanced(by: .seconds(2))
            )),
            .success(nil),
            .success(snapshot(
                name: "en0",
                received: 50_000,
                sent: 60_000,
                at: start.advanced(by: .seconds(6))
            )),
        ])

        fixture.controller.setEnabled(true)
        fixture.timers.fire()
        fixture.timers.fire()
        fixture.timers.fire()

        XCTAssertEqual(
            fixture.display.presentations.map(\.topText),
            ["0 KB/s", "1 KB/s", "0 KB/s", "0 KB/s"]
        )
        XCTAssertEqual(
            fixture.display.presentations.map(\.bottomText),
            ["0 KB/s", "2 KB/s", "0 KB/s", "0 KB/s"]
        )
    }

    func testTeardownTwiceIsIdempotent() {
        let fixture = makeFixture(results: [.success(nil)])
        fixture.controller.setEnabled(true)

        fixture.controller.teardown()
        fixture.controller.teardown()

        XCTAssertEqual(fixture.timers.tokens.first?.invalidateCount, 1)
        XCTAssertEqual(fixture.display.removeCount, 1)
    }

    func testTeardownWhileDisabledHasNoSideEffects() {
        let fixture = makeFixture()

        fixture.controller.teardown()
        fixture.controller.teardown()

        XCTAssertEqual(fixture.reader.readCount, 0)
        XCTAssertEqual(fixture.display.installCount, 0)
        XCTAssertEqual(fixture.display.removeCount, 0)
        XCTAssertTrue(fixture.timers.tokens.isEmpty)
    }

    func testReleaseWhileEnabledInvalidatesTimerAndRemovesDisplay() {
        let reader = ReaderStub(results: [.success(nil)])
        let display = DisplaySpy()
        let timers = TimerSchedulerSpy()
        var controller: NetworkStatusItemController? = NetworkStatusItemController(
            reader: reader,
            display: display,
            timerScheduler: timers,
            accessibilityText: accessibilityText
        )
        controller?.setEnabled(true)

        controller = nil

        XCTAssertEqual(timers.tokens.first?.invalidateCount, 1)
        XCTAssertEqual(display.removeCount, 1)
    }

    func testReleaseAfterDisableDoesNotCleanUpTwice() {
        let reader = ReaderStub(results: [.success(nil)])
        let display = DisplaySpy()
        let timers = TimerSchedulerSpy()
        var controller: NetworkStatusItemController? = NetworkStatusItemController(
            reader: reader,
            display: display,
            timerScheduler: timers,
            accessibilityText: accessibilityText
        )
        controller?.setEnabled(true)
        controller?.setEnabled(false)

        controller = nil

        XCTAssertEqual(timers.tokens.first?.invalidateCount, 1)
        XCTAssertEqual(display.removeCount, 1)
    }

    func testQueuedTimerTickAfterDisableDoesNotReadOrUpdateRemovedDisplay() {
        let fixture = makeFixture(results: [
            .success(nil),
            .failure(.failed),
        ])
        fixture.controller.setEnabled(true)
        fixture.controller.setEnabled(false)
        let updateCount = fixture.display.presentations.count

        fixture.timers.fire()

        XCTAssertEqual(fixture.reader.readCount, 1)
        XCTAssertEqual(fixture.display.presentations.count, updateCount)
        XCTAssertEqual(fixture.display.removeCount, 1)
    }

    func testAppKitDisplayInstallsUpdatesAndRemovesDedicatedStatusItem() {
        let display = AppKitNetworkStatusItemDisplay()
        display.install()
        defer { display.remove() }

        guard let item = display.statusItem, let button = item.button else {
            XCTFail("Expected a status item button")
            return
        }
        let installedItem = item
        let expectedHeight = button.bounds.height > 0
            ? button.bounds.height
            : NSStatusBar.system.thickness
        let presentation = NetworkStatusItemPresentation.zero(
            accessibilityText: accessibilityText
        )

        display.install()
        display.update(presentation)

        XCTAssertTrue(display.statusItem === installedItem)
        XCTAssertEqual(item.length, 56)
        XCTAssertEqual(
            item.autosaveName,
            NSStatusItem.AutosaveName(NetworkStatusItemMetrics.autosaveName)
        )
        XCTAssertNil(button.target)
        XCTAssertNil(button.action)
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.imageScaling, .scaleNone)
        XCTAssertEqual(button.image?.size.height, expectedHeight)
        XCTAssertEqual(button.toolTip, presentation.accessibilityText)
        XCTAssertEqual(button.accessibilityLabel(), presentation.accessibilityText)

        display.remove()
        display.remove()
        XCTAssertNil(display.statusItem)
    }

    func testFoundationSchedulerCreatesRequestedIntervalTimerInCommonMode() {
        var installedTimer: Timer?
        var installedMode: RunLoop.Mode?
        let scheduler = FoundationNetworkStatusTimerScheduler { timer, mode in
            installedTimer = timer
            installedMode = mode
        }

        let token = scheduler.schedule(every: 0.125) {}
        defer { token.invalidate() }

        XCTAssertEqual(installedTimer?.timeInterval, 0.125)
        XCTAssertEqual(installedMode, .common)
        XCTAssertTrue(installedTimer?.isValid == true)
    }

    private func makeFixture(
        results: [Result<NetworkInterfaceByteSnapshot?, TestError>] = []
    ) -> ControllerFixture {
        let reader = ReaderStub(results: results)
        let display = DisplaySpy()
        let timers = TimerSchedulerSpy()
        let controller = NetworkStatusItemController(
            reader: reader,
            display: display,
            timerScheduler: timers,
            accessibilityText: accessibilityText
        )
        return ControllerFixture(
            controller: controller,
            reader: reader,
            display: display,
            timers: timers
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

    private func accessibilityText(_ upload: String, _ download: String) -> String {
        "Upload \(upload), Download \(download)"
    }
}

private extension NetworkStatusItemControllerTests {
    enum TestError: Error {
        case failed
    }

    final class ReaderStub: NetworkInterfaceByteReading {
        private var results: [Result<NetworkInterfaceByteSnapshot?, TestError>]
        private(set) var readCount = 0

        init(results: [Result<NetworkInterfaceByteSnapshot?, TestError>]) {
            self.results = results
        }

        func readSnapshot() throws -> NetworkInterfaceByteSnapshot? {
            readCount += 1
            return try results.removeFirst().get()
        }
    }

    @MainActor
    final class DisplaySpy: NetworkStatusItemDisplaying {
        private(set) var installCount = 0
        private(set) var presentations: [NetworkStatusItemPresentation] = []
        private(set) var removeCount = 0

        func install() {
            installCount += 1
        }

        func update(_ presentation: NetworkStatusItemPresentation) {
            presentations.append(presentation)
        }

        func remove() {
            removeCount += 1
        }
    }

    @MainActor
    final class TimerTokenSpy: NetworkStatusTimerToken {
        private(set) var invalidateCount = 0

        func invalidate() {
            invalidateCount += 1
        }
    }

    @MainActor
    final class TimerSchedulerSpy: NetworkStatusTimerScheduling {
        typealias Action = @MainActor () -> Void

        private(set) var intervals: [TimeInterval] = []
        private(set) var tokens: [TimerTokenSpy] = []
        private var actions: [Action] = []

        func schedule(
            every interval: TimeInterval,
            action: @escaping Action
        ) -> any NetworkStatusTimerToken {
            let token = TimerTokenSpy()
            intervals.append(interval)
            tokens.append(token)
            actions.append(action)
            return token
        }

        func fire() {
            actions.last?()
        }

        func fire(at index: Int) {
            actions[index]()
        }
    }

    struct ControllerFixture {
        let controller: NetworkStatusItemController
        let reader: ReaderStub
        let display: DisplaySpy
        let timers: TimerSchedulerSpy
    }
}
