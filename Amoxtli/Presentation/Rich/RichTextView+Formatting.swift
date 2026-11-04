import AppKit

/// The formatting tools, applied directly to the formatted text. Each is one undoable step and
/// works as a toggle, like its Markdown counterpart in the source editor.
extension RichTextView: FormattingTarget {
    var selectedText: String {
        (string as NSString).substring(with: selectedRange())
    }

    func apply(_ command: FormatCommand, actionName: String) {
        switch command {
        case .bold: toggleInline(.strong)
        case .italic: toggleInline(.emphasis)
        case .underline: toggleInline(.underline)
        case .strikethrough: toggleInline(.strikethrough)
        case .inlineCode: toggleInline(.code)
        case .heading(let level): setHeading(level)
        case .quote: toggleQuote()
        case .bulletList: toggleList(isOrdered: false)
        case .numberedList: toggleList(isOrdered: true)
        case .codeBlock: toggleCodeBlock()
        case .table(let dimensions): insertTable(dimensions)
        case .horizontalRule: insertBlocks([RichParagraph(block: .thematicBreak)], selecting: nil)
        case .link(let text, let destination): insertLink(text: text, destination: destination)
        }
        undoManager?.setActionName(actionName)
    }

    func revealHeading(_ entry: TOCEntry, among entries: [TOCEntry]) {
        guard let textStorage, let target = entries.firstIndex(of: entry) else { return }
        var count = 0
        for paragraph in textStorage.paragraphRanges(in: NSRange(location: 0, length: textStorage.length)) {
            guard case .heading = kind(at: paragraph.location).block else { continue }
            if count == target {
                return reveal(paragraph)
            }
            count += 1
        }
    }

    func focusEditor() {
        window?.makeFirstResponder(self)
    }

