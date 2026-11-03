import XCTest
@testable import Amoxtli

final class MarkdownSerializerTests: XCTestCase {
    private func parse(_ source: String) throws -> MarkdownModel {
        try MarkdownParser().parse(source)
    }

    private func serialize(_ source: String) throws -> String {
        MarkdownSerializer.markdown(from: RichDocumentBuilder.paragraphs(from: try parse(source)))
    }

    /// Writing the document back must not change what it says.
    private func assertRoundTrip(_ source: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let written = try serialize(source)
        XCTAssertEqual(try parse(written), try parse(source), "Escrito:\n\(written)", file: file, line: line)
        XCTAssertEqual(try serialize(written), written, "No es estable:\n\(written)", file: file, line: line)
    }

    private func paragraph(_ text: String) -> RichParagraph {
        RichParagraph(block: .paragraph, runs: [InlineRun(text: text)])
    }

    // MARK: - Round trips

    func testInlineStyles() throws {
        try assertRoundTrip("# Título\n\nUn párrafo con **negrita**, *cursiva*, `código`, ~~tachado~~ y <u>subrayado</u>.")
    }

    func testNestedStyles() throws {
        try assertRoundTrip("***todo*** y **negrita con *cursiva* dentro** y <u>**ambos**</u>")
    }

    func testNestedLists() throws {
        try assertRoundTrip("- uno\n- dos\n  - anidado\n  - otro\n- tres")
    }

    func testOrderedListKeepsItsStart() throws {
        try assertRoundTrip("3. a\n4. b\n5. c")
    }

    func testOrderedListInsideBulletList() throws {
        try assertRoundTrip("- a\n  1. x\n  2. y\n- b")
    }

    func testListItemWithTwoParagraphs() throws {
        try assertRoundTrip("- a\n\n  b\n- c")
    }

    func testQuoteWithList() throws {
        try assertRoundTrip("> cita\n>\n> - item\n> - otro\n\nfuera")
    }

    func testCodeBlockWithBackticksAndBlankLines() throws {
        try assertRoundTrip("```swift\nlet a = 1\n\nlet b = \"```\"\n```")
    }

    func testCodeInsideList() throws {
        try assertRoundTrip("- paso\n\n  ```\n  make\n  ```\n- otro")
    }

    func testTable() throws {
        try assertRoundTrip("| A | B | C |\n|:--|:-:|--:|\n| 1 | x \\| y | **z** |\n| | dos | |")
    }

    func testLinks() throws {
        try assertRoundTrip("Ver [la *guía*](https://example.com/a_(b)) y [ancla](#intro).")
    }

    func testHardLineBreak() throws {
        try assertRoundTrip("línea uno\\\nlínea dos")
    }

    func testImageAndRule() throws {
        try assertRoundTrip("![logo](https://example.com/a.png)\n\n---\n\nfin")
    }

    func testTextThatLooksLikeSyntax() throws {
        try assertRoundTrip("2 * 3 = 6, snake_case, \\*no\\*, a [b] c, \\[x\\](y), C#, 1\\. no es lista, a &amp;amp; b, \\<b\\>")
    }

    func testHeadingEndingInHash() throws {
        try assertRoundTrip("## Lenguaje C\\#")
    }

    // MARK: - Output

    func testCanonicalOutput() throws {
        XCTAssertEqual(try serialize("Título\n===\n\n* uno\n* dos\n\n__fuerte__ _suave_"), "# Título\n\n- uno\n- dos\n\n**fuerte** *suave*\n")
    }

    func testSpacesStayOutsideMarkers() {
        let paragraph = RichParagraph(block: .paragraph, runs: [
            InlineRun(text: "a"),
            InlineRun(text: " negrita ", style: .strong),
            InlineRun(text: "b"),
        ])
        XCTAssertEqual(MarkdownSerializer.markdown(from: [paragraph]), "a **negrita** b\n")
    }

    func testTextAtLineStartIsEscaped() throws {
        for text in ["# no es título", "> no es cita", "- no es lista", "+ tampoco", "1. no es lista", "---", "```"] {
            let written = MarkdownSerializer.markdown(from: [paragraph(text)])
            XCTAssertEqual(try parse(written).blocks, [.paragraph(InlineText(runs: [InlineRun(text: text)]))], written)
        }
    }

    func testAdjacentListsStaySeparate() throws {
        let first = RichListItem(listID: 1, itemID: 2, isOrdered: false, start: 1)
        let second = RichListItem(listID: 3, itemID: 4, isOrdered: false, start: 1)
        let written = MarkdownSerializer.markdown(from: [
            RichParagraph(block: .paragraph, containers: [.listItem(first)], runs: [InlineRun(text: "a")]),
            RichParagraph(block: .paragraph, containers: [.listItem(second)], runs: [InlineRun(text: "b")]),
        ])
        XCTAssertEqual(try parse(written).blocks.count, 2, written)
    }

    func testNewItemsAreNumberedInOrder() {
        let paragraphs = (0..<3).map { index in
            RichParagraph(
                block: .paragraph,
                containers: [.listItem(RichListItem(listID: 1, itemID: 10 + index, isOrdered: true, start: 1))],
                runs: [InlineRun(text: "item")]
            )
        }
        XCTAssertEqual(MarkdownSerializer.markdown(from: paragraphs), "1. item\n2. item\n3. item\n")
    }

    func testEmptyTopLevelParagraphsDisappear() {
        XCTAssertEqual(MarkdownSerializer.markdown(from: [paragraph("a"), paragraph(""), paragraph("b")]), "a\n\nb\n")
    }

    func testEmptyDocument() {
        XCTAssertEqual(MarkdownSerializer.markdown(from: []), "")
    }
}
