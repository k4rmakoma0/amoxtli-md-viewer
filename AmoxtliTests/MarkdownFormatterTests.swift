import XCTest
@testable import Amoxtli

/// Selections are written inline: `«` and `»` around selected text, `‸` for the caret.
final class MarkdownFormatterTests: XCTestCase {
    private func format(_ command: FormatCommand, _ marked: String) -> String {
        let (text, selection) = unmark(marked)
        let edit = MarkdownFormatter.edit(for: command, in: text, selection: selection)
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return mark(result, edit.selection)
    }

    private func unmark(_ marked: String) -> (String, NSRange) {
        let source = marked as NSString
        let caret = source.range(of: "‸")
        if caret.location != NSNotFound {
            return (source.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
        }
        let start = source.range(of: "«").location
        let end = source.range(of: "»").location
        let text = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        return (text, NSRange(location: start, length: end - start - 1))
    }

    private func mark(_ text: String, _ selection: NSRange) -> String {
        let source = NSMutableString(string: text)
        if selection.length == 0 {
            source.insert("‸", at: selection.location)
        } else {
            source.insert("»", at: NSMaxRange(selection))
            source.insert("«", at: selection.location)
        }
        return source as String
    }

    // MARK: - Inline

    func testBoldWrapsSelection() {
        XCTAssertEqual(format(.bold, "Hola «mundo»"), "Hola **«mundo»**")
    }

    func testBoldIsRemovedFromAroundSelection() {
        XCTAssertEqual(format(.bold, "Hola **«mundo»**"), "Hola «mundo»")
    }

    func testBoldIsRemovedWhenMarkersAreSelected() {
        XCTAssertEqual(format(.bold, "Hola «**mundo**»"), "Hola «mundo»")
    }

    func testBoldWithoutSelectionLeavesCaretBetweenMarkers() {
        XCTAssertEqual(format(.bold, "Hola ‸"), "Hola **‸**")
    }

    func testSurroundingSpacesStayOutsideMarkers() {
        XCTAssertEqual(format(.bold, "Hola« mundo »adiós"), "Hola **«mundo»** adiós")
    }

    func testItalicInsideBoldKeepsBold() {
        XCTAssertEqual(format(.italic, "**«negrita»**"), "**_«negrita»_**")
    }

    func testItalicToggles() {
        XCTAssertEqual(format(.italic, "_«uno»_"), "«uno»")
    }

    func testUnderlineUsesHTMLTag() {
        XCTAssertEqual(format(.underline, "«a»"), "<u>«a»</u>")
    }

    func testStrikethroughAndInlineCode() {
        XCTAssertEqual(format(.strikethrough, "«a»"), "~~«a»~~")
        XCTAssertEqual(format(.inlineCode, "«a»"), "`«a»`")
    }

    func testOffsetsCountUTF16() {
        XCTAssertEqual(format(.bold, "🌮 «taco»"), "🌮 **«taco»**")
    }

    // MARK: - Headings

    func testHeadingKeepsCaretOnSameCharacter() {
        XCTAssertEqual(format(.heading(2), "Títul‸o"), "## Títul‸o")
    }

    func testHeadingReplacesOtherLevel() {
        XCTAssertEqual(format(.heading(3), "# Tít‸ulo"), "### Tít‸ulo")
    }

    func testSameHeadingLevelTogglesOff() {
        XCTAssertEqual(format(.heading(2), "## Tít‸ulo"), "Tít‸ulo")
    }

    func testLevelZeroMakesBodyText() {
        XCTAssertEqual(format(.heading(0), "### a‸"), "a‸")
    }

    func testHeadingOnEmptyLine() {
        XCTAssertEqual(format(.heading(1), "‸"), "# ‸")
    }

    // MARK: - Quotes and lists

    func testQuotePrefixesEveryLine() {
        XCTAssertEqual(format(.quote, "«uno\ndos»"), "«> uno\n> dos»")
    }

    func testQuoteTogglesOff() {
        XCTAssertEqual(format(.quote, "«> uno\n> dos»"), "«uno\ndos»")
    }

    func testBulletListSkipsBlankLines() {
        XCTAssertEqual(format(.bulletList, "«uno\n\ndos»"), "«- uno\n\n- dos»")
    }

    func testNumberedListReplacesBullets() {
        XCTAssertEqual(format(.numberedList, "«- uno\n- dos»"), "«1. uno\n2. dos»")
    }

    func testNumberedListTogglesOff() {
        XCTAssertEqual(format(.numberedList, "«1. uno\n2. dos»"), "«uno\ndos»")
    }

    func testListKeepsIndentation() {
        XCTAssertEqual(format(.bulletList, "«  uno»"), "«  - uno»")
    }

    func testSelectionEndingAtLineStartLeavesNextLineAlone() {
        XCTAssertEqual(format(.bulletList, "«uno\n»dos"), "«- uno»\ndos")
    }

    // MARK: - Blocks

    func testCodeBlockWrapsLines() {
        XCTAssertEqual(format(.codeBlock, "«let a = 1»"), "```\n«let a = 1»\n```")
    }

    func testCodeBlockUnwraps() {
        XCTAssertEqual(format(.codeBlock, "«```\nlet a\n```»"), "«let a»")
    }

    func testEmptyCodeBlockLeavesCaretInside() {
        XCTAssertEqual(format(.codeBlock, "‸"), "```\n‸\n```")
    }

    func testRuleAfterParagraphGetsBlankLine() {
        XCTAssertEqual(format(.horizontalRule, "Texto‸"), "Texto\n\n---‸")
    }

    func testRuleOnLineUnderParagraphGetsBlankLine() {
        XCTAssertEqual(format(.horizontalRule, "Texto\n‸"), "Texto\n\n---‸")
    }

    func testRuleBeforeParagraphGetsBlankLine() {
        XCTAssertEqual(format(.horizontalRule, "‸\nTexto"), "---‸\n\nTexto")
    }

    func testTableSelectsFirstHeader() {
        let header = String(localized: "Columna 1")
        let second = String(localized: "Columna 2")
        XCTAssertEqual(format(.table, "‸"), "| «\(header)» | \(second) |\n| --- | --- |\n|  |  |")
    }

    // MARK: - Links

    func testLinkReplacesSelection() {
        XCTAssertEqual(
            format(.link(text: "Amoxtli", destination: "https://amoxtli.dev"), "Visita «Amoxtli»"),
            "Visita [Amoxtli](https://amoxtli.dev)‸"
        )
    }

    func testLinkEscapesBracketsAndWrapsSpaces() {
        XCTAssertEqual(format(.link(text: "a [b]", destination: "mi archivo.md"), "‸"), "[a \\[b\\]](<mi archivo.md>)‸")
    }

    func testLinkWithoutTextShowsDestination() {
        XCTAssertEqual(format(.link(text: " ", destination: "https://a.b"), "‸"), "[https://a.b](https://a.b)‸")
    }
}

final class LinkInputTests: XCTestCase {
    func testBareDomainGetsHTTPS() {
        XCTAssertEqual(LinkInput.normalized("amoxtli.dev"), "https://amoxtli.dev")
    }

    func testURLWithSchemeIsKept() {
        XCTAssertEqual(LinkInput.normalized(" http://a.b/c "), "http://a.b/c")
    }

    func testBareAddressGetsMailto() {
        XCTAssertEqual(LinkInput.normalized("hola@amoxtli.dev"), "mailto:hola@amoxtli.dev")
    }

    func testAnchorsAndPathsAreKept() {
        XCTAssertEqual(LinkInput.normalized("#intro"), "#intro")
        XCTAssertEqual(LinkInput.normalized("./notas.md"), "./notas.md")
        XCTAssertEqual(LinkInput.normalized("notas"), "notas")
    }

    func testEmptyInputIsRejected() {
        XCTAssertNil(LinkInput.normalized("  \n"))
    }
}
