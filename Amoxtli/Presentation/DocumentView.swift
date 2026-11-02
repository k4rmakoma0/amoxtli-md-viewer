import SwiftUI

/// Window of a single file: its table of contents in the sidebar and the document. There is no
/// file list in this mode.
struct DocumentView: View {
    let document: MarkdownDocument
    var fileURL: URL?
    @State private var viewModel = DocumentViewModel()
    @State private var links = LinkInteractionViewModel()
    @SceneStorage("isSidebarPresented") private var isSidebarPresented = true

    var body: some View {
        ReaderSplitView(isSidebarPresented: $isSidebarPresented) {
            TableOfContentsView(entries: viewModel.tableOfContents) { entry in
                links.scroll(toBlock: entry.blockIndex)
            }
        } detail: {
            MarkdownReaderView(viewModel: viewModel, links: links, fileURL: fileURL)
        }
        .toolbar { OpenToolbarItem() }
        .focusedSceneValue(\.sidebarTabAction, SidebarTabAction(availableTabs: [.contents]) { _ in
            isSidebarPresented = true
        })
        .task(id: document.content) {
            await viewModel.load(document.content)
        }
    }
}

#Preview {
    DocumentView(document: MarkdownDocument(data: Data("# Amoxtli\n\nVisor de *Markdown*.".utf8)))
}
