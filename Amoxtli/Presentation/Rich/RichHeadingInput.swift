import AppKit

/// Interprets heading syntax only in the paragraph being typed into. The serializer still
/// escapes literal text; this changes the paragraph's kind before the edit is published.
@MainActor
enum RichHeadingInput {
    struct Replacement {
        let range: NSRange
        let text: NSAttributedString
    }

    static func replacement(
        for input: Any,
        in storage: NSAttributedString,
        range: NSRange,
        kind: RichParagraphKind,
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> Replacement? {
        guard let text = (input as? String) ?? (input as? NSAttributedString)?.string,
              kind.block == .paragraph, !text.isEmpty,
              text.rangeOfCharacter(from: .newlines) == nil,
              range.location <= storage.length, range.length <= storage.length - range.location else { return nil }
        let paragraph = storage.contentRange(of: storage.paragraphRange(at: range.location))
        guard NSMaxRange(range) <= NSMaxRange(paragraph) else { return nil }
        // Most keystrokes cannot introduce a heading. Avoid copying the growing paragraph
        // unless the edit starts with a marker or retains one at the beginning.
        if range.location == paragraph.location {
            guard text.hasPrefix("#") || text.hasPrefix("\\") else { return nil }
        } else {
            let first = (storage.string as NSString).character(at: paragraph.location)
            guard first == 0x23 || first == 0x5C else { return nil }
            if storage.attribute(.literalHeadingMarker, at: paragraph.location, effectiveRange: nil) as? Bool == true {
                return nil
            }
        }

        let replaced = NSRange(location: paragraph.location, length: NSMaxRange(range) - paragraph.location)
        let prefix = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: replaced))
        let localRange = NSRange(location: range.location - paragraph.location, length: range.length)
        // Input methods can commit attributed strings with only composition attributes.
        // Keep the editor's semantic kind and styles as defaults for every committed run.
        let inserted = NSMutableAttributedString(string: text, attributes: typingAttributes)
        if let attributed = input as? NSAttributedString {
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, run, _ in
                inserted.addAttributes(attributes, range: run)
            }
        }
        prefix.replaceCharacters(in: localRange, with: inserted)

        // Only consume an escape entered now. A backslash already present in a loaded
        // document is content and must survive edits elsewhere in the paragraph.
        if localRange.location <= 1, prefix.string.hasPrefix("\\#"), isPlainMarker(in: prefix, length: 2) {
            prefix.deleteCharacters(in: NSRange(location: 0, length: 1))
            prefix.addAttribute(.literalHeadingMarker, value: true, range: NSRange(location: 0, length: 1))
            return Replacement(range: replaced, text: prefix)
        }

        guard prefix.string.hasPrefix("#"),
              prefix.attribute(.literalHeadingMarker, at: 0, effectiveRange: nil) as? Bool != true,
              let marker = prefix.string.range(of: #"^#{1,6}[ \t]+(?=\S)"#, options: .regularExpression) else { return nil }
        let markerLength = NSRange(marker, in: prefix.string).length
        guard isPlainMarker(in: prefix, length: markerLength) else { return nil }
        let level = prefix.string.prefix { $0 == "#" }.count
        prefix.deleteCharacters(in: NSRange(location: 0, length: markerLength))
        prefix.addAttribute(.richParagraph, value: kind.with(block: .heading(level: level)), range: NSRange(location: 0, length: prefix.length))
        return Replacement(range: replaced, text: prefix)
    }

    private static func isPlainMarker(in text: NSAttributedString, length: Int) -> Bool {
        var isPlain = true
        text.enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, _, stop in
            let style = InlineStyle(rawValue: attributes[.inlineStyle] as? Int ?? 0)
            if style.contains(.code) || attributes[.link] != nil {
                isPlain = false
                stop.pointee = true
            }
        }
        return isPlain
    }
}
