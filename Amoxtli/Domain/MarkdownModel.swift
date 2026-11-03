import Foundation

nonisolated struct MarkdownModel: Equatable, Sendable {
    let blocks: [MarkdownBlock]
}

nonisolated enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, content: InlineText)
    case paragraph(InlineText)
    case orderedList([ListItem])
    case unorderedList([ListItem])
    case blockQuote([MarkdownBlock])
    case codeBlock(languageHint: String?, code: String)
    case table(MarkdownTable)
    case image(MarkdownImage)
    case thematicBreak
}

nonisolated struct ListItem: Equatable, Sendable {
    let ordinal: Int
    let blocks: [MarkdownBlock]
}

nonisolated struct MarkdownTable: Equatable, Sendable {
    enum Alignment: Equatable, Sendable {
        case leading, center, trailing
    }

    let columns: [Alignment]
    let header: [InlineText]
    let rows: [[InlineText]]
}

nonisolated struct MarkdownImage: Equatable, Sendable {
    let source: URL
    let altText: String

    /// Only remote images can load: the sandbox has no access to paths relative to the document.
    var isRemote: Bool {
        let scheme = source.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

nonisolated struct InlineText: Equatable, Sendable {
    let runs: [InlineRun]

    var plainText: String {
        runs.map(\.text).joined()
    }
}

nonisolated struct InlineRun: Equatable, Sendable {
    let text: String
    var style: InlineStyle = []
    var link: URL?
}

nonisolated struct InlineStyle: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let emphasis = InlineStyle(rawValue: 1 << 0)
    static let strong = InlineStyle(rawValue: 1 << 1)
    static let code = InlineStyle(rawValue: 1 << 2)
    static let strikethrough = InlineStyle(rawValue: 1 << 3)
    /// Markdown has no underline: it is written as `<u>text</u>`, as most editors do.
    static let underline = InlineStyle(rawValue: 1 << 4)
}
