import CoreGraphics
import Foundation

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int) -> Unmanaged<CFArray>

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ connection: Int, _ selector: Int, _ windows: CFArray) -> Unmanaged<CFArray>

struct WindowSpaceBridge {
    static let live = WindowSpaceBridge()

    func currentPresentation(containing windowNumber: Int) -> FrontmostWindowPresentation {
        let intervalToken = PerformanceDiagnosticsRecorder.shared.beginInterval(
            category: .systemQuery,
            name: "currentPresentation"
        )
        let result = currentPresentationResult(containing: windowNumber)

        if intervalToken != nil {
            let resultMetadata = ["result": diagnosticsResult(for: result)]
            PerformanceDiagnosticsRecorder.shared.recordEvent(
                category: .systemQuery,
                name: "currentPresentation",
                metadata: resultMetadata
            )
            PerformanceDiagnosticsRecorder.shared.endInterval(
                intervalToken,
                metadata: resultMetadata
            )
        }

        return result
    }

    private func currentPresentationResult(containing windowNumber: Int) -> FrontmostWindowPresentation {
        guard let currentSpace = currentSpaceDictionary(),
              let currentSpaceID = currentSpaceID(from: currentSpace),
              spaceIDs(containing: windowNumber).contains(currentSpaceID) else {
            return .normal
        }

        return presentation(for: currentSpace)
    }

    private var connection: Int {
        _CGSDefaultConnection()
    }

    func currentSpaceID() -> UInt64? {
        PerformanceDiagnosticsRecorder.shared.measure(
            category: .systemQuery,
            name: "currentSpaceID"
        ) {
            guard let currentSpace = currentSpaceDictionary() else {
                return nil
            }

            return currentSpaceID(from: currentSpace)
        }
    }

    func spaceIDs(containing windowNumber: Int) -> [UInt64] {
        let intervalToken = PerformanceDiagnosticsRecorder.shared.beginInterval(
            category: .systemQuery,
            name: "spaceIDsContaining"
        )
        let windows = [NSNumber(value: windowNumber)] as CFArray
        let spaces = CGSCopySpacesForWindows(connection, 7, windows).takeRetainedValue() as NSArray
        let spaceIDs = spaces.compactMap { rawSpace in
            if let spaceID = rawSpace as? UInt64 {
                return spaceID
            }

            if let number = rawSpace as? NSNumber {
                return number.uint64Value
            }

            return nil
        }

        let resultMetadata = [
            "rawSpaceCount": String(spaces.count),
            "spaceCount": String(spaceIDs.count),
        ]
        if intervalToken != nil, spaces.count == 0 || spaceIDs.isEmpty {
            recordSpaceIDsContainingFailure(
                windowNumber: windowNumber,
                rawSpaceCount: spaces.count,
                usableSpaceCount: spaceIDs.count
            )
        }
        PerformanceDiagnosticsRecorder.shared.endInterval(intervalToken, metadata: resultMetadata)

        return spaceIDs
    }

    private func currentSpaceDictionary() -> [String: Any]? {
        currentDisplayDictionary()?["Current Space"] as? [String: Any]
    }

    private func currentDisplayDictionary() -> [String: Any]? {
        displayDictionaries().first
    }

    private func displayDictionaries() -> [[String: Any]] {
        let displaySpaces = CGSCopyManagedDisplaySpaces(connection).takeRetainedValue() as NSArray
        return displaySpaces.compactMap { $0 as? [String: Any] }
    }

    private func currentSpaceID(from currentSpace: [String: Any]) -> UInt64? {
        if let spaceID = currentSpace["id64"] as? UInt64 {
            return spaceID
        }

        if let spaceIDNumber = currentSpace["id64"] as? NSNumber {
            return spaceIDNumber.uint64Value
        }

        return nil
    }

    private func presentation(for currentSpace: [String: Any]?) -> FrontmostWindowPresentation {
        guard let currentSpace else {
            return .normal
        }

        if currentSpace["TileLayoutManager"] != nil {
            return .immersive
        }

        if let spaceType = currentSpace["type"] as? Int, spaceType != 0 {
            return .immersive
        }

        if let spaceType = currentSpace["type"] as? NSNumber, spaceType.intValue != 0 {
            return .immersive
        }

        return .normal
    }

    private func recordSpaceIDsContainingFailure(
        windowNumber: Int,
        rawSpaceCount: Int,
        usableSpaceCount: Int
    ) {
        PerformanceDiagnosticsRecorder.shared.recordEvent(
            category: .systemQuery,
            name: "spaceIDsContaining.failure",
            metadata: [
                "reason": rawSpaceCount == 0 ? "empty" : "unusableResult",
                "windowNumber": String(windowNumber),
                "rawSpaceCount": String(rawSpaceCount),
                "spaceCount": String(usableSpaceCount),
            ]
        )
    }

    private func diagnosticsResult(for presentation: FrontmostWindowPresentation) -> String {
        switch presentation {
        case .normal:
            return "normal"
        case .immersive:
            return "immersive"
        }
    }
}
