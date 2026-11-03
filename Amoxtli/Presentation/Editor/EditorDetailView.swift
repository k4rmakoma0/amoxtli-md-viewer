import SwiftUI

/// The document pane of both windows: the source, the formatted document or both side by side,
/// with the reading stats below. Both editors write to the same Markdown text, so in the split
/// view either side can be edited and the other follows.
struct EditorDetailView: View {
    @Binding var mode: EditorMode
    @Binding var text: String
    /// Changes when another document is shown, which renders it right away and from the top.
    let documentID: AnyHashable
    let viewModel: DocumentViewModel
    let links: LinkInteractionViewModel
    @Bindable var editor: EditorController

    private let preferences = TypographyPreferences()
    private let renderDelay: Duration = .milliseconds(250)

    var body: some View {
        // The stats get a row of their own rather than a safe area bar: the editors are AppKit
        // scroll views, which neither stop above such a bar nor fade text that passes under it,
        // and the split view ignores it altogether.
        VStack(spacing: 0) {
            content
                .environment(\.typography, preferences.typography)
            readingStats
        }
        .frame(minWidth: 480, minHeight: 360)
        .task(id: documentID) {
            await viewModel.load(.success(text))
        }
        .task(id: text) {
            try? await Task.sleep(for: renderDelay)
            guard !Task.isCancelled else { return }
            await viewModel.update(text)
        }
        .onChange(of: viewModel.tableOfContents, initial: true) { _, entries in
            links.updateAnchors(HeadingAnchors(entries: entries))
            links.hover(nil)
        }
        .sheet(item: $editor.linkRequest) { request in
            LinkSheet(request: request) { text, destination in
                editor.insertLink(text: text, destination: destination)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Another document gets editors of its own, starting at the top with no undo history.
        Group {
            switch mode {
            case .source:
                source
            case .formatted:
                formatted
            case .split:
                HSplitView {
                    source
                        .frame(minWidth: 280)
                    formatted
                        .frame(minWidth: 280)
                }
            }
        }
        .id(documentID)
    }

    private var formatted: some View {
        RichEditor(text: $text, controller: editor, links: links, tableOfContents: viewModel.tableOfContents)
            .overlay { LinkStatusOverlay() }
            .environment(links)
    }

    private var source: some View {
        SourceEditor(text: $text, controller: editor)
    }

    @ViewBuilder
    private var readingStats: some View {
        if case .loaded = viewModel.state, let stats = viewModel.readingStats {
            ReadingStatsView(stats: stats)
        }
    }
}
