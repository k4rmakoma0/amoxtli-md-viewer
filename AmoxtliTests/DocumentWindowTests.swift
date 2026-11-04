import AppKit
import XCTest
@testable import Amoxtli

@MainActor
final class DocumentWindowTests: XCTestCase {
    func testMultipleDocumentsHaveUniqueCustomizableToolbarItems() async throws {
        var documents: [NSDocument] = []
        defer { documents.forEach { $0.close() } }

        // Use the hosted app's DocumentGroup, including its real split view and toolbar.
        // The regression appeared when a second window reused the toolbar's identifier.
        for _ in 0..<3 {
            documents.append(try NSDocumentController.shared.openUntitledDocumentAndDisplay(true))
            for document in documents {
                for controller in document.windowControllers {
                    controller.window?.contentView?.layoutSubtreeIfNeeded()
                    controller.window?.displayIfNeeded()
                }
            }
            await Task.yield()
        }

        for document in documents {
            let window = try XCTUnwrap(document.windowControllers.first?.window)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let toolbar = try XCTUnwrap(window.toolbar)
            let identifiers = toolbar.items.map(\.itemIdentifier)
            XCTAssertTrue(toolbar.allowsUserCustomization)
            XCTAssertEqual(identifiers.filter { $0.rawValue == "sidebar" }.count, 1)

            let uniqueItems = identifiers.filter { $0 != .space && $0 != .flexibleSpace }
            XCTAssertEqual(Set(uniqueItems).count, uniqueItems.count, "Duplicate toolbar items: \(identifiers)")
        }
    }
}