    /// Puts the paragraph at the top of the view, as following a link to a section does.
    private func reveal(_ paragraph: NSRange) {
        setSelectedRange(NSRange(location: paragraph.location, length: 0))
        guard let layoutManager, let textContainer, let clipView = enclosingScrollView?.contentView else {
            return scrollRangeToVisible(paragraph)
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        let y = max(0, rect.minY + textContainerOrigin.y - 16)
        clipView.scroll(to: NSPoint(x: 0, y: min(y, max(0, frame.height - clipView.bounds.height))))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    // MARK: - Inline

    /// With nothing selected, the style applies to what is typed next.
    private func toggleInline(_ style: InlineStyle) {
        guard let textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else {
            let current = InlineStyle(rawValue: typingAttributes[.inlineStyle] as? Int ?? 0)
            let toggled = current.contains(style) ? current.subtracting(style) : current.union(style)
            typingAttributes = styler.attributes(for: kind(at: range.location), style: toggled)
            return
        }
        var isApplied = true
        textStorage.enumerateAttribute(.inlineStyle, in: range) { value, _, stop in
            if !InlineStyle(rawValue: value as? Int ?? 0).contains(style) {
                isApplied = false
                stop.pointee = true
            }
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.inlineStyle, in: range) { value, run, _ in
            let current = InlineStyle(rawValue: value as? Int ?? 0)
            let updated = isApplied ? current.subtracting(style) : current.union(style)
            textStorage.addAttribute(.inlineStyle, value: updated.rawValue, range: run)
        }
        styler.restyle(range, in: textStorage)
        textStorage.endEditing()
        didChangeText()
    }

    // MARK: - Paragraphs

    private var selectedParagraphs: [NSRange] {
        guard let textStorage else { return [] }
        return textStorage.paragraphRanges(in: selectedRange())
    }

    /// Applies a change to the selected paragraphs, or to the kind of what is typed next in
    /// the empty paragraph at the end.
    private func changeSelectedKinds(_ transform: ([RichParagraphKind]) -> [RichParagraphKind]) {
        let ranges = selectedParagraphs
        guard !ranges.isEmpty else {
            let location = selectedRange().location
            if let changed = transform([kind(at: location)]).first {
                setKind(changed, ofParagraphAt: location)
            }
            return
        }
        changeKinds(of: ranges, to: transform(ranges.map { kind(at: $0.location) }))
    }

    private func setHeading(_ level: Int) {
        changeSelectedKinds { kinds in
            let isApplied = level > 0 && kinds.filter(\.isText).allSatisfy { $0.block == .heading(level: level) }
            let block: RichBlock = level == 0 || isApplied ? .paragraph : .heading(level: level)
            return kinds.map { $0.isText ? $0.with(block: block) : $0 }
        }
    }

    private func toggleQuote() {
        changeSelectedKinds { kinds in
            let isQuoted = kinds.allSatisfy { kind in kind.containers.contains { if case .quote = $0 { true } else { false } } }
            if isQuoted {
                return kinds.map { kind in
                    guard let last = kind.containers.lastIndex(where: { if case .quote = $0 { true } else { false } }) else { return kind }
                    var containers = kind.containers
                    containers.remove(at: last)
                    return kind.with(containers: containers)
                }
            }
            let quote = RichContainer.quote(id: makeID())
            return kinds.map { $0.tableCell == nil ? $0.with(containers: $0.containers + [quote]) : $0 }
        }
    }

    private func toggleList(isOrdered: Bool) {
        let previous = selectedParagraphs.first.flatMap { $0.location > 0 ? kind(at: $0.location - 1) : nil }
        changeSelectedKinds { kinds in
            let items = kinds.map { kind -> RichListItem? in
                if case .listItem(let item) = kind.containers.last { return item }
                return nil
            }
            if items.allSatisfy({ $0?.isOrdered == isOrdered }) {
                return kinds.map { $0.with(containers: Array($0.containers.dropLast())) }
            }
            if items.allSatisfy({ $0 != nil }) {
                let listID = makeID()
                return zip(kinds, items).map { kind, item in
                    guard let item else { return kind }
                    let switched = RichListItem(listID: listID, itemID: item.itemID, isOrdered: isOrdered, start: 1)
                    return kind.with(containers: kind.containers.dropLast() + [.listItem(switched)])
                }
            }
            let (listID, start) = joinableList(after: previous, containers: kinds.first?.containers ?? [], isOrdered: isOrdered)
            return kinds.map { kind in
                guard kind.tableCell == nil else { return kind }
                let item = RichListItem(listID: listID, itemID: makeID(), isOrdered: isOrdered, start: start)
                return kind.with(containers: kind.containers + [.listItem(item)])
            }
        }
    }

    /// A new list right after one of the same kind continues it, as in a word processor.
    private func joinableList(after previous: RichParagraphKind?, containers: [RichContainer], isOrdered: Bool) -> (Int, Int) {
        if let previous, previous.containers.count == containers.count + 1, Array(previous.containers.dropLast()) == containers,
           case .listItem(let item) = previous.containers.last, item.isOrdered == isOrdered {
            return (item.listID, item.start)
        }
        return (makeID(), 1)
    }

    private func toggleCodeBlock() {
        changeSelectedKinds { kinds in
            if kinds.allSatisfy(\.isCode) {
                return kinds.map { $0.with(block: .paragraph) }
            }
            let block = RichBlock.code(id: makeID(), language: nil)
            return kinds.map { $0.isText || $0.isCode ? $0.with(block: block) : $0 }
        }
    }

    // MARK: - Insertions

    private func insertTable(_ dimensions: TableDimensions) {
        let tableID = makeID()
        let alignments = Array(repeating: MarkdownTable.Alignment.leading, count: dimensions.columns)
        let headers = dimensions.headers
        var cells: [RichParagraph] = []
        for row in 0..<dimensions.rows {
            for column in 0..<dimensions.columns {
                let runs = row == 0 ? [InlineRun(text: headers[column])] : []
                cells.append(RichParagraph(block: .tableCell(RichTableCell(tableID: tableID, row: row, column: column, alignments: alignments)), runs: runs))
            }
        }
        insertBlocks(cells, selecting: headers.first)
    }

    /// Inserts blocks after the current paragraph, or in its place when it is empty, with an
    /// empty paragraph after them at the end of the document so typing can go on below.
    private func insertBlocks(_ blocks: [RichParagraph], selecting placeholder: String?) {
        guard let textStorage else { return }
        let caret = selectedRange().location
        let paragraph = textStorage.paragraphRange(at: caret)
        let content = textStorage.contentRange(of: paragraph)
        let current = kind(at: caret)
        let containers = current.tableCell == nil ? current.containers : []
        let placed = blocks.map { RichParagraph(block: $0.block, containers: containers, runs: $0.runs) }
        let isEmpty = content.length == 0 && current.isText
        let insertion = isEmpty ? content : NSRange(location: NSMaxRange(paragraph), length: 0)
        let inserted = NSMutableAttributedString()
        if !isEmpty, paragraph.length == content.length {
            inserted.append(NSAttributedString(string: "\n", attributes: styler.attributes(for: current, style: [])))
        }
        let blockStart = insertion.location + inserted.length
        let following = RichParagraph(block: .paragraph, containers: containers)
        inserted.append(converter.attributedString(from: placed + [following]))
        if NSMaxRange(insertion) < textStorage.length, !isEmpty {
            inserted.append(NSAttributedString(string: "\n", attributes: styler.attributes(for: .body, style: [])))
        }
        guard shouldChangeText(in: insertion, replacementString: inserted.string) else { return }
        textStorage.replaceCharacters(in: insertion, with: inserted)
        styler.restyle(NSRange(location: insertion.location, length: inserted.length), in: textStorage)
        didChangeText()
        let selection = placeholder.flatMap { text -> NSRange? in
            let found = (inserted.string as NSString).range(of: text)
            return found.location == NSNotFound ? nil : NSRange(location: insertion.location + found.location, length: found.length)
        }
        // Otherwise the caret goes to the paragraph after the blocks.
        let afterBlocks = blockStart + converter.attributedString(from: placed).length + 1
        setSelectedRange(selection ?? NSRange(location: min(afterBlocks, textStorage.length), length: 0))
    }

    private func insertLink(text: String, destination: String) {
        guard let textStorage, let url = URL(string: destination) else { return }
        let range = selectedRange()
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (string as NSString).substring(with: range)
        let label = typed.isEmpty ? (current.isEmpty ? destination : current) : typed
        let style = range.length > 0 ? textStorage.inlineStyle(at: range.location) : InlineStyle(rawValue: typingAttributes[.inlineStyle] as? Int ?? 0)
        let attributes = styler.attributes(for: kind(at: range.location), style: style, link: url)
        guard shouldChangeText(in: range, replacementString: label) else { return }
        textStorage.replaceCharacters(in: range, with: NSAttributedString(string: label, attributes: attributes))
        didChangeText()
        setSelectedRange(NSRange(location: range.location + label.utf16.count, length: 0))
    }
}
