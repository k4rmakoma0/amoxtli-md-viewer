import Foundation

/// Word count and estimated reading time of a document's prose. Code blocks and images are left
/// out: they are not read at the same pace as text.
nonisolated struct ReadingStats: Equatable, Sendable {
    static let wordsPerMinute = 200

    let wordCount: Int

    /// Rounded minutes of reading, or `nil` when it takes less than one minute.
    var readingMinutes: Int? {
        guard wordCount >= Self.wordsPerMinute else { return nil }
        return Int((Double(wordCount) / Double(Self.wordsPerMinute)).rounded())
    }

    init(wordCount: Int) {
        self.wordCount = wordCount
    }

    init(blocks: [MarkdownBlock]) {
        self.init(wordCount: blocks.reduce(0) { $0 + Self.wordCount(in: $1) })
    }

    private static func wordCount(in block: MarkdownBlock) -> Int {
        switch block {
        case .heading(_, let content), .paragraph(let content):
            wordCount(in: content.plainText)
        case .orderedList(let items), .unorderedList(let items):
            items.flatMap(\.blocks).reduce(0) { $0 + wordCount(in: $1) }
        case .blockQuote(let blocks):
            blocks.reduce(0) { $0 + wordCount(in: $1) }
        case .table(let table):
            (table.header + table.rows.joined()).reduce(0) { $0 + wordCount(in: $1.plainText) }
        case .codeBlock, .image, .thematicBreak:
            0
        }
    }

    /// Uses the system's word boundaries, so it also counts languages written without spaces.
    private static func wordCount(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
