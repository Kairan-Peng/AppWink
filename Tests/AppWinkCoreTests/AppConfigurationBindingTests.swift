import Foundation

import XCTest
@testable import AppWinkCore

final class AppConfigurationBindingTests: XCTestCase {
    func testContainsBindingMatchesApplicationIdentity() {
        let storedApplication = makeApplication(
            name: "Stored",
            bundleIdentifier: "com.example.shared",
            path: "/Applications/Stored.app"
        )
        let selectedApplication = makeApplication(
            name: "Selected",
            bundleIdentifier: "com.example.shared",
            path: "/Applications/Selected.app"
        )
        let binding = HotkeyBinding(target: .application(storedApplication))
        let configuration = AppConfiguration(bindings: [binding])

        XCTAssertTrue(
            configuration.containsBinding(
                matching: .application(selectedApplication)
            )
        )
        XCTAssertFalse(
            configuration.containsBinding(
                matching: .application(selectedApplication),
                excludingBindingID: binding.id
            )
        )
    }

    func testContainsBindingMatchesFileAndFolderTargetModes() {
        let item = makeItem(path: "/tmp/Shared")
        let handler = makeApplication(
            bundleIdentifier: "com.example.handler",
            path: "/Applications/Handler.app"
        )
        let folderTarget = HotkeyTarget.folder(item, .finderNewTab)
        let fileTarget = HotkeyTarget.file(item, .application(handler))
        let configuration = AppConfiguration(
            bindings: [
                HotkeyBinding(target: folderTarget),
                HotkeyBinding(target: fileTarget),
            ]
        )

        XCTAssertTrue(configuration.containsBinding(matching: folderTarget))
        XCTAssertTrue(configuration.containsBinding(matching: fileTarget))
    }

    func testSameFileSystemTargetWithDifferentModesIsAllowed() {
        let item = makeItem(path: "/tmp/Shared.txt")
        let handler = makeApplication(
            bundleIdentifier: "com.example.handler",
            path: "/Applications/Handler.app"
        )
        let configuration = AppConfiguration(
            bindings: [
                HotkeyBinding(target: .file(item, .systemDefault)),
            ]
        )

        XCTAssertFalse(
            configuration.containsBinding(
                matching: .file(item, .application(handler))
            )
        )
    }

    func testUpdateTargetRejectsDuplicateWithoutMutation() {
        let item = makeItem(path: "/tmp/Shared.txt")
        let handler = makeApplication(
            bundleIdentifier: "com.example.handler",
            path: "/Applications/Handler.app"
        )
        let first = HotkeyBinding(target: .file(item, .systemDefault))
        let second = HotkeyBinding(target: .file(item, .application(handler)))
        var configuration = AppConfiguration(bindings: [first, second])
        let originalBindings = configuration.bindings

        let result = configuration.updateTarget(
            second.target,
            forBindingID: first.id
        )

        XCTAssertEqual(result, .duplicate)
        XCTAssertEqual(configuration.bindings, originalBindings)
    }

    func testUpdateTargetAppliesNonduplicateTarget() {
        let binding = HotkeyBinding(
            target: .application(
                makeApplication(
                    bundleIdentifier: "com.example.before",
                    path: "/Applications/Before.app"
                )
            )
        )
        let updatedTarget = HotkeyTarget.folder(
            makeItem(path: "/tmp/Folder"),
            .finderNewTab
        )
        var configuration = AppConfiguration(bindings: [binding])

        let result = configuration.updateTarget(
            updatedTarget,
            forBindingID: binding.id
        )

        XCTAssertEqual(result, .updated)
        XCTAssertEqual(configuration.bindings.first?.target, updatedTarget)
    }

    func testUpdateTargetReturnsUnchangedForSameIdentity() {
        let storedApplication = makeApplication(
            name: "Stored",
            bundleIdentifier: "com.example.shared",
            path: "/Applications/Stored.app"
        )
        let equivalentApplication = makeApplication(
            name: "Equivalent",
            bundleIdentifier: "com.example.shared",
            path: "/Applications/Equivalent.app"
        )
        let binding = HotkeyBinding(target: .application(storedApplication))
        var configuration = AppConfiguration(bindings: [binding])

        let result = configuration.updateTarget(
            .application(equivalentApplication),
            forBindingID: binding.id
        )

        XCTAssertEqual(result, .unchanged)
        XCTAssertEqual(configuration.bindings.first?.target, binding.target)
    }

    func testUpdateTargetReturnsBindingNotFound() {
        var configuration = AppConfiguration()

        let result = configuration.updateTarget(
            .file(makeItem(path: "/tmp/Missing.txt"), .systemDefault),
            forBindingID: UUID()
        )

        XCTAssertEqual(result, .bindingNotFound)
        XCTAssertTrue(configuration.bindings.isEmpty)
    }

