import AppKit
import XCTest
@testable import Amoxtli

final class TextDifferenceTests: XCTestCase {
    private func apply(_ difference: TextDifference, to text: String) -> String {
        (text as NSString).replacingCharacters(in: difference.range, with: difference.replacement)
    }

    func testInsertionInTheMiddle() {
        let difference = TextDifference(from: "Hola mundo", to: "Hola gran mundo")
        XCTAssertEqual(difference, TextDifference(range: NSRange(location: 5, length: 0), replacement: "gran "))
    }

    func testDeletion() {
        let difference = TextDifference(from: "a **b** c", to: "a b c")
        XCTAssertEqual(difference, TextDifference(range: NSRange(location: 2, length: 5), replacement: "b"))
    }

    func testIdenticalTextsHaveNoDifference() {
        XCTAssertTrue(TextDifference(from: "igual", to: "igual").isEmpty)
    }

    func testCharactersOfTwoUnitsAreNotSplit() {
        let difference = TextDifference(from: "a🌮b", to: "a🌯b")
        XCTAssertEqual(difference.range, NSRange(location: 1, length: 2))
        XCTAssertEqual(difference.replacement, "🌯")
    }

    func testWholeReplacement() {
        XCTAssertEqual(apply(TextDifference(from: "uno", to: "dos"), to: "uno"), "dos")
        XCTAssertEqual(apply(TextDifference(from: "", to: "nuevo"), to: ""), "nuevo")
    }

    func testSelectionAfterTheChangeShifts() {
        let difference = TextDifference(from: "Hola mundo", to: "Hola gran mundo")
        XCTAssertEqual(difference.adjusting(NSRange(location: 7, length: 2)), NSRange(location: 12, length: 2))
    }

    func testSelectionBeforeTheChangeStays() {
        let difference = TextDifference(from: "Hola mundo", to: "Hola mundo!")
        XCTAssertEqual(difference.adjusting(NSRange(location: 2, length: 1)), NSRange(location: 2, length: 1))
    }

    func testSelectionInsideTheChangeMovesToItsEnd() {
        let difference = TextDifference(from: "a viejo b", to: "a nuevo texto b")
        XCTAssertEqual(difference.adjusting(NSRange(location: 4, length: 0)), NSRange(location: 2 + difference.replacement.utf16.count, length: 0))
    }

    @MainActor
    func testSourceEditorKeepsItsCaretWhenTextChangesElsewhere() {
        let view = SourceTextView.make()
        view.show("# Título\n\nUno dos")
        view.setSelectedRange(NSRange(location: 14, length: 0))
        view.show("# Título nuevo\n\nUno dos")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 20, length: 0))
        XCTAssertEqual(view.string, "# Título nuevo\n\nUno dos")
    }
}
