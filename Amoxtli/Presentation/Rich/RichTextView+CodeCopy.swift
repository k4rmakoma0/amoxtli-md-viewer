import AppKit

/// Copying a whole code block: the button beside its language chip, or Copiar código in the
/// context menu. The code goes to the clipboard as plain text, without the fence.
extension RichTextView {
    /// The code block whose copy button is at a point in the view, as the location its first
    /// paragraph starts at.
    func codeBlock(withCopyButtonAt point: NSPoint) -> Int? {
        guard let layoutManager = layoutManager as? RichLayoutManager else { return nil }
        let origin = textContainerOrigin
        return layoutManager.codeBlock(withCopyButtonAt: NSPoint(x: point.x - origin.x, y: point.y - origin.y))
    }

    /// The copy button's rectangle in the view.
    func codeCopyButtonRect(forBlockAt location: Int) -> NSRect? {
        let origin = textContainerOrigin
        return (layoutManager as? RichLayoutManager)?.codeCopyButtonRect(forBlockAt: location)?.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// The code of the block with a paragraph at a location, without the last line break;
    /// `nil` outside code or for a block with no text yet.
    func code(ofBlockAt location: Int) -> String? {
        guard let textStorage, location < textStorage.length, textStorage.paragraphKind(at: location)?.isCode == true else { return nil }
        let content = textStorage.contentRange(of: textStorage.codeBlockRange(at: location))
        return (textStorage.string as NSString).substring(with: content)
    }

    /// Where the code block at the caret starts; at the end of the text, the block is the
    /// paragraph that ends there.
    var codeBlockAtCaret: Int? {
        guard let textStorage, codeLanguageAtCaret != nil else { return nil }
        let caret = selectedRange().location
        let location = caret == textStorage.length ? caret - 1 : caret
        guard location >= 0, textStorage.paragraphKind(at: location)?.isCode == true else { return nil }
        return textStorage.codeBlockRange(at: location).location
    }

    /// Puts the block's code on the clipboard and shows a check mark on its button for a moment.
    @discardableResult
    func copyCode(ofBlockAt location: Int, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let code = code(ofBlockAt: location) else { return false }
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        showCopied(block: textStorage?.codeBlockRange(at: location).location ?? location)
        return true
    }

    private func showCopied(block: Int) {
        guard let layoutManager = layoutManager as? RichLayoutManager else { return }
        layoutManager.copiedCodeBlock = block
        needsDisplay = true
        NSAccessibility.post(
            element: self,
            notification: .announcementRequested,
            userInfo: [.announcement: String(localized: "Código copiado"), .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, let layoutManager = self.layoutManager as? RichLayoutManager, layoutManager.copiedCodeBlock == block else { return }
            layoutManager.copiedCodeBlock = nil
            self.needsDisplay = true
        }
    }
}
