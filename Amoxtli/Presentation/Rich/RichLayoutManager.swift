import AppKit

/// Draws what the paragraphs' kinds imply but their text doesn't contain: list markers, the bar
/// beside quotes and the background of code blocks. Markers aren't text, so typing never moves
/// or breaks them, and they renumber as items come and go.
nonisolated final class RichLayoutManager: NSLayoutManager {
    weak var styler: RichStyler?
    /// The kind of the empty line at the end while the caret is on it, which only the text
    /// view knows. A code block that continues there doesn't end on the line above.
    var emptyLastLineKind: RichParagraphKind?
    /// The code block whose copy button shows a check mark, for a moment after it copied.
    var copiedCodeBlock: Int?

    /// The markers to draw, by the location of the paragraph that starts each item, and the
    /// numbering after the last paragraph.
    private var numbering: (markers: [Int: [RichListMarker]], end: RichListMarker.Numbering)?

    override func processEditing(
        for textStorage: NSTextStorage,
        edited editMask: NSTextStorageEditActions,
        range newCharRange: NSRange,
        changeInLength delta: Int,
        invalidatedRange invalidatedCharRange: NSRange
    ) {
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
        numbering = nil
        copiedCodeBlock = nil
        // Numbers further down may change with any edit to the list. Asking for glyph ranges
        // isn't allowed while the text is being edited, so the whole view repaints. The editors
        // only edit their text on the main thread, though AppKit doesn't declare it here.
        let textViews = textContainers.compactMap(\.textView)
        MainActor.assumeIsolated {
            for textView in textViews {
                textView.needsDisplay = true
            }
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawDecorations(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawDecorations(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage, let styler else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let markers = currentNumbering(in: textStorage).markers
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
                let font = textStorage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont ?? styler.typography.body
                let baseline = first.minY + location(forGlyphAt: glyphIndexForCharacter(at: paragraph.location)).y
                draw(marker.text, depth: marker.depth, kind: kind, font: font, baseline: baseline, lineStart: first.minX, styler: styler)
            }
        }
    }

    /// The empty line at the end of the text has no characters, so its kind exists only in the
    /// style kept for typing. Drawing its marker, quote bar or code background there shows
    /// what is about to be written, as soon as a list or a quote starts.
    func drawEmptyLastLine(as kind: RichParagraphKind, style: InlineStyle, at origin: NSPoint) {
        guard let textStorage, let styler else { return }
        let line = extraLineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
        guard line.height > 0 else { return }
        let font = styler.font(for: kind, style: style)
        let previous = textStorage.length > 0 ? textStorage.paragraphKind(at: textStorage.length - 1) : nil
        let spacingBefore = styler.paragraphStyle(for: kind, previous: previous, next: nil).paragraphSpacingBefore
        let baseline = line.minY + spacingBefore + defaultBaselineOffset(for: font)
        if let background = emptyLastLineCodeBackground(styler: styler) {
            fillCode(background.rect.offsetBy(dx: origin.x, dy: origin.y), roundsTop: background.isFirst, roundsBottom: true)
            if background.isFirst {
                drawStripControls(for: kind, block: textStorage.length, in: background.rect.offsetBy(dx: origin.x, dy: origin.y), styler: styler)
            }
        }
        drawQuoteBars(line, kind: kind, styler: styler)
        var numbering = currentNumbering(in: textStorage).end
        for marker in numbering.markers(for: kind.containers) {
            draw(marker.text, depth: marker.depth, kind: kind, font: font, baseline: baseline, lineStart: line.minX, styler: styler)
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

    // MARK: - Tables

    /// TextKit draws a cell's borders and background only while it redraws that cell's text,
    /// so lines between cells vanished when the view repainted part of a table, and a
    /// translucent line drawn twice where cells meet looked different from one drawn once.
    /// Each table that reaches the area being drawn is drawn whole instead, each line once.
    func drawTables(in rect: NSRect, at origin: NSPoint, align: (NSRect) -> NSRect) {
        guard let textStorage, let styler, let container = textContainers.first, textStorage.length > 0 else { return }
        // Reaches the cells around the area too, as it may fall between their lines of text.
        let area = rect.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: 0, dy: -4 * CGFloat(styler.typography.size.points))
        let characters = characterRange(forGlyphRange: glyphRange(forBoundingRect: area, in: container), actualGlyphRange: nil)
        var drawn: Set<ObjectIdentifier> = []
        for paragraph in textStorage.paragraphRanges(in: characters) {
            guard let table = tableBlock(at: paragraph.location)?.table, drawn.insert(ObjectIdentifier(table)).inserted else { continue }
            drawTable(table, at: paragraph.location, origin: origin, styler: styler, align: align)
        }
    }

    private func tableBlock(at location: Int) -> NSTextTableBlock? {
        guard let textStorage, location < textStorage.length else { return nil }
        let style = textStorage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        return style?.textBlocks.first as? NSTextTableBlock
    }

    private func drawTable(_ table: NSTextTable, at location: Int, origin: NSPoint, styler: RichStyler, align: (NSRect) -> NSRect) {
        guard let textStorage else { return }
        let cells = cellBounds(in: textStorage.range(of: table, at: location)).map { (block: $0.block, rect: $0.rect.offsetBy(dx: origin.x, dy: origin.y)) }
        guard let first = cells.first?.rect else { return }
        let bounds = cells.dropFirst().reduce(first) { $0.union($1.rect) }
        let header = cells.filter { $0.block.startingRow == 0 }.map(\.rect)
        if let firstHeader = header.first {
            SurfaceColors.tableHeader.setFill()
            align(header.dropFirst().reduce(firstHeader) { $0.union($1) }).fill()
        }
        let width = styler.tableBorderWidth
        var lines: [NSRect] = cells.flatMap { cell in
            [NSRect(x: cell.rect.minX, y: cell.rect.minY, width: cell.rect.width, height: width),
             NSRect(x: cell.rect.minX, y: cell.rect.minY, width: width, height: cell.rect.height)]
        }
        lines.append(NSRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height))
        lines.append(NSRect(x: bounds.minX, y: bounds.maxY - width, width: bounds.width, height: width))
        // Aligned to pixels and filled as one shape, so where lines cross they aren't darker.
        let path = NSBezierPath()
        path.windingRule = .nonZero
        for line in lines {
            path.appendRect(align(line))
        }
        SurfaceColors.tableBorder.setFill()
        path.fill()
    }

    /// Each cell's whole rectangle, borders and padding included, in container coordinates.
    /// Two paragraphs in one cell share its block, so each block is measured once.
    private func cellBounds(in range: NSRange) -> [(block: NSTextTableBlock, rect: NSRect)] {
        guard let textStorage else { return [] }
        var seen: Set<ObjectIdentifier> = []
        var cells: [(block: NSTextTableBlock, rect: NSRect)] = []
        for paragraph in textStorage.paragraphRanges(in: range) {
            guard let block = tableBlock(at: paragraph.location), seen.insert(ObjectIdentifier(block)).inserted else { continue }
            let glyph = glyphIndexForCharacter(at: paragraph.location)
            let rect = boundsRect(for: block, at: glyph, effectiveRange: nil)
            if !rect.isEmpty { cells.append((block, rect)) }
        }
        return cells
    }

    // MARK: - Code blocks

    private let codePaddingY: CGFloat = 6

    /// Covers the lines of code without the spacing around the block, plus some padding at
    /// its last line and the strip with the copy button and language chip above its first.
    private func drawCodeBackground(_ used: [NSRect], area: NSRect, kind: RichParagraphKind, paragraph: NSRange, styler: RichStyler) {
        guard let textStorage, let first = used.first, let last = used.last else { return }
        let isFirst = paragraph.location == 0 || textStorage.paragraphKind(at: paragraph.location - 1) != kind
        let continuesOnEmptyLastLine = NSMaxRange(paragraph) == textStorage.length && emptyLastLineKind == kind
        let isLast = textStorage.paragraphKind(at: NSMaxRange(paragraph)) != kind && !continuesOnEmptyLastLine
        // A block that starts the text has its strip in the view's margin, drawn by the view.
        let hasStrip = isFirst && paragraph.location > 0
        let top = hasStrip ? codeTop(firstLineTop: first.minY, styler: styler) : area.minY
        let bottom = isLast ? last.maxY + codePaddingY : area.maxY
        let indent = styler.indent(of: kind.containers)
        let background = NSRect(x: area.minX + indent, y: top, width: area.width - indent, height: bottom - top)
        fillCode(background, roundsTop: hasStrip, roundsBottom: isLast)
        if hasStrip {
            drawStripControls(for: kind, block: paragraph.location, in: background, styler: styler)
        }
    }

    /// TextKit adds no spacing before the first paragraph of the text and clips what is drawn
    /// above it, so the strip of a code block that starts the text goes in the view's margin.
    func drawLeadingCodeStrip(at origin: NSPoint) {
        guard let textStorage, let styler, textStorage.length > 0, let kind = textStorage.paragraphKind(at: 0), kind.isCode,
              let first = lineRects(of: textStorage.paragraphRange(at: 0)).first else { return }
        let indent = styler.indent(of: kind.containers)
        let top = codeTop(firstLineTop: first.used.minY, styler: styler)
        let strip = NSRect(x: first.rect.minX + indent, y: top, width: first.rect.width - indent, height: first.rect.minY - top)
        fillCode(strip.offsetBy(dx: origin.x, dy: origin.y), roundsTop: true, roundsBottom: false)
        drawStripControls(for: kind, block: 0, in: strip.offsetBy(dx: origin.x, dy: origin.y), styler: styler)
    }

    private func codeTop(firstLineTop: CGFloat, styler: RichStyler) -> CGFloat {
        firstLineTop - codePaddingY - styler.codeChipStripHeight
    }

    /// The background of a code block on the empty last line, in container coordinates, and
    /// whether that line starts the block.
    private func emptyLastLineCodeBackground(styler: RichStyler) -> (rect: NSRect, isFirst: Bool)? {
        guard let textStorage, let kind = emptyLastLineKind, kind.isCode else { return nil }
        let line = extraLineFragmentRect
        guard line.height > 0 else { return nil }
        let previous = textStorage.length > 0 ? textStorage.paragraphKind(at: textStorage.length - 1) : nil
        let isFirst = previous != kind
        // As for the first paragraph, there is no spacing before the line when it is the only one.
        let spacingBefore = textStorage.length > 0 ? styler.paragraphStyle(for: kind, previous: previous, next: nil).paragraphSpacingBefore : 0
        let textTop = line.minY + spacingBefore
        let top = isFirst ? codeTop(firstLineTop: textTop, styler: styler) : line.minY
        let bottom = textTop + defaultLineHeight(for: styler.font(for: kind, style: [])) + codePaddingY
        let indent = styler.indent(of: kind.containers)
        return (NSRect(x: line.minX + indent, y: top, width: line.width - indent, height: bottom - top), isFirst)
    }

    /// Rounds only the ends of the block, since its lines are drawn one paragraph at a time.
    private func fillCode(_ rect: NSRect, roundsTop: Bool, roundsBottom: Bool) {
        let radius = min(8, rect.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.midY))
        corner(of: path, at: NSPoint(x: rect.minX, y: rect.minY), toward: NSPoint(x: rect.maxX, y: rect.minY), radius: roundsTop ? radius : 0)
        corner(of: path, at: NSPoint(x: rect.maxX, y: rect.minY), toward: NSPoint(x: rect.maxX, y: rect.maxY), radius: roundsTop ? radius : 0)
        corner(of: path, at: NSPoint(x: rect.maxX, y: rect.maxY), toward: NSPoint(x: rect.minX, y: rect.maxY), radius: roundsBottom ? radius : 0)
        corner(of: path, at: NSPoint(x: rect.minX, y: rect.maxY), toward: NSPoint(x: rect.minX, y: rect.minY), radius: roundsBottom ? radius : 0)
        path.close()
        SurfaceColors.codeBackground.setFill()
        path.fill()
    }

    private func corner(of path: NSBezierPath, at point: NSPoint, toward next: NSPoint, radius: CGFloat) {
        if radius > 0 {
            path.appendArc(from: point, to: next, radius: radius)
        } else {
            path.line(to: point)
        }
    }

    // MARK: - Language chip

    private func chipTitle(for kind: RichParagraphKind) -> String {
        guard case .code(_, let language) = kind.block, let label = CodeLanguage.label(forFenceInfo: language) else {
            return String(localized: "Elegir lenguaje")
        }
        return label
    }

    private func chipAttributes(styler: RichStyler) -> [NSAttributedString.Key: Any] {
        [.font: styler.codeChipFont, .foregroundColor: NSColor.secondaryLabelColor]
    }

    private func chevron(styler: RichStyler) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: styler.codeChipFont.pointSize * 0.75, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
        return NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    /// At the top right of the block's background.
    private func chipRect(for kind: RichParagraphKind, in background: NSRect, styler: RichStyler) -> NSRect {
        let title = (chipTitle(for: kind) as NSString).size(withAttributes: chipAttributes(styler: styler))
        let chevronWidth = chevron(styler: styler)?.size.width ?? 0
        let width = (title.width + chevronWidth + 4 + 16).rounded(.up)
        return NSRect(x: background.maxX - 6 - width, y: background.minY + 6, width: width, height: styler.codeChipHeight)
    }

    private func drawStripControls(for kind: RichParagraphKind, block: Int, in background: NSRect, styler: RichStyler) {
        let chip = chipRect(for: kind, in: background, styler: styler)
        drawChip(for: kind, in: chip, styler: styler)
        drawCopyButton(in: copyButtonRect(besideChip: chip), showsCheckmark: copiedCodeBlock == block, styler: styler)
    }

    private func drawChip(for kind: RichParagraphKind, in chip: NSRect, styler: RichStyler) {
        NSColor.tertiarySystemFill.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
        let attributes = chipAttributes(styler: styler)
        let title = chipTitle(for: kind) as NSString
        let titleSize = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: chip.minX + 8, y: chip.midY - titleSize.height / 2), withAttributes: attributes)
        if let chevron = chevron(styler: styler) {
            let rect = NSRect(x: chip.minX + 8 + titleSize.width + 4, y: chip.midY - chevron.size.height / 2, width: chevron.size.width, height: chevron.size.height)
            chevron.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    // MARK: - Copy button

    /// A square as tall as the chip, just to its left.
    private func copyButtonRect(besideChip chip: NSRect) -> NSRect {
        NSRect(x: chip.minX - 4 - chip.height, y: chip.minY, width: chip.height, height: chip.height)
    }

    private func drawCopyButton(in button: NSRect, showsCheckmark: Bool, styler: RichStyler) {
        NSColor.tertiarySystemFill.setFill()
        NSBezierPath(roundedRect: button, xRadius: 5, yRadius: 5).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: styler.codeChipFont.pointSize * 0.85, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
        let name = showsCheckmark ? "checkmark" : "doc.on.doc"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let rect = NSRect(x: button.midX - symbol.size.width / 2, y: button.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height)
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // MARK: - Strip hit testing

    /// The background of the strip of the code block that starts at a location (the text's
    /// length for a block that is only the empty last line), in container coordinates.
    private func stripBackground(forBlockAt location: Int, styler: RichStyler) -> (kind: RichParagraphKind, rect: NSRect)? {
        guard let textStorage else { return nil }
        if location == textStorage.length {
            guard let kind = emptyLastLineKind, let background = emptyLastLineCodeBackground(styler: styler), background.isFirst else { return nil }
            return (kind, background.rect)
        }
        guard let kind = textStorage.paragraphKind(at: location), kind.isCode else { return nil }
        guard let first = lineRects(of: textStorage.paragraphRange(at: location)).first else { return nil }
        let indent = styler.indent(of: kind.containers)
        let top = codeTop(firstLineTop: first.used.minY, styler: styler)
        return (kind, NSRect(x: first.rect.minX + indent, y: top, width: first.rect.width - indent, height: first.rect.maxY - top))
    }

    /// The chip of the code block that starts at a location, in container coordinates.
    func codeChipRect(forBlockAt location: Int) -> NSRect? {
        guard let styler, let background = stripBackground(forBlockAt: location, styler: styler) else { return nil }
        return chipRect(for: background.kind, in: background.rect, styler: styler)
    }

    /// The copy button of the code block that starts at a location, in container coordinates.
    func codeCopyButtonRect(forBlockAt location: Int) -> NSRect? {
        codeChipRect(forBlockAt: location).map(copyButtonRect(besideChip:))
    }

    /// The code block whose chip is at a point in container coordinates, as the location its
    /// first paragraph starts at.
    func codeBlock(withChipAt point: NSPoint) -> Int? {
        codeBlock(at: point, hitting: codeChipRect(forBlockAt:))
    }

    /// The code block whose copy button is at a point in container coordinates.
    func codeBlock(withCopyButtonAt point: NSPoint) -> Int? {
        codeBlock(at: point, hitting: codeCopyButtonRect(forBlockAt:))
    }

    private func codeBlock(at point: NSPoint, hitting control: (Int) -> NSRect?) -> Int? {
        guard let textStorage, let container = textContainers.first else { return nil }
        if let rect = control(textStorage.length), rect.contains(point) {
            return textStorage.length
        }
        guard textStorage.length > 0 else { return nil }
        let character = characterIndexForGlyph(at: glyphIndex(for: point, in: container))
        guard character < textStorage.length, textStorage.paragraphKind(at: character)?.isCode == true else { return nil }
        let block = textStorage.codeBlockRange(at: character).location
        guard let rect = control(block), rect.contains(point) else { return nil }
        return block
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
    private func draw(_ marker: String, depth: Int, kind: RichParagraphKind, font: NSFont, baseline: CGFloat, lineStart: CGFloat, styler: RichStyler) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let size = (marker as NSString).size(withAttributes: attributes)
        let textStart = styler.indent(of: kind.containers.prefix(depth + 1))
        let point = NSPoint(x: lineStart + textStart - size.width - 6, y: baseline - font.ascender)
        (marker as NSString).draw(at: point, withAttributes: attributes)
    }

    // MARK: - Markers

    private func currentNumbering(in storage: NSTextStorage) -> (markers: [Int: [RichListMarker]], end: RichListMarker.Numbering) {
        if let numbering { return numbering }
        let computed = RichListMarker.numbering(of: storage)
        numbering = computed
        return computed
    }
}
