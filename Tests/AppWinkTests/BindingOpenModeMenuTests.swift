import AppKit
import AppWinkCore
import XCTest
@testable import AppWinkRuntime

@MainActor
final class BindingOpenModeMenuTests: XCTestCase {
    func testFolderMenuKeepsDefaultCandidatesAndChooseOtherOrder() throws {
        let application = makeApplication(name: "Code")
        let binding = HotkeyBinding(
            target: .folder(makeItem(isFolder: true), .finderNewTab)
        )
        let coordinator = makeCoordinator(
            binding: binding,
            presentation: makePresentation(
                openingModeLabel: "Finder",
                candidate: application,
                candidateIsSelected: false
            )
        )

        let menu = coordinator.makeMenu()

        XCTAssertEqual(menu.items.map { $0.title }, ["Finder", "", "Code", "", "Choose Other…"])
        XCTAssertEqual(menu.items[0].state, NSControl.StateValue.on)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].state, NSControl.StateValue.off)
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertNotNil(menu.items[0].image)
        XCTAssertNotNil(menu.items[2].image)
        XCTAssertNotNil(menu.items[4].image)
    }

    func testFileMenuMarksSelectedApplicationAndDispatchesEveryAction() throws {
        let application = makeApplication(name: "Code")
        let binding = HotkeyBinding(
            target: .file(
                makeItem(isFolder: false),
                .application(application)
            )
        )
        var selectedFolderMode: FolderOpenMode?
        var selectedFileMode: FileOpenMode?
        var chooseOtherCount = 0
        let coordinator = makeCoordinator(
            binding: binding,
            presentation: makePresentation(
                openingModeLabel: "Code",
                candidate: application,
                candidateIsSelected: true
            ),
            selectFolderMode: { selectedFolderMode = $0 },
            selectFileMode: { selectedFileMode = $0 },
            chooseOtherApplication: { chooseOtherCount += 1 }
        )
        let menu = coordinator.makeMenu()

        XCTAssertEqual(menu.items.map { $0.title }, ["System Default", "", "Code", "", "Choose Other…"])
        XCTAssertEqual(menu.items[0].state, NSControl.StateValue.off)
        XCTAssertEqual(menu.items[2].state, NSControl.StateValue.on)

        coordinator.selectFileDefault(menu.items[0])
        XCTAssertEqual(selectedFileMode, .systemDefault)

        coordinator.selectApplication(menu.items[2])
        XCTAssertEqual(selectedFileMode, .application(application))
        XCTAssertNil(selectedFolderMode)

        coordinator.chooseOther(menu.items[4])
        XCTAssertEqual(chooseOtherCount, 1)
    }

    func testFolderApplicationSelectionDispatchesFolderMode() {
        let application = makeApplication(name: "Code")
        let binding = HotkeyBinding(
            target: .folder(makeItem(isFolder: true), .finderNewTab)
        )
        var selectedMode: FolderOpenMode?
        let coordinator = makeCoordinator(
            binding: binding,
            presentation: makePresentation(
                openingModeLabel: "Finder",
                candidate: application,
                candidateIsSelected: false
            ),
            selectFolderMode: { selectedMode = $0 }
        )
        let menu = coordinator.makeMenu()

        coordinator.selectApplication(menu.items[2])

        XCTAssertEqual(selectedMode, .application(application))
    }

    func testSplitHitTargetAssignsEveryPointToExactlyOneButton() {
        let view = BindingOpenModeSplitHitTargetView(frame: controlFrame)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            view.openButton.frame,
            NSRect(
                x: 0,
                y: 0,
                width: SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
                height: SettingsDesignTokens.BindingOpenMode.height
            )
        )
        XCTAssertEqual(
            view.menuButton.frame,
            NSRect(
                x: SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
                y: 0,
                width: SettingsDesignTokens.BindingOpenMode.width -
                    SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
                height: SettingsDesignTokens.BindingOpenMode.height
            )
        )
        XCTAssertTrue(view.hitTest(NSPoint(x: 1, y: 1)) === view.openButton)
        XCTAssertTrue(
            view.hitTest(
                NSPoint(
                    x: SettingsDesignTokens.BindingOpenMode.iconRegionWidth - 0.1,
                    y: 10
                )
            ) === view.openButton
        )
        XCTAssertTrue(
            view.hitTest(
                NSPoint(
                    x: SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
                    y: 10
                )
            ) === view.menuButton
        )
        XCTAssertTrue(
            view.hitTest(
                NSPoint(
                    x: SettingsDesignTokens.BindingOpenMode.width - 1,
                    y: SettingsDesignTokens.BindingOpenMode.height - 1
                )
            ) === view.menuButton
        )
        XCTAssertNil(view.hitTest(NSPoint(x: -1, y: 10)))
        XCTAssertNil(
            view.hitTest(
                NSPoint(
                    x: SettingsDesignTokens.BindingOpenMode.width + 1,
                    y: 10
                )
            )
        )
    }

    func testOpenButtonMouseAndAccessibilityPressOnlyOpenTarget() throws {
        let view = BindingOpenModeOpenHitTargetView(frame: openButtonFrame)
        var openCount = 0
        view.activationHandler = { openCount += 1 }

        view.mouseDown(with: try makeMouseEvent())
        XCTAssertEqual(openCount, 1)

        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertEqual(openCount, 2)
    }

    func testMenuButtonMouseAndAccessibilityPressOnlyPresentMenu() throws {
        let view = BindingOpenModeMenuHitTargetView(frame: menuButtonFrame)
        var presentationCount = 0
        view.menuPresentationHandler = { presentationCount += 1 }

        view.mouseDown(with: try makeMouseEvent())
        XCTAssertEqual(presentationCount, 1)

        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertEqual(presentationCount, 2)
    }

    func testKeyboardActivationIsIndependentForOpenAndMenuButtons() throws {
        let openButton = BindingOpenModeOpenHitTargetView(frame: openButtonFrame)
        let menuButton = BindingOpenModeMenuHitTargetView(frame: menuButtonFrame)
        var openCount = 0
        var menuCount = 0
        openButton.activationHandler = { openCount += 1 }
        menuButton.menuPresentationHandler = { menuCount += 1 }

        for keyCode in [UInt16(36), 49, 76] {
            openButton.keyDown(with: try makeKeyEvent(keyCode: keyCode))
        }
        for keyCode in [UInt16(36), 49, 76, 125, 126] {
            menuButton.keyDown(with: try makeKeyEvent(keyCode: keyCode))
        }

        XCTAssertEqual(openCount, 3)
        XCTAssertEqual(menuCount, 5)
    }

    func testHoverCallbacksRemainIndependentAcrossBothSegments() throws {
        let openButton = BindingOpenModeOpenHitTargetView(frame: openButtonFrame)
        let menuButton = BindingOpenModeMenuHitTargetView(frame: menuButtonFrame)
        var events: [(BindingOpenModeSegment, Bool)] = []
        openButton.hoverHandler = { events.append((.open, $0)) }
        menuButton.hoverHandler = { events.append((.menu, $0)) }
        let event = try makeMouseEvent()

        openButton.mouseEntered(with: event)
        openButton.mouseExited(with: event)
        menuButton.mouseEntered(with: event)
        menuButton.mouseExited(with: event)

        XCTAssertEqual(events.map(\.0), [.open, .open, .menu, .menu])
        XCTAssertEqual(events.map(\.1), [true, false, true, false])
    }

    func testBothButtonsKeepKeyboardFocusWithoutNativeFocusRings() {
        let view = BindingOpenModeSplitHitTargetView(frame: controlFrame)

        for button in [view.openButton, view.menuButton] as [NSButton] {
            XCTAssertTrue(button.acceptsFirstResponder)
            XCTAssertTrue(button.canBecomeKeyView)
            XCTAssertEqual(button.focusRingType, .none)
        }
        XCTAssertTrue(view.openButton.nextKeyView === view.menuButton)
    }

    private func makeCoordinator(
        binding: HotkeyBinding,
        presentation: HotkeyTargetPresentation,
        selectFolderMode: @escaping (FolderOpenMode) -> Void = { _ in },
        selectFileMode: @escaping (FileOpenMode) -> Void = { _ in },
        chooseOtherApplication: @escaping () -> Void = {}
    ) -> BindingOpenModeSplitHitTarget.Coordinator {
        let coordinator = BindingOpenModeSplitHitTarget.Coordinator(
            selectFolderMode: selectFolderMode,
            selectFileMode: selectFileMode,
            chooseOtherApplication: chooseOtherApplication
        )
        coordinator.binding = binding
        coordinator.presentation = presentation
        coordinator.finderTitle = "Finder"
        coordinator.chooseOtherApplicationTitle = "Choose Other…"
        coordinator.openingApplicationUnavailableTitle = "Unavailable"
        return coordinator
    }

    private func makePresentation(
        openingModeLabel: String,
        candidate: ManagedApplication,
        candidateIsSelected: Bool
    ) -> HotkeyTargetPresentation {
        let candidateOption = HotkeyTargetPresentation.ApplicationOption(
            id: .bundleIdentifier(candidate.bundleIdentifier!),
            application: candidate,
            displayName: candidate.displayName,
            image: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil),
            isSelected: candidateIsSelected
        )
        let defaultMode = HotkeyTargetPresentation.OpeningMode(
            label: "System Default",
            image: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil),
            fallbackSymbolName: "app.fill"
        )
        return HotkeyTargetPresentation(
            displayName: "Target",
            targetImage: nil,
            fallbackSymbolName: "doc",
            openingMode: .init(
                label: openingModeLabel,
                image: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil),
                fallbackSymbolName: "app.fill"
            ),
            finderOpeningMode: .init(
                label: "Finder",
                image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil),
                fallbackSymbolName: "folder"
            ),
            systemDefaultOpeningMode: defaultMode,
            applicationCandidates: [candidateOption],
            accessibilityValue: "Target",
            availability: .available
        )
    }

    private func makeApplication(name: String) -> ManagedApplication {
        ManagedApplication(
            displayName: name,
            bundleIdentifier: "com.example.\(name.lowercased())",
            fallbackPath: "/Applications/\(name).app",
            bookmarkData: Data([0x01])
        )
    }

    private func makeItem(isFolder: Bool) -> ManagedFileSystemItem {
        ManagedFileSystemItem(
            displayName: isFolder ? "Folder" : "File.txt",
            fallbackPath: isFolder ? "/tmp/Folder" : "/tmp/File.txt",
            bookmarkData: Data([0x01])
        )
    }

    private func makeMouseEvent() throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 10, y: 10),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private func makeKeyEvent(keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    private var controlFrame: NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: SettingsDesignTokens.BindingOpenMode.width,
            height: SettingsDesignTokens.BindingOpenMode.height
        )
    }

    private var openButtonFrame: NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
            height: SettingsDesignTokens.BindingOpenMode.height
        )
    }

    private var menuButtonFrame: NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: SettingsDesignTokens.BindingOpenMode.width -
                SettingsDesignTokens.BindingOpenMode.iconRegionWidth,
            height: SettingsDesignTokens.BindingOpenMode.height
        )
    }
}
