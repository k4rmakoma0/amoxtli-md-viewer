import SwiftUI

/// The document pane with its reading stats, shared by the single-file and folder windows.
struct MarkdownReaderView: View {
    let viewModel: DocumentViewModel
    let links: LinkInteractionViewModel
    var fileURL: URL?

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 360)
            .focusedSceneValue(\.shownFileURL, fileURL)
            .safeAreaBar(edge: .bottom) { readingStats }
            .onChange(of: viewModel.tableOfContents, initial: true) { _, entries in
                links.updateAnchors(HeadingAnchors(entries: entries))
                links.hover(nil)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let model):
            MarkdownContentView(model: model, links: links)
                .id(viewModel.loadCount)
        case .failed(let error):
            DocumentErrorView(error: error)
        }
    }

    @ViewBuilder
    private var readingStats: some View {
        if case .loaded = viewModel.state, let stats = viewModel.readingStats {
            ReadingStatsView(stats: stats)
        }
    }
}

#Preview {
    MarkdownReaderView(viewModel: DocumentViewModel(), links: LinkInteractionViewModel())
}
