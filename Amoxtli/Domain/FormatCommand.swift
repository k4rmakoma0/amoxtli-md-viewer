import Foundation

/// A formatting tool, from the toolbar, the Format menu or the context menu.
nonisolated enum FormatCommand: Hashable, Sendable {
    /// Level 0 turns the line back into body text.
    case heading(Int)
    case bold
    case italic
    case underline
    case strikethrough
    case inlineCode
    case quote
    case bulletList
    case numberedList
    case codeBlock
    case table(TableDimensions)
    case horizontalRule
    case link(text: String, destination: String)

    static let headingLevels = 1...6
}

/// A change to apply to the text, in UTF-16 offsets as the text view counts them.
nonisolated struct TextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
    /// Selection once the replacement is in place.
    let selection: NSRange
}

/// What a person types as a link destination, made into one Markdown can use.
nonisolated enum LinkInput {
    /// `nil` for empty input. Adds `https://` to bare domains and `mailto:` to bare addresses,
    /// and leaves anchors, paths and anything with a scheme as they are.
    static func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if hasScheme(trimmed) || ["#", "/", "."].contains(where: trimmed.hasPrefix) {
            return trimmed
        }
        if trimmed.contains("@"), !trimmed.contains("/") {
            return "mailto:" + trimmed
        }
        return trimmed.contains(".") ? "https://" + trimmed : trimmed
    }

    private static func hasScheme(_ text: String) -> Bool {
        text.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*:/) != nil
    }
}
