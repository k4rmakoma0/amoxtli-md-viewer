import AppKit

/// Moves the document between its paragraphs and the text the formatted editor shows.
@MainActor
struct RichTextConverter {
    let styler: RichStyler

    /// Hard line breaks are line separators in the text view, so they stay inside the paragraph.
    private static let lineSeparator = "\u{2028}"
    private static let attachmentCharacter = "\u{FFFC}"

    /// Each paragraph is styled as soon as it is added, and each code block colored as soon as
    /// it ends. Attributes are kept as an array of runs, so changing them far before the end
    /// of a long text shifts every run after them: styling the whole text afterwards took
    /// minutes for a document of a few megabytes.
    func attributedString(from paragraphs: [RichParagraph]) -> NSAttributedString {
        let kinds = paragraphs.map { RichParagraphKind(block: $0.block, containers: $0.containers) }
        let result = NSMutableAttributedString()
        var codeStart: Int?
        for (index, paragraph) in paragraphs.enumerated() {
            let kind = kinds[index]
            let next = kinds.indices.contains(index + 1) ? kinds[index + 1] : nil
            let start = result.length
            result.append(content(of: paragraph, kind: kind))
            if next != nil {
                result.append(NSAttributedString(string: "\n", attributes: styler.attributes(for: kind, style: [])))
            }
            let range = NSRange(location: start, length: result.length - start)
            styler.style(range, as: kind, previous: index > 0 ? kinds[index - 1] : nil, next: next, in: result)
            guard case .code(let id, _) = kind.block else { continue }
            let blockStart = codeStart ?? start
            if case .code(let nextID, _) = next?.block, nextID == id {
                codeStart = blockStart
            } else {
                let block = NSRange(location: blockStart, length: result.length - blockStart)
                styler.colorCode(result.contentRange(of: block), as: kind, in: result)
                codeStart = nil
            }
        }
        // An empty last paragraph has no characters to carry its kind, so the one before it
        // is spaced as `restyle` spaces it, against the empty last line.
        if result.length > 0, result.mutableString.character(at: result.length - 1) == 0x0A {
            styler.restyle(result.paragraphRange(at: result.length - 1), in: result)
        }
        return result
    }

    private func content(of paragraph: RichParagraph, kind: RichParagraphKind) -> NSAttributedString {
        switch paragraph.block {
        case .thematicBreak:
            return attachment(RichAttachments.horizontalRule(), kind: kind)
        case .image(let image):
            return attachment(RichAttachments.image(image), kind: kind)
        default:
            let text = NSMutableAttributedString()
            for run in paragraph.runs {
                let shown = run.text.replacingOccurrences(of: "\n", with: Self.lineSeparator)
                text.append(NSAttributedString(string: shown, attributes: styler.attributes(for: kind, style: run.style, link: run.link)))
            }
            // A hash that survived parsing is literal. Editing an escaped paragraph must not
            // activate the shortcut used for newly typed heading markers.
            if paragraph.block == .paragraph, text.string.hasPrefix("#") {
                text.addAttribute(.literalHeadingMarker, value: true, range: NSRange(location: 0, length: 1))
            }
            return text
        }
    }

    private func attachment(_ attachment: NSTextAttachment, kind: RichParagraphKind) -> NSAttributedString {
        var attributes = styler.attributes(for: kind, style: [])
        attributes[.attachment] = attachment
        return NSAttributedString(string: Self.attachmentCharacter, attributes: attributes)
    }

    // MARK: - Reading

    func paragraphs(from text: NSAttributedString) -> [RichParagraph] {
        var paragraphs: [RichParagraph] = []
        for range in text.paragraphRanges(in: NSRange(location: 0, length: text.length)) {
            let kind = text.paragraphKind(at: range.location) ?? .body
            let paragraph = RichParagraph(block: kind.block, containers: kind.containers, runs: runs(in: text.contentRange(of: range), of: text, kind: kind))
            // Return inside a table cell makes a second paragraph in the same cell.
            if let last = paragraphs.last, kind.tableCell != nil, last.block == paragraph.block, last.containers == paragraph.containers {
                paragraphs[paragraphs.count - 1].runs += [InlineRun(text: " ")] + paragraph.runs
            } else {
                paragraphs.append(paragraph)
            }
        }
        return paragraphs
    }

    private func runs(in range: NSRange, of text: NSAttributedString, kind: RichParagraphKind) -> [InlineRun] {
        var runs: [InlineRun] = []
        text.enumerateAttributes(in: range) { attributes, run, _ in
            let shown = (text.string as NSString).substring(with: run)
            let content = shown
                .replacingOccurrences(of: Self.attachmentCharacter, with: "")
                .replacingOccurrences(of: Self.lineSeparator, with: "\n")
            guard !content.isEmpty else { return }
            let style = kind.isCode ? [] : InlineStyle(rawValue: attributes[.inlineStyle] as? Int ?? 0)
            let link = kind.isCode ? nil : NSTextView.linkURL(from: attributes[.link])
            // Editor-only attributes may split a semantic run, including an inline code
            // span. They must not create extra Markdown delimiters when writing it back.
            if let last = runs.last, last.style == style, last.link == link {
                runs[runs.count - 1] = InlineRun(text: last.text + content, style: style, link: link)
            } else {
                runs.append(InlineRun(text: content, style: style, link: link))
            }
        }
        return runs
    }
}
