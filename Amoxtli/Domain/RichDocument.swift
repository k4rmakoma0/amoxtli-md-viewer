import Foundation

/// The document as the formatted editor holds it: a flat list of paragraphs, each one knowing
/// what it is and what it sits inside. A text view edits paragraphs, not trees, so this is the
/// shape that survives typing, and it has all that's needed to write the Markdown back.
nonisolated struct RichParagraph: Hashable, Sendable {
    var block: RichBlock
    /// Outermost first: a list item inside a quote is `[.quote, .listItem]`.
    var containers: [RichContainer] = []
    /// A hard line break is a `"\n"` inside a run, as the parser reports it.
    var runs: [InlineRun] = []

    var plainText: String {
        runs.map(\.text).joined()
    }
}

nonisolated enum RichBlock: Hashable, Sendable {
    case paragraph
    case heading(level: Int)
    /// One paragraph per line of code. Lines with the same `id` are one block.
    case code(id: Int, language: String?)
    case thematicBreak
    case image(MarkdownImage)
    case tableCell(RichTableCell)
}

nonisolated struct RichTableCell: Hashable, Sendable {
    let tableID: Int
    /// Row 0 is the header.
    let row: Int
    let column: Int
    let alignments: [MarkdownTable.Alignment]
}

nonisolated enum RichContainer: Hashable, Sendable {
    case quote(id: Int)
    case listItem(RichListItem)
}

nonisolated struct RichListItem: Hashable, Sendable {
    let listID: Int
    /// Paragraphs with the same `itemID` belong to one item; a new one starts a new item.
    let itemID: Int
    let isOrdered: Bool
    /// The number of the list's first item.
    let start: Int
}

/// Flattens the parsed model into paragraphs, giving every list, item, quote, code block and
/// table its own id.
nonisolated struct RichDocumentBuilder {
    private var nextID = 0
    private var paragraphs: [RichParagraph] = []

    static func paragraphs(from model: MarkdownModel) -> [RichParagraph] {
        var builder = RichDocumentBuilder()
        builder.add(model.blocks, in: [])
        return builder.paragraphs
    }

    private mutating func makeID() -> Int {
        nextID += 1
        return nextID
    }

    private mutating func add(_ blocks: [MarkdownBlock], in containers: [RichContainer]) {
        guard !blocks.isEmpty else {
            // An empty item or quote still needs a paragraph to exist in the text view.
            if !containers.isEmpty { paragraphs.append(RichParagraph(block: .paragraph, containers: containers)) }
            return
        }
        for block in blocks {
            add(block, in: containers)
        }
    }

    private mutating func add(_ block: MarkdownBlock, in containers: [RichContainer]) {
        switch block {
        case .heading(let level, let content):
            paragraphs.append(RichParagraph(block: .heading(level: level), containers: containers, runs: content.runs))
        case .paragraph(let content):
            paragraphs.append(RichParagraph(block: .paragraph, containers: containers, runs: content.runs))
        case .orderedList(let items):
            addList(items, isOrdered: true, in: containers)
        case .unorderedList(let items):
            addList(items, isOrdered: false, in: containers)
        case .blockQuote(let blocks):
            add(blocks, in: containers + [.quote(id: makeID())])
        case .codeBlock(let languageHint, let code):
            let id = makeID()
            for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                let runs = line.isEmpty ? [] : [InlineRun(text: String(line))]
                paragraphs.append(RichParagraph(block: .code(id: id, language: languageHint), containers: containers, runs: runs))
            }
        case .table(let table):
            addTable(table, in: containers)
        case .image(let image):
            paragraphs.append(RichParagraph(block: .image(image), containers: containers))
        case .thematicBreak:
            paragraphs.append(RichParagraph(block: .thematicBreak, containers: containers))
        }
    }

    private mutating func addList(_ items: [ListItem], isOrdered: Bool, in containers: [RichContainer]) {
        let listID = makeID()
        let start = items.first?.ordinal ?? 1
        for item in items {
            let listItem = RichListItem(listID: listID, itemID: makeID(), isOrdered: isOrdered, start: start)
            add(item.blocks, in: containers + [.listItem(listItem)])
        }
    }

    private mutating func addTable(_ table: MarkdownTable, in containers: [RichContainer]) {
        let tableID = makeID()
        for (row, cells) in ([table.header] + table.rows).enumerated() {
            for (column, cell) in cells.enumerated() {
                let position = RichTableCell(tableID: tableID, row: row, column: column, alignments: table.columns)
                paragraphs.append(RichParagraph(block: .tableCell(position), containers: containers, runs: cell.runs))
            }
        }
    }
}
