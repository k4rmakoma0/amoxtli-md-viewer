import Foundation

/// Lines up the scroll positions of the two editors of the split view. The source and the
/// formatted document have very different heights (a table, an image or a code block take
/// more or less room on each side), so a percentage would drift. Instead, each top-level block
/// is a pair of offsets, one per side, and positions between two blocks are interpolated.
nonisolated struct SplitScrollMap: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        let source: Double
        let formatted: Double
    }

    /// Increasing on both sides, from the top of both documents to the end of both.
    let points: [Point]

    /// `sourceAnchors` and `formattedAnchors` are where each block starts on each side, as the
    /// scroll offset that puts it at the top. They pair up only when both sides have the same
    /// blocks; otherwise the map only aligns the tops and the ends. `sourceEnd` and
    /// `formattedEnd` are each side's largest scroll offset.
    init(sourceAnchors: [Double], formattedAnchors: [Double], sourceEnd: Double, formattedEnd: Double) {
        var points = [Point(source: 0, formatted: 0)]
        if sourceAnchors.count == formattedAnchors.count {
            for (source, formatted) in zip(sourceAnchors, formattedAnchors) {
                // Near the end a block can't reach the top, so the end takes over there.
                guard let last = points.last, source > last.source, formatted > last.formatted,
                      source < sourceEnd, formatted < formattedEnd else { continue }
                points.append(Point(source: source, formatted: formatted))
            }
        }
        if let last = points.last, sourceEnd > last.source, formattedEnd > last.formatted {
            points.append(Point(source: sourceEnd, formatted: formattedEnd))
        }
        self.points = points
    }

    func formattedOffset(forSource offset: Double) -> Double {
        Self.map(offset, from: \.source, to: \.formatted, in: points)
    }

    func sourceOffset(forFormatted offset: Double) -> Double {
        Self.map(offset, from: \.formatted, to: \.source, in: points)
    }

    private static func map(_ offset: Double, from input: KeyPath<Point, Double>, to output: KeyPath<Point, Double>, in points: [Point]) -> Double {
        guard let first = points.first, let last = points.last, points.count > 1 else { return 0 }
        if offset <= first[keyPath: input] { return first[keyPath: output] }
        if offset >= last[keyPath: input] { return last[keyPath: output] }
        // The first point past the offset; the one before it is at or before the offset.
        var low = 1
        var high = points.count - 1
        while low < high {
            let middle = (low + high) / 2
            if points[middle][keyPath: input] > offset { high = middle } else { low = middle + 1 }
        }
        let start = points[low - 1]
        let end = points[low]
        let fraction = (offset - start[keyPath: input]) / (end[keyPath: input] - start[keyPath: input])
        return start[keyPath: output] + fraction * (end[keyPath: output] - start[keyPath: output])
    }
}

/// Which paragraphs of the formatted document start one of the Markdown's top-level blocks,
/// the ones the parser reports a source line for (`MarkdownParser.topLevelBlockLines(in:)`).
nonisolated enum RichTopLevelBlocks {
    /// What a paragraph needs to tell where blocks start.
    struct Outline: Equatable, Sendable {
        let block: RichBlock
        let containers: [RichContainer]
        let isEmpty: Bool

        init(block: RichBlock, containers: [RichContainer], isEmpty: Bool) {
            self.block = block
            self.containers = containers
            self.isEmpty = isEmpty
        }

        init(_ paragraph: RichParagraph) {
            self.init(block: paragraph.block, containers: paragraph.containers, isEmpty: paragraph.plainText.isEmpty)
        }
    }

    /// Paragraphs of one list, quote, code block or table are one block; any other paragraph
    /// is a block of its own. An empty paragraph outside of everything writes no Markdown
    /// (as the one after a table that ends the text), so it starts no block.
    static func starts(of paragraphs: [Outline]) -> [Int] {
        var starts: [Int] = []
        var previous: Group?
        for (index, paragraph) in paragraphs.enumerated() {
            if paragraph.isEmpty, paragraph.block == .paragraph, paragraph.containers.isEmpty { continue }
            let group = Group(paragraph)
            if group == nil || group != previous { starts.append(index) }
            previous = group
        }
        return starts
    }

    private enum Group: Equatable {
        case quote(Int)
        case list(Int)
        case code(Int)
        case table(Int)

        init?(_ paragraph: Outline) {
            switch paragraph.containers.first {
            case .quote(let id): self = .quote(id)
            case .listItem(let item): self = .list(item.listID)
            case nil:
                switch paragraph.block {
                case .code(let id, _): self = .code(id)
                case .tableCell(let cell): self = .table(cell.tableID)
                default: return nil
                }
            }
        }
    }
}

/// Where each line of a text starts, as UTF-16 offsets, the unit text views count in.
nonisolated enum TextLines {
    static func startOffsets(in text: String) -> [Int] {
        var starts = [0]
        var previous: UInt16?
        for (offset, unit) in text.utf16.enumerated() {
            // "\r\n" ends one line, not two.
            if unit == 0x0A, previous == 0x0D {
                starts[starts.count - 1] = offset + 1
            } else if unit == 0x0A || unit == 0x0D {
                starts.append(offset + 1)
            }
            previous = unit
        }
        return starts
    }
}
