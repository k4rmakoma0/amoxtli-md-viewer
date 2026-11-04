import XCTest
@testable import Amoxtli

final class MarkdownSyntaxTests: XCTestCase {
    private func spans(_ text: String, _ kind: SyntaxKind) -> [NSRange] {
        // In text order: the scanner reports spans by the pattern that found them.
        MarkdownSyntaxScanner.scan(text).spans.filter { $0.kind == kind }.map(\.range).sorted { $0.location < $1.location }
    }

    private func range(_ location: Int, _ length: Int) -> NSRange {
        NSRange(location: location, length: length)
    }

    func testHeadingLineAndMarker() {
        XCTAssertEqual(spans("## Hola", .heading(level: 2)), [range(0, 7)])
        XCTAssertEqual(spans("## Hola", .marker), [range(0, 3)])
    }

    func testStrongWithMarkers() {
        XCTAssertEqual(spans("a **b** c", .strong), [range(4, 1)])
        XCTAssertEqual(spans("a **b** c", .marker), [range(2, 2), range(5, 2)])
    }

    func testEmphasis() {
        XCTAssertEqual(spans("a _b_ y *c*", .emphasis), [range(3, 1), range(9, 1)])
    }

    func testNothingInsideCodeSpanIsSyntax() {
        XCTAssertEqual(spans("`*no*`", .inlineCode), [range(0, 6)])
        XCTAssertEqual(spans("`*no*`", .emphasis), [])
    }

    func testFencedCodeIsNotFormatted() {
        let text = "```\n*x*\n```\ntexto *y*"
        let scan = MarkdownSyntaxScanner.scan(text)
        XCTAssertEqual(spans(text, .codeBlock), [range(4, 3)])
        XCTAssertEqual(spans(text, .emphasis), [range(19, 1)])
        XCTAssertFalse(scan.endsInFence)
        XCTAssertEqual(scan.fencedLines, [range(0, 4), range(4, 4)])
    }

    func testOpenFenceCarriesOver() {
        XCTAssertTrue(MarkdownSyntaxScanner.scan("```swift\nlet a").endsInFence)
    }

    func testLinesInsideFenceWhenStartingInOne() {
        let scan = MarkdownSyntaxScanner.scan("*x*", lines: range(0, 3), startsInFence: true)
        XCTAssertEqual(scan.spans, [SyntaxSpan(range: range(0, 3), kind: .codeBlock)])
    }

    func testLinkTextAndDestination() {
        XCTAssertEqual(spans("[a](b)", .linkText), [range(1, 1)])
        XCTAssertEqual(spans("[a](b)", .linkDestination), [range(4, 1)])
    }

    func testListMarkers() {
        XCTAssertEqual(spans("- uno", .listMarker), [range(0, 1)])
        XCTAssertEqual(spans("12. uno", .listMarker), [range(0, 3)])
    }

    func testQuote() {
        XCTAssertEqual(spans("> cita", .quote), [range(0, 6)])
        XCTAssertEqual(spans("> cita", .marker), [range(0, 2)])
    }

    func testUnderlineAndStrikethrough() {
        XCTAssertEqual(spans("<u>a</u>", .underline), [range(3, 1)])
        XCTAssertEqual(spans("~~a~~", .strikethrough), [range(2, 1)])
    }

    func testHorizontalRule() {
        XCTAssertEqual(spans("texto\n\n---", .horizontalRule), [range(7, 3)])
    }
}

final class SourceHeadingLocatorTests: XCTestCase {
    private func location(of title: String, occurrence: Int = 0, in text: String) throws -> Int? {
        let entries = TOCBuilder.entries(for: try MarkdownParser().parse(text).blocks)
        let entry = try XCTUnwrap(entries.filter { $0.title == title }.dropFirst(occurrence).first)
        return SourceHeadingLocator.location(of: entry, among: entries, in: text)
    }

    func testFindsHeadingLine() throws {
        XCTAssertEqual(try location(of: "Dos", in: "# Uno\n\ntexto\n\n## Dos"), 14)
    }

    func testSkipsHeadingsInsideCode() throws {
        XCTAssertEqual(try location(of: "Sí", in: "```\n# no\n```\n# Sí"), 13)
    }

    func testIgnoresFormattingInTitle() throws {
        XCTAssertEqual(try location(of: "Hola mundo", in: "texto\n\n# **Hola** mundo"), 7)
    }

    func testRepeatedTitlesFindTheirOwnLine() throws {
        XCTAssertEqual(try location(of: "A", occurrence: 1, in: "# A\n# A"), 4)
    }
}
