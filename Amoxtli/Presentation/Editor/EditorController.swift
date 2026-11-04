import AppKit
import Observation

/// What the link sheet starts with.
struct LinkRequest: Identifiable {
    let id = UUID()
    var text: String
    var destination: String
}

/// An editor the formatting tools and the table of contents can act on: the source or the
/// formatted one.
@MainActor
protocol FormattingTarget: AnyObject {
    var selectedText: String { get }
    func apply(_ command: FormatCommand, actionName: String)
    func revealHeading(_ entry: TOCEntry, among entries: [TOCEntry])
    func focusEditor()
}

/// Connects the toolbar, the menus and the table of contents with the editors of a window.
@Observable
final class EditorController {
    /// Whether an editor is on screen, which is when the formatting tools can act.
    private(set) var isAttached = false
    /// Set to ask for a link's destination; the sheet inserts the link when it is confirmed.
    var linkRequest: LinkRequest?
    var isInsertingTable = false

    /// Every editor on screen. The tools act on the one used last.
    @ObservationIgnored private var targets: [WeakTarget] = []

    func attach(_ target: any FormattingTarget) {
        targets.removeAll { $0.value == nil || $0.value === target }
        targets.append(WeakTarget(value: target))
        isAttached = true
    }

    func detach(_ target: any FormattingTarget) {
        targets.removeAll { $0.value == nil || $0.value === target }
        isAttached = !targets.isEmpty
    }

    /// Called when an editor takes keyboard focus, so the tools follow it.
    func activate(_ target: any FormattingTarget) {
        attach(target)
    }

    private var activeTarget: (any FormattingTarget)? {
        targets.last?.value
    }

    func perform(_ tool: FormatTool) {
        guard !isInsertingTable, linkRequest == nil else { return }
        if tool == .table {
            guard activeTarget != nil else { return }
            isInsertingTable = true
        } else if let command = tool.command {
            activeTarget?.apply(command, actionName: tool.title)
        } else {
            requestLink()
        }
    }

    func requestLink() {
        guard let activeTarget, !isInsertingTable else { return }
        let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = pasted.flatMap(URL.init(string:)).flatMap { $0.scheme == "http" || $0.scheme == "https" ? $0.absoluteString : nil }
        linkRequest = LinkRequest(text: activeTarget.selectedText, destination: suggestion ?? "")
    }

    func insertLink(text: String, destination: String) {
        guard let destination = LinkInput.normalized(destination), let activeTarget else { return }
        activeTarget.apply(.link(text: text, destination: destination), actionName: String(localized: "Enlace"))
        activeTarget.focusEditor()
    }

    func insertTable(_ dimensions: TableDimensions) {
        isInsertingTable = false
        guard let activeTarget else { return }
        activeTarget.apply(.table(dimensions), actionName: String(localized: "Tabla"))
        activeTarget.focusEditor()
    }

    func revealHeading(_ entry: TOCEntry, among entries: [TOCEntry]) {
        for target in targets {
            target.value?.revealHeading(entry, among: entries)
        }
    }

    func focus() {
        activeTarget?.focusEditor()
    }

    private struct WeakTarget {
        weak var value: (any FormattingTarget)?
    }
}
