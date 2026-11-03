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
            coordinator.show(text, in: textView)
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

        func show(_ markdown: String, in textView: RichTextView) {
            shownText = markdown
            let model = (try? MarkdownParser().parse(markdown)) ?? MarkdownModel(blocks: [])
            let selection = textView.selectedRange()
            textView.show(RichDocumentBuilder.paragraphs(from: model))
            textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
        }

        /// Rebuilds the text in the new typography, keeping the document and the selection.
        func apply(_ typography: Typography, to textView: RichTextView) {
            let paragraphs = textView.paragraphs
            let selection = textView.selectedRange()
            textView.styler.typography = typography
            textView.show(paragraphs)
            textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
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
