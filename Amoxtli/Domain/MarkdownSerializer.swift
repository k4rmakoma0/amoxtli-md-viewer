import Foundation

/// Writes the formatted editor's paragraphs back as Markdown. The output is canonical, not the
/// original source: `-` for bullets, `**` and `*` for emphasis, fenced code. What it guarantees
/// is that parsing the result gives back the same document.
nonisolated struct MarkdownSerializer {
    private var lines: [String] = []
    private var previous: RichParagraph?
    private var itemNumbers: [Int: Int] = [:]
    private var itemsSeen: [Int: Int] = [:]
    private var markerWidths: [Int: Int] = [:]
    private var bulletByList: [Int: Character] = [:]

    static func markdown(from paragraphs: [RichParagraph]) -> String {
        var serializer = MarkdownSerializer()
        var index = paragraphs.startIndex
        while index < paragraphs.endIndex {
            let unit = unitEnd(startingAt: index, in: paragraphs)
            serializer.write(Array(paragraphs[index..<unit]))
            index = unit
        }
        return serializer.lines.isEmpty ? "" : serializer.lines.joined(separator: "\n") + "\n"
    }

    /// Code lines and table cells are written together as one block.
    private static func unitEnd(startingAt start: Int, in paragraphs: [RichParagraph]) -> Int {
        let first = paragraphs[start]
        var end = start + 1
        while end < paragraphs.endIndex, belongTogether(first, paragraphs[end]) {
            end += 1
        }
        return end
    }

    private static func belongTogether(_ first: RichParagraph, _ other: RichParagraph) -> Bool {
        guard first.containers == other.containers else { return false }
        switch (first.block, other.block) {
        case (.code(let a, _), .code(let b, _)): return a == b
        case (.tableCell(let a), .tableCell(let b)): return a.tableID == b.tableID
        default: return false
        }
    }

    // MARK: - Units

    private mutating func write(_ unit: [RichParagraph]) {
        guard let first = unit.first, let last = unit.last else { return }
        // An empty top-level paragraph is only a blank line, which Markdown already puts
        // between blocks.
        if first.block == .paragraph, first.containers.isEmpty, first.runs.allSatisfy({ $0.text.allSatisfy(\.isWhitespace) }) {
            return
        }
        if let previous {
            writeSeparator(after: previous, before: first)
        }
        let (firstPrefix, continuationPrefix) = prefixes(for: first)
        for (index, line) in content(of: unit).enumerated() {
            let prefixed = (index == 0 ? firstPrefix : continuationPrefix) + line
            lines.append(line.isEmpty ? trimmingTrailingSpaces(prefixed) : prefixed)
        }
        previous = last
    }

    private func content(of unit: [RichParagraph]) -> [String] {
        guard let first = unit.first else { return [] }
        switch first.block {
        case .paragraph:
            return InlineSerializer.markdown(first.runs)
                .components(separatedBy: "\n")
                .enumerated()
                .map { index, line in LineStart.escaped(index == 0 ? line : String(line.drop { $0 == " " })) }
        case .heading(let level):
            let text = InlineSerializer.markdown(first.runs.map { InlineRun(text: $0.text.replacingOccurrences(of: "\n", with: " "), style: $0.style, link: $0.link) })
            return [trimmingTrailingSpaces(String(repeating: "#", count: level) + " " + LineStart.escapingClosingHashes(text))]
        case .code(_, let language):
            return codeBlock(unit.map(\.plainText), language: language)
        case .thematicBreak:
            return ["---"]
        case .image(let image):
            return ["![\(InlineSerializer.escapedLabel(image.altText))](\(InlineSerializer.destination(image.source)))"]
        case .tableCell:
            return TableSerializer.lines(for: unit)
        }
    }

    private func codeBlock(_ code: [String], language: String?) -> [String] {
        let longestRun = code.map(InlineSerializer.longestBacktickRun).max() ?? 0
        let fence = String(repeating: "`", count: max(3, longestRun + 1))
        return [fence + (language ?? "")] + code + [fence]
    }

    // MARK: - Containers

    /// The prefix of the paragraph's first line and of the lines after it. A list item's marker
    /// only goes on the first line of its first paragraph; everything after is indented to match.
    private mutating func prefixes(for paragraph: RichParagraph) -> (first: String, continuation: String) {
        var first = ""
        var continuation = ""
        for (depth, container) in paragraph.containers.enumerated() {
            switch container {
            case .quote:
                first += "> "
                continuation += "> "
            case .listItem(let item):
                let isContinuing = previous.map { $0.containers.indices.contains(depth) && $0.containers[depth] == container } ?? false
                if isContinuing {
                    let indent = String(repeating: " ", count: markerWidths[item.itemID] ?? 2)
                    first += indent
                    continuation += indent
                } else {
                    let marker = newItemMarker(for: item, atDepth: depth)
                    first += marker
                    continuation += String(repeating: " ", count: marker.count)
                }
            }
        }
        return (first, continuation)
    }

    private mutating func newItemMarker(for item: RichListItem, atDepth depth: Int) -> String {
        let bullet = bullet(for: item, atDepth: depth)
        let marker: String
        if item.isOrdered {
            let index = itemsSeen[item.listID, default: 0]
            itemsSeen[item.listID] = index + 1
            marker = "\(item.start + index)\(bullet) "
        } else {
            marker = "\(bullet) "
        }
        markerWidths[item.itemID] = marker.count
        return marker
    }

    /// Two different lists one after the other would merge into one if they used the same
    /// marker, so the second one switches to the alternative.
    private mutating func bullet(for item: RichListItem, atDepth depth: Int) -> Character {
        if let known = bulletByList[item.listID] { return known }
        let standard: Character = item.isOrdered ? "." : "-"
        let alternative: Character = item.isOrdered ? ")" : "*"
        var chosen = standard
        if let previous, previous.containers.indices.contains(depth),
           case .listItem(let neighbor) = previous.containers[depth],
           neighbor.listID != item.listID, neighbor.isOrdered == item.isOrdered,
           bulletByList[neighbor.listID] == standard {
            chosen = alternative
        }
        bulletByList[item.listID] = chosen
        return chosen
    }

    // MARK: - Separators

    /// List items follow each other directly; anything else gets a blank line, which keeps the
    /// quotes and list items it is inside.
    private mutating func writeSeparator(after previous: RichParagraph, before next: RichParagraph) {
        let shared = zip(previous.containers, next.containers).prefix { $0 == $1 }.count
        if shared < next.containers.count, case .listItem(let item) = next.containers[shared] {
            if shared < previous.containers.count, case .listItem(let other) = previous.containers[shared], other.listID == item.listID {
                return
            }
            let startsSublist = shared == previous.containers.count && shared > 0 && (!item.isOrdered || item.start == 1)
            if startsSublist, [.paragraph].contains(previous.block) || isHeading(previous.block) {
                return
            }
        }
        var blank = ""
        for container in next.containers.prefix(shared) {
            switch container {
            case .quote:
                blank += "> "
            case .listItem(let item):
                blank += String(repeating: " ", count: markerWidths[item.itemID] ?? 2)
            }
        }
        lines.append(trimmingTrailingSpaces(blank))
    }

    private func isHeading(_ block: RichBlock) -> Bool {
        if case .heading = block { return true }
        return false
    }

    private func trimmingTrailingSpaces(_ line: String) -> String {
        String(line.reversed().drop { $0 == " " }.reversed())
    }
}

