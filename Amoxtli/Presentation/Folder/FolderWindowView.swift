import SwiftUI

/// Window for an opened folder. Its value is a security-scoped bookmark, so the system restores
/// the window with everything it needs to get access to the folder again.
struct FolderWindowView: View {
    @Binding var bookmark: Data?

    @State private var viewModel = FolderViewModel()
    @State private var document = DocumentViewModel()

    var body: some View {
        content
            .navigationTitle(viewModel.folderName ?? String(localized: "Carpeta"))
            .frame(minWidth: 640, minHeight: 360)
            .toolbar { OpenToolbarItem() }
            .task(id: bookmark) {
                guard let bookmark else { return }
                await viewModel.open(bookmark)
                if let current = viewModel.bookmark, current != bookmark {
                    self.bookmark = current
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if bookmark == nil {
            FolderUnavailableView(reason: .noFolder, onChooseFolder: chooseFolder)
        } else {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let sections):
                FolderBrowserView(sections: sections, viewModel: viewModel, document: document)
            case .empty:
                FolderUnavailableView(reason: .noMarkdownFiles, onChooseFolder: chooseFolder)
            case .failed(let error):
                FolderUnavailableView(reason: .failed(error), onChooseFolder: chooseFolder)
            }
        }
    }

    private func chooseFolder() {
        if let chosen = FolderPicker().chooseFolder() {
            bookmark = chosen
        }
    }
}
