import AppKit
import XCTest
@testable import Amoxtli

final class CodeLanguageLabelTests: XCTestCase {
    func testKnownLanguagesShowTheirName() {
        XCTAssertEqual(CodeLanguage.label(forFenceInfo: "js"), "JavaScript")
        XCTAssertEqual(CodeLanguage.label(forFenceInfo: "bash"), "Shell")
    }

    func testOtherLanguagesShowTheirWord() {
        XCTAssertEqual(CodeLanguage.label(forFenceInfo: "rust title=\"a\""), "rust")
    }

    func testNoLanguageNoLabel() {
        XCTAssertNil(CodeLanguage.label(forFenceInfo: nil))
        XCTAssertNil(CodeLanguage.label(forFenceInfo: " "))
    }

    func testFenceInfo() {
        let text = "  ```swift  \n~~~ py\n```\n"
        XCTAssertEqual(MarkdownSyntaxScanner.fenceInfo(NSRange(location: 0, length: 12), in: text), "swift")
        XCTAssertEqual(MarkdownSyntaxScanner.fenceInfo(NSRange(location: 13, length: 6), in: text), "py")
        XCTAssertEqual(MarkdownSyntaxScanner.fenceInfo(NSRange(location: 20, length: 3), in: text), "")
    }
}

private func color(of text: String, in storage: NSAttributedString, occurrence: Int = 0) -> NSColor? {
    let source = storage.string as NSString
    var range = NSRange(location: 0, length: 0)
    var start = 0
    for _ in 0...occurrence {
        range = source.range(of: text, range: NSRange(location: start, length: source.length - start))
        start = NSMaxRange(range)
    }
    guard range.location != NSNotFound else { return nil }
    return storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
}

@MainActor
final class RichCodeHighlightingTests: XCTestCase {
    private func makeView(_ markdown: String) throws -> RichTextView {
        let view = RichTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.show(RichDocumentBuilder.paragraphs(from: try MarkdownParser().parse(markdown)))
        return view
    }

    private func markdown(of view: RichTextView) -> String {
        MarkdownSerializer.markdown(from: view.paragraphs)
    }

    private func placeCaret(after text: String, in view: RichTextView) {
        let found = (view.string as NSString).range(of: text)
        view.setSelectedRange(NSRange(location: NSMaxRange(found), length: 0))
    }

    func testCodeIsColoredByItsLanguage() throws {
        let view = try makeView("```swift\nlet a = \"x\" // nota\n```")
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertEqual(color(of: "let", in: storage), CodeColors.color(for: .keyword))
        XCTAssertEqual(color(of: "\"x\"", in: storage), CodeColors.color(for: .string))
        XCTAssertEqual(color(of: "// nota", in: storage), CodeColors.color(for: .comment))
        XCTAssertEqual(color(of: " = ", in: storage), .labelColor)
    }

    func testCommentSpanningLinesIsColoredOnEachLine() throws {
        let view = try makeView("```js\n/* uno\ndos */ let\n```")
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertEqual(color(of: "dos", in: storage), CodeColors.color(for: .comment))
        XCTAssertEqual(color(of: "let", in: storage), CodeColors.color(for: .keyword))
    }

    func testCodeWithoutAKnownLanguageIsPlain() throws {
        let view = try makeView("```\nlet a\n```\n\n```cobol\nlet b\n```")
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertEqual(color(of: "let", in: storage), .labelColor)
        XCTAssertEqual(color(of: "let", in: storage, occurrence: 1), .labelColor)
    }

    func testTypingRecolors() throws {
        let view = try makeView("```python\nx = 1\n```")
        placeCaret(after: "x = 1", in: view)
        view.insertText(" # fin", replacementRange: view.selectedRange())
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertEqual(color(of: "# fin", in: storage), CodeColors.color(for: .comment))
        XCTAssertEqual(color(of: "1", in: storage), CodeColors.color(for: .number))
    }

    func testOpeningAStringRecolorsTheLinesBelow() throws {
        let view = try makeView("```python\nx\ny = 1\n```")
        placeCaret(after: "x", in: view)
        view.insertText(" = \"\"\"", replacementRange: view.selectedRange())
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertEqual(color(of: "y = 1", in: storage), CodeColors.color(for: .string))
    }

    func testChoosingALanguageWritesTheFenceAndColors() throws {
        let view = try makeView("```\nlet a\nvar b\n```\n\nfin")
        placeCaret(after: "var b", in: view)
        XCTAssertEqual(view.codeLanguageAtCaret, .some(nil))
        view.setCodeLanguage("swift")
        XCTAssertEqual(markdown(of: view), "```swift\nlet a\nvar b\n```\n\nfin\n")
        XCTAssertEqual(view.codeLanguageAtCaret, .some("swift"))
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertEqual(color(of: "let", in: storage), CodeColors.color(for: .keyword))
        XCTAssertEqual(color(of: "var", in: storage), CodeColors.color(for: .keyword))
    }

