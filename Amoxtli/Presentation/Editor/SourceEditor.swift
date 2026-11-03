import AppKit
import SwiftUI

/// The Markdown source, editable and highlighted.
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController

    @Environment(\.undoManager) private var undoManager
    @Environment(\.typography) private var typography

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SourceTextView.make()
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator.highlighter
        context.coordinator.highlighter.typography = typography
        textView.typingAttributes = context.coordinator.highlighter.baseAttributes
        context.coordinator.undoManager = undoManager
        context.coordinator.show(text, in: textView)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        scrollView.documentView = textView
        textView.controller = controller
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
        if typography != context.coordinator.highlighter.typography {
            context.coordinator.apply(typography, to: textView)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? SourceTextView else { return }
        textView.controller?.detach(textView)
        // Undo steps of a text view that is going away can't be replayed into another one.
        if let undoManager = coordinator.undoManager, let storage = textView.textStorage {
            undoManager.removeAllActions(withTarget: storage)
            undoManager.removeAllActions(withTarget: textView)
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

        func apply(_ typography: Typography, to textView: SourceTextView) {
            highlighter.typography = typography
            textView.typingAttributes = highlighter.baseAttributes
            if let storage = textView.textStorage {
                highlighter.restyle(storage)
            }
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
