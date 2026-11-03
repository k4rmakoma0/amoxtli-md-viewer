import Foundation

/// Applies a formatting tool to Markdown source by writing the syntax for the person. Tools that
/// are already applied are removed instead, so every one of them works as a toggle.
nonisolated enum MarkdownFormatter {
    static func edit(for command: FormatCommand, in text: String, selection: NSRange) -> TextEdit {
        let source = text as NSString
        let selection = clamped(selection, to: source)
        switch command {
        case .bold: return InlineToggle(open: "**", close: "**").edit(in: source, selection: selection)
        case .italic: return InlineToggle(open: "_", close: "_").edit(in: source, selection: selection)
        case .underline: return InlineToggle(open: "<u>", close: "</u>").edit(in: source, selection: selection)
        case .strikethrough: return InlineToggle(open: "~~", close: "~~").edit(in: source, selection: selection)
        case .inlineCode: return InlineToggle(open: "`", close: "`").edit(in: source, selection: selection)
        case .heading(let level): return LineEditor(source: source, selection: selection).heading(level: level)
        case .quote: return LineEditor(source: source, selection: selection).quote()
        case .bulletList: return LineEditor(source: source, selection: selection).bulletList()
        case .numberedList: return LineEditor(source: source, selection: selection).numberedList()
        case .codeBlock: return LineEditor(source: source, selection: selection).codeBlock()
        case .table: return BlockInserter(source: source, selection: selection).insert(table, selecting: tableFirstHeader)
        case .horizontalRule: return BlockInserter(source: source, selection: selection).insert("---")
        case .link(let text, let destination): return link(text: text, destination: destination, in: source, selection: selection)
        }
    }

    private static func clamped(_ selection: NSRange, to source: NSString) -> NSRange {
        let location = min(max(selection.location, 0), source.length)
        return NSRange(location: location, length: min(max(selection.length, 0), source.length - location))
    }

    // MARK: - Table

    private static var tableFirstHeader: String { String(localized: "Columna 1") }

    private static var table: String {
        let second = String(localized: "Columna 2")
        return "| \(tableFirstHeader) | \(second) |\n| --- | --- |\n|  |  |"
    }

    // MARK: - Links

    private static func link(text: String, destination: String, in source: NSString, selection: NSRange) -> TextEdit {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = escapedLabel(trimmedText.isEmpty ? destination : trimmedText)
        let target = destination.contains(where: { $0.isWhitespace || $0 == "(" || $0 == ")" })
            ? "<\(destination)>"
            : destination
        let replacement = "[\(label)](\(target))"
        let end = selection.location + replacement.utf16.count
        return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: end, length: 0))
    }

    private static func escapedLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}

// MARK: - Inline styles

