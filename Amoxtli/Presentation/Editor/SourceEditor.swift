import AppKit
import SwiftUI

/// The Markdown source, editable and highlighted.
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: SourceEditorController

    @Environment(\.undoManager) private var undoManager

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SourceTextView.make()
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator.highlighter
        textView.typingAttributes = context.coordinator.highlighter.baseAttributes
        context.coordinator.undoManager = undoManager
        context.coordinator.show(text, in: textView)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        scrollView.documentView = textView
        controller.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.undoManager = undoManager
        guard let textView = scrollView.documentView as? SourceTextView else { return }
        if text != context.coordinator.shownText {
            context.coordinator.show(text, in: textView)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? SourceTextView, let controller = textView.controller {
            controller.detach(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var undoManager: UndoManager?
        let highlighter = SourceHighlighter()
        /// The text last shown or typed, so updates that come back from typing are recognized.
        private(set) var shownText = ""

        init(text: Binding<String>) {
            self.text = text
        }

        /// The highlighter styles the new text as the storage reports the change.
        func show(_ newText: String, in textView: SourceTextView) {
            shownText = newText
            textView.replaceAll(with: newText)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            shownText = newText
            text.wrappedValue = newText
        }

        /// The document's own undo manager, so that typing marks the document as edited.
        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }
    }
}