// MARK: - Line starts

/// Text at the start of a line that Markdown would read as syntax.
private nonisolated enum LineStart {
    static func escaped(_ line: String) -> String {
        let patterns = [
            #"^#{1,6}(?:\s|$)"#,
            #"^>"#,
            #"^[-+*](?:\s|$)"#,
            #"^(?:=+|-+)\s*$"#,
            #"^(?:```|~~~)"#,
        ]
        if patterns.contains(where: { line.range(of: $0, options: .regularExpression) != nil }) {
            return "\\" + line
        }
        if let number = line.range(of: #"^\d{1,9}(?=[.)](?:\s|$))"#, options: .regularExpression) {
            return line[number] + "\\" + line[number.upperBound...]
        }
        return line
    }

    /// A heading's text ending in `#` would lose it as a closing sequence.
    static func escapingClosingHashes(_ text: String) -> String {
        guard text.hasSuffix("#") else { return text }
        let hashes = text.reversed().prefix { $0 == "#" }.count
        return text.dropLast(hashes) + "\\" + String(repeating: "#", count: hashes)
    }
}

// MARK: - Tables

private nonisolated enum TableSerializer {
    static func lines(for cells: [RichParagraph]) -> [String] {
        let positions = cells.compactMap { paragraph -> (RichTableCell, [InlineRun])? in
            guard case .tableCell(let cell) = paragraph.block else { return nil }
            return (cell, paragraph.runs)
        }
        guard let alignments = positions.first?.0.alignments, !alignments.isEmpty else { return [] }
        let rowCount = (positions.map(\.0.row).max() ?? 0) + 1
        var grid = Array(repeating: Array(repeating: "", count: alignments.count), count: rowCount)
        for (cell, runs) in positions where alignments.indices.contains(cell.column) {
            let text = InlineSerializer.markdown(runs, escapingPipes: true).replacingOccurrences(of: "\\\n", with: " ")
            grid[cell.row][cell.column] = text
        }
        let delimiter = alignments.map { alignment -> String in
            switch alignment {
            case .leading: "---"
            case .center: ":---:"
            case .trailing: "---:"
            }
        }
        let header = grid.first ?? []
        return [row(header), row(delimiter)] + grid.dropFirst().map(row)
    }

    private static func row(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }
}

