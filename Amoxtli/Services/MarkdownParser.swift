import Foundation

nonisolated protocol MarkdownParsing: Sendable {
    func parse(_ source: String) throws -> MarkdownModel
}

/// Builds the block tree by grouping `AttributedString` runs on their `PresentationIntent` path.
nonisolated struct MarkdownParser: MarkdownParsing {
    func parse(_ source: String) throws -> MarkdownModel {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible,
            appliesSourcePositionAttributes: true
        )
        let attributed = try AttributedString(markdown: source, options: options)
        return MarkdownModel(blocks: blocks(from: parsedRuns(in: attributed, source: source), depth: 0))
    }

    private func parsedRuns(in attributed: AttributedString, source: String) -> [ParsedRun] {
        var tableTails: [Int: TableSourceTail] = [:]
        var previousTableID: Int?
        let runs = attributed.runs.map { run in
            let parsed = ParsedRun(
                // `components` lists the innermost intent first; grouping needs outermost first.
                path: (run.presentationIntent?.components ?? []).reversed(),
                inline: InlineRun(
                    text: String(attributed[run.range].characters),
                    style: InlineStyle(run.inlinePresentationIntent),
                    link: run.link
                ),
                imageURL: run.imageURL,
                isHTML: run.inlinePresentationIntent?.contains(.inlineHTML) ?? false
            )
            if let position = run.markdownSourcePosition {
                if let previousTableID, previousTableID != parsed.tableID {
                    tableTails[previousTableID]?.followingSourceLine = position.startLine
                }
                previousTableID = parsed.tableID
                if let tableID = parsed.tableID {
                    let tail = TableSourceTail(path: parsed.path, sourceLine: position.endLine)
                    if position.endLine >= (tableTails[tableID]?.sourceLine ?? 0) {
                        tableTails[tableID] = tail
                    }
                }
            }
            return parsed
        }
        guard !tableTails.isEmpty else { return runs }
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let rowCounts = tableTails.mapValues { $0.bodyRowCount(in: lines) }
        return runs.map { run in
            var run = run
            run.tableBodyRowCount = run.tableID.flatMap { rowCounts[$0] } ?? 0
            return run
        }
    }

    // MARK: - Blocks

    private func blocks(from runs: [ParsedRun], depth: Int) -> [MarkdownBlock] {
        groups(of: runs, depth: depth).flatMap { blocks(from: $0, depth: depth) }
    }

    private func blocks(from group: RunGroup, depth: Int) -> [MarkdownBlock] {
        let childDepth = depth + 1
        switch group.intent?.kind {
        case .header(let level):
            return [.heading(level: level, content: inlineText(from: group.runs))]
        case .orderedList:
            return [.orderedList(listItems(from: group.runs, depth: childDepth))]
        case .unorderedList:
            return [.unorderedList(listItems(from: group.runs, depth: childDepth))]
        case .blockQuote:
            return [.blockQuote(blocks(from: group.runs, depth: childDepth))]
        case .codeBlock(let languageHint):
            return [codeBlock(from: group.runs, languageHint: languageHint)]
        case .table(let columns):
            return [.table(table(from: group.runs, columns: columns, depth: childDepth))]
        case .thematicBreak:
            return [.thematicBreak]
        default:
            return paragraphBlocks(from: group.runs)
        }
    }

    private func groups(of runs: [ParsedRun], depth: Int) -> [RunGroup] {
        var groups: [RunGroup] = []
        for run in runs {
            let intent = run.path.indices.contains(depth) ? run.path[depth] : nil
            if let last = groups.indices.last, let intent, groups[last].intent?.identity == intent.identity {
                groups[last].runs.append(run)
            } else {
                groups.append(RunGroup(intent: intent, runs: [run]))
            }
        }
        return groups
    }

    private func listItems(from runs: [ParsedRun], depth: Int) -> [ListItem] {
        groups(of: runs, depth: depth).map { group in
            ListItem(
                ordinal: ordinal(of: group.intent),
                blocks: blocks(from: group.runs, depth: depth + 1)
            )
        }
    }

    private func ordinal(of intent: PresentationIntent.IntentType?) -> Int {
        if case .listItem(let ordinal) = intent?.kind { return ordinal }
        return 1
    }

    private func codeBlock(from runs: [ParsedRun], languageHint: String?) -> MarkdownBlock {
        let code = runs.map(\.inline.text).joined()
        return .codeBlock(
            languageHint: languageHint?.isEmpty == true ? nil : languageHint,
            code: code.hasSuffix("\n") ? String(code.dropLast()) : code
        )
    }

    // MARK: - Paragraphs

    /// `Text` can't host an `AsyncImage`, so images break the paragraph into separate blocks.
    private func paragraphBlocks(from runs: [ParsedRun]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var pending: [ParsedRun] = []

        func flushPending() {
            if pending.contains(where: { !$0.inline.text.allSatisfy(\.isWhitespace) }) {
                blocks.append(.paragraph(inlineText(from: pending)))
            }
            pending = []
        }

        for run in runs {
            if let source = run.imageURL {
                flushPending()
                // Images without alt text arrive with U+FFFC as their only text.
                let altText = run.inline.text == "\u{FFFC}" ? "" : run.inline.text
                blocks.append(.image(MarkdownImage(source: source, altText: altText)))
            } else {
                pending.append(run)
            }
        }
        flushPending()
        return blocks
    }

    /// Adjacent runs with the same attributes are merged: soft breaks arrive as runs of their own.
    private func inlineText(from runs: [ParsedRun]) -> InlineText {
        var merged: [InlineRun] = []
        for run in underlined(runs) {
            if let last = merged.last, last.style == run.style, last.link == run.link {
                merged[merged.count - 1] = InlineRun(text: last.text + run.text, style: last.style, link: last.link)
            } else {
                merged.append(run)
            }
        }
        return InlineText(runs: merged)
    }

    /// The parser keeps `<u>` and `</u>` as inline HTML runs. They become the underline style of
    /// the runs between them; any other HTML stays as text.
    private func underlined(_ runs: [ParsedRun]) -> [InlineRun] {
        var depth = 0
        var result: [InlineRun] = []
        for run in runs {
            if run.isHTML, let change = underlineChange(for: run.inline.text) {
                depth = max(0, depth + change)
                continue
            }
            var inline = run.inline
            if depth > 0 { inline.style.insert(.underline) }
            result.append(inline)
        }
        return result
    }

    private func underlineChange(for tag: String) -> Int? {
        switch tag.lowercased() {
        case "<u>", "<ins>": 1
        case "</u>", "</ins>": -1
        default: nil
        }
    }

    // MARK: - Tables

    private func table(
        from runs: [ParsedRun],
        columns: [PresentationIntent.TableColumn],
        depth: Int
    ) -> MarkdownTable {
        var header: [InlineText] = emptyRow(columnCount: columns.count)
        var rowsByIndex: [Int: [InlineText]] = [:]

        for group in groups(of: runs, depth: depth) {
            let cells = tableRow(from: group.runs, columnCount: columns.count, depth: depth + 1)
            if case .tableRow(let rowIndex) = group.intent?.kind {
                rowsByIndex[rowIndex] = cells
            } else {
                header = cells
            }
        }

        return MarkdownTable(
            columns: columns.map(MarkdownTable.Alignment.init),
            header: header,
            rows: bodyRows(from: rowsByIndex, columnCount: columns.count, minimumRowCount: runs.first?.tableBodyRowCount ?? 0)
        )
    }

    /// The parser emits no runs for empty cells, so they are recovered from the column index.
    private func tableRow(from runs: [ParsedRun], columnCount: Int, depth: Int) -> [InlineText] {
        var cells = emptyRow(columnCount: columnCount)
        for group in groups(of: runs, depth: depth) {
            if case .tableCell(let column) = group.intent?.kind, cells.indices.contains(column) {
                cells[column] = inlineText(from: group.runs)
            }
        }
        return cells
    }

    /// A row made only of empty cells emits no runs either, leaving a gap in the row indices.
    private func bodyRows(from rowsByIndex: [Int: [InlineText]], columnCount: Int, minimumRowCount: Int) -> [[InlineText]] {
        let lastIndex = max(rowsByIndex.keys.max() ?? 0, minimumRowCount)
        guard lastIndex > 0 else { return [] }
        return (1...lastIndex).map { rowsByIndex[$0] ?? emptyRow(columnCount: columnCount) }
    }

    private func emptyRow(columnCount: Int) -> [InlineText] {
        Array(repeating: InlineText(runs: []), count: columnCount)
    }
}

