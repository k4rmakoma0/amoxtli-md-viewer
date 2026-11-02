import SwiftUI

struct FolderBrowserView: View {
    let sections: [MarkdownFolderSection]
    @Bindable var viewModel: FolderViewModel
    let document: DocumentViewModel

    @State private var links = LinkInteractionViewModel()
    @SceneStorage("sidebarTab") private var sidebarTab = SidebarTab.files

    var body: some View {
        ReaderSplitView {
            sidebar
                .safeAreaBar(edge: .top) { sidebarTabPicker }
        } detail: {
            detail
        }
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
            Text("Índice").tag(SidebarTab.contents)
            Text("Archivos").tag(SidebarTab.files)
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

private enum SidebarTab: String {
    case contents, files
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
