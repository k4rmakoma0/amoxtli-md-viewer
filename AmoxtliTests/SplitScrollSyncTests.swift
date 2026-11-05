import AppKit
import XCTest
@testable import Amoxtli

final class SplitScrollMapTests: XCTestCase {
    func testInterpolatesBetweenBlocks() {
        let map = SplitScrollMap(sourceAnchors: [100, 200], formattedAnchors: [300, 400], sourceEnd: 1000, formattedEnd: 2000)
        XCTAssertEqual(map.formattedOffset(forSource: 0), 0)
        XCTAssertEqual(map.formattedOffset(forSource: 50), 150)
        XCTAssertEqual(map.formattedOffset(forSource: 100), 300)
        XCTAssertEqual(map.formattedOffset(forSource: 150), 350)
        XCTAssertEqual(map.formattedOffset(forSource: 600), 1200)
        XCTAssertEqual(map.formattedOffset(forSource: 1000), 2000)
    }

    func testMapsBothWays() {
        let map = SplitScrollMap(sourceAnchors: [100, 200], formattedAnchors: [300, 400], sourceEnd: 1000, formattedEnd: 2000)
        for offset in stride(from: 0.0, through: 1000, by: 25) {
            XCTAssertEqual(map.sourceOffset(forFormatted: map.formattedOffset(forSource: offset)), offset, accuracy: 0.0001)
        }
    }

    func testClampsOutsideTheDocument() {
        let map = SplitScrollMap(sourceAnchors: [100], formattedAnchors: [300], sourceEnd: 1000, formattedEnd: 2000)
        XCTAssertEqual(map.formattedOffset(forSource: -40), 0)
        XCTAssertEqual(map.formattedOffset(forSource: 5000), 2000)
    }

    func testDifferentBlockCountsAlignOnlyTopsAndEnds() {
        let map = SplitScrollMap(sourceAnchors: [100, 200], formattedAnchors: [300], sourceEnd: 1000, formattedEnd: 2000)
        XCTAssertEqual(map.points.count, 2)
        XCTAssertEqual(map.formattedOffset(forSource: 500), 1000)
    }

    func testBlocksPastTheEndGiveWayToIt() {
        // The last blocks can't reach the top of the view, so the ends line up instead.
        let map = SplitScrollMap(sourceAnchors: [100, 900, 950], formattedAnchors: [300, 1500, 2100], sourceEnd: 920, formattedEnd: 2000)
        XCTAssertEqual(map.points.map(\.source), [0, 100, 900, 920])
        XCTAssertEqual(map.formattedOffset(forSource: 920), 2000)
    }

    func testSkipsBlocksThatDontMoveForward() {
        let map = SplitScrollMap(sourceAnchors: [100, 100, 200, 300], formattedAnchors: [300, 350, 290, 400], sourceEnd: 1000, formattedEnd: 2000)
        XCTAssertEqual(map.points.map(\.source), [0, 100, 300, 1000])
    }

    func testContentThatFitsDoesntScroll() {
        let map = SplitScrollMap(sourceAnchors: [10], formattedAnchors: [20], sourceEnd: 0, formattedEnd: 0)
        XCTAssertEqual(map.formattedOffset(forSource: 0), 0)
        XCTAssertEqual(map.sourceOffset(forFormatted: 30), 0)
    }
}

final class TextLinesTests: XCTestCase {
    func testLineStartsInUTF16() {
        XCTAssertEqual(TextLines.startOffsets(in: ""), [0])
        XCTAssertEqual(TextLines.startOffsets(in: "a\nb\n"), [0, 2, 4])
        XCTAssertEqual(TextLines.startOffsets(in: "😀\nb"), [0, 3])
        XCTAssertEqual(TextLines.startOffsets(in: "a\r\nb\rc"), [0, 3, 5])
    }
}

/// The source and the formatted document must count the same top-level blocks, or the split
/// view can only line up their tops and ends.
final class TopLevelBlockTests: XCTestCase {
    private func lines(_ markdown: String) throws -> [Int] {
        try MarkdownParser().topLevelBlockLines(in: markdown)
    }

    private func formattedStarts(_ markdown: String) throws -> [Int] {
        let paragraphs = RichDocumentBuilder.paragraphs(from: try MarkdownParser().parse(markdown))
        return RichTopLevelBlocks.starts(of: paragraphs.map(RichTopLevelBlocks.Outline.init))
    }

    func testLinesOfEachKindOfBlock() throws {
        let markdown = """
        # Título

        Un párrafo
        de dos líneas.

        - uno
        - dos
          - anidado

        > cita
        >
        > - con lista

        ```swift
        let x = 1

        print(x)
        ```

        | A | B |
        |---|---|
        | 1 | 2 |

        ---

        1. último
        """
        XCTAssertEqual(try lines(markdown), [1, 3, 6, 10, 14, 20, 24, 26])
        XCTAssertEqual(try formattedStarts(markdown).count, 8)
    }

    func testImagesSplitAParagraphOnBothSides() throws {
        let markdown = "Antes\n![alt](https://example.com/a.png)\ndespués\n\nOtro"
        XCTAssertEqual(try lines(markdown), [1, 2, 3, 5])
        XCTAssertEqual(try formattedStarts(markdown).count, 4)
    }