private nonisolated struct ParsedRun {
    let path: [PresentationIntent.IntentType]
    let inline: InlineRun
    let imageURL: URL?
    let isHTML: Bool
    var tableBodyRowCount = 0

    var tableID: Int? {
        path.first { if case .table = $0.kind { true } else { false } }?.identity
    }
}

/// Foundation omits every run of an empty table row, including all trailing rows. Source
/// positions anchor recovery at a table it already recognized; only empty continuation rows
/// immediately after its last visible cell are inspected, never other Markdown blocks.
private nonisolated struct TableSourceTail {
    let sourceLine: Int
    var followingSourceLine: Int?
    private let rowIndex: Int
    private let quoteDepth: Int

    init(path: [PresentationIntent.IntentType], sourceLine: Int) {
        self.sourceLine = sourceLine
        rowIndex = path.compactMap { intent -> Int? in
            if case .tableRow(let index) = intent.kind { return index }
            return nil
        }.first ?? 0
        quoteDepth = path.filter { if case .blockQuote = $0.kind { true } else { false } }.count
    }

    func bodyRowCount(in lines: [Substring]) -> Int {
        var count = rowIndex
        // Source positions are one-based. Skip the delimiter following a header; a body
        // row's next source line is already its continuation. Never cross the next block
        // recognized by Foundation, including an outdented pipe-only paragraph.
        var next = rowIndex == 0 ? sourceLine + 1 : sourceLine
        while lines.indices.contains(next), next + 1 < (followingSourceLine ?? Int.max), isEmptyRow(lines[next]) {
            count += 1
            next += 1
        }
        return count
    }

    private func isEmptyRow(_ line: Substring) -> Bool {
        var cells = line.drop { $0 == " " || $0 == "\t" }
        for _ in 0..<quoteDepth {
            guard cells.first == ">" else { return false }
            cells = cells.dropFirst().drop { $0 == " " || $0 == "\t" }
        }
        return cells.contains("|") && cells.allSatisfy { $0 == "|" || $0 == " " || $0 == "\t" }
    }
}

private nonisolated struct RunGroup {
    let intent: PresentationIntent.IntentType?
    var runs: [ParsedRun]
}

private nonisolated extension InlineStyle {
    init(_ intent: InlinePresentationIntent?) {
        self = []
        guard let intent else { return }
        if intent.contains(.emphasized) { insert(.emphasis) }
        if intent.contains(.stronglyEmphasized) { insert(.strong) }
        if intent.contains(.code) { insert(.code) }
        if intent.contains(.strikethrough) { insert(.strikethrough) }
    }
}

private nonisolated extension MarkdownTable.Alignment {
    init(_ column: PresentationIntent.TableColumn) {
        switch column.alignment {
        case .center: self = .center
        case .right: self = .trailing
        default: self = .leading
        }
    }
}
