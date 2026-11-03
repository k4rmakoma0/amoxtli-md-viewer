import Foundation

/// Finds where a table of contents entry is in the Markdown source, so the source editor can
/// scroll to it. Entries come from the parsed model, which has no source positions.
nonisolated enum SourceHeadingLocator {
    /// UTF-16 offset of the heading's line, or `nil` when the source has no such heading.
    static func location(of entry: TOCEntry, among entries: [TOCEntry], in text: String) -> Int? {
        guard let target = entries.firstIndex(where: { $0.id == entry.id }) else { return nil }
        let lines = headingLines(in: text)
        // Matching by title, in order, survives headings the scanner can't see, such as those
        // inside a list. Formatting in the title is ignored on both sides.
        var cursor = 0
        for (index, candidate) in entries.enumerated() where index <= target {
            let key = normalized(candidate.title)
            guard let match = lines[cursor...].firstIndex(where: { normalized($0.title) == key }) else {
                if index == target { break }
                continue
            }
            if index == target { return lines[match].location }
            cursor = match + 1
        }
        return lines.count == entries.count ? lines[target].location : nil
    }

    private static func headingLines(in text: String) -> [(location: Int, title: String)] {
        let source = text as NSString
        return MarkdownSyntaxScanner.scan(text).spans.compactMap { span in
            guard case .heading = span.kind else { return nil }
            let line = source.substring(with: span.range)
            let title = line.replacing(/^ {0,3}#{1,6}[ \t]*/, with: "").replacing(/[ \t]+#+[ \t]*$/, with: "")
            return (span.range.location, title)
        }
    }

    private static func normalized(_ title: String) -> String {
        String(title.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
