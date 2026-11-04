import AppKit

nonisolated extension NSAttributedString.Key {
    /// What a paragraph is and what it sits inside, as a `RichParagraphKind`. Every character of
    /// a paragraph, its line break included, carries the same value.
    static let richParagraph = NSAttributedString.Key("dev.alananaya.amoxtli.richParagraph")
    /// The `InlineStyle` of the text, as its raw value. Fonts are derived from it, so it is what
    /// is read back when writing Markdown.
    static let inlineStyle = NSAttributedString.Key("dev.alananaya.amoxtli.inlineStyle")
    /// A literal leading hash, loaded from Markdown or entered with `\#`. Kept on the hash
    /// itself so later typing cannot turn it into a heading after its escape is hidden.
    static let literalHeadingMarker = NSAttributedString.Key("dev.alananaya.amoxtli.literalHeadingMarker")
}

/// A paragraph's block and containers, boxed as an object so the text storage can hold it and
/// tell when two runs carry the same one.
nonisolated final class RichParagraphKind: NSObject, Sendable {
    let block: RichBlock
    let containers: [RichContainer]

    static let body = RichParagraphKind(block: .paragraph, containers: [])

    init(block: RichBlock, containers: [RichContainer]) {
        self.block = block
        self.containers = containers
    }

    func with(block: RichBlock) -> RichParagraphKind {
        RichParagraphKind(block: block, containers: containers)
    }

    func with(containers: [RichContainer]) -> RichParagraphKind {
        RichParagraphKind(block: block, containers: containers)
    }

    var isText: Bool {
        switch block {
        case .paragraph, .heading: true
        default: false
        }
    }

    var tableCell: RichTableCell? {
        if case .tableCell(let cell) = block { return cell }
        return nil
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RichParagraphKind else { return false }
        return block == other.block && containers == other.containers
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(block)
        hasher.combine(containers)
        return hasher.finalize()
    }
}

nonisolated extension NSAttributedString {
    /// The paragraph around a location, line break included. At the very end of a text that
    /// ends with a line break, that is the empty paragraph after it.
    func paragraphRange(at location: Int) -> NSRange {
        (string as NSString).paragraphRange(for: NSRange(location: min(location, length), length: 0))
    }

    func paragraphRanges(in range: NSRange) -> [NSRange] {
        let text = string as NSString
        var ranges: [NSRange] = []
        var location = text.paragraphRange(for: NSRange(location: min(range.location, length), length: 0)).location
        repeat {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }
            ranges.append(paragraph)
            location = NSMaxRange(paragraph)
        } while location < NSMaxRange(range)
        return ranges
    }

    func paragraphKind(at location: Int) -> RichParagraphKind? {
        guard location < length else { return nil }
        return attribute(.richParagraph, at: location, effectiveRange: nil) as? RichParagraphKind
    }

    func inlineStyle(at location: Int) -> InlineStyle {
        guard location < length, let raw = attribute(.inlineStyle, at: location, effectiveRange: nil) as? Int else { return [] }
        return InlineStyle(rawValue: raw)
    }

    /// The paragraphs of a range plus the ones just before and after it.
    func withNeighborParagraphs(_ range: NSRange) -> NSRange {
        var result = range
        if result.location > 0 {
            result = NSUnionRange(result, paragraphRange(at: result.location - 1))
        }
        if NSMaxRange(result) < length {
            result = NSUnionRange(result, paragraphRange(at: NSMaxRange(result)))
        }
        return result
    }

    /// The paragraph's text, without its line break.
    func contentRange(of paragraph: NSRange) -> NSRange {
        var content = paragraph
        let text = string as NSString
        while content.length > 0, [0x0A, 0x0D, 0x2029].contains(text.character(at: NSMaxRange(content) - 1)) {
            content.length -= 1
        }
        return content
    }
}
