import AppKit

/// The formatted document, editable as in a word processor. Markdown syntax never shows: what a
/// paragraph is lives in its attributes, and the editor writes the Markdown from them.
///
/// AppKit is required here: SwiftUI has no editable rich text view, and tables need
/// `NSTextTable`, which only TextKit 1 lays out.
final class RichTextView: NSTextView {
    weak var controller: EditorController?
    weak var links: LinkInteractionViewModel?
    /// Called when the view takes keyboard focus, before anything can be typed.
    var onFocus: (() -> Void)?
    let styler: RichStyler
    private(set) lazy var converter = RichTextConverter(styler: styler)

    private let normalizer: RichTextNormalizer
    private var hoverTrackingArea: NSTrackingArea?
    /// Ids for the lists, items, quotes and code blocks the tools create. They start far above
    /// those of a freshly built document, so the two never collide.
    private var nextID = 1_000_000
    private let readingWidth: CGFloat = 800
    private let minimumMargin: CGFloat = 32

    static func make() -> RichTextView {
        let styler = RichStyler()
        let storage = NSTextStorage()
        let layoutManager = RichLayoutManager()
        layoutManager.styler = styler
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = RichTextView(frame: .zero, textContainer: container, styler: styler)
        storage.delegate = view.normalizer
        return view
    }

    private init(frame: NSRect, textContainer: NSTextContainer, styler: RichStyler) {
        self.styler = styler
        normalizer = RichTextNormalizer(styler: styler)
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RichTextView is only created in code")
    }

    private func configure() {
        isEditable = true
        isSelectable = true
        isRichText = true
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        usesFontPanel = false
        // Substitutions would write characters the person didn't type into the Markdown.
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
        linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        typingAttributes = styler.attributes(for: .body, style: [])
        setAccessibilityLabel(String(localized: "Documento"))
    }

    // MARK: - Content

    /// Replaces the whole document. Undo can't reach the previous one.
    func show(_ paragraphs: [RichParagraph]) {
        guard let textStorage else { return }
        styler.forgetTables()
        var editable = paragraphs
        if case .tableCell = paragraphs.last?.block {
            // An empty final cell needs a newline to carry its position in text storage.
            // A following body paragraph also lets typing continue outside the table.
            editable.append(RichParagraph(block: .paragraph))
        }
        textStorage.setAttributedString(converter.attributedString(from: editable))
        normalizer.discardPending()
        updateListAccessibility()
        connectImages()
        undoManager?.removeAllActions(withTarget: textStorage)
        undoManager?.removeAllActions(withTarget: self)
        updateTypingAttributes()
    }

    var paragraphs: [RichParagraph] {
        textStorage.map(converter.paragraphs(from:)) ?? []
    }

    func makeID() -> Int {
        nextID += 1
        return nextID
    }

