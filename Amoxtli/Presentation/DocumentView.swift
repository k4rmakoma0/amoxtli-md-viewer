import SwiftUI

/// Window of a single file: its table of contents in the sidebar and the document. There is no
/// file list in this mode.
struct DocumentView: View {
    let document: MarkdownDocument
    var fileURL: URL?
    @State private var viewModel = DocumentViewModel()
    @State private var links = LinkInteractionViewModel()

    var body: some View {
        ReaderSplitView {
            TableOfContentsView(entries: viewModel.tableOfContents) { entry in
                links.scroll(toBlock: entry.blockIndex)
            }
        } detail: {
            MarkdownReaderView(viewModel: viewModel, links: links, fileURL: fileURL)
        }
        .task(id: document.content) {
            await viewModel.load(document.content)
        }
    }
}

#Preview {
    DocumentView(document: MarkdownDocument(data: Data("# Amoxtli\n\nVisor de *Markdown*.".utf8)))
}
