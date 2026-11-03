import AppKit

/// AppKit is required here: SwiftUI's `TextEditor` has no access to the text storage, which the
/// syntax highlighting styles, nor to the selection the formatting tools act on.
final class SourceTextView: NSTextView {
    weak var controller: SourceEditorController?

    private let readingWidth: CGFloat = 800
    private let minimumMargin: CGFloat = 32

    static func make() -> SourceTextView {
        let view = SourceTextView(usingTextLayoutManager: true)
        view.configure()
        return view
    }

    private func configure() {
        isEditable = true
        isSelectable = true
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        // Substitutions would change Markdown syntax: smart quotes break code, and a dash
        // replacement breaks `---`.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        smartInsertDeleteEnabled = false
        isContinuousSpellCheckingEnabled = true
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        setAccessibilityLabel(String(localized: "Markdown"))
    }

    /// Replaces everything, as when another file is shown. Undo can't reach the previous text.
    func replaceAll(with text: String) {
        guard let textStorage else { return }
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: text)
        setSelectedRange(NSRange(location: 0, length: 0))
        undoManager?.removeAllActions(withTarget: textStorage)
        undoManager?.removeAllActions(withTarget: self)
    }

    /// Applies a formatting tool's edit as one undoable step.
    func apply(_ edit: TextEdit, actionName: String) {
        guard let textStorage, isEditable, shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        undoManager?.setActionName(actionName)
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    // MARK: - Layout

    /// Keeps lines at a comfortable reading width, centered, like the formatted view.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let margin = max(minimumMargin, (newSize.width - readingWidth) / 2)
        if textContainerInset.width != margin {
            textContainerInset = NSSize(width: margin, height: 40)
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        menu.addItem(standardItem(String(localized: "Cortar"), action: #selector(cut(_:))))
        menu.addItem(standardItem(String(localized: "Copiar"), action: #selector(copy(_:))))
        menu.addItem(standardItem(String(localized: "Pegar"), action: #selector(paste(_:))))
        menu.addItem(.separator())
        menu.addItem(formatItem())
        menu.addItem(.separator())
        menu.addItem(standardItem(String(localized: "Seleccionar todo"), action: #selector(selectAll(_:))))
        return menu
    }

    private func standardItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func formatItem() -> NSMenuItem {
        let submenu = NSMenu()
        for (index, group) in FormatTool.menuGroups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            for tool in group {
                submenu.addItem(toolItem(tool))
            }
        }
        let item = NSMenuItem(title: String(localized: "Formato"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func toolItem(_ tool: FormatTool) -> NSMenuItem {
        let action = MenuAction { [weak controller] in
            controller?.perform(tool)
        }
        let item = NSMenuItem(title: tool.title, action: #selector(MenuAction.invoke), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.image = NSImage(systemSymbolName: tool.systemImage, accessibilityDescription: nil)
        return item
    }
}
