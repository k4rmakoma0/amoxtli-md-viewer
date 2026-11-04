import AppKit
import XCTest
@testable import Amoxtli

@MainActor
final class RichTextViewTests: XCTestCase {
    private func makeView(_ markdown: String) throws -> RichTextView {
        let view = RichTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.show(RichDocumentBuilder.paragraphs(from: try MarkdownParser().parse(markdown)))
        return view
    }

    private func markdown(of view: RichTextView) -> String {
        MarkdownSerializer.markdown(from: view.paragraphs)
    }

    /// Puts the caret right after the first occurrence of `text`.
    private func placeCaret(after text: String, in view: RichTextView) {
        let found = (view.string as NSString).range(of: text)
        view.setSelectedRange(NSRange(location: NSMaxRange(found), length: 0))
    }

    private func select(_ text: String, in view: RichTextView) {
        view.setSelectedRange((view.string as NSString).range(of: text))
    }

    // MARK: - Conversion

    func testParagraphsSurviveTheTextView() throws {
        let source = "# Título\n\nTexto **fuerte** y [enlace](https://a.b).\n\n- uno\n  - dos\n\n> cita\n\n```\ncódigo\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n---\n"
        let paragraphs = RichDocumentBuilder.paragraphs(from: try MarkdownParser().parse(source))
        let view = RichTextView.make()
        view.show(paragraphs)
        XCTAssertEqual(view.paragraphs, paragraphs)
    }

    func testNoMarkdownSyntaxIsShown() throws {
        let view = try makeView("# Título\n\n**fuerte** y `código`\n\n- uno")
        XCTAssertEqual(view.string, "Título\nfuerte y código\nuno")
    }

    // MARK: - Return

    func testReturnInListStartsANewItem() throws {
        let view = try makeView("- uno")
        placeCaret(after: "uno", in: view)
        view.insertNewline(nil)
        view.insertText("dos", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "- uno\n- dos\n")
    }

    func testReturnOnEmptyItemLeavesTheList() throws {
        let view = try makeView("- uno")
        placeCaret(after: "uno", in: view)
        view.insertNewline(nil)
        view.insertNewline(nil)
        view.insertText("fuera", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "- uno\n\nfuera\n")
    }

    func testReturnAtEndOfHeadingContinuesWithBodyText() throws {
        let view = try makeView("# Título\n\nTexto")
        placeCaret(after: "Título", in: view)
        view.insertNewline(nil)
        view.insertText("nuevo", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "# Título\n\nnuevo\n\nTexto\n")
    }

