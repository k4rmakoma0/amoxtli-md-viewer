import XCTest
@testable import Amoxtli

/// `‸` marks the caret before and after Return.
final class SourceListContinuationTests: XCTestCase {
    private func pressReturn(_ marked: String, startsInFence: Bool = false) -> String? {
        let source = marked as NSString
        let caret = source.range(of: "‸")
        let text = source.replacingCharacters(in: caret, with: "")
        guard let edit = SourceListContinuation.edit(in: text, selection: NSRange(location: caret.location, length: 0), startsInFence: startsInFence) else { return nil }
        let result = NSMutableString(string: (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement))
        result.insert("‸", at: edit.selection.location)
        return result as String
    }

    func testBulletContinues() {
        XCTAssertEqual(pressReturn("- uno‸"), "- uno\n- ‸")
        XCTAssertEqual(pressReturn("* uno‸"), "* uno\n* ‸")
    }

    func testNumberGoesUp() {
        XCTAssertEqual(pressReturn("1. uno‸"), "1. uno\n2. ‸")
        XCTAssertEqual(pressReturn("9) nueve‸"), "9) nueve\n10) ‸")
    }

    func testIndentationAndQuotesAreKept() {
        XCTAssertEqual(pressReturn("  - anidado‸"), "  - anidado\n  - ‸")
        XCTAssertEqual(pressReturn("> - en cita‸"), "> - en cita\n> - ‸")
        XCTAssertEqual(pressReturn("> cita‸"), "> cita\n> ‸")
    }

    func testTextAfterTheCaretMovesToTheNewItem() {
        XCTAssertEqual(pressReturn("- uno‸ dos"), "- uno\n- ‸ dos")
    }

    func testEmptyItemEndsTheList() {
        XCTAssertEqual(pressReturn("- uno\n- ‸"), "- uno\n‸")
        XCTAssertEqual(pressReturn("> - ‸"), "> ‸")
        XCTAssertEqual(pressReturn("> ‸"), "‸")
    }

    func testPlainTextAndHeadingsAreLeftToTheTextView() {
        XCTAssertNil(pressReturn("texto‸"))
        XCTAssertNil(pressReturn("# Título‸"))
        XCTAssertNil(pressReturn("-sin espacio‸"))
        XCTAssertNil(pressReturn("1.5 no es lista‸"))
    }

    func testCaretBeforeTheTextLeavesALineBreak() {
        XCTAssertNil(pressReturn("‸- uno"))
    }

    func testCodeBlocksAreLeftAlone() {
        XCTAssertNil(pressReturn("- dentro de código‸", startsInFence: true))
    }
}

@MainActor
final class SourceEditorReturnTests: XCTestCase {
    private func makeView(_ text: String) -> SourceTextView {
        let view = SourceTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.show(text)
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return view
    }

    func testReturnContinuesAListAndEndsItOnAnEmptyItem() {
        let view = makeView("1. uno")
        view.insertNewline(nil)
        view.insertText("dos", replacementRange: view.selectedRange())
        view.insertNewline(nil)
        view.insertNewline(nil)
        view.insertText("fin", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "1. uno\n2. dos\nfin")
    }

    func testReturnOutsideAListIsALineBreak() {
        let view = makeView("texto")
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "texto\n")
    }

    func testListStartedWithTheToolContinuesWithReturn() {
        let view = makeView("")
        view.apply(.bulletList, actionName: "")
        view.insertText("uno", replacementRange: view.selectedRange())
        view.insertNewline(nil)
        view.insertText("dos", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "- uno\n- dos")
    }
}
