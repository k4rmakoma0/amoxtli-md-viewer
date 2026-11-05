import AppKit

/// The colors of code tokens, the same in both editors: a light and a dark value each, tuned
/// to read well on the code background, close to Xcode's default theme. Comments use the
/// system's secondary label color.
nonisolated enum CodeColors {
    static func color(for kind: CodeTokenKind) -> NSColor {
        switch kind {
        case .keyword: keyword
        case .type: type
        case .string: string
        case .number: number
        case .comment: .secondaryLabelColor
        case .property: property
        case .tag: tag
        case .attribute: attribute
        }
    }

    private static let keyword = dynamic("keyword", light: 0x9B2393, dark: 0xFF7AB2)
    private static let type = dynamic("type", light: 0x3900A0, dark: 0xDABAFF)
    private static let string = dynamic("string", light: 0xC41A16, dark: 0xFF8170)
    private static let number = dynamic("number", light: 0x1C00CF, dark: 0xD9C97C)
    private static let property = dynamic("property", light: 0x326D74, dark: 0x67B7A4)
    private static let tag = dynamic("tag", light: 0x0B4F79, dark: 0x5DD8FF)
    private static let attribute = dynamic("attribute", light: 0x815F03, dark: 0xCC9768)

    private static func dynamic(_ name: String, light: Int, dark: Int) -> NSColor {
        NSColor.adaptive("code.\(name)") { isDark, _ in isDark ? rgb(dark) : rgb(light) }
    }

    private static func rgb(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Colors a code block's text, which starts at `range.location`, over the base color
    /// already set on it. Without a known language the code keeps the base color.
    static func color(_ range: NSRange, of storage: NSMutableAttributedString, language: CodeLanguage?, base: NSColor) {
        storage.addAttribute(.foregroundColor, value: base, range: range)
        guard let language, range.length > 0 else { return }
        let code = storage.mutableString.substring(with: range)
        for token in CodeHighlighter.tokens(in: code, language: language) {
            let tokenRange = NSRange(location: range.location + token.range.location, length: token.range.length)
            storage.addAttribute(.foregroundColor, value: color(for: token.kind), range: tokenRange)
        }
    }
}
