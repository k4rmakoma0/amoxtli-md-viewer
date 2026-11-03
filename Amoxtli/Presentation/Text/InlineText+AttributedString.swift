import AppKit

extension InlineText {
    func attributedString(style: MarkdownTextStyle, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing

        let result = NSMutableAttributedString()
        for run in runs {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: run.style.font(basedOn: style.font),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
            if run.style.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if run.style.contains(.underline) {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
            }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }
}

private extension InlineStyle {
    func font(basedOn base: NSFont) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if contains(.strong) { traits.insert(.bold) }
        if contains(.emphasis) { traits.insert(.italic) }
        let font = contains(.code)
            ? NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
            : base
        return traits.isEmpty ? font : font.withTraits(traits)
    }
}