/// Wraps the selection in a pair of markers, or removes them when they are already there.
private nonisolated struct InlineToggle {
    let open: String
    let close: String

    func edit(in source: NSString, selection: NSRange) -> TextEdit {
        let target = trimmingWhitespace(selection, in: source)
        if let outer = markersAround(target, in: source) {
            let inner = source.substring(with: target)
            return TextEdit(range: outer, replacement: inner, selection: NSRange(location: outer.location, length: target.length))
        }
        let selected = source.substring(with: target)
        if isWrapped(selected) {
            let inner = String(selected.utf16.dropFirst(open.utf16.count).dropLast(close.utf16.count)) ?? selected
            return TextEdit(range: target, replacement: inner, selection: NSRange(location: target.location, length: inner.utf16.count))
        }
        let wrapped = open + selected + close
        let start = target.location + open.utf16.count
        return TextEdit(range: target, replacement: wrapped, selection: NSRange(location: start, length: target.length))
    }

    /// Markdown ignores markers next to spaces, so ` palabra ` becomes `**palabra**`, not `** palabra **`.
    private func trimmingWhitespace(_ selection: NSRange, in source: NSString) -> NSRange {
        var start = selection.location
        var end = NSMaxRange(selection)
        while start < end, isWhitespace(source.character(at: start)) { start += 1 }
        while end > start, isWhitespace(source.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private func markersAround(_ target: NSRange, in source: NSString) -> NSRange? {
        let openLength = open.utf16.count
        let closeLength = close.utf16.count
        guard target.location >= openLength, NSMaxRange(target) + closeLength <= source.length else { return nil }
        let before = NSRange(location: target.location - openLength, length: openLength)
        let after = NSRange(location: NSMaxRange(target), length: closeLength)
        guard source.substring(with: before) == open, source.substring(with: after) == close else { return nil }
        guard isWholeEmphasisRun(before: before, after: after, in: source) else { return nil }
        return NSRange(location: before.location, length: openLength + target.length + closeLength)
    }

    /// `_` inside `__bold__` belongs to the bold markers. A single marker only counts when its
    /// run is odd: one marker on its own, or three for bold and italic together.
    private func isWholeEmphasisRun(before: NSRange, after: NSRange, in source: NSString) -> Bool {
        guard open == close, open.utf16.count == 1, let marker = open.utf16.first else { return true }
        var run = 0
        var index = NSMaxRange(before) - 1
        while index >= 0, source.character(at: index) == marker {
            run += 1
            index -= 1
        }
        return run % 2 == 1
    }

    private func isWrapped(_ text: String) -> Bool {
        text.utf16.count >= open.utf16.count + close.utf16.count && text.hasPrefix(open) && text.hasSuffix(close)
    }
}

// MARK: - Lines

/// Tools that act on every line the selection touches.
private nonisolated struct LineEditor {
    let source: NSString
    let selection: NSRange

    private var lineRange: NSRange {
        // A selection that ends right after a line break doesn't reach into the next line.
        var covered = selection
        if covered.length > 0, source.character(at: NSMaxRange(covered) - 1) == 0x0A {
            covered.length -= 1
        }
        return source.lineRange(for: covered)
    }

    /// The lines without their final line break, which stays where it is.
    private var block: (range: NSRange, lines: [String]) {
        var range = lineRange
        if range.length > 0, source.character(at: NSMaxRange(range) - 1) == 0x0A {
            range.length -= 1
        }
        return (range, source.substring(with: range).components(separatedBy: "\n"))
    }

    func heading(level: Int) -> TextEdit {
        let levels = block.lines.filter(isContent).map(Self.headingLevel)
        let isAlreadyApplied = level > 0 && !levels.isEmpty && levels.allSatisfy { $0 == level }
        let prefix = isAlreadyApplied || level == 0 ? "" : String(repeating: "#", count: level) + " "
        return replacingPrefixes(matching: /^ {0,3}#{1,6}(?:[ \t]+|$)/) { _ in prefix }
    }

    func quote() -> TextEdit {
        let isQuoted = block.lines.filter(isContent).allSatisfy { $0.firstMatch(of: Self.quotePrefix) != nil }
        if isQuoted, block.lines.contains(where: isContent) {
            return replacingPrefixes(matching: Self.quotePrefix) { _ in "" }
        }
        return replacingPrefixes(matching: /^/) { line in isContent(line) ? "> " : ">" }
    }

    func bulletList() -> TextEdit {
        let isBulleted = block.lines.filter(isContent).allSatisfy { $0.firstMatch(of: Self.bulletPrefix) != nil }
        if isBulleted, block.lines.contains(where: isContent) {
            return replacingListMarkers { _, indentation in indentation }
        }
        return replacingListMarkers { _, indentation in indentation + "- " }
    }

    func numberedList() -> TextEdit {
        let isNumbered = block.lines.filter(isContent).allSatisfy { $0.firstMatch(of: Self.numberPrefix) != nil }
        if isNumbered, block.lines.contains(where: isContent) {
            return replacingListMarkers { _, indentation in indentation }
        }
        return replacingListMarkers { ordinal, indentation in indentation + "\(ordinal). " }
    }

    func codeBlock() -> TextEdit {
        let (range, lines) = block
        if lines.count >= 2, let first = lines.first, let last = lines.last,
           first.firstMatch(of: Self.fence) != nil, last.firstMatch(of: Self.fence) != nil {
            let inner = lines.dropFirst().dropLast().joined(separator: "\n")
            return TextEdit(range: range, replacement: inner, selection: NSRange(location: range.location, length: inner.utf16.count))
        }
        let content = lines.joined(separator: "\n")
        let replacement = "```\n" + content + "\n```"
        let contentStart = range.location + 4
        return TextEdit(range: range, replacement: replacement, selection: NSRange(location: contentStart, length: content.utf16.count))
    }

    // MARK: Helpers

    private static var quotePrefix: Regex<Substring> { /^ {0,3}> ?/ }
    private static var bulletPrefix: Regex<Substring> { /^\s*[-*+][ \t]+/ }
    private static var numberPrefix: Regex<Substring> { /^\s*\d{1,9}[.)][ \t]+/ }
    private static var listPrefix: Regex<(Substring, Substring)> { /^(\s*)(?:[-*+]|\d{1,9}[.)])[ \t]+/ }
    private static var fence: Regex<Substring> { /^ {0,3}(?:```|~~~)/ }

    private static func headingLevel(of line: String) -> Int {
        guard let match = line.firstMatch(of: /^ {0,3}(#{1,6})(?:[ \t]|$)/) else { return 0 }
        return match.1.count
    }

    private func isContent(_ line: String) -> Bool {
        line.contains { !$0.isWhitespace }
    }

    /// Replaces each line's list marker, numbering the lines with content from 1.
    private func replacingListMarkers(_ marker: @escaping (_ ordinal: Int, _ indentation: String) -> String) -> TextEdit {
        var ordinal = 0
        return transformingLines { line in
            guard isContent(line) else { return (line, 0, 0) }
            ordinal += 1
            let match = line.firstMatch(of: Self.listPrefix)
            let indentation = match.map { String($0.1) } ?? String(line.prefix { $0 == " " || $0 == "\t" })
            let oldPrefixLength = match.map { $0.0.utf16.count } ?? indentation.utf16.count
            let newPrefix = marker(ordinal, indentation)
            let rest = String(line.utf16.dropFirst(oldPrefixLength)) ?? line
            return (newPrefix + rest, oldPrefixLength, newPrefix.utf16.count)
        }
    }

    private func replacingPrefixes(
        matching pattern: Regex<Substring>,
        with newPrefix: @escaping (String) -> String
    ) -> TextEdit {
        let isSingleLine = block.lines.count == 1
        return transformingLines { line in
            // Several lines at once leave the empty ones alone, but a single empty line is where
            // the person wants to start typing.
            guard isSingleLine || isContent(line) || newPrefix(line) == ">" else { return (line, 0, 0) }
            let oldPrefixLength = line.firstMatch(of: pattern)?.0.utf16.count ?? 0
            let prefix = newPrefix(line)
            let rest = String(line.utf16.dropFirst(oldPrefixLength)) ?? line
            return (prefix + rest, oldPrefixLength, prefix.utf16.count)
        }
    }

    /// Rewrites each line. The closure returns the new line and the lengths of the prefix it
    /// replaced and of the one it wrote, which is how the caret stays on the same character.
    private func transformingLines(_ transform: (String) -> (line: String, oldPrefix: Int, newPrefix: Int)) -> TextEdit {
        let (range, lines) = block
        let results = lines.map(transform)
        let replacement = results.map(\.line).joined(separator: "\n")
        guard selection.length == 0, let first = results.first else {
            return TextEdit(range: range, replacement: replacement, selection: NSRange(location: range.location, length: replacement.utf16.count))
        }
        let column = selection.location - range.location
        let newColumn = max(first.newPrefix, column - first.oldPrefix + first.newPrefix)
        return TextEdit(range: range, replacement: replacement, selection: NSRange(location: range.location + newColumn, length: 0))
    }
}

// MARK: - Blocks

/// Inserts a block of its own, with the blank lines Markdown needs around it. Without the one
/// before, `---` under a paragraph would turn that paragraph into a heading.
private nonisolated struct BlockInserter {
    let source: NSString
    let selection: NSRange

    func insert(_ block: String, selecting placeholder: String? = nil) -> TextEdit {
        let line = contentRange(ofLineAt: NSMaxRange(selection))
        let lineIsEmpty = isBlank(line)
        let insertion: NSRange
        var prefix = ""
        if lineIsEmpty {
            insertion = line
            if line.location > 0, !isBlank(contentRange(ofLineAt: line.location - 1)) { prefix = "\n" }
        } else {
            insertion = NSRange(location: NSMaxRange(line), length: 0)
            prefix = "\n\n"
        }
        let hasNextLine = NSMaxRange(line) < source.length
        let nextLineHasContent = hasNextLine && !isBlank(contentRange(ofLineAt: NSMaxRange(line) + 1))
        let suffix = nextLineHasContent ? "\n" : ""
        let replacement = prefix + block + suffix
        let blockStart = insertion.location + prefix.utf16.count
        return TextEdit(range: insertion, replacement: replacement, selection: finalSelection(in: block, startingAt: blockStart, placeholder: placeholder))
    }

    private func finalSelection(in block: String, startingAt start: Int, placeholder: String?) -> NSRange {
        if let placeholder, let found = block.range(of: placeholder) {
            let offset = block.utf16.distance(from: block.startIndex, to: found.lowerBound)
            return NSRange(location: start + offset, length: placeholder.utf16.count)
        }
        return NSRange(location: start + block.utf16.count, length: 0)
    }

    private func contentRange(ofLineAt location: Int) -> NSRange {
        var range = source.lineRange(for: NSRange(location: min(location, source.length), length: 0))
        if range.length > 0, source.character(at: NSMaxRange(range) - 1) == 0x0A {
            range.length -= 1
        }
        return range
    }

    private func isBlank(_ range: NSRange) -> Bool {
        !source.substring(with: range).contains { !$0.isWhitespace }
    }
}
