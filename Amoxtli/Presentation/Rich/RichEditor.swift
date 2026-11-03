import AppKit
import SwiftUI

/// The formatted document, editable. It writes Markdown back to `text` on every edit, and only
/// then: opening and reading a file never rewrites it.
struct RichEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    let links: LinkInteractionViewModel
    /// For anchors and the table of contents, which point at headings.
    let tableOfContents: [TOCEntry]

    @Environment(\.undoManager) private var undoManager
    @Environment(\.typography) private var typography
    @Environment(\.colorSchemeContrast) private var contrast

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = RichTextView.make()
        textView.delegate = context.coordinator
        textView.links = links
        textView.controller = controller
        textView.onFocus = { [weak coordinator = context.coordinator, weak textView] in
            if let coordinator, let textView { coordinator.showLatest(in: textView) }
        }
        textView.styler.typography = typography
        context.coordinator.undoManager = undoManager
        context.coordinator.show(text, in: textView)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        scrollView.documentView = textView
        controller.attach(textView)
        if text.isEmpty {
            // A new document is ready to type into.
            Task { @MainActor in textView.focusEditor() }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.undoManager = undoManager
        guard let textView = scrollView.documentView as? RichTextView else { return }
        textView.links = links
        textView.linkTextAttributes?[.underlineStyle] = contrast == .increased ? NSUnderlineStyle.single.rawValue : 0
        if text != coordinator.shownText {
            coordinator.scheduleShow(text, in: textView)
        }
        if typography != textView.styler.typography {
            coordinator.apply(typography, to: textView)
        }
        if let request = links.scrollRequest, request != coordinator.handledScrollRequest {
            coordinator.handledScrollRequest = request
            if let entry = tableOfContents.first(where: { $0.blockIndex == request.blockIndex }) {
                textView.revealHeading(entry, among: tableOfContents)
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? RichTextView else { return }
        textView.controller?.detach(textView)
        textView.links?.hover(nil)
        coordinator.forgetUndo(of: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var undoManager: UndoManager?
        var handledScrollRequest: LinkInteractionViewModel.ScrollRequest?
        /// The Markdown last shown or written, so updates that come back from typing are
        /// recognized and don't rebuild the view.
        private(set) var shownText = ""

        init(text: Binding<String>) {
            self.text = text
        }

        private var pendingShow: Task<Void, Never>?
        private let showDelay: Duration = .milliseconds(200)

        func show(_ markdown: String, in textView: RichTextView) {
            pendingShow?.cancel()
            shownText = markdown
            let model = (try? MarkdownParser().parse(markdown)) ?? MarkdownModel(blocks: [])
            rebuild(textView) { textView.show(RichDocumentBuilder.paragraphs(from: model)) }
        }

        /// Text that changed elsewhere, as typing in the source beside this view. The whole
        /// document is rebuilt, so it waits for a pause in the typing.
        func scheduleShow(_ markdown: String, in textView: RichTextView) {
            pendingShow?.cancel()
            pendingShow = Task { @MainActor [weak self, weak textView] in
                try? await Task.sleep(for: self?.showDelay ?? .zero)
                guard !Task.isCancelled, let self, let textView else { return }
                self.show(markdown, in: textView)
            }
        }

        /// Catches up with the document before this view is typed into, so typing never starts
        /// from an older version and overwrites what was written elsewhere. The binding is read
        /// directly, since SwiftUI may not have passed the latest text down yet.
        @discardableResult
        func showLatest(in textView: RichTextView) -> Bool {
            let latest = text.wrappedValue
            guard latest != shownText else { return false }
            show(latest, in: textView)
            return true
        }

        /// An edit made on an outdated document is refused; the view shows the current one instead.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let textView = textView as? RichTextView else { return true }
            return !showLatest(in: textView)
        }

        /// Keeps the scroll position and the caret where they were, as far as the new text allows.
        private func rebuild(_ textView: RichTextView, _ change: () -> Void) {
            let selection = textView.selectedRange()
            let clipView = textView.enclosingScrollView?.contentView
            let origin = clipView?.bounds.origin
            change()
            textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
            if let clipView, let origin, let layoutManager = textView.layoutManager, let container = textView.textContainer {
                layoutManager.ensureLayout(for: container)
                clipView.scroll(to: origin)
                textView.enclosingScrollView?.reflectScrolledClipView(clipView)
            }
        }

        /// Rebuilds the text in the new typography, keeping the document and the selection.
        func apply(_ typography: Typography, to textView: RichTextView) {
            let paragraphs = textView.paragraphs
            textView.styler.typography = typography
            rebuild(textView) { textView.show(paragraphs) }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? RichTextView else { return }
            let markdown = MarkdownSerializer.markdown(from: textView.paragraphs)
            shownText = markdown
            text.wrappedValue = markdown
        }

        /// The document's own undo manager, so that typing marks the document as edited.
        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        /// Undo steps of a text view that is going away can't be replayed into another one.
        func forgetUndo(of textView: RichTextView) {
            guard let undoManager, let storage = textView.textStorage else { return }
            undoManager.removeAllActions(withTarget: storage)
            undoManager.removeAllActions(withTarget: textView)
        }
    }
}
