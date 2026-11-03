import XCTest
@testable import Amoxtli

final class MarkdownParserTests: XCTestCase {
    private func parse(_ source: String) throws -> [MarkdownBlock] {
        try MarkdownParser().parse(source).blocks
    }

    private func text(_ string: String) -> InlineText {
        InlineText(runs: [InlineRun(text: string)])
    }

    private func item(_ ordinal: Int, _ string: String) -> ListItem {
        ListItem(ordinal: ordinal, blocks: [.paragraph(text(string))])
    }

    // MARK: - Headings and paragraphs

    func testHeadingLevelsOneThroughSix() throws {
        let source = (1...6).map { "\(String(repeating: "#", count: $0)) H\($0)" }.joined(separator: "\n\n")
        let expected = (1...6).map { MarkdownBlock.heading(level: $0, content: text("H\($0)")) }
        XCTAssertEqual(try parse(source), expected)
    }

    func testSeparateParagraphsStaySeparate() throws {
        XCTAssertEqual(try parse("uno\n\ndos"), [.paragraph(text("uno")), .paragraph(text("dos"))])
    }

    func testSoftBreakJoinsLinesWithSpace() throws {
        XCTAssertEqual(try parse("uno\ndos"), [.paragraph(text("uno dos"))])
    }

    // MARK: - Lists

    func testUnorderedList() throws {
        XCTAssertEqual(try parse("- a\n- b"), [.unorderedList([item(1, "a"), item(2, "b")])])
    }

    func testOrderedListKeepsSourceNumbering() throws {
        XCTAssertEqual(try parse("3. a\n4. b"), [.orderedList([item(3, "a"), item(4, "b")])])
    }

    func testNestedLists() throws {
        let expected: [MarkdownBlock] = [
            .unorderedList([
                ListItem(ordinal: 1, blocks: [
                    .paragraph(text("a")),
                    .orderedList([item(1, "a1"), item(2, "a2")]),
                ]),
                item(2, "b"),
            ]),
        ]
        XCTAssertEqual(try parse("- a\n  1. a1\n  2. a2\n- b"), expected)
    }

    // MARK: - Quotes, code and breaks

    func testBlockQuoteContainsNestedBlocks() throws {
        let expected: [MarkdownBlock] = [
            .blockQuote([
                .heading(level: 2, content: text("t")),
                .paragraph(text("cita")),
            ]),
        ]
        XCTAssertEqual(try parse("> ## t\n>\n> cita"), expected)
    }

    func testConsecutiveBlockQuotesStaySeparate() throws {
        let expected: [MarkdownBlock] = [
            .blockQuote([.paragraph(text("a"))]),
            .blockQuote([.paragraph(text("b"))]),
        ]
        XCTAssertEqual(try parse("> a\n\n<!-- -->\n\n> b").filter(isQuote), expected)
    }

    private func isQuote(_ block: MarkdownBlock) -> Bool {
        if case .blockQuote = block { return true }
        return false
    }

    func testCodeBlockWithLanguage() throws {
        let expected = MarkdownBlock.codeBlock(languageHint: "swift", code: "let x = 1\n\nlet y = 2")
        XCTAssertEqual(try parse("```swift\nlet x = 1\n\nlet y = 2\n```"), [expected])
    }

    func testCodeBlockWithoutLanguage() throws {
        XCTAssertEqual(try parse("```\nx\n```"), [.codeBlock(languageHint: nil, code: "x")])
    }

    func testIndentedCodeBlock() throws {
        XCTAssertEqual(try parse("    x"), [.codeBlock(languageHint: nil, code: "x")])
    }

    func testThematicBreak() throws {
        XCTAssertEqual(
            try parse("a\n\n---\n\nb"),
            [.paragraph(text("a")), .thematicBreak, .paragraph(text("b"))]
        )
    }

    // MARK: - Inline

    func testInlineStyles() throws {
        let expected = InlineText(runs: [
            InlineRun(text: "b", style: .strong),
            InlineRun(text: " "),
            InlineRun(text: "i", style: .emphasis),
            InlineRun(text: " "),
            InlineRun(text: "c", style: .code),
            InlineRun(text: " "),
            InlineRun(text: "bi", style: [.strong, .emphasis]),
        ])
        XCTAssertEqual(try parse("**b** *i* `c` ***bi***"), [.paragraph(expected)])
    }

    func testLink() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let expected = InlineText(runs: [InlineRun(text: "ir", link: url)])
        XCTAssertEqual(try parse("[ir](https://example.com)"), [.paragraph(expected)])
    }

