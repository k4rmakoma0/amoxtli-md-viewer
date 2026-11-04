import Foundation

/// The formatting in effect at the caret or across the selection, which the toolbar and the
/// Format menu show as pressed buttons and checkmarks.
nonisolated struct ActiveFormats: Equatable, Sendable {
    enum ListKind: Equatable, Sendable {
        case bulleted, numbered
    }

    var inline: InlineStyle = []
    var hasLink = false
    /// 0 for body text.
    var headingLevel = 0
    var list: ListKind?
    var isQuote = false
    var isCodeBlock = false

    static let none = ActiveFormats()
}

/// Reads the active formatting from Markdown source, from the syntax around the caret.
nonisolated enum SourceFormatDetector {
    /// Only the caret's line is scanned, so moving the caret stays cheap in long documents;
    /// `startsInFence` says whether that line begins inside a fenced code block.
    static func activeFormats(in text: String, selection: NSRange, startsInFence: Bool) -> ActiveFormats {
        let source = text as NSString
        let location = min(selection.location, source.length)
        let line = source.lineRange(for: NSRange(location: location, length: 0))
        let scan = MarkdownSyntaxScanner.scan(text, lines: line, startsInFence: startsInFence)
        var formats = ActiveFormats()
        // The opening fence, the code and the closing fence are all part of the block.
        formats.isCodeBlock = startsInFence || scan.endsInFence
        for span in scan.spans {
            switch span.kind {
            case .heading(let level):
                formats.headingLevel = level
            case .quote:
                formats.isQuote = true
            case .listMarker:
                let marker = source.substring(with: span.range)
                formats.list = marker.first?.isNumber == true ? .numbered : .bulleted
            case .strong where covers(span.range, selection):
                formats.inline.insert(.strong)
            case .emphasis where covers(span.range, selection):
                formats.inline.insert(.emphasis)
            case .underline where covers(span.range, selection):
                formats.inline.insert(.underline)
            case .strikethrough where covers(span.range, selection):
                formats.inline.insert(.strikethrough)
            case .inlineCode where covers(span.range, selection):
                formats.inline.insert(.code)
            case .linkText where covers(span.range, selection):
                formats.hasLink = true
            default:
                break
            }
        }
        return formats
    }

    /// A caret counts from the start of the styled text to its end, between the markers,
    /// which is where typing takes that style. A selection must lie within the styled text.
    private static func covers(_ styled: NSRange, _ selection: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= styled.location && selection.location <= NSMaxRange(styled)
        }
        return selection.location >= styled.location && NSMaxRange(selection) <= NSMaxRange(styled)
    }
}
