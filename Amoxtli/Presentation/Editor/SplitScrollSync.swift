import AppKit

/// An editor of the split view, which scrolls in step with the other one.
protocol SplitScrollSide: AnyObject {
    /// Where each top-level Markdown block starts, in the view's coordinates, in order.
    func blockOffsets() -> [CGFloat]
}

/// Keeps the two editors of the split view at the same place in the document. The side the
/// person scrolls, or types in, leads; the other follows, block by block (`SplitScrollMap`).
/// AppKit is needed for this: SwiftUI can't observe or set the scroll offset of AppKit text views.
final class SplitScrollSync {
    enum Role {
        case source, formatted

        var other: Role { self == .source ? .formatted : .source }
    }

    private struct Side {
        weak var scrollView: NSScrollView?
        weak var editor: (any SplitScrollSide)?
        let observers: [NSObjectProtocol]
    }

    private var sides: [Role: Side] = [:]
    /// The map is rebuilt only when a side's text or layout changes.
    private var map: SplitScrollMap?
    private var isFollowing = false
    /// The scroll wheel, including the momentum after it, leads for a moment after each event.
    /// Events are watched rather than overriding `scrollWheel(with:)`, which would opt the
    /// scroll views out of responsive scrolling.
    private var lastWheel: (role: Role, time: ContinuousClock.Instant)?
    private var wheelMonitor: Any?
    private let wheelLead: Duration = .milliseconds(300)
    /// Dragging a scroller or a trackpad gesture leads until it ends.
    private var liveScrolling: Role?
    private var pendingFollow: Task<Void, Never>?
    private let followDelay: Duration = .milliseconds(250)

    func attach(_ scrollView: NSScrollView, editor: any SplitScrollSide, as role: Role) {
        if let old = sides[role]?.scrollView { detach(old) }
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        scrollView.documentView?.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        var observers = [
            center.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scrolled(role) }
            },
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.liveScrolling = role }
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.liveScrolling == role { self?.liveScrolling = nil }
                }
            },
        ]
        if let documentView = scrollView.documentView {
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: documentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.map = nil }
            })
        }
        sides[role] = Side(scrollView: scrollView, editor: editor, observers: observers)
        map = nil
        watchWheel()
    }

    private func watchWheel() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.wheelMoved(event) }
            return event
        }
    }

    private func wheelMoved(_ event: NSEvent) {
        let role = sides.first { _, side in
            guard let scrollView = side.scrollView, scrollView.window === event.window else { return false }
            return scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil))
        }?.key
        if let role { lastWheel = (role, .now) }
    }

    /// Only the scroll view that is attached goes, since the editor that replaces it may
    /// attach first.
    func detach(_ scrollView: NSScrollView) {
        guard let role = sides.first(where: { $0.value.scrollView === scrollView })?.key, let side = sides.removeValue(forKey: role) else { return }
        side.observers.forEach(NotificationCenter.default.removeObserver)
        if liveScrolling == role { liveScrolling = nil }
        if lastWheel?.role == role { lastWheel = nil }
        map = nil
        if sides.isEmpty, let wheelMonitor {
            NSEvent.removeMonitor(wheelMonitor)
            self.wheelMonitor = nil
        }
    }

    /// A side's text or typography changed, so blocks moved. Once the changes pause, the side
    /// that isn't being typed in catches up with the one that is.
    func contentChanged() {
        map = nil
        pendingFollow?.cancel()
        pendingFollow = Task { [weak self] in
            try? await Task.sleep(for: self?.followDelay ?? .zero)
            guard !Task.isCancelled, let self, let role = self.leader() else { return }
            self.follow(role)
        }
    }

    private func scrolled(_ role: Role) {
        guard !isFollowing, leader() == role else { return }
        follow(role)
    }

    /// The side the person is scrolling, or else the one with keyboard focus, whose caret may
    /// scroll it. A side that scrolls for any other reason leads nothing.
    private func leader() -> Role? {
        if let liveScrolling { return liveScrolling }
        if let lastWheel, ContinuousClock.now - lastWheel.time < wheelLead { return lastWheel.role }
        return [Role.source, .formatted].first { role in
            guard let scrollView = sides[role]?.scrollView, let documentView = scrollView.documentView else { return false }
            return scrollView.window?.firstResponder === documentView
        }
    }

    private func follow(_ role: Role) {
        guard let leading = sides[role]?.scrollView, let following = sides[role.other]?.scrollView else { return }
        // Measuring may lay text out and move either view; none of that is the person scrolling.
        isFollowing = true
        defer { isFollowing = false }
        guard let map = currentMap() else { return }
        let offset = Double(leading.contentView.bounds.minY)
        let target = CGFloat(role == .source ? map.formattedOffset(forSource: offset) : map.sourceOffset(forFormatted: offset))
        let clipView = following.contentView
        guard abs(clipView.bounds.minY - target) >= 0.5 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: target))
        following.reflectScrolledClipView(clipView)
    }

    private func currentMap() -> SplitScrollMap? {
        if let map { return map }
        guard let source = sides[.source], let formatted = sides[.formatted],
              let sourceView = source.scrollView, let formattedView = formatted.scrollView,
              let sourceEditor = source.editor, let formattedEditor = formatted.editor else { return nil }
        let sourceAnchors = sourceEditor.blockOffsets().map(Double.init)
        let formattedAnchors = formattedEditor.blockOffsets().map(Double.init)
        let map = SplitScrollMap(
            sourceAnchors: sourceAnchors,
            formattedAnchors: formattedAnchors,
            sourceEnd: largestOffset(of: sourceView),
            formattedEnd: largestOffset(of: formattedView)
        )
        self.map = map
        return map
    }

    private func largestOffset(of scrollView: NSScrollView) -> Double {
        Double(max(0, (scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height))
    }
}

