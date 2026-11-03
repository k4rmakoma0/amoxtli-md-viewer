import SwiftUI

/// The document pane of both windows: the source, the formatted document or both, with the
/// reading stats below. The formatted side follows the text a moment after typing stops.
struct EditorDetailView: View {
    @Binding var mode: EditorMode
    @Binding var text: String
    /// Changes when another document is shown, which renders it right away and from the top.
    let documentID: AnyHashable
    let viewModel: DocumentViewModel
    let links: LinkInteractionViewModel
    @Bindable var editor: SourceEditorController

    private let preferences = TypographyPreferences()
    private let renderDelay: Duration = .milliseconds(250)

    var body: some View {
        content
            .environment(\.typography, preferences.typography)
            .frame(minWidth: 480, minHeight: 360)
            .safeAreaBar(edge: .bottom) { readingStats }
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

    private var source: some View {
        SourceEditor(text: $text, controller: editor)
    }

    private var formatted: some View {
        MarkdownReaderView(viewModel: viewModel, links: links) {
            mode = .source
            Task { editor.focus() }
        }
    }

    @ViewBuilder
    private var readingStats: some View {
        if case .loaded = viewModel.state, let stats = viewModel.readingStats {
            ReadingStatsView(stats: stats)
        }
    }
}
