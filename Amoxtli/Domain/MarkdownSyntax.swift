import Foundation

nonisolated enum SyntaxKind: Equatable, Sendable {
    case heading(level: Int)
    /// Characters that are Markdown syntax rather than text, such as `**` or `#`.
    case marker
    case strong
    case emphasis
    case underline
    case strikethrough
    case inlineCode
    case codeBlock
    case linkText
    case linkDestination
    case quote
    case listMarker
    case horizontalRule
}

nonisolated struct SyntaxSpan: Equatable, Sendable {
    let range: NSRange
    let kind: SyntaxKind
}

nonisolated struct SyntaxScan: Equatable, Sendable {
    let spans: [SyntaxSpan]
    /// Whether the scanned lines leave a fenced code block open, so the next ones are code.
    let endsInFence: Bool
    /// Every scanned line, line break included, after which a fenced code block is open. An edit
    /// can then tell whether the line before it starts inside a code block without rescanning.
    let fencedLines: [NSRange]
}

/// Finds the syntax to highlight in the source editor. It works line by line, so that an edit
/// only needs its own lines scanned again; the one state carried between lines is whether they
/// are inside a fenced code block.
nonisolated enum MarkdownSyntaxScanner {
    /// `text` is a `String`, which keeps the many regular expression calls from copying a
    /// text view's mutable storage each time.
    static func scan(_ text: String, lines range: NSRange, startsInFence: Bool) -> SyntaxScan {
        LineScanner(string: text, source: text as NSString).scan(lines: range, startsInFence: startsInFence)
    }

    static func isFence(_ line: NSRange, in text: String) -> Bool {
        Patterns.fence.firstMatch(in: text, range: line) != nil
    }

    static func scan(_ text: String) -> SyntaxScan {
        scan(text, lines: NSRange(location: 0, length: text.utf16.count), startsInFence: false)
    }

    private struct LineScanner {
        let string: String
        let source: NSString
        private var spans: [SyntaxSpan] = []
        private var fencedLines: [NSRange] = []

        init(string: String, source: NSString) {
            self.string = string
            self.source = source
        }

        consuming func scan(lines range: NSRange, startsInFence: Bool) -> SyntaxScan {
            var isInFence = startsInFence
            var location = range.location
            let end = NSMaxRange(range)
            repeat {
                let lineRange = source.lineRange(for: NSRange(location: min(location, source.length), length: 0))
                isInFence = scanLine(contentRange(of: lineRange), isInFence: isInFence)
                if isInFence { fencedLines.append(lineRange) }
                location = NSMaxRange(lineRange)
            } while location < end && location < source.length
            return SyntaxScan(spans: spans, endsInFence: isInFence, fencedLines: fencedLines)
        }

        private func contentRange(of line: NSRange) -> NSRange {
            var content = line
            while content.length > 0, [0x0A, 0x0D].contains(source.character(at: NSMaxRange(content) - 1)) {
                content.length -= 1
            }
            return content
        }

        private mutating func add(_ range: NSRange, _ kind: SyntaxKind) {
            if range.location != NSNotFound, range.length > 0 {
                spans.append(SyntaxSpan(range: range, kind: kind))
            }
        }

        /// Returns whether the next line is inside a fenced code block.
        private mutating func scanLine(_ line: NSRange, isInFence: Bool) -> Bool {
            let isFence = Patterns.fence.firstMatch(in: string, range: line) != nil
            if isFence {
                add(line, .marker)
                return !isInFence
            }
            if isInFence {
                add(line, .codeBlock)
                return true
            }
            scanBlock(line)
            return false
        }

        private mutating func scanBlock(_ line: NSRange) {
            if let heading = Patterns.heading.firstMatch(in: string, range: line) {
                add(line, .heading(level: heading.range(at: 1).length))
                add(heading.range, .marker)
                scanInline(remainder(of: line, after: heading.range))
                return
            }
            if Patterns.horizontalRule.firstMatch(in: string, range: line) != nil {
                add(line, .horizontalRule)
                return
            }
            var rest = line
            if let quote = Patterns.quote.firstMatch(in: string, range: line) {
                add(line, .quote)
                add(quote.range, .marker)
                rest = remainder(of: line, after: quote.range)
            }
            if let list = Patterns.listMarker.firstMatch(in: string, range: rest) {
                add(list.range(at: 1), .listMarker)
                rest = remainder(of: rest, after: list.range)
            }
            scanInline(rest)
        }

        private func remainder(of line: NSRange, after prefix: NSRange) -> NSRange {
            NSRange(location: NSMaxRange(prefix), length: NSMaxRange(line) - NSMaxRange(prefix))
        }

        private mutating func scanInline(_ range: NSRange) {
            guard range.length > 0 else { return }
            // Code spans go first: nothing inside them is syntax.
            let code = Patterns.inlineCode.matches(in: string, range: range)
            for match in code {
                add(match.range, .inlineCode)
                add(match.range(at: 1), .marker)
                add(match.range(at: 3), .marker)
            }
            let isOutsideCode = { (match: NSTextCheckingResult) in
                !code.contains { NSIntersectionRange($0.range, match.range).length > 0 }
            }
            for match in Patterns.link.matches(in: string, range: range) where isOutsideCode(match) {
                add(match.range(at: 1), .marker)
                add(match.range(at: 2), .linkText)
                add(match.range(at: 3), .marker)
                add(match.range(at: 4), .linkDestination)
                add(match.range(at: 5), .marker)
            }
            for (pattern, kind) in Patterns.wrapped {
                for match in pattern.matches(in: string, range: range) where isOutsideCode(match) {
                    add(match.range(at: 1), .marker)
                    add(match.range(at: 2), kind)
                    add(match.range(at: 3), .marker)
                }
            }
        }
    }

    // MARK: - Patterns

    private enum Patterns {
        // `NSRegularExpression` is immutable and documented as safe to use from any thread.
        nonisolated(unsafe) static let fence = make(#"^ {0,3}(?:```|~~~)"#)
        nonisolated(unsafe) static let heading = make(#"^ {0,3}(#{1,6})(?:[ \t]+|$)"#)
        nonisolated(unsafe) static let horizontalRule = make(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
        nonisolated(unsafe) static let quote = make(#"^ {0,3}(?:> ?)+"#)
        nonisolated(unsafe) static let listMarker = make(#"^[ \t]*([-*+]|\d{1,9}[.)])[ \t]+"#)
        nonisolated(unsafe) static let inlineCode = make(#"(`+)(?!`)(.+?)(?<!`)(\1)(?!`)"#)
        nonisolated(unsafe) static let link = make(#"(!?\[)([^\]\n]*)(\]\()([^)\n]*)(\))"#)
        nonisolated(unsafe) static let wrapped: [(NSRegularExpression, SyntaxKind)] = [
            (make(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)"#), .strong),
            // One pattern per marker: each only has to stay clear of its own character, so
            // `_italic_` can sit right inside `**bold**` and the other way around.
            (make(#"(?<![*\\])(\*)(?![*\s])(.+?)(?<![*\s\\])(\*)(?!\*)"#), .emphasis),
            (make(#"(?<![_\w\\])(_)(?![_\s])(.+?)(?<![_\s\\])(_)(?![_\w])"#), .emphasis),
            (make(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#), .strikethrough),
            (make(#"(<u>)(.+?)(</u>)"#, options: .caseInsensitive), .underline),
        ]

        /// The patterns are fixed, so a failure here is a mistake in this file that tests catch.
        private static func make(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            do {
                return try NSRegularExpression(pattern: pattern, options: options.union(.anchorsMatchLines))
            } catch {
                preconditionFailure("Invalid syntax pattern \(pattern): \(error)")
            }
        }
    }
}
