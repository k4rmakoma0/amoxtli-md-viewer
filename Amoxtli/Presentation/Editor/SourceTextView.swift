import AppKit

/// AppKit is required here: SwiftUI's `TextEditor` has no access to the text storage, which the
/// syntax highlighting styles, nor to the selection the formatting tools act on.
final class SourceTextView: NSTextView {
    weak var controller: EditorController?
    /// Called when the view takes keyboard focus, before anything can be typed.
    var onFocus: (() -> Void)?

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

    /// Shows text that changed elsewhere, as an edit in the formatted editor. Only what differs
    /// is replaced, so the selection, the scroll position and the highlighting of the rest stay.
    /// Its own undo steps no longer match the text, so they go.
    func show(_ text: String) {
        guard let textStorage else { return }
        let difference = TextDifference(from: textStorage.string, to: text)
        guard !difference.isEmpty else { return }
        let selection = difference.adjusting(selectedRange())
        textStorage.replaceCharacters(in: difference.range, with: difference.replacement)
        let location = min(selection.location, textStorage.length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, textStorage.length - location)))
        undoManager?.removeAllActions(withTarget: textStorage)
        undoManager?.removeAllActions(withTarget: self)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { controller?.formatsChanged(in: self) }
    }

    override func didChangeText() {
        super.didChangeText()
        controller?.formatsChanged(in: self)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocus?()
            controller?.activate(self)
        }
        return didBecome
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
        EditingContextMenu.make(for: self, controller: controller)
    }
}

extension SourceTextView: FormattingTarget {
    var selectedText: String {
        (string as NSString).substring(with: selectedRange())
    }

    var activeFormats: ActiveFormats {
        guard let textStorage else { return .none }
        let selection = selectedRange()
        let lineStart = (string as NSString).lineRange(for: NSRange(location: selection.location, length: 0)).location
        let startsInFence = SourceHighlighter.isInFence(atLineStart: lineStart, in: textStorage)
        return SourceFormatDetector.activeFormats(in: string, selection: selection, startsInFence: startsInFence)
    }

    func apply(_ command: FormatCommand, actionName: String) {
        apply(MarkdownFormatter.edit(for: command, in: string, selection: selectedRange()), actionName: actionName)
    }

    func revealHeading(_ entry: TOCEntry, among entries: [TOCEntry]) {
        guard let location = SourceHeadingLocator.location(of: entry, among: entries, in: string) else { return }
        let range = NSRange(location: location, length: 0)
        setSelectedRange(range)
        scrollRangeToVisible(range)
    }

    func focusEditor() {
        window?.makeFirstResponder(self)
    }
}
