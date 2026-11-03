import AppKit
import XCTest
@testable import Amoxtli

@MainActor
final class EditorMenuTests: XCTestCase {
    private func items(of menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in
            [item] + (item.submenu.map(items(of:)) ?? [])
        }
    }

    private func menuItems() throws -> [NSMenuItem] {
        items(of: try XCTUnwrap(NSApp.mainMenu))
    }

    func testMenuBarCanSaveDocuments() throws {
        let save = NSSelectorFromString("saveDocument:")
        XCTAssertTrue(try menuItems().contains { $0.action == save })
    }

    func testFormatMenuOffersToolsWithShortcuts() throws {
        let items = try menuItems()
        let bold = items.first { $0.title == FormatTool.bold.title }
        XCTAssertEqual(bold?.keyEquivalent, "b")
        XCTAssertEqual(bold?.keyEquivalentModifierMask, .command)
        let heading = items.first { $0.title == FormatTool.heading(2).title }
        XCTAssertEqual(heading?.keyEquivalent, "2")
    }

    func testFormatToolsAreDisabledWithoutAnEditor() throws {
        let menu = try XCTUnwrap(NSApp.mainMenu)
        menu.items.compactMap(\.submenu).forEach { $0.update() }
        let bold = try menuItems().first { $0.title == FormatTool.bold.title }
        XCTAssertEqual(bold?.isEnabled, false)
    }

    func testMenuBarCanStillCloseWindows() throws {
        let close = try menuItems().first { $0.keyEquivalent == "w" && $0.keyEquivalentModifierMask == .command }
        XCTAssertNotNil(close)
    }
}