    private func connectImages() {
        guard let textStorage else { return }
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            (value as? ImageAttachment)?.layoutManager = layoutManager
        }
    }

    // MARK: - Accessibility

    /// VoiceOver can't see the drawn bullets and numbers, so the first paragraph of each item
    /// carries them as accessibility attributes. Only paragraphs whose marker changed are
    /// touched, since every attribute change lays the text out again.
    private func updateListAccessibility() {
        guard let textStorage, textStorage.length > 0 else { return }
        let markers = RichListMarker.markers(in: textStorage).compactMapValues(\.last)
        let whole = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.accessibilityListItemIndex, in: whole) { value, range, _ in
            if value != nil, markers[textStorage.paragraphRange(at: range.location).location] == nil {
                removeListAccessibility(in: range, of: textStorage)
            }
        }
        for (location, marker) in markers {
            let paragraph = textStorage.paragraphRange(at: location)
            let index = textStorage.attribute(.accessibilityListItemIndex, at: location, effectiveRange: nil) as? Int
            let prefix = textStorage.attribute(.accessibilityListItemPrefix, at: location, effectiveRange: nil) as? NSAttributedString
            guard index != marker.index || prefix?.string != marker.text + " " else { continue }
            textStorage.addAttributes([
                .accessibilityListItemPrefix: NSAttributedString(string: marker.text + " "),
                .accessibilityListItemIndex: marker.index,
                .accessibilityListItemLevel: marker.level,
            ], range: paragraph)
        }
        textStorage.endEditing()
    }

    private func removeListAccessibility(in range: NSRange, of textStorage: NSTextStorage) {
        for key in [NSAttributedString.Key.accessibilityListItemPrefix, .accessibilityListItemIndex, .accessibilityListItemLevel] {
            textStorage.removeAttribute(key, range: range)
        }
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let margin = max(minimumMargin, (newSize.width - readingWidth) / 2)
        if textContainerInset.width != margin {
            textContainerInset = NSSize(width: margin, height: 40)
        }
    }

    // MARK: - Paragraph kinds

    /// The kind of the paragraph at a location. The empty paragraph at the end of the text has
    /// no characters to hold one, so it continues the text before it, unless that is a block
    /// that can't be typed into.
    func kind(at location: Int) -> RichParagraphKind {
        guard let textStorage else { return .body }
        let paragraph = textStorage.paragraphRange(at: location)
        if paragraph.length > 0, let kind = textStorage.paragraphKind(at: paragraph.location) {
            return kind
        }
        guard paragraph.location > 0, let previous = textStorage.paragraphKind(at: paragraph.location - 1) else { return .body }
        return previous.isText ? previous : RichParagraphKind.body.with(containers: previous.containers)
    }

    /// Changes paragraphs' kinds as one undoable step.
    func changeKinds(of paragraphs: [NSRange], to kinds: [RichParagraphKind]) {
        guard let textStorage, let first = paragraphs.first, let last = paragraphs.last else { return }
        let union = NSUnionRange(first, last)
        guard shouldChangeText(in: union, replacementString: nil) else { return }
        textStorage.beginEditing()
        for (range, kind) in zip(paragraphs, kinds) {
            textStorage.addAttribute(.richParagraph, value: kind, range: range)
        }
        styler.restyle(textStorage.withNeighborParagraphs(union), in: textStorage)
        textStorage.endEditing()
        didChangeText()
        updateTypingAttributes()
    }

    /// Sets the kind of the paragraph at a location, even the empty one at the end.
    func setKind(_ kind: RichParagraphKind, ofParagraphAt location: Int) {
        guard let textStorage else { return }
        let paragraph = textStorage.paragraphRange(at: location)
        if paragraph.length == 0 {
            typingAttributes = styler.attributes(for: kind, style: [])
            needsDisplay = true
        } else {
            changeKinds(of: [paragraph], to: [kind])
        }
    }

    /// Typing continues the paragraph at the caret and the style of the text just before it.
    private func updateTypingAttributes() {
        guard let textStorage else { return }
        let caret = selectedRange().location
        let paragraph = textStorage.paragraphRange(at: caret)
        let style = caret > paragraph.location ? textStorage.inlineStyle(at: caret - 1) : []
        typingAttributes = styler.attributes(for: kind(at: caret), style: style)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { updateTypingAttributes() }
    }

    /// Paragraphs are made uniform before anyone hears of the change, so the Markdown written
    /// from them is already right.
    override func didChangeText() {
        if let textStorage { normalizer.normalizePending(in: textStorage) }
        updateListAccessibility()
        super.didChangeText()
        if editRemovedText {
            editRemovedText = false
            clearEmptyElementAtCaret()
        }
    }

    /// Whether the edit in progress only removes text, which is when an element may be left empty.
    private var editRemovedText = false

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let shouldChange = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if shouldChange {
            editRemovedText = affectedCharRange.length > 0 && replacementString?.isEmpty == true
        }
        return shouldChange
    }

    /// Deleting all of an element's text deletes the element too: a heading, a list item, a
    /// quote or a code block left empty becomes body text, and so does what is typed next.
    /// Without this, the empty paragraph and the style kept for typing stay that element until
    /// the caret moves. Two empty lines keep what they are, since emptiness is part of them: a
    /// table cell, and a blank line between other lines of a code block. An element chosen for
    /// an empty paragraph isn't touched either, since choosing it removes no text.
    private func clearEmptyElementAtCaret() {
        guard let textStorage, selectedRange().length == 0 else { return }
        let caret = selectedRange().location
        let paragraph = textStorage.paragraphRange(at: caret)
        guard textStorage.contentRange(of: paragraph).length == 0 else { return }
        let current = paragraph.length > 0
            ? textStorage.paragraphKind(at: paragraph.location)
            : typingAttributes[.richParagraph] as? RichParagraphKind
        guard let current, current != .body, current.tableCell == nil else { return }
        if current.isCode, isInsideLongerCodeBlock(paragraph, kind: current, in: textStorage) { return }
        setKind(.body, ofParagraphAt: caret)
        if paragraph.length > 0 { updateTypingAttributes() }
    }

    private func isInsideLongerCodeBlock(_ paragraph: NSRange, kind: RichParagraphKind, in textStorage: NSTextStorage) -> Bool {
        let before = paragraph.location > 0 ? textStorage.paragraphKind(at: paragraph.location - 1) : nil
        let after = textStorage.paragraphKind(at: NSMaxRange(paragraph))
        return before == kind || after == kind
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocus?()
            controller?.activate(self)
        }
        return didBecome
    }

    /// Text from elsewhere comes in plain, taking the style of where it lands.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    // MARK: - Keys

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        // insertText commits an input method's composition; setMarkedText owns the interim
        // characters. A commit without an explicit range replaces that composition in full.
        let implicitRange = hasMarkedText() ? markedRange() : selectedRange()
        let range = replacementRange.location == NSNotFound ? implicitRange : replacementRange
        if selectedRanges.count == 1, let textStorage,
           let replacement = RichHeadingInput.replacement(
               for: insertString, in: textStorage, range: range,
               kind: kind(at: range.location), typingAttributes: typingAttributes
           ) {
            // Replace only the prefix through the typed text. AppKit keeps the caret at its
            // end and records both the removed syntax and the new kind in the same undo step.
            super.insertText(replacement.text, replacementRange: replacement.range)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    override func insertNewline(_ sender: Any?) {
        guard let textStorage else { return super.insertNewline(sender) }
        let caret = selectedRange()
        let kind = kind(at: caret.location)
        let paragraph = textStorage.paragraphRange(at: caret.location)
        let content = textStorage.contentRange(of: paragraph)
        if kind.tableCell != nil, moveToCell(after: paragraph) { return }
        // Return on an empty item or quote line steps out of it, as in Pages.
        if caret.length == 0, content.length == 0, !kind.containers.isEmpty, kind.isText {
            return setKind(kind.with(containers: outdented(kind.containers)), ofParagraphAt: caret.location)
        }
        if kind.isCode, content.length == 0, caret.location > 0, self.kind(at: caret.location - 1) == kind {
            return setKind(kind.with(block: .paragraph), ofParagraphAt: caret.location)
        }
        let isAtEnd = caret.location == NSMaxRange(content)
        super.insertNewline(sender)
        let next = kindAfterNewline(from: kind, isAtEnd: isAtEnd)
        if next != kind {
            setKind(next, ofParagraphAt: selectedRange().location)
        }
    }

    private func kindAfterNewline(from kind: RichParagraphKind, isAtEnd: Bool) -> RichParagraphKind {
        var next = kind
        switch kind.block {
        case .heading where isAtEnd, .thematicBreak, .image, .tableCell:
            next = kind.with(block: .paragraph)
        default:
            break
        }
        if case .listItem(let item) = next.containers.last {
            next = next.with(containers: next.containers.dropLast() + [.listItem(newItem(like: item))])
        }
        return next
    }

    override func insertTab(_ sender: Any?) {
        guard let textStorage else { return super.insertTab(sender) }
        let paragraph = textStorage.paragraphRange(at: selectedRange().location)
        let kind = kind(at: selectedRange().location)
        if kind.tableCell != nil {
            if !moveToCell(after: paragraph) { NSSound.beep() }
        } else if case .listItem = kind.containers.last {
            indentListItems()
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        guard let textStorage else { return super.insertBacktab(sender) }
        let paragraph = textStorage.paragraphRange(at: selectedRange().location)
        let kind = kind(at: selectedRange().location)
        if kind.tableCell != nil {
            if !moveToCell(before: paragraph) { NSSound.beep() }
        } else if case .listItem = kind.containers.last {
            setKind(kind.with(containers: outdented(kind.containers)), ofParagraphAt: selectedRange().location)
        } else {
            super.insertBacktab(sender)
        }
    }

    /// At the start of a paragraph, Delete first undoes what the paragraph is (a list item, a
    /// quote, a heading) before joining it with the one above, as in Pages.
    override func deleteBackward(_ sender: Any?) {
        guard let textStorage, selectedRange().length == 0 else { return super.deleteBackward(sender) }
        let caret = selectedRange().location
        let paragraph = textStorage.paragraphRange(at: caret)
        guard caret == paragraph.location, caret > 0 else { return super.deleteBackward(sender) }
        let kind = kind(at: caret)
        let previous = self.kind(at: caret - 1)
        switch previous.block {
        case .thematicBreak, .image:
            return deleteParagraph(at: caret - 1)
        case .tableCell where kind.tableCell == nil || kind.tableCell?.tableID == previous.tableCell?.tableID:
            return setSelectedRange(NSRange(location: caret - 1, length: 0))
        default:
            break
        }
        // The first paragraph of an item or a quote: what's around it differs from the line above.
        if !kind.containers.isEmpty, kind.containers != previous.containers {
            return setKind(kind.with(containers: outdented(kind.containers)), ofParagraphAt: caret)
        }
        if case .heading = kind.block {
            return setKind(kind.with(block: .paragraph), ofParagraphAt: caret)
        }
        if kind.isCode, previous != kind {
            return setKind(kind.with(block: .paragraph), ofParagraphAt: caret)
        }
        super.deleteBackward(sender)
    }

    private func deleteParagraph(at location: Int) {
        guard let textStorage else { return }
        let range = textStorage.paragraphRange(at: location)
        guard shouldChangeText(in: range, replacementString: "") else { return }
        textStorage.replaceCharacters(in: range, with: "")
        didChangeText()
    }

    // MARK: - Lists

    func newItem(like item: RichListItem) -> RichListItem {
        RichListItem(listID: item.listID, itemID: makeID(), isOrdered: item.isOrdered, start: item.start)
    }

    /// One level out. Leaving a nested list makes the paragraph a new item of the list around it.
    func outdented(_ containers: [RichContainer]) -> [RichContainer] {
        var result = Array(containers.dropLast())
        if case .listItem = containers.last, case .listItem(let parent) = result.last {
            result[result.count - 1] = .listItem(newItem(like: parent))
        }
        return result
    }

    /// Makes each selected item part of the item above it, in a list nested there.
    private func indentListItems() {
        guard let textStorage else { return }
        let ranges = textStorage.paragraphRanges(in: selectedRange())
        var kinds: [RichParagraphKind] = []
        var previous = ranges.first.map { $0.location > 0 ? kind(at: $0.location - 1) : RichParagraphKind.body } ?? .body
        for range in ranges {
            let kind = kind(at: range.location)
            let depth = kind.containers.count - 1
            guard case .listItem(let item) = kind.containers.last, previous.containers.count > depth,
                  case .listItem(let sibling) = previous.containers[depth], sibling.listID == item.listID else {
                kinds.append(kind)
                previous = kind
                continue
            }
            let nestedListID: Int
            if previous.containers.count > depth + 1, case .listItem(let nested) = previous.containers[depth + 1] {
                nestedListID = nested.listID
            } else {
                nestedListID = makeID()
            }
            let nested = RichListItem(listID: nestedListID, itemID: makeID(), isOrdered: item.isOrdered, start: 1)
            let indented = kind.with(containers: Array(previous.containers.prefix(depth + 1)) + [.listItem(nested)])
            kinds.append(indented)
            previous = indented
        }
        changeKinds(of: ranges, to: kinds)
    }

    // MARK: - Tables

    @discardableResult
    private func moveToCell(after paragraph: NSRange) -> Bool {
        guard let textStorage, let cell = kind(at: paragraph.location).tableCell else { return false }
        let next = NSMaxRange(paragraph)
        if next < textStorage.length, kind(at: next).tableCell?.tableID == cell.tableID {
            setSelectedRange(textStorage.contentRange(of: textStorage.paragraphRange(at: next)))
            return true
        }
        return false
    }

    @discardableResult
    private func moveToCell(before paragraph: NSRange) -> Bool {
        guard let textStorage, paragraph.location > 0, let cell = kind(at: paragraph.location).tableCell else { return false }
        guard kind(at: paragraph.location - 1).tableCell?.tableID == cell.tableID else { return false }
        setSelectedRange(textStorage.contentRange(of: textStorage.paragraphRange(at: paragraph.location - 1)))
        return true
    }

    // MARK: - Links

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        links?.hover(linkCharacterIndex(at: point).flatMap(link(atCharacter:)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        links?.hover(nil)
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        guard let url = NSTextView.linkURL(from: link), let links else { return }
        let text = linkText(atCharacter: charIndex)
        Task { await links.activate(url, displayedText: text) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let links, let index = linkCharacterIndex(at: point), let url = link(atCharacter: index) {
            return LinkContextMenu.make(model: links.menuModel(for: url, displayedText: linkText(atCharacter: index)), links: links)
        }
        return EditingContextMenu.make(for: self, controller: controller)
    }
}

/// Keeps every paragraph uniform as text is typed, pasted or deleted: each one takes the kind
/// of its first character and is styled again, along with its neighbors, whose spacing
/// depends on it. This happens once the edit is done: restyling beyond the edited range while
/// the text view is still processing it would move the selection to the end of that range.
@MainActor
final class RichTextNormalizer: NSObject, NSTextStorageDelegate {
    private let styler: RichStyler
    private var pending: NSRange?

    init(styler: RichStyler) {
        self.styler = styler
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        pending = pending.map { NSUnionRange($0, editedRange) } ?? editedRange
    }

    func discardPending() {
        pending = nil
    }

    func normalizePending(in textStorage: NSTextStorage) {
        guard let edited = pending, textStorage.length > 0 else { return }
        pending = nil
        let start = min(edited.location, textStorage.length - 1)
        let end = min(NSMaxRange(edited), textStorage.length - 1)
        let range = NSUnionRange(textStorage.paragraphRange(at: start), textStorage.paragraphRange(at: end))
        textStorage.beginEditing()
        styler.restyle(textStorage.withNeighborParagraphs(range), in: textStorage)
        textStorage.endEditing()
    }
}
