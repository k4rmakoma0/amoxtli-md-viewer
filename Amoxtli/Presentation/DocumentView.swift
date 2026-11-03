import SwiftUI

/// Window of a single file: its table of contents in the sidebar and the document. There is no
/// file list in this mode.
struct DocumentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var viewModel = DocumentViewModel()
    @State private var links = LinkInteractionViewModel()
    @State private var editor = EditorController()
    @SceneStorage("isSidebarPresented") private var isSidebarPresented = true
    @SceneStorage("editorMode") private var mode = EditorMode.formatted

    var body: some View {
        ReaderSplitView(isSidebarPresented: $isSidebarPresented) {
            TableOfContentsView(entries: viewModel.tableOfContents) { entry in
                links.scroll(toBlock: entry.blockIndex)
                editor.revealHeading(entry, among: viewModel.tableOfContents)
            }
        } detail: {
            detail
        }
        .toolbar(id: "document") {
            OpenToolbarItem()
            EditorToolbar(mode: $mode, editor: editor)
        }
        .focusedSceneValue(\.sidebarTabAction, SidebarTabAction(availableTabs: [.contents]) { _ in
            isSidebarPresented = true
        })
        .focusedSceneValue(\.editorController, editor)
        .focusedSceneValue(\.editorMode, $mode)
    }

    /// A file that couldn't be decoded is explained instead of shown, and can't be edited.
    @ViewBuilder
    private var detail: some View {
        if let error = document.loadError {
            DocumentErrorView(error: error)
                .frame(minWidth: 480, minHeight: 360)
        } else {
            EditorDetailView(
                mode: $mode,
                text: $document.text,
                documentID: ObjectIdentifier(document),
                viewModel: viewModel,
                links: links,
                editor: editor
            )
        }
    }
}

#Preview {
    DocumentView(document: MarkdownDocument(text: "# Amoxtli\n\nEditor de *Markdown*."))
}
