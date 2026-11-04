import AppKit

/// The language of a code block. The fence that holds it isn't shown in the formatted editor,
/// so it is chosen from the context menu and shown on the block.
extension RichTextView {
    /// The info string of the code block at the caret: `nil` outside code, `.some(nil)` in
    /// code without a language.
    var codeLanguageAtCaret: String?? {
        guard case .code(_, let language) = kindAtCaret.block else { return nil }
        return .some(language)
    }

    /// Sets the language of the whole code block at the caret as one undoable step; `nil`
    /// leaves the block without one.
    func setCodeLanguage(_ language: String?) {
        guard let textStorage else { return }
        let kind = kindAtCaret
        guard case .code(let id, _) = kind.block else { return }
        let block = RichBlock.code(id: id, language: language)
        let caret = selectedRange().location
        let isOnEmptyLastLine = caret == textStorage.length && textStorage.paragraphRange(at: caret).length == 0
        // At the end of the text, the block is the paragraph that ends there.
        let location = caret == textStorage.length ? caret - 1 : caret
        if location >= 0, case .code(let lineID, _)? = textStorage.paragraphKind(at: location)?.block, lineID == id {
            let paragraphs = textStorage.paragraphRanges(in: textStorage.codeBlockRange(at: location))
            let kinds = paragraphs.map { (textStorage.paragraphKind(at: $0.location) ?? kind).with(block: block) }
            changeKinds(of: paragraphs, to: kinds)
            undoManager?.setActionName(String(localized: "Lenguaje"))
        }
        if isOnEmptyLastLine {
            typingAttributes = styler.attributes(for: kind.with(block: block), style: [])
            needsDisplay = true
        }
    }

    /// The code block whose language chip is at a point in the view, as the location its
    /// first paragraph starts at.
    func codeBlock(withChipAt point: NSPoint) -> Int? {
        guard let layoutManager = layoutManager as? RichLayoutManager else { return nil }
        let origin = textContainerOrigin
        return layoutManager.codeBlock(withChipAt: NSPoint(x: point.x - origin.x, y: point.y - origin.y))
    }

    /// The chip's rectangle in the view.
    func codeChipRect(forBlockAt location: Int) -> NSRect? {
        let origin = textContainerOrigin
        return (layoutManager as? RichLayoutManager)?.codeChipRect(forBlockAt: location)?.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// The menu of languages, under the block's chip. The caret moves into the block first
    /// unless it's already there, since the choice applies to the block at the caret.
    func showLanguageMenu(forBlockAt location: Int) {
        guard let menu = languageMenu(forBlockAt: location), let chip = codeChipRect(forBlockAt: location) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: chip.minX, y: chip.maxY + 4), in: self)
    }

    func languageMenu(forBlockAt location: Int) -> NSMenu? {
        guard let textStorage else { return nil }
        if location < textStorage.length {
            let block = textStorage.contentRange(of: textStorage.codeBlockRange(at: location))
            let caret = selectedRange().location
            if caret < block.location || caret > NSMaxRange(block) {
                setSelectedRange(NSRange(location: location, length: 0))
            }
        }
        guard let current = codeLanguageAtCaret else { return nil }
        let choice = CodeLanguageChoice(current: current) { [weak self] in self?.setCodeLanguage($0) }
        return EditingContextMenu.languageItem(choice).submenu
    }

    /// Right-clicking outside the selection moves the caret there first, so the menu is
    /// about what was clicked.
    func moveCaretForContextMenu(to point: NSPoint) {
        let index = characterIndexForInsertion(at: point)
        let selection = selectedRange()
        guard index < selection.location || index > NSMaxRange(selection) else { return }
        setSelectedRange(NSRange(location: index, length: 0))
    }
}
