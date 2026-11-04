import AppKit

/// Moves the document between its paragraphs and the text the formatted editor shows.
@MainActor
struct RichTextConverter {
    let styler: RichStyler

    /// Hard line breaks are line separators in the text view, so they stay inside the paragraph.
    private static let lineSeparator = "\u{2028}"
    private static let attachmentCharacter = "\u{FFFC}"

    func attributedString(from paragraphs: [RichParagraph]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let kind = RichParagraphKind(block: paragraph.block, containers: paragraph.containers)
            result.append(content(of: paragraph, kind: kind))
            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: styler.attributes(for: kind, style: [])))
            }
        }
        let storage = NSTextStorage(attributedString: result)
        styler.restyle(NSRange(location: 0, length: storage.length), in: storage)
        return storage
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
