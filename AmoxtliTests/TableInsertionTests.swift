import AppKit
import XCTest
@testable import Amoxtli

@MainActor
final class TableInsertionTests: XCTestCase {
    private func makeView(_ markdown: String = "") throws -> RichTextView {
        let view = RichTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.show(RichDocumentBuilder.paragraphs(from: try MarkdownParser().parse(markdown)))
        return view
    }

    private func firstTable(in markdown: String) throws -> MarkdownTable {
        let model = try MarkdownParser().parse(markdown)
        return try XCTUnwrap(model.blocks.compactMap { block -> MarkdownTable? in
            if case .table(let table) = block { return table }
            return nil
        }.first)
    }

    private func cells(in view: RichTextView) -> [RichTableCell] {
        view.paragraphs.compactMap { paragraph in
            if case .tableCell(let cell) = paragraph.block { return cell }
            return nil
        }
    }

    func testDimensionsRejectInvalidAndExcessiveCounts() {
        for (columns, rows) in [(0, 2), (-1, 2), (2, 0), (2, -1), (21, 2), (2, 101), (Int.max, Int.max)] {
            XCTAssertNil(TableDimensions(columns: columns, rows: rows))
        }
        XCTAssertNotNil(TableDimensions(columns: 1, rows: 1))
        XCTAssertNotNil(TableDimensions(columns: 20, rows: 100))
    }

    func testTableToolRequestsDimensionsWithoutEditing() {
        let controller = EditorController()
        let target = TableFormattingTarget()
        controller.attach(target)

        controller.perform(.table)

        XCTAssertTrue(controller.isInsertingTable)
        XCTAssertTrue(target.commands.isEmpty)
        XCTAssertEqual(target.focusCount, 0)
    }

    func testCancellingTableRequestDoesNotInsertAnything() {
        let controller = EditorController()
        let target = TableFormattingTarget()
        controller.attach(target)
        controller.perform(.table)

        // Dismissing the sheet clears its presentation binding without confirming insertion.
        controller.isInsertingTable = false

        XCTAssertTrue(target.commands.isEmpty)
        controller.perform(.table)
        XCTAssertTrue(controller.isInsertingTable)
        XCTAssertTrue(target.commands.isEmpty)
    }

    func testFormattingDoesNotChangeTheDocumentWhileDimensionsArePending() {
        let controller = EditorController()
        let target = TableFormattingTarget()
        controller.attach(target)
        controller.perform(.table)

        controller.perform(.bold)

        XCTAssertTrue(controller.isInsertingTable)
        XCTAssertTrue(target.commands.isEmpty)
    }

    func testTableToolDoesNotPresentWithoutAnEditor() {
        let controller = EditorController()
        controller.perform(.table)
        XCTAssertFalse(controller.isInsertingTable)
    }

    func testConfirmationInsertsRequestedDimensionsIntoActiveEditor() throws {
        let controller = EditorController()
        let first = TableFormattingTarget()
        let active = TableFormattingTarget()
        let dimensions = try XCTUnwrap(TableDimensions(columns: 3, rows: 4))
        controller.attach(first)
        controller.activate(active)
        controller.perform(.table)

        controller.insertTable(dimensions)

        XCTAssertFalse(controller.isInsertingTable)
        XCTAssertTrue(first.commands.isEmpty)
        XCTAssertEqual(active.commands, [.table(dimensions)])
        XCTAssertEqual(active.focusCount, 1)
    }

    func testSourceTableUsesRequestedCountsAndSelectsFirstHeader() throws {
        let dimensions = try XCTUnwrap(TableDimensions(columns: 3, rows: 4))
        let edit = MarkdownFormatter.edit(for: .table(dimensions), in: "", selection: NSRange(location: 0, length: 0))
        let table = try firstTable(in: edit.replacement)

        XCTAssertEqual(table.columns.count, 3)
        XCTAssertEqual(table.header.map(\.plainText), dimensions.headers)
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertTrue(table.rows.allSatisfy { $0.count == 3 && $0.allSatisfy { $0.plainText.isEmpty } })
        XCTAssertEqual((edit.replacement as NSString).substring(with: edit.selection), dimensions.headers.first)
    }

    func testRichTableUsesRequestedCountsAndSelectsFirstHeader() throws {
        let dimensions = try XCTUnwrap(TableDimensions(columns: 3, rows: 4))
        let view = try makeView()
        view.apply(.table(dimensions), actionName: "")

        let positions = cells(in: view)
        XCTAssertEqual(positions.count, 12)
        XCTAssertEqual(Set(positions.map(\.row)), Set(0..<4))
        XCTAssertEqual(Set(positions.map(\.column)), Set(0..<3))
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), dimensions.headers.first)
    }

    func testRichTableKeepsAllEmptyBodyRowsAfterSavingAndReopening() throws {
        let dimensions = try XCTUnwrap(TableDimensions(columns: 3, rows: 4))
        let view = try makeView()
        view.apply(.table(dimensions), actionName: "")
        let markdown = MarkdownSerializer.markdown(from: view.paragraphs)
        let reopened = try makeView(markdown)

        XCTAssertEqual(cells(in: reopened).count, dimensions.columns * dimensions.rows)
        XCTAssertEqual(MarkdownSerializer.markdown(from: reopened.paragraphs), markdown)
    }

    func testSingleRowTableContainsOnlyItsHeaderInBothEditors() throws {
        let dimensions = try XCTUnwrap(TableDimensions(columns: 1, rows: 1))
        let sourceEdit = MarkdownFormatter.edit(for: .table(dimensions), in: "", selection: NSRange(location: 0, length: 0))
        let sourceTable = try firstTable(in: sourceEdit.replacement)
        XCTAssertEqual(sourceTable.columns.count, 1)
        XCTAssertEqual(sourceTable.header.map(\.plainText), dimensions.headers)
        XCTAssertTrue(sourceTable.rows.isEmpty)

        let view = try makeView()
        view.apply(.table(dimensions), actionName: "")
        XCTAssertEqual(cells(in: view).count, 1)
        let written = MarkdownSerializer.markdown(from: view.paragraphs)
        XCTAssertTrue(try firstTable(in: written).rows.isEmpty)
    }

    func testRichTableInsertionIsUndoableAsOneEdit() throws {
        let dimensions = try XCTUnwrap(TableDimensions(columns: 3, rows: 4))
        let view = try makeView("Before")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        let delegate = TableUndoDelegate()
        delegate.manager.groupsByEvent = false
        view.delegate = delegate

        delegate.manager.beginUndoGrouping()
        view.apply(.table(dimensions), actionName: "")
        view.breakUndoCoalescing()
        delegate.manager.endUndoGrouping()
        XCTAssertEqual(cells(in: view).count, 12)
        XCTAssertTrue(delegate.manager.canUndo)

        delegate.manager.undo()
        XCTAssertEqual(view.string, "Before")
        XCTAssertTrue(cells(in: view).isEmpty)

        delegate.manager.redo()
        XCTAssertEqual(cells(in: view).count, 12)
    }
}

@MainActor
private final class TableFormattingTarget: FormattingTarget {
    var selectedText = ""
    var commands: [FormatCommand] = []
    var focusCount = 0

    func apply(_ command: FormatCommand, actionName: String) { commands.append(command) }
    func revealHeading(_ entry: TOCEntry, among entries: [TOCEntry]) {}
    func focusEditor() { focusCount += 1 }
}

@MainActor
private final class TableUndoDelegate: NSObject, NSTextViewDelegate {
    let manager = UndoManager()

    func undoManager(for view: NSTextView) -> UndoManager? { manager }
}