    func testAllTargetModesRoundTripInConfiguration() throws {
        let item = makeItem(path: "/tmp/Target")
        let application = makeApplication(
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
        let configuration = AppConfiguration(
            bindings: targets.map { HotkeyBinding(target: $0) }
        )

        let data = try JSONEncoder().encode(configuration)

        XCTAssertEqual(
            try JSONDecoder().decode(AppConfiguration.self, from: data),
            configuration
        )
    }

    func testLegacyBindingsPreserveOrderAndStoredValues() throws {
        let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let firstApplication = makeApplication(
            bundleIdentifier: "com.example.first",
            path: "/Applications/First.app"
        )
        let secondApplication = makeApplication(
            bundleIdentifier: "com.example.second",
            path: "/Applications/Second.app"
        )
        let firstShortcut = AppShortcut(keyCode: 8, modifiers: [.option])
        let secondShortcut = AppShortcut(keyCode: 12, modifiers: [.command])
        let data = try jsonData([
            "bindings": [
                [
                    "id": firstID.uuidString,
                    "application": try jsonObject(for: firstApplication),
                    "toggleShortcut": try jsonObject(for: firstShortcut),
                    "isEnabled": false,
                    "source": "user",
                ],
                [
                    "id": secondID.uuidString,
                    "application": try jsonObject(for: secondApplication),
                    "toggleShortcut": try jsonObject(for: secondShortcut),
                    "isEnabled": true,
                    "source": "activityMonitorFeature",
                ],
            ],
        ])

        let configuration = try JSONDecoder().decode(
            AppConfiguration.self,
            from: data
        )

        XCTAssertEqual(configuration.bindings.map(\.id), [firstID, secondID])
        XCTAssertEqual(
            configuration.bindings.map(\.target),
            [.application(firstApplication), .application(secondApplication)]
        )
        XCTAssertEqual(
            configuration.bindings.map(\.shortcut),
            [firstShortcut, secondShortcut]
        )
        XCTAssertEqual(configuration.bindings.map(\.isEnabled), [false, true])
        XCTAssertEqual(
            configuration.bindings.map(\.source),
            [.user, .activityMonitorFeature]
        )
    }

    func testManagedActivityMonitorSourceRoundTrips() throws {
        let binding = HotkeyBinding(
            target: .application(
                makeApplication(
                    bundleIdentifier: "com.apple.ActivityMonitor",
                    path: "/System/Applications/Utilities/Activity Monitor.app"
                )
            ),
            shortcut: AppShortcut(keyCode: 47, modifiers: [.control, .command]),
            source: .activityMonitorFeature
        )
        let configuration = AppConfiguration(bindings: [binding])

        let decoded = try JSONDecoder().decode(
            AppConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertEqual(decoded.bindings.first, binding)
        XCTAssertEqual(decoded.bindings.first?.source, .activityMonitorFeature)
    }

    func testMixedCanonicalAndLegacyBindingsPreserveOrder() throws {
        let canonical = HotkeyBinding(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            target: .file(makeItem(path: "/tmp/Canonical.txt"), .systemDefault)
        )
        let legacyID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let legacyApplication = makeApplication(
            bundleIdentifier: "com.example.legacy",
            path: "/Applications/Legacy.app"
        )
        let data = try jsonData([
            "bindings": [
                try jsonObject(for: canonical),
                [
                    "id": legacyID.uuidString,
                    "application": try jsonObject(for: legacyApplication),
                ],
            ],
        ])

        let configuration = try JSONDecoder().decode(
            AppConfiguration.self,
            from: data
        )

        XCTAssertEqual(configuration.bindings.map(\.id), [canonical.id, legacyID])
        XCTAssertEqual(configuration.bindings.first, canonical)
        XCTAssertEqual(
            configuration.bindings.last?.target,
            .application(legacyApplication)
        )
    }

    func testPresentMalformedOrNullBindingsRejectsWithoutSingleAppFallback() throws {
        let legacyApplication = makeApplication(
            bundleIdentifier: "com.example.legacy",
            path: "/Applications/Legacy.app"
        )
        let malformedValues: [Any] = [
            NSNull(),
            [["id": UUID().uuidString]],
        ]

        for malformedBindings in malformedValues {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    AppConfiguration.self,
                    from: try jsonData([
                        "bindings": malformedBindings,
                        "selectedApplication": try jsonObject(
                            for: legacyApplication
                        ),
                    ])
                )
            )
        }
    }

    func testLegacySingleApplicationConfigurationMigratesToBinding() throws {
        let application = makeApplication(
            bundleIdentifier: "com.example.legacy",
            path: "/Applications/Legacy.app"
        )
        let launchShortcut = AppShortcut(keyCode: 8, modifiers: [.option])
        let quitShortcut = AppShortcut(keyCode: 12, modifiers: [.command])
        let data = try jsonData([
            "selectedApplication": try jsonObject(for: application),
            "launchShortcut": try jsonObject(for: launchShortcut),
            "quitShortcut": try jsonObject(for: quitShortcut),
        ])

        let configuration = try JSONDecoder().decode(
            AppConfiguration.self,
            from: data
        )

        XCTAssertEqual(configuration.bindings.count, 1)
        XCTAssertEqual(
            configuration.bindings.first?.target,
            .application(application)
        )
        XCTAssertEqual(configuration.bindings.first?.shortcut, launchShortcut)
        XCTAssertTrue(configuration.bindings.first?.isEnabled == true)
        XCTAssertEqual(configuration.bindings.first?.source, .user)
    }

    func testEncodingUsesCanonicalConfigurationAndBindingShape() throws {
        let configuration = AppConfiguration(
            bindings: [
                HotkeyBinding(
                    target: .application(
                        makeApplication(
                            bundleIdentifier: "com.example.canonical",
                            path: "/Applications/Canonical.app"
                        )
                    ),
                    shortcut: AppShortcut(keyCode: 8, modifiers: [.option])
                ),
            ]
        )

        let object = try jsonObject(for: configuration)
        let bindings = try XCTUnwrap(object["bindings"] as? [[String: Any]])
        let binding = try XCTUnwrap(bindings.first)

        XCTAssertNil(object["selectedApplication"])
        XCTAssertNil(object["launchShortcut"])
        XCTAssertNil(object["quitShortcut"])
        XCTAssertNotNil(binding["target"])
        XCTAssertNotNil(binding["shortcut"])
        XCTAssertNil(binding["application"])
        XCTAssertNil(binding["toggleShortcut"])
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
