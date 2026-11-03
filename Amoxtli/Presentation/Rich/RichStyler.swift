import AppKit

/// Derives every visual attribute of the formatted editor from the paragraph kinds and inline
/// styles stored in the text, so restyling a paragraph never depends on how it looked before.
nonisolated final class RichStyler {
    var typography = Typography()

    /// One table object per table, so all of its cells lay out together. Cells are cached too,
    /// since two paragraphs in one cell must share the same block to stay in that cell.
    private var tables: [Int: NSTextTable] = [:]
    private var cells: [RichTableCell: NSTextTableBlock] = [:]

    private var size: CGFloat { CGFloat(typography.size.points) }
    var listIndent: CGFloat { 26 * typography.size.scale }
    var quoteIndent: CGFloat { 20 * typography.size.scale }
    let codePadding: CGFloat = 12

    func forgetTables() {
        tables = [:]
        cells = [:]
    }

    /// The attributes of new text in a paragraph, as when typing.
    func attributes(for kind: RichParagraphKind, style: InlineStyle, link: URL? = nil) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .richParagraph: kind,
            .inlineStyle: style.rawValue,
            .font: font(for: kind, style: style),
            .foregroundColor: color(for: kind),
            .paragraphStyle: paragraphStyle(for: kind, previous: nil, next: nil),
        ]
        let effective = kind.isCode ? [] : style
        if effective.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if effective.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if effective.contains(.code) { attributes[.backgroundColor] = NSColor.quaternarySystemFill }
        if let link { attributes[.link] = link }
        return attributes
    }

    /// Restyles whole paragraphs from what they store. Their kind comes from their first
    /// character, which is how a paragraph merged into another takes that one's kind.
    func restyle(_ range: NSRange, in storage: NSTextStorage) {
        for paragraph in storage.paragraphRanges(in: range) {
            let kind = storage.paragraphKind(at: paragraph.location) ?? .body
            let previous = paragraph.location > 0 ? storage.paragraphKind(at: paragraph.location - 1) : nil
            let next = storage.paragraphKind(at: NSMaxRange(paragraph))
            storage.addAttribute(.richParagraph, value: kind, range: paragraph)
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(for: kind, previous: previous, next: next), range: paragraph)
            storage.addAttribute(.foregroundColor, value: color(for: kind), range: paragraph)
            storage.enumerateAttribute(.inlineStyle, in: paragraph) { value, run, _ in
                let style = kind.isCode ? [] : InlineStyle(rawValue: value as? Int ?? 0)
                storage.addAttribute(.font, value: font(for: kind, style: style), range: run)
                set(.underlineStyle, NSUnderlineStyle.single.rawValue, if: style.contains(.underline), in: run, of: storage)
                set(.strikethroughStyle, NSUnderlineStyle.single.rawValue, if: style.contains(.strikethrough), in: run, of: storage)
                set(.backgroundColor, NSColor.quaternarySystemFill, if: style.contains(.code), in: run, of: storage)
            }
        }
    }

    private func set(_ key: NSAttributedString.Key, _ value: Any, if isSet: Bool, in range: NSRange, of storage: NSTextStorage) {
        if isSet {
            storage.addAttribute(key, value: value, range: range)
        } else {
            storage.removeAttribute(key, range: range)
        }
    }

    // MARK: - Fonts

    func font(for kind: RichParagraphKind, style: InlineStyle) -> NSFont {
        switch kind.block {
        case .code:
            return typography.code
        case .heading(let level):
            return withInlineStyle(style, base: typography.heading(level: level))
        case .tableCell(let cell) where cell.row == 0:
            return withInlineStyle(style, base: typography.body.withTraits(.bold))
        default:
            return withInlineStyle(style, base: typography.body)
        }
    }

    private func withInlineStyle(_ style: InlineStyle, base: NSFont) -> NSFont {
        let font = style.contains(.code) ? NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular) : base
        var traits: NSFontDescriptor.SymbolicTraits = []
        if style.contains(.strong) { traits.insert(.bold) }
        if style.contains(.emphasis) { traits.insert(.italic) }
        return traits.isEmpty ? font : font.withTraits(traits)
    }

    private func color(for kind: RichParagraphKind) -> NSColor {
        kind.containers.contains { if case .quote = $0 { true } else { false } } ? .secondaryLabelColor : .labelColor
    }

    // MARK: - Paragraphs

    /// Indents are the sum of the containers' indents, which is also where the layout manager
    /// draws list markers and quote bars.
    func indent(of containers: some Collection<RichContainer>) -> CGFloat {
        containers.reduce(0) { total, container in
            switch container {
            case .quote: total + quoteIndent
            case .listItem: total + listIndent
            }
        }
    }

    /// Spacing depends on the neighbors: lines of one code block and items of one list sit
    /// close together, and leaving either leaves room.
    func paragraphStyle(for kind: RichParagraphKind, previous: RichParagraphKind?, next: RichParagraphKind?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = indent(of: kind.containers)
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.lineSpacing = 3 * typography.size.scale
        style.paragraphSpacing = spacingAfter(kind, next: next)
        style.paragraphSpacingBefore = spacingBefore(kind, previous: previous)
        switch kind.block {
        case .code:
            style.firstLineHeadIndent += codePadding
            style.headIndent += codePadding
            style.tailIndent = -codePadding
            style.lineSpacing = 0
        case .tableCell(let cell):
            style.textBlocks = [block(for: cell)]
            style.alignment = alignment(of: cell)
        default:
            break
        }
        return style
    }

    private func spacingAfter(_ kind: RichParagraphKind, next: RichParagraphKind?) -> CGFloat {
        switch kind.block {
        case .code(let id, _):
            if case .code(let nextID, _) = next?.block, nextID == id { return 0 }
            return size
        case .tableCell:
            return 0
        default:
            return isInSameList(kind, next) ? size * 0.3 : size * 0.75
        }
    }

    private func isInSameList(_ kind: RichParagraphKind, _ next: RichParagraphKind?) -> Bool {
        guard case .listItem(let item) = kind.containers.first, case .listItem(let other) = next?.containers.first else { return false }
        return item.listID == other.listID
    }

    private func spacingBefore(_ kind: RichParagraphKind, previous: RichParagraphKind?) -> CGFloat {
        switch kind.block {
        case .heading(let level):
            return level <= 2 ? size : size * 0.5
        case .code(let id, _):
            if case .code(let previousID, _) = previous?.block, previousID == id { return 0 }
            return size * 0.5
        default:
            // The paragraph after a code block or a table, which have no spacing of their own.
            switch previous?.block {
            case .code, .tableCell: return kind.tableCell == nil ? size * 0.75 : 0
            default: return 0
            }
        }
    }

    // MARK: - Tables

    private func block(for cell: RichTableCell) -> NSTextTableBlock {
        if let cached = cells[cell] { return cached }
        let block = NSTextTableBlock(table: table(for: cell), startingRow: cell.row, rowSpan: 1, startingColumn: cell.column, columnSpan: 1)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(.separatorColor)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        if cell.row == 0 {
            block.backgroundColor = .quaternarySystemFill
        }
        cells[cell] = block
        return block
    }

    private func table(for cell: RichTableCell) -> NSTextTable {
        if let cached = tables[cell.tableID] { return cached }
        let table = NSTextTable()
        table.numberOfColumns = cell.alignments.count
        table.collapsesBorders = true
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        tables[cell.tableID] = table
        return table
    }

    private func alignment(of cell: RichTableCell) -> NSTextAlignment {
        guard cell.alignments.indices.contains(cell.column) else { return .natural }
        switch cell.alignments[cell.column] {
        case .leading: return .natural
        case .center: return .center
        case .trailing: return .right
        }
    }
}

nonisolated extension RichParagraphKind {
    var isCode: Bool {
        if case .code = block { return true }
        return false
    }
}