    func testRemovingTheLanguage() throws {
        let view = try makeView("```swift\nlet a\n```")
        placeCaret(after: "let", in: view)
        view.setCodeLanguage(nil)
        XCTAssertEqual(markdown(of: view), "```\nlet a\n```\n")
        XCTAssertEqual(color(of: "let", in: try XCTUnwrap(view.textStorage)), .labelColor)
    }

    func testRightClickInCodeOffersTheLanguage() throws {
        let view = try makeView("texto\n\n```\nlet b\n```")
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        placeCaret(after: "tex", in: view)
        func menuTitles(at text: String) throws -> [String] {
            let layoutManager = try XCTUnwrap(view.layoutManager)
            let container = try XCTUnwrap(view.textContainer)
            let glyphs = layoutManager.glyphRange(forCharacterRange: (view.string as NSString).range(of: text), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            let point = NSPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y)
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .rightMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            return view.menu(for: event)?.items.map(\.title) ?? []
        }
        XCTAssertTrue(try menuTitles(at: "let b").contains(String(localized: "Lenguaje")))
        XCTAssertFalse(try menuTitles(at: "texto").contains(String(localized: "Lenguaje")))
    }

    private func location(of text: String, in view: RichTextView) -> Int {
        (view.string as NSString).range(of: text).location
    }

    func testEveryCodeBlockHasAChipThatFindsItsBlock() throws {
        let view = try makeView("texto\n\n```\n{\n}\n```\n\n```js\nlet x\n```")
        for start in [location(of: "{", in: view), location(of: "let x", in: view)] {
            let chip = try XCTUnwrap(view.codeChipRect(forBlockAt: start))
            XCTAssertEqual(view.codeBlock(withChipAt: NSPoint(x: chip.midX, y: chip.midY)), start)
        }
        XCTAssertNil(view.codeChipRect(forBlockAt: location(of: "texto", in: view)))
    }

    func testABlockThatStartsTheTextHasItsChipInTheMargin() throws {
        let view = try makeView("```\n{}\n```")
        let chip = try XCTUnwrap(view.codeChipRect(forBlockAt: 0))
        XCTAssertGreaterThan(chip.minY, 0)
        XCTAssertLessThan(chip.maxY, view.textContainerOrigin.y)
        XCTAssertEqual(view.codeBlock(withChipAt: NSPoint(x: chip.midX, y: chip.midY)), 0)
    }

    private func usedRect(of text: String, in view: RichTextView) throws -> NSRect {
        let layoutManager = try XCTUnwrap(view.layoutManager)
        layoutManager.ensureLayout(for: try XCTUnwrap(view.textContainer))
        let glyph = layoutManager.glyphIndexForCharacter(at: location(of: text, in: view))
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    func testReturnAtTheEndOfTheTextKeepsTheNewLineInTheBlock() throws {
        for markdown in ["```swift\nfunc {\n```", "texto\n\n```swift\nfunc {\n```"] {
            let view = try makeView(markdown)
            placeCaret(after: "func {", in: view)
            let before = try usedRect(of: "func {", in: view)
            view.insertNewline(nil)
            let layoutManager = try XCTUnwrap(view.layoutManager)
            layoutManager.ensureLayout(for: try XCTUnwrap(view.textContainer))
            let emptyLine = layoutManager.extraLineFragmentUsedRect
            XCTAssertEqual(try usedRect(of: "func {", in: view), before, markdown)
            XCTAssertEqual(emptyLine.minY, before.maxY, accuracy: 0.5, markdown)
            view.insertText("aaa", replacementRange: view.selectedRange())
            XCTAssertEqual(try usedRect(of: "aaa", in: view).minY, emptyLine.minY, accuracy: 0.5, markdown)
            XCTAssertEqual(try usedRect(of: "func {", in: view), before, markdown)
        }
    }

    func testTextIsNotTheChip() throws {
        let view = try makeView("```\nlet x\n```")
        let layoutManager = try XCTUnwrap(view.layoutManager)
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: 3), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: try XCTUnwrap(view.textContainer))
        let point = NSPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y)
        XCTAssertNil(view.codeBlock(withChipAt: point))
    }

    func testChipMenuChoosesTheLanguageOfItsBlock() throws {
        let view = try makeView("```\n{}\n```\n\nfin")
        placeCaret(after: "fin", in: view)
        let menu = try XCTUnwrap(view.languageMenu(forBlockAt: 0))
        let json = try XCTUnwrap(menu.items.first { $0.title == "JSON" })
        try XCTUnwrap(json.target as? MenuAction).invoke()
        XCTAssertEqual(markdown(of: view), "```json\n{}\n```\n\nfin\n")
    }

    func testChipMenuKeepsTheCaretInsideTheBlock() throws {
        let view = try makeView("```\nuno\ndos\n```")
        placeCaret(after: "do", in: view)
        let caret = view.selectedRange()
        _ = view.languageMenu(forBlockAt: 0)
        XCTAssertEqual(view.selectedRange(), caret)
    }

    func testOutsideCodeThereIsNoLanguage() throws {
        let view = try makeView("texto")
        placeCaret(after: "tex", in: view)
        XCTAssertNil(view.codeLanguageAtCaret)
        view.setCodeLanguage("swift")
        XCTAssertEqual(markdown(of: view), "texto\n")
    }

    func testOtherBlocksKeepTheirLanguage() throws {
        let view = try makeView("```js\nlet a\n```\n\n```\nlet b\n```")
        placeCaret(after: "let b", in: view)
        view.setCodeLanguage("python")
        XCTAssertEqual(markdown(of: view), "```js\nlet a\n```\n\n```python\nlet b\n```\n")
    }
}

