import AppKit
import Observation

/// What the link sheet starts with.
struct LinkRequest: Identifiable {
    let id = UUID()
    var text: String
    var destination: String
}

/// Connects the toolbar, the menus and the table of contents with the source editor of a window.
@Observable
final class SourceEditorController {
    /// Whether a source editor is on screen, which is when the formatting tools can act.
    private(set) var isAttached = false
    /// Set to ask for a link's destination; the sheet inserts the link when it is confirmed.
    var linkRequest: LinkRequest?

    @ObservationIgnored private weak var textView: SourceTextView?

    func attach(_ textView: SourceTextView) {
        self.textView = textView
        textView.controller = self
        isAttached = true
    }

    func detach(_ textView: SourceTextView) {
        guard self.textView === textView else { return }
        self.textView = nil
        isAttached = false
    }

    func perform(_ tool: FormatTool) {
        if let command = tool.command {
            apply(command, actionName: tool.title)
        } else {
            requestLink()
        }
    }

    func requestLink() {
        guard let textView else { return }
        let selected = (textView.string as NSString).substring(with: textView.selectedRange())
        let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = pasted.flatMap(URL.init(string:)).flatMap { $0.scheme == "http" || $0.scheme == "https" ? $0.absoluteString : nil }
        linkRequest = LinkRequest(text: selected, destination: suggestion ?? "")
    }

    func insertLink(text: String, destination: String) {
        guard let destination = LinkInput.normalized(destination) else { return }
        apply(.link(text: text, destination: destination), actionName: String(localized: "Enlace"))
        focus()
    }

    func revealHeading(_ entry: TOCEntry, among entries: [TOCEntry]) {
        guard let textView, let location = SourceHeadingLocator.location(of: entry, among: entries, in: textView.string) else { return }
        let range = NSRange(location: location, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    private func apply(_ command: FormatCommand, actionName: String) {
        guard let textView else { return }
        let edit = MarkdownFormatter.edit(for: command, in: textView.string, selection: textView.selectedRange())
        textView.apply(edit, actionName: actionName)
    }
}
