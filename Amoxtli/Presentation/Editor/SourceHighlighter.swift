import AppKit

/// Styles the Markdown source as it is typed. Only the edited lines are scanned again, unless the
/// edit opens or closes a fenced code block, which changes every line after it.
@MainActor
final class SourceHighlighter: NSObject, NSTextStorageDelegate {
    var typography = Typography()

    private static let fenceKey = NSAttributedString.Key("dev.alananaya.amoxtli.fencedLine")

    private var font: NSFont { typography.body }

    var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3 * typography.size.scale
        return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    /// Styles the whole text again, as when the typography changes.
    func restyle(_ storage: NSTextStorage) {
        highlight(NSRange(location: 0, length: storage.length), in: storage, startsInFence: false, followsUp: false)
    }

    // `willProcessEditing` is where the delegate may change attributes of the edited text.
    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let lines = (textStorage.string as NSString).lineRange(for: editedRange)
        highlight(lines, in: textStorage, startsInFence: startsInFence(lines, in: textStorage), followsUp: true)
    }

    private func highlight(_ lines: NSRange, in storage: NSTextStorage, startsInFence: Bool, followsUp: Bool) {
        let text = storage.string
        let scan = MarkdownSyntaxScanner.scan(text, lines: lines, startsInFence: startsInFence)
        apply(scan, to: lines, in: storage)
        colorCode(touching: lines, in: storage)
        let next = NSMaxRange(lines)
        guard followsUp, next < storage.length, scan.endsInFence != nextLineStartsInFence(at: next, in: storage, text: text) else { return }
        // The edit opened or closed a code block: everything below it changes.
        highlight(NSRange(location: next, length: storage.length - next), in: storage, startsInFence: scan.endsInFence, followsUp: false)
    }

    private func startsInFence(_ lines: NSRange, in storage: NSTextStorage) -> Bool {
        Self.isInFence(atLineStart: lines.location, in: storage)
    }

    /// Whether the line starting at a location begins inside a fenced code block, as the last
    /// highlighting pass found it.
    static func isInFence(atLineStart location: Int, in storage: NSAttributedString) -> Bool {
        location > 0 && location <= storage.length && storage.attribute(fenceKey, at: location - 1, effectiveRange: nil) != nil
    }

    /// What the line after the edit was scanned with, worked out from how it was marked: a fence
    /// line marked as open opened a block, so it started outside one, and the opposite for others.
    private func nextLineStartsInFence(at location: Int, in storage: NSTextStorage, text: String) -> Bool {
        let source = text as NSString
        let line = content(of: source.lineRange(for: NSRange(location: location, length: 0)), in: source)
        let isMarked = storage.attribute(Self.fenceKey, at: location, effectiveRange: nil) != nil
        return MarkdownSyntaxScanner.isFence(line, in: text) ? !isMarked : isMarked
    }

    private func apply(_ scan: SyntaxScan, to lines: NSRange, in storage: NSTextStorage) {
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: lines)
        for line in scan.fencedLines {
            storage.addAttribute(Self.fenceKey, value: true, range: line)
        }
        for span in scan.spans {
            style(span, in: storage)
        }
        storage.endEditing()
    }

    // MARK: - Code

    /// Colors the code blocks the lines touch, each one whole, from the line after its opening
    /// fence up to its closing fence. The fence marks of the lines before tell where a block
    /// that started above them opened; code with no known language keeps the base color.
    private func colorCode(touching lines: NSRange, in storage: NSTextStorage) {
        let text = storage.string
        let source = text as NSString
        var location = blockStart(before: lines.location, in: storage, source: source)
        var opening: (info: String, codeStart: Int)?
        while location < storage.length, location < NSMaxRange(lines) || opening != nil {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            let startsInFence = Self.isInFence(atLineStart: line.location, in: storage)
            let isMarked = storage.attribute(Self.fenceKey, at: line.location, effectiveRange: nil) != nil
            if !startsInFence, isMarked {
                opening = (MarkdownSyntaxScanner.fenceInfo(content(of: line, in: source), in: text), NSMaxRange(line))
            } else if startsInFence, !isMarked, let block = opening {
                color(NSRange(location: block.codeStart, length: line.location - block.codeStart), info: block.info, in: storage)
                opening = nil
            }
            location = NSMaxRange(line)
        }
        if let block = opening {
            color(NSRange(location: block.codeStart, length: storage.length - block.codeStart), info: block.info, in: storage)
        }
    }

    /// The start of the opening fence line of the block a location is in, or of its own line.
    private func blockStart(before location: Int, in storage: NSTextStorage, source: NSString) -> Int {
        var line = source.lineRange(for: NSRange(location: min(location, storage.length), length: 0))
        while line.location > 0, Self.isInFence(atLineStart: line.location, in: storage) {
            line = source.lineRange(for: NSRange(location: line.location - 1, length: 0))
        }
        return line.location
    }

    private func color(_ code: NSRange, info: String, in storage: NSTextStorage) {
        guard code.length > 0, let language = CodeLanguage(fenceInfo: info) else { return }
        storage.beginEditing()
        CodeColors.color(code, of: storage, language: language, base: .labelColor)
        storage.endEditing()
    }

    private func content(of line: NSRange, in source: NSString) -> NSRange {
        var content = line
        while content.length > 0, [0x0A, 0x0D].contains(source.character(at: NSMaxRange(content) - 1)) {
            content.length -= 1
        }
        return content
    }

    // MARK: - Styles

    private func style(_ span: SyntaxSpan, in storage: NSTextStorage) {
        switch span.kind {
        case .heading(let level):
            let size = font.pointSize * headingScale(level)
            let heading = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
            storage.addAttribute(.font, value: heading.withTraits(.bold), range: span.range)
        case .marker, .linkDestination, .horizontalRule:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
        case .strong:
            addTraits(.bold, to: span.range, in: storage)
        case .emphasis:
            addTraits(.italic, to: span.range, in: storage)
        case .underline:
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
        case .inlineCode, .codeBlock:
            storage.addAttribute(.font, value: typography.code, range: span.range)
            storage.addAttribute(.backgroundColor, value: NSColor.quaternarySystemFill, range: span.range)
        case .linkText:
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: span.range)
        case .quote:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
        case .listMarker:
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: span.range)
        }
    }

    private func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: 1.45
        case 2: 1.3
        case 3: 1.15
        default: 1
        }
    }

    /// Adds to the font already there, so bold inside a heading keeps the heading's size.
    private func addTraits(_ traits: NSFontDescriptor.SymbolicTraits, to range: NSRange, in storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let current = value as? NSFont ?? font
            storage.addAttribute(.font, value: current.withTraits(traits), range: subrange)
        }
    }
}