    func testUnderlineTagBecomesUnderline() throws {
        let expected = InlineText(runs: [
            InlineRun(text: "a "),
            InlineRun(text: "b", style: .underline),
            InlineRun(text: " c"),
        ])
        XCTAssertEqual(try parse("a <u>b</u> c"), [.paragraph(expected)])
    }

    func testInsTagBecomesUnderline() throws {
        let expected = InlineText(runs: [InlineRun(text: "x", style: [.strong, .underline])])
        XCTAssertEqual(try parse("<ins>**x**</ins>"), [.paragraph(expected)])
    }

    func testOtherInlineHTMLStaysAsText() throws {
        XCTAssertEqual(try parse("a <b>x</b>"), [.paragraph(text("a <b>x</b>"))])
    }

    func testImageSplitsParagraph() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a.png"))
        let image = MarkdownImage(source: url, altText: "alt")
        XCTAssertTrue(image.isRemote)
        XCTAssertEqual(
            try parse("antes ![alt](https://example.com/a.png) después"),
            [.paragraph(text("antes ")), .image(image), .paragraph(text(" después"))]
        )
    }

    func testRelativeImageIsNotRemote() throws {
        guard case .image(let image) = try parse("![alt](img/a.png)").first else {
            return XCTFail("Se esperaba una imagen")
        }
        XCTAssertFalse(image.isRemote)
    }

    func testImageWithoutAltTextHasEmptyAltText() throws {
        guard case .image(let image) = try parse("![](img/a.png)").first else {
            return XCTFail("Se esperaba una imagen")
        }
        XCTAssertEqual(image.altText, "")
    }

    // MARK: - Malformed input

    func testMalformedInputIsKeptAsText() throws {
        XCTAssertEqual(try parse("**sin cerrar [link]("), [.paragraph(text("**sin cerrar [link]("))])
    }

    func testUnterminatedCodeFenceRunsToEndOfDocument() throws {
        XCTAssertEqual(try parse("```\nx"), [.codeBlock(languageHint: nil, code: "x")])
    }

    func testEmptySourceHasNoBlocks() throws {
        XCTAssertEqual(try parse(""), [])
    }

    // MARK: - GFM support (documents what Foundation's parser actually does)

    func testGFMTableIsSupported() throws {
        let expected = MarkdownTable(
            columns: [.leading, .center, .trailing],
            header: [text("A"), text("B"), text("C")],
            rows: [[text("1"), text("2"), text("3")]]
        )
        XCTAssertEqual(try parse("| A | B | C |\n|:--|:-:|--:|\n| 1 | 2 | 3 |"), [.table(expected)])
    }

    func testTableEmptyCellsAndRowsArePreserved() throws {
        let empty = InlineText(runs: [])
        let expected = MarkdownTable(
            columns: [.leading, .leading],
            header: [text("A"), text("B")],
            rows: [[empty, text("x")], [empty, empty], [text("y"), empty]]
        )
        let source = "| A | B |\n|---|---|\n|   | x |\n|   |   |\n| y |   |"
        XCTAssertEqual(try parse(source), [.table(expected)])
    }

    func testGFMStrikethroughIsSupported() throws {
        let expected = InlineText(runs: [InlineRun(text: "x", style: .strikethrough)])
        XCTAssertEqual(try parse("~~x~~"), [.paragraph(expected)])
    }

    func testGFMAutolinkIsSupported() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let expected = InlineText(runs: [InlineRun(text: "https://example.com", link: url)])
        XCTAssertEqual(try parse("https://example.com"), [.paragraph(expected)])
    }

    func testGFMTaskListIsNotInterpreted() throws {
        XCTAssertEqual(try parse("- [ ] a\n- [x] b"), [.unorderedList([item(1, "[ ] a"), item(2, "[x] b")])])
    }

    func testFootnoteIsNotInterpreted() throws {
        let source = "a[^1]\n\n[^1]: una nota"
        XCTAssertEqual(try parse(source), [.paragraph(text("a[^1]")), .paragraph(text("[^1]: una nota"))])
    }

    func testHardLineBreakIsKept() throws {
        XCTAssertEqual(try parse("uno\ndos  \ntres"), [.paragraph(text("uno dos\ntres"))])
    }

    func testRawHTMLIsKeptAsLiteralText() throws {
        XCTAssertEqual(try parse("<div>x</div>"), [.paragraph(text("<div>x</div>\n"))])
    }
}
