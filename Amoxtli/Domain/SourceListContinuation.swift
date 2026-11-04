import Foundation

/// What Return does on a list or quote line of Markdown source: the next line starts with the
/// same markers, the next number, the same indentation. On an item with no text, Return removes
/// its marker instead, which is how a list ends.
nonisolated enum SourceListContinuation {
    /// `nil` when Return should only insert a line break: outside lists and quotes, inside a
    /// fenced code block, or with the caret before the line's text.
    static func edit(in text: String, selection: NSRange, startsInFence: Bool) -> TextEdit? {
        guard !startsInFence else { return nil }
        let source = text as NSString
        let lineRange = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0))
        let line = contentRange(of: lineRange, in: source)
        // A selection reaching into another line is replaced as usual.
        guard NSMaxRange(selection) <= NSMaxRange(line) else { return nil }
        let content = source.substring(with: line)
        guard let prefix = LinePrefix(content), prefix.isContinued else { return nil }
        let prefixEnd = line.location + prefix.length
        guard selection.location >= prefixEnd else { return nil }

        let rest = (content as NSString).substring(from: prefix.length)
        if rest.allSatisfy(\.isWhitespace), selection.length == 0 {
            let remaining = prefix.withoutInnermostMarker
            return TextEdit(range: line, replacement: remaining, selection: NSRange(location: line.location + remaining.utf16.count, length: 0))
        }
        let next = "\n" + prefix.continuation
        return TextEdit(range: selection, replacement: next, selection: NSRange(location: selection.location + next.utf16.count, length: 0))
    }

    private static func contentRange(of line: NSRange, in source: NSString) -> NSRange {
        var content = line
        while content.length > 0, [0x0A, 0x0D].contains(source.character(at: NSMaxRange(content) - 1)) {
            content.length -= 1
        }
        return content
    }
}

/// The indentation, quote markers and list marker at the start of a line.
private nonisolated struct LinePrefix {
    let indentation: String
    let quotes: String
    let innerIndentation: String
    let marker: Marker?
    let length: Int

    enum Marker {
        case bullet(Character)
        case number(Int, delimiter: Character)

        var next: String {
            switch self {
            case .bullet(let character): "\(character) "
            case .number(let value, let delimiter): "\(value + 1)\(delimiter) "
            }
        }
    }

    init?(_ line: String) {
        guard let match = line.firstMatch(of: /^([ \t]*)((?:>[ \t]?)*)([ \t]*)(?:([-*+])|(\d{1,9})([.)]))?([ \t]+)?/) else { return nil }
        indentation = String(match.1)
        quotes = String(match.2)
        innerIndentation = String(match.3)
        // A marker only counts with a space after it: `-text` and `1.5` are text.
        if match.7 != nil, let bullet = match.4?.first {
            marker = .bullet(bullet)
        } else if match.7 != nil, let digits = match.5, let value = Int(digits), let delimiter = match.6?.first {
            marker = .number(value, delimiter: delimiter)
        } else {
            marker = nil
        }
        length = marker == nil ? (indentation + quotes).utf16.count : match.0.utf16.count
    }

    var isContinued: Bool {
        marker != nil || !quotes.isEmpty
    }

    /// The start of the next line: the same nesting, and the next marker.
    var continuation: String {
        let quotePrefix = quotes.isEmpty || quotes.hasSuffix(" ") ? quotes : quotes + " "
        return indentation + quotePrefix + innerIndentation + (marker?.next ?? "")
    }

    /// An empty item loses its list marker; an empty quote line loses its quote.
    var withoutInnermostMarker: String {
        marker == nil ? "" : indentation + quotes
    }
}
