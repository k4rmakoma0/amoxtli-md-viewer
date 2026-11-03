import SwiftUI

/// The formatted document, shared by the single-file and folder windows.
struct MarkdownReaderView: View {
    let viewModel: DocumentViewModel
    let links: LinkInteractionViewModel
    /// Offered on an empty document, which has nothing to show until something is written.
    var onStartWriting: (() -> Void)?

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
        } actions: {
            if let onStartWriting {
                Button("Escribir", action: onStartWriting)
            }
        }
    }
}

#Preview {
    MarkdownReaderView(viewModel: DocumentViewModel(), links: LinkInteractionViewModel())
}
