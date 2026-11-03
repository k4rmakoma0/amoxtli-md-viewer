import SwiftUI

/// The formatted document, shared by the single-file and folder windows.
struct MarkdownReaderView: View {
    let viewModel: DocumentViewModel
    let links: LinkInteractionViewModel

    var body: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let model):
            MarkdownContentView(model: model, links: links)
                .id(viewModel.loadCount)
        case .failed(.empty):
            emptyDocument
        case .failed(let error):
            DocumentErrorView(error: error)
        }
    }

    private var emptyDocument: some View {
        ContentUnavailableView {
            Label("Documento vacío", systemImage: "doc")
        } description: {
            Text("Escribe en Markdown para ver aquí el documento con formato.")
        }
    }
}

#Preview {
    MarkdownReaderView(viewModel: DocumentViewModel(), links: LinkInteractionViewModel())
}
