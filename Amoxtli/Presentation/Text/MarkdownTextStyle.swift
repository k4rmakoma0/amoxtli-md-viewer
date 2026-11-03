import AppKit

/// The kind of text a block shows, which decides its font once the typography is known.
enum MarkdownTextRole: Equatable {
    case body, tableCell, tableHeader, code
    case heading(level: Int)
}

struct MarkdownTextStyle: Equatable {
    var font: NSFont
    var lineSpacing: CGFloat = 0

    init(_ role: MarkdownTextRole, typography: Typography) {
        switch role {
        case .body:
            font = typography.body
            lineSpacing = 3 * typography.size.scale
        case .tableCell:
            font = typography.body
        case .tableHeader:
            font = typography.body.withTraits(.bold)
        case .code:
            font = typography.code
        case .heading(let level):
            font = typography.heading(level: level)
        }
    }
}

nonisolated extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
