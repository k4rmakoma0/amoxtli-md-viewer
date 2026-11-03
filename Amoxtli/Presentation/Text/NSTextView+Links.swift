import AppKit

/// Finding links under the pointer in the formatted editor, which uses TextKit 1: its layout
/// manager answers these questions directly.
extension NSTextView {
    /// Asks the layout manager directly: in a visible window, `characterIndexForInsertion(at:)`
    /// returns the end of the text, so no link would ever be found.
    func linkCharacterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        // The layout manager answers with the nearest character, even for a point beside the line.
        guard index < textStorage.length, rect(ofCharacterAt: index).contains(point) else { return nil }
        return index
    }

    func link(atCharacter index: Int) -> URL? {
        Self.linkURL(from: textStorage?.attribute(.link, at: index, effectiveRange: nil))
    }

    /// The whole text of the link, even when part of it has its own style.
    func linkText(atCharacter index: Int) -> String? {
        guard let textStorage, index < textStorage.length else { return nil }
        var range = NSRange()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        _ = textStorage.attribute(.link, at: index, longestEffectiveRange: &range, in: fullRange)
        return (textStorage.string as NSString).substring(with: range)
    }

    static func linkURL(from attribute: Any?) -> URL? {
        switch attribute {
        case let url as URL: url
        case let string as String: URL(string: string)
        default: nil
        }
    }

    private func rect(ofCharacterAt index: Int) -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let characters = NSRange(location: index, length: 1)
        let glyphs = layoutManager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }
}