// MARK: - Inline

nonisolated enum InlineSerializer {
    private enum Marker: CaseIterable {
        case underline, strikethrough, strong, emphasis

        var style: InlineStyle {
            switch self {
            case .underline: .underline
            case .strikethrough: .strikethrough
            case .strong: .strong
            case .emphasis: .emphasis
            }
        }

        var open: String {
            switch self {
            case .underline: "<u>"
            case .strikethrough: "~~"
            case .strong: "**"
            case .emphasis: "*"
            }
        }

        var close: String {
            self == .underline ? "</u>" : open
        }
    }

    static func markdown(_ runs: [InlineRun], escapingPipes: Bool = false) -> String {
        let characters = Array(runs.map(\.text).joined())
        let escaper = Escaper(characters: characters, escapesPipes: escapingPipes)
        var output = ""
        var offset = 0
        for segment in linkSegments(of: runs) {
            let length = segment.runs.reduce(0) { $0 + $1.text.count }
            let styled = styledText(segment.runs, startingAt: offset, escaper: escaper)
            if let link = segment.link {
                output += "[\(styled)](\(destination(link)))"
            } else {
                output += styled
            }
            offset += length
        }
        return output
    }

    static func destination(_ url: URL) -> String {
        let text = url.absoluteString
        return text.contains(where: { $0.isWhitespace || "()<>".contains($0) }) ? "<\(text.replacingOccurrences(of: ">", with: "%3E"))>" : text
    }

    static func escapedLabel(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    static func longestBacktickRun(_ text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    private static func linkSegments(of runs: [InlineRun]) -> [(link: URL?, runs: [InlineRun])] {
        var segments: [(link: URL?, runs: [InlineRun])] = []
        for run in runs where !run.text.isEmpty {
            if let last = segments.indices.last, segments[last].link == run.link {
                segments[last].runs.append(run)
            } else {
                segments.append((run.link, [run]))
            }
        }
        return segments
    }

    /// Opens and closes markers as the style changes from run to run. Spaces at the edges of a
    /// styled run go outside its markers, since `** bold**` isn't bold in Markdown.
    private static func styledText(_ runs: [InlineRun], startingAt start: Int, escaper: Escaper) -> String {
        var output = ""
        var open: [Marker] = []
        var offset = start
        for (index, run) in runs.enumerated() {
            let before = index > 0 ? runs[index - 1].style : []
            let after = index + 1 < runs.count ? runs[index + 1].style : []
            for piece in pieces(of: run, before: before, after: after) {
                let wanted = Marker.allCases.filter { piece.style.contains($0.style) }
                if let firstUnwanted = open.firstIndex(where: { !wanted.contains($0) }) {
                    output += open[firstUnwanted...].reversed().map(\.close).joined()
                    open.removeSubrange(firstUnwanted...)
                }
                for marker in wanted where !open.contains(marker) {
                    output += marker.open
                    open.append(marker)
                }
                let range = offset..<(offset + piece.text.count)
                output += piece.style.contains(.code) ? codeSpan(piece.text) : escaper.escaped(range)
                offset = range.upperBound
            }
        }
        output += open.reversed().map(\.close).joined()
        return output
    }

    /// The spaces keep the styles they share with the run beside them, which stay open across.
    private static func pieces(of run: InlineRun, before: InlineStyle, after: InlineStyle) -> [InlineRun] {
        guard !run.style.isEmpty, !run.style.contains(.code) else { return [run] }
        let leading = run.text.prefix { $0.isWhitespace }
        let rest = run.text.dropFirst(leading.count)
        let trailing = rest.reversed().prefix { $0.isWhitespace }.count
        let core = rest.dropLast(trailing)
        return [
            InlineRun(text: String(leading), style: run.style.intersection(before).subtracting(.code)),
            InlineRun(text: String(core), style: run.style),
            InlineRun(text: String(rest.suffix(trailing)), style: run.style.intersection(after).subtracting(.code)),
        ].filter { !$0.text.isEmpty }
    }

    private static func codeSpan(_ code: String) -> String {
        let fence = String(repeating: "`", count: longestBacktickRun(code) + 1)
        let padding = code.hasPrefix("`") || code.hasSuffix("`") ? " " : ""
        return fence + padding + code + padding + fence
    }
}

/// Escapes the characters of a paragraph that Markdown would otherwise read as syntax. It sees
/// the whole paragraph, since whether `*` or `[` is syntax depends on what surrounds it.
private nonisolated struct Escaper {
    let characters: [Character]
    let escapesPipes: Bool
    private let hasLinkSyntax: Bool

    init(characters: [Character], escapesPipes: Bool) {
        self.characters = characters
        self.escapesPipes = escapesPipes
        let text = String(characters)
        hasLinkSyntax = text.contains("](") || text.contains("][")
    }

    func escaped(_ range: Range<Int>) -> String {
        range.map(escaped(at:)).joined()
    }

    private func escaped(at index: Int) -> String {
        let character = characters[index]
        let before = index > 0 ? characters[index - 1] : nil
        let after = index + 1 < characters.count ? characters[index + 1] : nil
        switch character {
        case "\\", "`":
            return "\\\(character)"
        case "\n":
            return "\\\n"
        case "*", "~":
            return isSpaceOrEdge(before) && isSpaceOrEdge(after) ? "\(character)" : "\\\(character)"
        case "_":
            let isInsideWord = isWordCharacter(before) && isWordCharacter(after)
            return isInsideWord || (isSpaceOrEdge(before) && isSpaceOrEdge(after)) ? "_" : "\\_"
        case "[", "]":
            return hasLinkSyntax ? "\\\(character)" : "\(character)"
        case "<":
            return after.map { $0.isLetter || "/!?".contains($0) } ?? false ? "\\<" : "<"
        case "&":
            return startsEntity(at: index) ? "\\&" : "&"
        case "|":
            return escapesPipes ? "\\|" : "|"
        default:
            return "\(character)"
        }
    }

    private func isSpaceOrEdge(_ character: Character?) -> Bool {
        character.map(\.isWhitespace) ?? true
    }

    private func isWordCharacter(_ character: Character?) -> Bool {
        character.map { $0.isLetter || $0.isNumber } ?? false
    }

    private func startsEntity(at index: Int) -> Bool {
        let rest = String(characters[(index + 1)...].prefix(32))
        return rest.range(of: #"^#?[A-Za-z0-9]+;"#, options: .regularExpression) != nil
    }
}
