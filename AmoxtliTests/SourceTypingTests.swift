import AppKit
import XCTest
@testable import Amoxtli

/// Typing in the source editor as the keyboard does it, through key events, with the
/// highlighter restyling each edited line.
@MainActor
final class SourceTypingTests: XCTestCase {
    private var window: NSWindow?
    private let highlighter = SourceHighlighter()

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func makeView(_ text: String) -> SourceTextView {
        let view = SourceTextView.make()
        view.textStorage?.delegate = highlighter
        view.typingAttributes = highlighter.baseAttributes
        view.show(text)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        view.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        scrollView.documentView = view
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        window.makeFirstResponder(view)
        self.window = window
        return view
    }

    private func type(_ text: String, into view: SourceTextView) throws {
        let window = try XCTUnwrap(window)
        for character in text.map(String.init) {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0
            ))
            view.keyDown(with: event)
        }
    }

    private func placeCaret(after anchor: String, in view: SourceTextView) {
        let found = (view.string as NSString).range(of: anchor)
        view.setSelectedRange(NSRange(location: NSMaxRange(found), length: 0))
    }

    func testTypingInTheMiddleOfALineKeepsTheCaretThere() throws {
        let view = makeView("hola mundo")
        placeCaret(after: "ho", in: view)
        try type("xyz", into: view)
        XCTAssertEqual(view.string, "hoxyzla mundo")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testTypingNeverJumpsToTheNextLine() throws {
        let view = makeView("# Título\n\n- uno\n- dos\n\n```swift\nlet a\n```\n")
        for anchor in ["# Tí", "- u", "let"] {
            placeCaret(after: anchor, in: view)
            try type("ab", into: view)
        }
        XCTAssertEqual(view.string, "# Tíabtulo\n\n- uabno\n- dos\n\n```swift\nletab a\n```\n")
    }

    func testTypedLinesAreStillHighlighted() throws {
        let view = makeView("texto\n")
        placeCaret(after: "texto\n", in: view)
        try type("# Hola", into: view)
        let storage = try XCTUnwrap(view.textStorage)
        let font = try XCTUnwrap(storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(font.pointSize, highlighter.typography.body.pointSize)
        XCTAssertEqual(view.selectedRange(), NSRange(location: storage.length, length: 0))
    }
}