    func testCountsMatchForAssortedDocuments() throws {
        let documents = [
            "",
            "Solo texto",
            "# A\n## B\n### C",
            "- a\n\n- b\n\n\n1. c\n2. d",
            "> a\n\n> b",
            "```\n```\n\nTexto",
            "| A |\n|---|\n",
            "Texto  \ncon salto forzado\n\n***",
            "- [ ] tarea\n- [x] hecha",
            "<u>subrayado</u> y <b>html</b>",
            "---\n\n---\n\n- a\n\n***",
        ]
        for markdown in documents {
            XCTAssertEqual(try lines(markdown).count, try formattedStarts(markdown).count, markdown)
            XCTAssertEqual(try lines(markdown), try lines(markdown).sorted(), markdown)
        }
    }

    func testEmptyParagraphsOutsideBlocksStartNothing() {
        let body = RichTopLevelBlocks.Outline(block: .paragraph, containers: [], isEmpty: false)
        let empty = RichTopLevelBlocks.Outline(block: .paragraph, containers: [], isEmpty: true)
        XCTAssertEqual(RichTopLevelBlocks.starts(of: [body, empty, body]), [0, 2])
    }

    func testParagraphsOfOneContainerAreOneBlock() {
        let item = RichListItem(listID: 1, itemID: 2, isOrdered: false, start: 1)
        let other = RichListItem(listID: 1, itemID: 3, isOrdered: false, start: 1)
        let outlines = [
            RichTopLevelBlocks.Outline(block: .paragraph, containers: [.listItem(item)], isEmpty: false),
            RichTopLevelBlocks.Outline(block: .paragraph, containers: [.listItem(other)], isEmpty: true),
            RichTopLevelBlocks.Outline(block: .code(id: 4, language: nil), containers: [], isEmpty: false),
            RichTopLevelBlocks.Outline(block: .code(id: 4, language: nil), containers: [], isEmpty: true),
            RichTopLevelBlocks.Outline(block: .code(id: 5, language: nil), containers: [], isEmpty: false),
            RichTopLevelBlocks.Outline(block: .heading(level: 1), containers: [], isEmpty: false),
            RichTopLevelBlocks.Outline(block: .heading(level: 1), containers: [], isEmpty: false),
        ]
        XCTAssertEqual(RichTopLevelBlocks.starts(of: outlines), [0, 2, 4, 5, 6])
    }
}

@MainActor
final class SplitScrollSyncTests: XCTestCase {
    private let markdown = (1...40).map { index in
        index.isMultiple(of: 5)
            ? "| A | B |\n|---|---|\n| \(index) | x |\n| y | z |"
            : index.isMultiple(of: 3) ? "```\nlínea\nlínea\nlínea\n```" : "## Sección \(index)\n\nTexto del párrafo \(index)."
    }.joined(separator: "\n\n")

    private func makeEditors() throws -> (source: SourceTextView, formatted: RichTextView) {
        let source = SourceTextView.make()
        source.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        source.show(markdown)
        let formatted = RichTextView.make()
        formatted.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        formatted.show(RichDocumentBuilder.paragraphs(from: try MarkdownParser().parse(markdown)))
        return (source, formatted)
    }

    func testBothEditorsFindEveryBlock() throws {
        let (source, formatted) = try makeEditors()
        let blocks = try MarkdownParser().topLevelBlockLines(in: markdown).count
        let sourceOffsets = source.blockOffsets()
        let formattedOffsets = formatted.blockOffsets()
        XCTAssertEqual(sourceOffsets.count, blocks)
        XCTAssertEqual(formattedOffsets.count, blocks)
        XCTAssertEqual(sourceOffsets, sourceOffsets.sorted())
        XCTAssertEqual(formattedOffsets, formattedOffsets.sorted())
    }

    func testFormattedFollowsTheSourceBlockByBlock() throws {
        let (source, formatted) = try makeEditors()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let sourceScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let formattedScroll = NSScrollView(frame: NSRect(x: 500, y: 0, width: 500, height: 300))
        sourceScroll.documentView = source
        formattedScroll.documentView = formatted
        window.contentView?.addSubview(sourceScroll)
        window.contentView?.addSubview(formattedScroll)
        let sync = SplitScrollSync()
        sync.attach(sourceScroll, editor: source, as: .source)
        sync.attach(formattedScroll, editor: formatted, as: .formatted)
        window.makeFirstResponder(source)

        // The tenth block of the source at the top puts the tenth block of the formatted
        // document at the top.
        let sourceOffsets = source.blockOffsets()
        let formattedOffsets = formatted.blockOffsets()
        sourceScroll.contentView.scroll(to: NSPoint(x: 0, y: sourceOffsets[10]))
        XCTAssertEqual(formattedScroll.contentView.bounds.minY, formattedOffsets[10], accuracy: 1)

        // Scrolling the side without focus moves nothing; that is the text changing under it.
        formattedScroll.contentView.scroll(to: NSPoint(x: 0, y: formattedOffsets[3]))
        XCTAssertEqual(sourceScroll.contentView.bounds.minY, sourceOffsets[10], accuracy: 1)

        // Once the formatted side has focus, it leads.
        window.makeFirstResponder(formatted)
        formattedScroll.contentView.scroll(to: NSPoint(x: 0, y: formattedOffsets[20]))
        XCTAssertEqual(sourceScroll.contentView.bounds.minY, sourceOffsets[20], accuracy: 1)

        sync.detach(sourceScroll)
        formattedScroll.contentView.scroll(to: NSPoint(x: 0, y: formattedOffsets[5]))
        XCTAssertEqual(sourceScroll.contentView.bounds.minY, sourceOffsets[20], accuracy: 1)
    }
}
