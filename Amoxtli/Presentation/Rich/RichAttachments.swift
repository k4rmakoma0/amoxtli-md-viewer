import AppKit

/// Attachments for the blocks that aren't text: a divider and images.
@MainActor
enum RichAttachments {
    static func horizontalRule() -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = HorizontalRuleCell()
        return attachment
    }

    /// Remote images load in the background; until then, and for images the sandbox can't
    /// reach, a symbol stands in for them.
    static func image(_ image: MarkdownImage) -> NSTextAttachment {
        let attachment = ImageAttachment()
        attachment.image = NSImage(systemSymbolName: "photo", accessibilityDescription: image.altText)
        attachment.bounds = CGRect(x: 0, y: 0, width: 24, height: 20)
        if image.isRemote {
            attachment.load(image.source)
        }
        return attachment
    }
}

/// An image that resizes itself once loaded. The text view it belongs to lays out again then.
/// It is only touched on the main actor; AppKit declares attachments without isolation.
nonisolated final class ImageAttachment: NSTextAttachment, @unchecked Sendable {
    private static let maximumWidth: CGFloat = 760
    weak var layoutManager: NSLayoutManager?

    @MainActor
    func load(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return }
            self?.show(image)
        }
    }

    @MainActor
    private func show(_ image: NSImage) {
        let scale = min(1, Self.maximumWidth / max(image.size.width, 1))
        self.image = image
        bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
        guard let layoutManager, let storage = layoutManager.textStorage else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value as? ImageAttachment === self {
                layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                stop.pointee = true
            }
        }
    }
}

/// A line across the whole width of the text.
nonisolated final class HorizontalRuleCell: NSTextAttachmentCell {
    private let height: CGFloat = 16

    override func cellFrame(
        for textContainer: NSTextContainer,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        NSRect(x: 0, y: 0, width: max(lineFrag.width - textContainer.lineFragmentPadding * 2, 1), height: height)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        NSColor.separatorColor.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.midY.rounded(), width: cellFrame.width, height: 1).fill()
    }

    override func wantsToTrackMouse() -> Bool {
        false
    }
}