// MARK: - Block offsets

extension SourceTextView: SplitScrollSide {
    /// The parser says on which line each block starts; TextKit says where that line is.
    func blockOffsets() -> [CGFloat] {
        guard let textLayoutManager, let contentManager = textLayoutManager.textContentManager else { return [] }
        let text = string
        let lines = (try? MarkdownParser().topLevelBlockLines(in: text)) ?? []
        let starts = TextLines.startOffsets(in: text)
        let documentRange = contentManager.documentRange
        textLayoutManager.ensureLayout(for: documentRange)
        // A block that can't be found leaves the counts apart, and the map then aligns only
        // the tops and the ends.
        return lines.compactMap { line in
            guard starts.indices.contains(line - 1),
                  let location = contentManager.location(documentRange.location, offsetBy: starts[line - 1]),
                  let fragment = textLayoutManager.textLayoutFragment(for: location) else { return nil }
            return fragment.layoutFragmentFrame.minY + textContainerOrigin.y
        }
    }
}

extension RichTextView: SplitScrollSide {
    /// The top of the first line of each block's first paragraph, the spacing above it
    /// included, which for a code block holds its language strip.
    func blockOffsets() -> [CGFloat] {
        guard let textStorage, let layoutManager, let textContainer else { return [] }
        layoutManager.ensureLayout(for: textContainer)
        let paragraphs = textStorage.paragraphRanges(in: NSRange(location: 0, length: textStorage.length))
        let outlines = paragraphs.map { paragraph in
            let kind = kind(at: paragraph.location)
            return RichTopLevelBlocks.Outline(
                block: kind.block,
                containers: kind.containers,
                isEmpty: textStorage.contentRange(of: paragraph).length == 0
            )
        }
        return RichTopLevelBlocks.starts(of: outlines).map { index in
            let glyph = layoutManager.glyphIndexForCharacter(at: paragraphs[index].location)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textContainerOrigin.y
        }
    }
}
