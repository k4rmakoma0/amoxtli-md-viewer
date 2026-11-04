import AppKit
import SwiftUI
import XCTest
@testable import Amoxtli

@MainActor
final class RichHeadingInputTests: XCTestCase {
    private func makeView(_ markdown: String = "") throws -> RichTextView {
        let view = RichTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.show(RichDocumentBuilder.paragraphs(from: try MarkdownParser().parse(markdown)))
        return view
    }

    private func type(_ text: String, in view: RichTextView) {
        for character in text {
            view.insertText(String(character), replacementRange: view.selectedRange())
        }
    }

    private func markdown(of view: RichTextView) -> String {
        MarkdownSerializer.markdown(from: view.paragraphs)
    }

    func testHeadingConvertsWhenItsFirstContentIsTyped() throws {
        let view = try makeView()
        type("# ", in: view)
        XCTAssertEqual(view.string, "# ")
        XCTAssertEqual(view.paragraphs.first?.block, .paragraph)

        type("T", in: view)
        XCTAssertEqual(view.string, "T")
        XCTAssertEqual(view.paragraphs.first?.block, .heading(level: 1))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 0))

        type("ítulo", in: view)
        XCTAssertEqual(markdown(of: view), "# Título\n")
    }

    func testAllHeadingLevelsAndTabSeparator() throws {
        for level in 1...6 {
            let view = try makeView()
            let hashes = String(repeating: "#", count: level)
            type(hashes + "\tTítulo", in: view)
            XCTAssertEqual(view.string, "Título")
            XCTAssertEqual(view.paragraphs.first?.block, .heading(level: level))
            XCTAssertEqual(markdown(of: view), hashes + " Título\n")
        }
    }

    func testHashWithoutSeparatorAndHashesInsideTextStayLiteral() throws {
        for text in ["#etiqueta", "####### Título", "Texto # título", " # Título"] {
            let view = try makeView()
            type(text, in: view)
            XCTAssertEqual(view.string, text)
            XCTAssertEqual(view.paragraphs.first?.block, .paragraph)
        }
    }

    func testEscapedHashIsShownWithoutBackslashAndStaysLiteral() throws {
        let view = try makeView()
        type("\\#", in: view)
        XCTAssertEqual(view.string, "#")

        type(" Título", in: view)
        XCTAssertEqual(view.string, "# Título")
        XCTAssertEqual(view.paragraphs.first?.block, .paragraph)
        XCTAssertEqual(markdown(of: view), "\\# Título\n")
    }

    func testEscapedHeadingRemainsLiteralAfterRestylingAndReopening() throws {
        let view = try makeView()
        type("\\## Título", in: view)
        view.setSelectedRange(NSRange(location: 3, length: "Título".utf16.count))
        view.apply(.bold, actionName: "")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        type("Otro ", in: view)
        XCTAssertEqual(view.paragraphs.first?.block, .paragraph)
        XCTAssertEqual(view.string, "## Otro Título")

        let reopened = try makeView(markdown(of: view))
        reopened.setSelectedRange(NSRange(location: 3, length: "Otro Título".utf16.count))
        reopened.insertText("Nuevo", replacementRange: reopened.selectedRange())
        XCTAssertEqual(reopened.string, "## Nuevo")
        XCTAssertEqual(reopened.paragraphs.first?.block, .paragraph)
        XCTAssertEqual(try MarkdownParser().parse(markdown(of: reopened)).blocks.count, 1)
    }

    func testLoadedLiteralHeadingPrefixIsNotReinterpretedWhileEditing() throws {
        let view = try makeView("\\# Título")
        view.setSelectedRange(NSRange(location: 2, length: "Título".utf16.count))
        view.insertText("Nuevo", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "# Nuevo")
        XCTAssertEqual(markdown(of: view), "\\# Nuevo\n")
        XCTAssertEqual(view.paragraphs.first?.block, .paragraph)
    }

    func testEditingElsewhereKeepsAnExistingLiteralBackslash() throws {
        let view = try makeView("\\\\# literal")
        XCTAssertEqual(view.string, "\\# literal")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        type("!", in: view)
        XCTAssertEqual(view.string, "\\# literal!")
        XCTAssertEqual(markdown(of: view), "\\\\# literal!\n")
    }

    func testLiteralMarkerMetadataDoesNotSplitLoadedInlineCode() throws {
        let view = try makeView("`# literal`")
        XCTAssertEqual(markdown(of: view), "`# literal`\n")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        type("!", in: view)
        XCTAssertEqual(markdown(of: view), "`# literal!`\n")
    }

    func testHeadingPreservesInlineFormatting() throws {
        let view = try makeView()
        type("## ", in: view)
        view.apply(.bold, actionName: "")
        type("Título", in: view)
        XCTAssertEqual(view.paragraphs.first?.block, .heading(level: 2))
        XCTAssertTrue(view.paragraphs.first?.runs.allSatisfy { $0.style.contains(.strong) } == true)
        XCTAssertEqual(markdown(of: view), "## **Título**\n")
    }

    func testAttributedHeadingInputKeepsTypingStyle() throws {
        let view = try makeView()
        view.apply(.bold, actionName: "")
        view.insertText(NSAttributedString(string: "# Título"), replacementRange: view.selectedRange())
        XCTAssertEqual(markdown(of: view), "# **Título**\n")
    }

    func testAttributedEscapeInputKeepsListAndQuoteContainers() throws {
        for source in ["- texto", "> texto"] {
            let view = try makeView(source)
            let containers = try XCTUnwrap(view.paragraphs.first?.containers)
            view.selectAll(nil)
            view.insertText(NSAttributedString(string: "\\# literal"), replacementRange: view.selectedRange())
            XCTAssertEqual(view.string, "# literal")
            XCTAssertEqual(view.paragraphs.first?.block, .paragraph)
            XCTAssertEqual(view.paragraphs.first?.containers, containers)
        }
    }

    func testHeadingPreservesListAndQuoteContainers() throws {
        for source in ["- texto", "> texto"] {
            let view = try makeView(source)
            let containers = try XCTUnwrap(view.paragraphs.first?.containers)
            view.selectAll(nil)
            type("## Título", in: view)
            XCTAssertEqual(view.string, "Título")
            XCTAssertEqual(view.paragraphs.first?.block, .heading(level: 2))
            XCTAssertEqual(view.paragraphs.first?.containers, containers)
        }
    }

    func testCodeAndTableCellsKeepTypedHashes() throws {
        for source in ["```\ntexto\n```", "| A |\n|---|\n| texto |"] {
            let view = try makeView(source)
            let originalBlock = view.paragraphs.first?.block
            view.setSelectedRange(NSRange(location: 0, length: view.paragraphs.first?.plainText.utf16.count ?? 0))
            type("# Título", in: view)
            XCTAssertEqual(view.paragraphs.first?.plainText, "# Título")
            XCTAssertEqual(view.paragraphs.first?.block, originalBlock)
        }
    }

    func testInlineCodeKeepsTypedHashes() throws {
        let view = try makeView()
        view.apply(.inlineCode, actionName: "")
        type("# Título", in: view)
        XCTAssertEqual(view.string, "# Título")
        XCTAssertEqual(view.paragraphs.first?.block, .paragraph)
        XCTAssertEqual(markdown(of: view), "`# Título`\n")
    }

    func testMultilineInsertionStaysPlainText() throws {
        let view = try makeView()
        view.insertText("# Título\nTexto", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "# Título\nTexto")
        XCTAssertTrue(view.paragraphs.allSatisfy { $0.block == .paragraph })
    }

    func testHeadingCaretUsesUTF16Offsets() throws {
        let view = try makeView("🌮")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.insertNewline(nil)
        type("### 🐱", in: view)
        XCTAssertEqual(view.string, "🌮\n🐱")
        XCTAssertEqual(view.paragraphs.last?.block, .heading(level: 3))
        XCTAssertEqual(view.selectedRange(), NSRange(location: "🌮\n🐱".utf16.count, length: 0))
        XCTAssertEqual(markdown(of: view), "🌮\n\n### 🐱\n")
    }

    func testInputMethodConvertsOnlyAfterCommittingComposition() throws {
        let view = try makeView()
        type("# ", in: view)
        let unspecified = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: unspecified)
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.string, "# 仮")
        XCTAssertEqual(view.paragraphs.first?.block, .paragraph)

        view.insertText(NSAttributedString(string: "見出し"), replacementRange: unspecified)
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.string, "見出し")
        XCTAssertEqual(view.paragraphs.first?.block, .heading(level: 1))
        XCTAssertEqual(view.selectedRange(), NSRange(location: "見出し".utf16.count, length: 0))
        XCTAssertEqual(markdown(of: view), "# 見出し\n")
    }

    func testReturnAfterTypedHeadingContinuesWithBodyText() throws {
        let view = try makeView()
        type("# Título", in: view)
        view.insertNewline(nil)
        type("Texto", in: view)
        XCTAssertEqual(view.paragraphs.map(\.block), [.heading(level: 1), .paragraph])
        XCTAssertEqual(markdown(of: view), "# Título\n\nTexto\n")
    }

    func testCoordinatorWritesConvertedHeadingToMarkdownBinding() throws {
        var document = ""
        let binding = Binding(get: { document }, set: { document = $0 })
        let coordinator = RichEditor.Coordinator(text: binding)
        let view = try makeView()
        view.delegate = coordinator
        coordinator.show(document, in: view)

        type("## Título", in: view)
        XCTAssertEqual(document, "## Título\n")
        XCTAssertEqual(coordinator.shownText, document)
        XCTAssertEqual(view.string, "Título")
    }

    func testUndoAndRedoRestoreHeadingPrefixAndKindTogether() throws {
        let view = try makeView()
        let delegate = UndoDelegate()
        delegate.manager.groupsByEvent = false
        view.delegate = delegate
        delegate.manager.beginUndoGrouping()
        type("# ", in: view)
        view.breakUndoCoalescing()
        delegate.manager.endUndoGrouping()
        delegate.manager.removeAllActions()

        delegate.manager.beginUndoGrouping()
        type("T", in: view)
        view.breakUndoCoalescing()
        delegate.manager.endUndoGrouping()
        XCTAssertEqual(view.paragraphs.first?.block, .heading(level: 1))
        XCTAssertTrue(delegate.manager.canUndo)

        delegate.manager.undo()
        XCTAssertEqual(view.string, "# ")
        XCTAssertEqual(view.paragraphs.first?.block, .paragraph)

        delegate.manager.redo()
        XCTAssertEqual(view.string, "T")
        XCTAssertEqual(view.paragraphs.first?.block, .heading(level: 1))
    }
}

@MainActor
private final class UndoDelegate: NSObject, NSTextViewDelegate {
    let manager = UndoManager()

    func undoManager(for view: NSTextView) -> UndoManager? {
        manager
    }
}