@MainActor
final class SourceCodeHighlightingTests: XCTestCase {
    private func highlighted(_ text: String) -> (NSTextStorage, SourceHighlighter) {
        let highlighter = SourceHighlighter()
        let storage = NSTextStorage()
        storage.delegate = highlighter
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        return (storage, highlighter)
    }

    private func insert(_ text: String, after anchor: String, in storage: NSTextStorage) {
        let found = (storage.string as NSString).range(of: anchor)
        storage.replaceCharacters(in: NSRange(location: NSMaxRange(found), length: 0), with: text)
    }

    func testFencedCodeIsColoredByItsLanguage() {
        let (storage, highlighter) = highlighted("```swift\nlet a = 1\n```\nlet fuera")
        XCTAssertEqual(color(of: "let", in: storage), CodeColors.color(for: .keyword))
        XCTAssertEqual(color(of: "1", in: storage), CodeColors.color(for: .number))
        XCTAssertEqual(color(of: "let", in: storage, occurrence: 1), .labelColor)
        XCTAssertEqual(color(of: "swift", in: storage), .secondaryLabelColor)
        withExtendedLifetime(highlighter) {}
    }

    func testFenceWithoutLanguageIsPlain() {
        let (storage, highlighter) = highlighted("```\nlet a\n```")
        XCTAssertEqual(color(of: "let", in: storage), .labelColor)
        withExtendedLifetime(highlighter) {}
    }

    func testEditingALineRecolorsTheWholeBlock() {
        let (storage, highlighter) = highlighted("```js\n/* a\nb\nc */ let x\n```")
        XCTAssertEqual(color(of: "let", in: storage), CodeColors.color(for: .keyword))
        insert("x", after: "b", in: storage)
        XCTAssertEqual(color(of: "c */", in: storage), CodeColors.color(for: .comment))
        XCTAssertEqual(color(of: "let", in: storage), CodeColors.color(for: .keyword))
        withExtendedLifetime(highlighter) {}
    }

    func testTypingTheLanguageColorsTheBlock() {
        let (storage, highlighter) = highlighted("```\nlet a\n```")
        insert("swift", after: "```", in: storage)
        XCTAssertEqual(color(of: "let", in: storage), CodeColors.color(for: .keyword))
        withExtendedLifetime(highlighter) {}
    }

    func testUnclosedBlockIsColoredToTheEnd() {
        let (storage, highlighter) = highlighted("texto\n```py\ndef f():\n    return 1")
        XCTAssertEqual(color(of: "return", in: storage), CodeColors.color(for: .keyword))
        withExtendedLifetime(highlighter) {}
    }

    func testClosingTheBlockStopsTheColors() {
        let (storage, highlighter) = highlighted("```py\nx = 1\nif y")
        XCTAssertEqual(color(of: "if", in: storage), CodeColors.color(for: .keyword))
        insert("\n```", after: "x = 1", in: storage)
        XCTAssertEqual(color(of: "if", in: storage), .labelColor)
        withExtendedLifetime(highlighter) {}
    }
}

@MainActor
final class CodeLanguageMenuTests: XCTestCase {
    private func titlesAndStates(_ current: String?) -> [String] {
        let item = EditingContextMenu.languageItem(CodeLanguageChoice(current: current) { _ in })
        return (item.submenu?.items ?? []).map { $0.isSeparatorItem ? "-" : ($0.state == .on ? "✓" : "") + $0.title }
    }

    func testListsNoLanguageThenTheLanguagesByName() {
        XCTAssertEqual(titlesAndStates(nil), [
            "✓" + String(localized: "Ninguno"), "-",
            "CSS", "HTML", "JavaScript", "JSON", "Python", "Shell", "SQL", "Swift", "TypeScript",
        ])
    }

    func testChecksTheCurrentLanguage() {
        XCTAssertTrue(titlesAndStates("ts").contains("✓TypeScript"))
        XCTAssertFalse(titlesAndStates("ts").contains("✓" + String(localized: "Ninguno")))
    }

    func testShowsALanguageItDoesNotKnow() {
        XCTAssertEqual(titlesAndStates("rust").prefix(2), ["✓rust", String(localized: "Ninguno")])
    }

    func testChoosingCallsBack() {
        var chosen: String?? = .none
        let item = EditingContextMenu.languageItem(CodeLanguageChoice(current: nil) { chosen = .some($0) })
        let swift = item.submenu?.items.first { $0.title == "Swift" }
        _ = (swift?.target as? MenuAction).map { $0.invoke() }
        XCTAssertEqual(chosen, .some("swift"))
    }
}
