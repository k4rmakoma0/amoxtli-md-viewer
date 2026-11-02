import SwiftUI

struct FolderBrowserView: View {
    let sections: [MarkdownFolderSection]
    @Bindable var viewModel: FolderViewModel
    let document: DocumentViewModel

    @State private var links = LinkInteractionViewModel()
    @SceneStorage("sidebarTab") private var sidebarTab = SidebarTab.files
    @SceneStorage("isSidebarPresented") private var isSidebarPresented = true

    var body: some View {
        ReaderSplitView(isSidebarPresented: $isSidebarPresented) {
            // The empty states size to fit, so without the frame the picker would sink with them.
            sidebar
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaBar(edge: .top) { sidebarTabPicker }
        } detail: {
            detail
        }
        .focusedSceneValue(\.sidebarTabAction, SidebarTabAction(availableTabs: SidebarTab.allCases) { tab in
            sidebarTab = tab
            isSidebarPresented = true
        })
        .task(id: viewModel.selection) {
            if let selection = viewModel.selection {
                await document.load(contentsOf: selection)
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        switch sidebarTab {
        case .contents:
            tableOfContents
        case .files:
            FolderSidebarView(sections: sections, selection: $viewModel.selection)
        }
    }

    private var sidebarTabPicker: some View {
        Picker("Barra lateral", selection: $sidebarTab) {
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                Text(tab.title)
                    .help(tab.help)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var tableOfContents: some View {
        if viewModel.selectedFile == nil {
            ContentUnavailableView(
                "Sin índice",
                systemImage: "list.bullet.indent",
                description: Text("Elige un archivo para ver su índice.")
            )
        } else {
            TableOfContentsView(entries: document.tableOfContents) { entry in
                links.scroll(toBlock: entry.blockIndex)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let file = viewModel.selectedFile {
            MarkdownReaderView(viewModel: document, links: links, fileURL: file.url)
                .navigationSubtitle(Text(verbatim: file.name))
        } else {
            ContentUnavailableView(
                "Elige un archivo",
                systemImage: "doc.text",
                description: Text("Selecciona un archivo Markdown de la lista para leerlo.")
            )
        }
    }
}

private struct FolderSidebarView: View {
    let sections: [MarkdownFolderSection]
    @Binding var selection: MarkdownFile.ID?

    var body: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.files) { file in
                        Label {
                            Text(verbatim: file.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: "doc.text")
                        }
                        .accessibilityLabel(accessibilityLabel(for: file, in: section))
                    }
                } header: {
                    if !section.relativePath.isEmpty {
                        Text(verbatim: section.relativePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .accessibilityLabel(Text("Archivos de la carpeta"))
    }

    private func accessibilityLabel(for file: MarkdownFile, in section: MarkdownFolderSection) -> Text {
        section.relativePath.isEmpty ? Text(verbatim: file.name) : Text("\(file.name), en \(section.relativePath)")
    }
}
