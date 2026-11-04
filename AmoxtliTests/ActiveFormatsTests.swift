import XCTest
@testable import Amoxtli

final class SourceFormatDetectorTests: XCTestCase {
    /// `‸` marks the caret; `«` and `»` a selection.
    private func formats(_ marked: String, startsInFence: Bool = false) -> ActiveFormats {
        let source = marked as NSString
        let caret = source.range(of: "‸")
        if caret.location != NSNotFound {
            let text = source.replacingCharacters(in: caret, with: "")
            return SourceFormatDetector.activeFormats(in: text, selection: NSRange(location: caret.location, length: 0), startsInFence: startsInFence)
        }
        let start = source.range(of: "«").location
        let end = source.range(of: "»").location
        let text = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        return SourceFormatDetector.activeFormats(in: text, selection: NSRange(location: start, length: end - start - 1), startsInFence: startsInFence)
    }

    func testPlainTextHasNothingActive() {
        XCTAssertEqual(formats("texto‸ normal"), .none)
    }

    func testCaretInsideBold() {
        XCTAssertEqual(formats("a **ne‸grita** b").inline, .strong)
    }

    func testCaretAtTheInnerEdgesOfBold() {
        XCTAssertEqual(formats("a **‸negrita** b").inline, .strong)
        XCTAssertEqual(formats("a **negrita‸** b").inline, .strong)
    }

    func testCaretOutsideTheMarkersIsNotBold() {
        XCTAssertEqual(formats("a ‸**negrita** b").inline, [])
        XCTAssertEqual(formats("a **negrita**‸ b").inline, [])
    }

    func testNestedStyles() {
        XCTAssertEqual(formats("**negrita y _cur‸siva_**").inline, [.strong, .emphasis])
    }

    func testSelectionMustLieWithinTheStyle() {
        XCTAssertEqual(formats("**«negrita»** b").inline, .strong)
        XCTAssertEqual(formats("**nueva «negrita** b»").inline, [])
    }

    func testUnderlineStrikethroughCodeAndLink() {
        XCTAssertEqual(formats("<u>sub‸rayado</u>").inline, .underline)
        XCTAssertEqual(formats("~~ta‸chado~~").inline, .strikethrough)
        XCTAssertEqual(formats("`có‸digo`").inline, .code)
        XCTAssertTrue(formats("[en‸lace](https://a.b)").hasLink)
    }

    func testHeadingLevel() {
        XCTAssertEqual(formats("### Tí‸tulo").headingLevel, 3)
        XCTAssertEqual(formats("Tí‸tulo").headingLevel, 0)
    }

    func testListsAndQuote() {
        XCTAssertEqual(formats("- uno‸").list, .bulleted)
        XCTAssertEqual(formats("12. uno‸").list, .numbered)
        XCTAssertTrue(formats("> ci‸ta").isQuote)
        XCTAssertEqual(formats("> - uno‸").list, .bulleted)
    }

    func testOnlyTheCaretsLineCounts() {
        let result = formats("# Título\n\npárrafo‸")
        XCTAssertEqual(result.headingLevel, 0)
    }

    func testCodeBlockFromItsFencesAndContent() {
        XCTAssertTrue(formats("```swi‸ft\nlet a").isCodeBlock)
        XCTAssertTrue(formats("```\nlet ‸a\n```", startsInFence: true).isCodeBlock)
        XCTAssertEqual(formats("`**no**` y ‸ya").inline, [])
    }
}
