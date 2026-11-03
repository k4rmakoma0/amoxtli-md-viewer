import AppKit

/// Draws what the paragraphs' kinds imply but their text doesn't contain: list markers, the bar
/// beside quotes and the background of code blocks. Markers aren't text, so typing never moves
/// or breaks them, and they renumber as items come and go.
nonisolated final class RichLayoutManager: NSLayoutManager {
    weak var styler: RichStyler?

    /// The markers to draw, by the location of the paragraph that starts each item.
    private var markers: [Int: [RichListMarker]]?

    override func processEditing(
        for textStorage: NSTextStorage,
        edited editMask: NSTextStorageEditActions,
        range newCharRange: NSRange,
        changeInLength delta: Int,
        invalidatedRange invalidatedCharRange: NSRange
    ) {
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
        markers = nil
        // Numbers further down may change with any edit to the list. Asking for glyph ranges
        // isn't allowed while the text is being edited, so the whole view repaints.
        for container in textContainers {
            container.textView?.needsDisplay = true
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawDecorations(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawDecorations(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage, let styler else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let markers = currentMarkers(in: textStorage)
        for paragraph in textStorage.paragraphRanges(in: characters) {
            guard let kind = textStorage.paragraphKind(at: paragraph.location) else { continue }
            let lines = lineRects(of: paragraph).map { (rect: $0.rect.offsetBy(dx: origin.x, dy: origin.y), used: $0.used.offsetBy(dx: origin.x, dy: origin.y)) }
            guard let first = lines.first?.rect else { continue }
            let area = lines.map(\.rect).dropFirst().reduce(first) { $0.union($1) }
            if kind.isCode {
                drawCodeBackground(lines.map(\.used), area: area, kind: kind, paragraph: paragraph, styler: styler)
            }
            drawQuoteBars(area, kind: kind, styler: styler)
            for marker in markers[paragraph.location] ?? [] {
                draw(marker.text, depth: marker.depth, kind: kind, paragraph: paragraph, firstLine: first, styler: styler)
            }
        }
    }

    /// Each line's whole fragment, spacing included, and the part its text uses.
    private func lineRects(of paragraph: NSRange) -> [(rect: NSRect, used: NSRect)] {
        let glyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        var rects: [(rect: NSRect, used: NSRect)] = []
        enumerateLineFragments(forGlyphRange: glyphs) { rect, used, _, _, _ in
            rects.append((rect, used))
        }
        return rects
    }

    /// Covers the lines of code without the spacing around the block, plus some padding at
    /// its first and last line.
    private func drawCodeBackground(_ used: [NSRect], area: NSRect, kind: RichParagraphKind, paragraph: NSRange, styler: RichStyler) {
        guard let textStorage, let first = used.first, let last = used.last else { return }
        let padding: CGFloat = 6
        let isFirst = paragraph.location == 0 || textStorage.paragraphKind(at: paragraph.location - 1) != kind
        let isLast = textStorage.paragraphKind(at: NSMaxRange(paragraph)) != kind
        let top = isFirst ? first.minY - padding : area.minY
        let bottom = isLast ? last.maxY + padding : area.maxY
        let indent = styler.indent(of: kind.containers)
        NSColor.quaternarySystemFill.setFill()
        NSRect(x: area.minX + indent, y: top, width: area.width - indent, height: bottom - top).fill()
    }

    private func drawQuoteBars(_ area: NSRect, kind: RichParagraphKind, styler: RichStyler) {
        for (depth, container) in kind.containers.enumerated() {
            guard case .quote = container else { continue }
            let x = area.minX + styler.indent(of: kind.containers.prefix(depth)) + 2
            NSColor.tertiaryLabelColor.setFill()
            NSRect(x: x, y: area.minY, width: 3, height: area.height).fill()
        }
    }

    /// Right-aligned against the item's text, on the first line's baseline.
    private func draw(_ marker: String, depth: Int, kind: RichParagraphKind, paragraph: NSRange, firstLine: NSRect, styler: RichStyler) {
        guard let textStorage else { return }
        let font = textStorage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont ?? styler.typography.body
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let size = (marker as NSString).size(withAttributes: attributes)
        let textStart = styler.indent(of: kind.containers.prefix(depth + 1))
        let firstGlyph = glyphIndexForCharacter(at: paragraph.location)
        let baseline = firstLine.minY + location(forGlyphAt: firstGlyph).y
        let point = NSPoint(x: firstLine.minX + textStart - size.width - 6, y: baseline - font.ascender)
        (marker as NSString).draw(at: point, withAttributes: attributes)
    }

    // MARK: - Markers

    private func currentMarkers(in storage: NSTextStorage) -> [Int: [RichListMarker]] {
        if let markers { return markers }
        let computed = RichListMarker.markers(in: storage)
        markers = computed
        return computed
    }
}
