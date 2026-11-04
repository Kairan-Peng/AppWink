import Foundation

import XCTest
@testable import AppWinkCore

final class HotkeyBindingTests: XCTestCase {
    func testAllTargetModesRoundTrip() throws {
        let item = makeItem(path: "/tmp/Target")
        let application = makeApplication(
            name: "Handler",
            bundleIdentifier: "com.example.handler",
            path: "/Applications/Handler.app"
        )
        let targets: [HotkeyTarget] = [
            .application(application),
            .folder(item, .finderNewTab),
            .folder(item, .application(application)),
            .file(item, .systemDefault),
            .file(item, .application(application)),
        ]

        for target in targets {
            let binding = HotkeyBinding(
                target: target,
                shortcut: AppShortcut(keyCode: 8, modifiers: [.command, .option]),
                isEnabled: false,
                source: .activityMonitorFeature
            )
            let data = try JSONEncoder().encode(binding)

            XCTAssertEqual(
                try JSONDecoder().decode(HotkeyBinding.self, from: data),
                binding
            )
        }
    }

    func testLegacyApplicationBindingPreservesStoredValues() throws {
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let application = makeApplication(
            name: "Legacy",
            bundleIdentifier: "com.example.legacy",
            path: "/Applications/Legacy.app"
        )
        let shortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let data = try jsonData([
            "id": id.uuidString,
            "application": try jsonObject(for: application),
            "toggleShortcut": try jsonObject(for: shortcut),
            "isEnabled": false,
            "source": "activityMonitorFeature",
        ])

        let binding = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        XCTAssertEqual(binding.id, id)
        XCTAssertEqual(binding.target, .application(application))
        XCTAssertEqual(binding.shortcut, shortcut)
        XCTAssertFalse(binding.isEnabled)
        XCTAssertEqual(binding.source, .activityMonitorFeature)
    }

    func testLegacyBindingDefaultsMissingFields() throws {
        let application = makeApplication(
            bundleIdentifier: "com.example.defaults",
            path: "/Applications/Defaults.app"
        )
        let data = try jsonData([
            "id": UUID().uuidString,
            "application": try jsonObject(for: application),
        ])

        let binding = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        XCTAssertEqual(binding.target, .application(application))
        XCTAssertNil(binding.shortcut)
        XCTAssertTrue(binding.isEnabled)
        XCTAssertEqual(binding.source, .user)
    }

    func testPresentMalformedOrNullTargetRejectsWithoutLegacyFallback() throws {
        let application = makeApplication(
            bundleIdentifier: "com.example.legacy",
            path: "/Applications/Legacy.app"
        )
        let baseObject: [String: Any] = [
            "id": UUID().uuidString,
            "application": try jsonObject(for: application),
        ]

        for invalidTarget in [NSNull(), "application"] {
            var object = baseObject
            object["target"] = invalidTarget

            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    HotkeyBinding.self,
                    from: try jsonData(object)
                )
            )
        }
    }

    func testCanonicalShortcutTakesPrecedenceOverLegacyShortcut() throws {
        let canonicalShortcut = AppShortcut(keyCode: 8, modifiers: [.command])
        let legacyShortcut = AppShortcut(keyCode: 12, modifiers: [.option])
        let target = HotkeyTarget.application(
            makeApplication(
                bundleIdentifier: "com.example.canonical",
                path: "/Applications/Canonical.app"
            )
        )
        let baseObject: [String: Any] = [
            "id": UUID().uuidString,
            "target": try jsonObject(for: target),
            "toggleShortcut": try jsonObject(for: legacyShortcut),
        ]

        var canonicalObject = baseObject
        canonicalObject["shortcut"] = try jsonObject(for: canonicalShortcut)
        let canonicalBinding = try JSONDecoder().decode(
            HotkeyBinding.self,
            from: try jsonData(canonicalObject)
        )

        var nullObject = baseObject
        nullObject["shortcut"] = NSNull()
        let nullBinding = try JSONDecoder().decode(
            HotkeyBinding.self,
            from: try jsonData(nullObject)
        )

        XCTAssertEqual(canonicalBinding.shortcut, canonicalShortcut)
        XCTAssertNil(nullBinding.shortcut)
    }

    func testCanonicalEncodingOmitsLegacyKeys() throws {
        let binding = HotkeyBinding(
            target: .application(
                makeApplication(
                    bundleIdentifier: "com.example.canonical",
                    path: "/Applications/Canonical.app"
                )
            ),
            shortcut: AppShortcut(keyCode: 8, modifiers: [.option])
        )
        let object = try jsonObject(for: binding)

        XCTAssertNotNil(object["id"])
        XCTAssertNotNil(object["target"])
        XCTAssertNotNil(object["shortcut"])
        XCTAssertNotNil(object["isEnabled"])
        XCTAssertNotNil(object["source"])
        XCTAssertNil(object["application"])
        XCTAssertNil(object["toggleShortcut"])
    }

    private func makeItem(path: String) -> ManagedFileSystemItem {
        ManagedFileSystemItem(
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            fallbackPath: path,
            bookmarkData: Data("bookmark".utf8)
        )
    }

    private func makeApplication(
        name: String = "Application",
        bundleIdentifier: String?,
        path: String
    ) -> ManagedApplication {
        ManagedApplication(
            displayName: name,
            bundleIdentifier: bundleIdentifier,
            fallbackPath: path,
            bookmarkData: Data("bookmark".utf8)
        )
    }

    private func jsonObject<T: Encodable>(for value: T) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
                as? [String: Any]
        )
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}
