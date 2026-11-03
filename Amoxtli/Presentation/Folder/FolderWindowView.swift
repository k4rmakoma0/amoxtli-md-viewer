import AppKit
import SwiftUI

/// Window for an opened folder. Its value is a security-scoped bookmark, so the system restores
/// the window with everything it needs to get access to the folder again.
struct FolderWindowView: View {
    @Binding var bookmark: Data?

    @State private var viewModel = FolderViewModel()
    @State private var fileEditor = FolderFileEditor()
    @State private var editor = EditorController()
    @SceneStorage("editorMode") private var mode = EditorMode.formatted

    var body: some View {
        content
            .navigationTitle(viewModel.folderName ?? String(localized: "Carpeta"))
            .frame(minWidth: 640, minHeight: 360)
            .toolbar(id: "folder") {
                OpenToolbarItem()
                EditorToolbar(mode: $mode, editor: editor)
            }
            .focusedSceneValue(\.editorController, editor)
            .focusedSceneValue(\.editorMode, $mode)
            .task(id: bookmark) {
                guard let bookmark else { return }
                await viewModel.open(bookmark)
                if let current = viewModel.bookmark, current != bookmark {
                    self.bookmark = current
                }
            }
            .onDisappear { fileEditor.save() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                fileEditor.save()
            }
            .alert(
                "No se pudo guardar el archivo",
                isPresented: isShowingSaveFailure,
                presenting: fileEditor.saveFailure
            ) { _ in
                Button("Aceptar", role: .cancel) {}
            } message: { file in
                Text("Comprueba que tengas permiso para escribir en «\(file.lastPathComponent)». Si abriste esta carpeta con una versión anterior de Amoxtli, vuelve a abrirla.")
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
                FolderBrowserView(sections: sections, viewModel: viewModel, fileEditor: fileEditor, editor: editor, mode: $mode)
            case .empty:
                FolderUnavailableView(reason: .noMarkdownFiles, onChooseFolder: chooseFolder)
            case .failed(let error):
                FolderUnavailableView(reason: .failed(error), onChooseFolder: chooseFolder)
            }
        }
    }

    private var isShowingSaveFailure: Binding<Bool> {
        Binding {
            fileEditor.saveFailure != nil
        } set: { isPresented in
            if !isPresented { fileEditor.saveFailure = nil }
        }
    }

    private func chooseFolder() {
        if let chosen = FolderPicker().chooseFolder() {
            bookmark = chosen
        }
    }
}
