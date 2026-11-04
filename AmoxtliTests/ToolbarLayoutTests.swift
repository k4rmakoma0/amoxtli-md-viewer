import AppKit
import XCTest
@testable import Amoxtli

@MainActor
final class ToolbarLayoutTests: XCTestCase {
    /// The formatting items, in the order the toolbar declares them.
    private let formattingIDs = [
        "typography", "style",
        "bold", "italic", "underline", "strikethrough", "inlineCode",
        "bulletList", "numberedList", "quote",
        "link", "codeBlock", "table", "horizontalRule",
    ]

    /// A narrow window moves tools into the overflow menu one at a time from the right, so the
    /// ones that stay are always the first ones, with no group missing from the middle.
    func testToolsOverflowOneAtATimeFromTheRight() async throws {
        let document = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        defer { document.close() }
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        var visibleCounts: [Int] = []

        for width in [CGFloat(1000), CGFloat(900), CGFloat(800)] {
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: width, height: 700)), display: true)
            // The toolbar lays itself out again after the resize completes.
            try await Task.sleep(for: .milliseconds(450))
            window.contentView?.superview?.layoutSubtreeIfNeeded()

            let toolbar = try XCTUnwrap(window.toolbar)
            let visible = Set(try XCTUnwrap(toolbar.visibleItems).map(\.itemIdentifier.rawValue))
            let shown = formattingIDs.filter(visible.contains)
            XCTAssertLessThan(shown.count, formattingIDs.count, "Expected some tools in the overflow menu at width \(width)")
            XCTAssertEqual(shown, Array(formattingIDs.prefix(shown.count)), "Tools missing from the middle at width \(width)")
            visibleCounts.append(shown.count)
        }
        XCTAssertEqual(visibleCounts, visibleCounts.sorted(by: >), "A narrower window should never show more tools")
    }
}