    func testReturnInTableMovesToTheNextCell() throws {
        let view = try makeView("| A | B |\n|---|---|\n| 1 | 2 |")
        placeCaret(after: "A", in: view)
        view.insertNewline(nil)
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "B")
    }

    // MARK: - Delete

    func testDeleteAtStartOfItemRemovesTheBullet() throws {
        let view = try makeView("Texto\n\n- uno")
        placeCaret(after: "\n", in: view)
        view.deleteBackward(nil)
        XCTAssertEqual(markdown(of: view), "Texto\n\nuno\n")
    }

    func testDeleteAtStartOfHeadingMakesItBodyText() throws {
        let view = try makeView("Texto\n\n## Título")
        placeCaret(after: "\n", in: view)
        view.deleteBackward(nil)
        XCTAssertEqual(markdown(of: view), "Texto\n\nTítulo\n")
    }

    func testDeleteJoinsParagraphsKeepingTheFirstOnesKind() throws {
        let view = try makeView("# Título\n\nTexto")
        placeCaret(after: "\n", in: view)
        view.deleteBackward(nil)
        XCTAssertEqual(markdown(of: view), "# TítuloTexto\n")
    }

    // MARK: - Deleting all of an element's text

    /// Selects a paragraph's text and deletes it, then types in the emptied line.
    private func replaceText(_ text: String, with typed: String, in view: RichTextView) {
        select(text, in: view)
        view.deleteBackward(nil)
        view.insertText(typed, replacementRange: view.selectedRange())
    }

    func testEmptiedListItemBecomesBodyText() throws {
        let view = try makeView("- uno")
        replaceText("uno", with: "texto", in: view)
        XCTAssertEqual(markdown(of: view), "texto\n")
    }

    func testEmptiedItemInTheMiddleLeavesTheOtherItems() throws {
        let view = try makeView("1. uno\n2. dos\n3. tres")
        replaceText("dos", with: "texto", in: view)
        XCTAssertEqual(markdown(of: view), "1. uno\n\ntexto\n\n2. tres\n")
    }

    func testEmptiedQuoteBecomesBodyText() throws {
        let view = try makeView("> cita")
        replaceText("cita", with: "texto", in: view)
        XCTAssertEqual(markdown(of: view), "texto\n")
    }

    func testEmptiedSingleLineCodeBlockBecomesBodyText() throws {
        let view = try makeView("```\ncódigo\n```")
        replaceText("código", with: "texto", in: view)
        XCTAssertEqual(markdown(of: view), "texto\n")
    }

    func testEmptiedLineInsideLongerCodeBlockStaysCode() throws {
        let view = try makeView("```\nuno\ndos\ntres\n```")
        select("dos", in: view)
        view.deleteBackward(nil)
        XCTAssertEqual(markdown(of: view), "```\nuno\n\ntres\n```\n")
    }

    func testEmptiedTableCellStaysInTheTable() throws {
        let view = try makeView("| A | B |\n|---|---|\n| 1 | 2 |")
        select("1", in: view)
        view.deleteBackward(nil)
        XCTAssertEqual(markdown(of: view), "| A | B |\n| --- | --- |\n|  | 2 |\n")
    }

    func testDeletingPartOfAnItemKeepsIt() throws {
        let view = try makeView("- uno")
        placeCaret(after: "uno", in: view)
        view.deleteBackward(nil)
        XCTAssertEqual(markdown(of: view), "- un\n")
    }

    // MARK: - Code blocks

    func testReturnAddsBlankLinesInsideACodeBlock() throws {
        let view = try makeView("```\nuno\n```\n\nfin")
        placeCaret(after: "uno", in: view)
        view.insertNewline(nil)
        view.insertNewline(nil)
        view.insertText("dos", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "```\nuno\n\ndos\n```\n\nfin\n")
    }

    func testReturnAtTheEndOfTheDocumentStaysInTheCodeBlock() throws {
        let view = try makeView("```\nuno\n```")
        placeCaret(after: "uno", in: view)
        view.insertNewline(nil)
        view.insertNewline(nil)
        view.insertText("dos", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "```\nuno\n\ndos\n```\n")
    }

    func testDownArrowLeavesACodeBlockAtTheEnd() throws {
        let view = try makeView("```\nuno\n```")
        placeCaret(after: "uno", in: view)
        view.moveDown(nil)
        view.insertText("texto", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "```\nuno\n```\n\ntexto\n")
    }

    func testDownArrowFromAnEmptyLastCodeLineLeavesTheBlock() throws {
        let view = try makeView("```\nuno\n```")
        placeCaret(after: "uno", in: view)
        view.insertNewline(nil)
        view.moveDown(nil)
        view.insertText("texto", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "```\nuno\n```\n\ntexto\n")
    }

    func testDownArrowInsideACodeBlockMovesToTheNextLine() throws {
        let view = try makeView("```\nuno\ndos\n```")
        placeCaret(after: "uno", in: view)
        view.moveDown(nil)
        XCTAssertTrue(view.kind(at: view.selectedRange().location).isCode)
        XCTAssertEqual(markdown(of: view), "```\nuno\ndos\n```\n")
    }

    // MARK: - Tab

    func testTabNestsAnItemUnderTheOneAbove() throws {
        let view = try makeView("- uno\n- dos")
        placeCaret(after: "do", in: view)
        view.insertTab(nil)
        XCTAssertEqual(markdown(of: view), "- uno\n  - dos\n")
        view.insertBacktab(nil)
        XCTAssertEqual(markdown(of: view), "- uno\n- dos\n")
    }

    // MARK: - Tools

    func testBoldWritesMarkdown() throws {
        let view = try makeView("Hola mundo")
        select("mundo", in: view)
        view.apply(.bold, actionName: "")
        XCTAssertEqual(markdown(of: view), "Hola **mundo**\n")
        view.apply(.bold, actionName: "")
        XCTAssertEqual(markdown(of: view), "Hola mundo\n")
    }

    func testBoldWithoutSelectionAppliesToTyping() throws {
        let view = try makeView("Hola")
        placeCaret(after: "Hola", in: view)
        view.apply(.bold, actionName: "")
        view.insertText(" mundo", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "Hola **mundo**\n")
    }

    func testHeadingToolTogglesTheParagraph() throws {
        let view = try makeView("Título")
        placeCaret(after: "Tít", in: view)
        view.apply(.heading(2), actionName: "")
        XCTAssertEqual(markdown(of: view), "## Título\n")
        view.apply(.heading(2), actionName: "")
        XCTAssertEqual(markdown(of: view), "Título\n")
    }

    func testListToolsSwitchAndRemove() throws {
        let view = try makeView("uno\n\ndos")
        view.selectAll(nil)
        view.apply(.bulletList, actionName: "")
        XCTAssertEqual(markdown(of: view), "- uno\n- dos\n")
        view.apply(.numberedList, actionName: "")
        XCTAssertEqual(markdown(of: view), "1. uno\n2. dos\n")
        view.apply(.numberedList, actionName: "")
        XCTAssertEqual(markdown(of: view), "uno\n\ndos\n")
    }

    func testQuoteAndCodeBlockTools() throws {
        let view = try makeView("cita")
        view.selectAll(nil)
        view.apply(.quote, actionName: "")
        XCTAssertEqual(markdown(of: view), "> cita\n")
        view.apply(.quote, actionName: "")
        view.apply(.codeBlock, actionName: "")
        XCTAssertEqual(markdown(of: view), "```\ncita\n```\n")
    }

    func testLinkToolLinksTheSelection() throws {
        let view = try makeView("Visita Amoxtli")
        select("Amoxtli", in: view)
        view.apply(.link(text: "Amoxtli", destination: "https://amoxtli.dev"), actionName: "")
        XCTAssertEqual(markdown(of: view), "Visita [Amoxtli](https://amoxtli.dev)\n")
    }

    func testTableToolInsertsAnEditableTable() throws {
        let view = try makeView("Texto")
        placeCaret(after: "Texto", in: view)
        view.apply(.table(.standard), actionName: "")
        view.insertText("Nombre", replacementRange: view.selectedRange())
        let header = String(localized: "Columna 2")
        XCTAssertEqual(markdown(of: view), "Texto\n\n| Nombre | \(header) |\n| --- | --- |\n|  |  |\n")
    }

    func testRuleToolInsertsADivider() throws {
        let view = try makeView("Texto")
        placeCaret(after: "Texto", in: view)
        view.apply(.horizontalRule, actionName: "")
        view.insertText("después", replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "Texto\n\n---\n\ndespués\n")
    }

    func testOtherTypedSyntaxStaysTextInsideAnAutomaticHeading() throws {
        let view = try makeView("")
        view.insertText("# Título *sin cursiva*", replacementRange: view.selectedRange())
        let written = markdown(of: view)
        XCTAssertEqual(try MarkdownParser().parse(written).blocks, [.heading(level: 1, content: InlineText(runs: [InlineRun(text: "Título *sin cursiva*")]))])
    }

    // MARK: - Accessibility

    private func listPrefix(of text: String, in view: RichTextView) -> String? {
        let location = (view.string as NSString).range(of: text).location
        return (view.textStorage?.attribute(.accessibilityListItemPrefix, at: location, effectiveRange: nil) as? NSAttributedString)?.string
    }

    func testListMarkersAreReadByVoiceOver() throws {
        let view = try makeView("1. uno\n2. dos\n   - anidado")
        XCTAssertEqual(listPrefix(of: "uno", in: view), "1. ")
        XCTAssertEqual(listPrefix(of: "dos", in: view), "2. ")
        XCTAssertEqual(listPrefix(of: "anidado", in: view), "◦ ")
        XCTAssertEqual(view.textStorage?.attribute(.accessibilityListItemLevel, at: (view.string as NSString).range(of: "anidado").location, effectiveRange: nil) as? Int, 1)
    }

    func testMarkersFollowEdits() throws {
        let view = try makeView("1. uno\n2. dos")
        placeCaret(after: "uno", in: view)
        view.insertNewline(nil)
        view.insertText("medio", replacementRange: view.selectedRange())
        XCTAssertEqual(listPrefix(of: "medio", in: view), "2. ")
        XCTAssertEqual(listPrefix(of: "dos", in: view), "3. ")
        view.selectAll(nil)
        view.apply(.numberedList, actionName: "")
        XCTAssertNil(listPrefix(of: "dos", in: view))
    }

    // MARK: - Active formatting

    func testCaretInsideStyledTextReportsItsStyles() throws {
        let view = try makeView("Texto **fuerte y *mixto*** normal")
        placeCaret(after: "mix", in: view)
        XCTAssertEqual(view.activeFormats.inline, [.strong, .emphasis])
        placeCaret(after: "norm", in: view)
        XCTAssertEqual(view.activeFormats.inline, [])
    }

    func testSelectionReportsOnlyWhatAllOfItHas() throws {
        let view = try makeView("**fuerte** suave")
        select("fuerte", in: view)
        XCTAssertEqual(view.activeFormats.inline, .strong)
        select("fuerte** suave".replacingOccurrences(of: "**", with: ""), in: view)
        XCTAssertEqual(view.activeFormats.inline, [])
    }

    func testBlocksAreReported() throws {
        let view = try makeView("## Título\n\n> 1. citado\n\n```\ncódigo\n```")
        placeCaret(after: "Títu", in: view)
        XCTAssertEqual(view.activeFormats.headingLevel, 2)
        placeCaret(after: "cita", in: view)
        XCTAssertTrue(view.activeFormats.isQuote)
        XCTAssertEqual(view.activeFormats.list, .numbered)
        placeCaret(after: "códi", in: view)
        XCTAssertTrue(view.activeFormats.isCodeBlock)
    }

    func testLinkIsReportedInsideIt() throws {
        let view = try makeView("Ver [Amoxtli](https://amoxtli.dev) hoy")
        placeCaret(after: "Amox", in: view)
        XCTAssertTrue(view.activeFormats.hasLink)
        placeCaret(after: "ho", in: view)
        XCTAssertFalse(view.activeFormats.hasLink)
    }

    func testToolbarFollowsTheCaretThroughTheController() throws {
        let view = try makeView("**fuerte** suave")
        let controller = EditorController()
        view.controller = controller
        controller.attach(view)
        placeCaret(after: "fuer", in: view)
        XCTAssertTrue(controller.isActive(.bold))
        placeCaret(after: "sua", in: view)
        XCTAssertFalse(controller.isActive(.bold))
        controller.perform(.bold)
        XCTAssertTrue(controller.isActive(.bold), "Bold with nothing selected applies to typing, so it shows as on")
        XCTAssertTrue(controller.isActive(.bodyText))
        XCTAssertFalse(controller.isActive(.table))
    }

    // MARK: - Empty last line

    /// The empty line after Return has no characters, only a style for typing; its marker is
    /// drawn from that style with the numbering that follows the text.
    private func markerOfEmptyLastLine(in view: RichTextView) throws -> [String] {
        let storage = try XCTUnwrap(view.textStorage)
        let kind = try XCTUnwrap(view.typingAttributes[.richParagraph] as? RichParagraphKind)
        var numbering = RichListMarker.numbering(of: storage).end
        return numbering.markers(for: kind.containers).map(\.text)
    }

    func testNewLastItemIsNumberedAfterTheOthers() throws {
        let view = try makeView("1. uno\n2. dos")
        placeCaret(after: "dos", in: view)
        view.insertNewline(nil)
        XCTAssertEqual(view.selectedRange().location, view.textStorage?.length)
        XCTAssertEqual(try markerOfEmptyLastLine(in: view), ["3."])
    }

    func testListStartedOnAnEmptyDocumentHasItsMarker() throws {
        let view = try makeView("")
        view.apply(.bulletList, actionName: "")
        XCTAssertEqual(try markerOfEmptyLastLine(in: view), ["•"])
    }
}
