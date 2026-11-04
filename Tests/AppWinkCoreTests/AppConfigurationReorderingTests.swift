import Foundation

import XCTest
@testable import AppWinkCore

final class AppConfigurationReorderingTests: XCTestCase {
    func testMoveBindingMovesBindingDownwardByOffset() {
        let bindings = makeBindingsForReordering()
        var configuration = AppConfiguration(bindings: bindings)

        configuration.moveBinding(withID: bindings[0].id, toOffset: 3)

        XCTAssertEqual(configuration.bindings.map(\.id), [bindings[1].id, bindings[2].id, bindings[0].id])
    }

    func testMoveBindingMovesBindingUpwardByOffset() {
        let bindings = makeBindingsForReordering()
        var configuration = AppConfiguration(bindings: bindings)

        configuration.moveBinding(withID: bindings[2].id, toOffset: 0)

        XCTAssertEqual(configuration.bindings.map(\.id), [bindings[2].id, bindings[0].id, bindings[1].id])
    }

    func testMoveBindingIgnoresUnknownBindingID() {
        let bindings = makeBindingsForReordering()
        var configuration = AppConfiguration(bindings: bindings)

        configuration.moveBinding(withID: UUID(), toOffset: 0)

        XCTAssertEqual(configuration.bindings.map(\.id), bindings.map(\.id))
    }

    func testSetBindingOrderAppliesCompleteCustomOrder() {
        let bindings = makeBindingsForReordering()
        var configuration = AppConfiguration(bindings: bindings)

        configuration.setBindingOrder([bindings[2].id, bindings[0].id, bindings[1].id])

        XCTAssertEqual(configuration.bindings.map(\.id), [bindings[2].id, bindings[0].id, bindings[1].id])
    }

    func testSetBindingOrderIgnoresIncompleteOrder() {
        let bindings = makeBindingsForReordering()
        var configuration = AppConfiguration(bindings: bindings)

        configuration.setBindingOrder([bindings[1].id, bindings[0].id])

        XCTAssertEqual(configuration.bindings.map(\.id), bindings.map(\.id))
    }

    func testSetBindingOrderIgnoresDuplicateOrder() {
        let bindings = makeBindingsForReordering()
        var configuration = AppConfiguration(bindings: bindings)

        configuration.setBindingOrder([bindings[1].id, bindings[1].id, bindings[0].id])

        XCTAssertEqual(configuration.bindings.map(\.id), bindings.map(\.id))
    }

    private func makeBindingsForReordering() -> [HotkeyBinding] {
        [
            HotkeyBinding(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                target: .application(
                    ManagedApplication(
                        displayName: "App One",
                        bundleIdentifier: "com.example.appone",
                        fallbackPath: "/Applications/AppOne.app",
                        bookmarkData: Data()
                    )
                )),
            HotkeyBinding(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                target: .folder(
                    ManagedFileSystemItem(
                        displayName: "Folder",
                        fallbackPath: "/tmp/Folder",
                        bookmarkData: Data()
                    ),
                    .finderNewTab
                )),
            HotkeyBinding(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                target: .file(
                    ManagedFileSystemItem(
                        displayName: "Document.txt",
                        fallbackPath: "/tmp/Document.txt",
                        bookmarkData: Data()
                    ),
                    .systemDefault
                )),
        ]
    }
}
