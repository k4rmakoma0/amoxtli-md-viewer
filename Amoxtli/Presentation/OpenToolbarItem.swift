import AppKit
import SwiftUI

/// "Open" split button: a click opens a file, and its menu also offers a folder.
struct OpenToolbarItem: CustomizableToolbarContent {
    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "open", placement: .navigation) {
            OpenMenu()
        }
    }
}

private struct OpenMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(RecentItemsModel.self) private var recents

    var body: some View {
        Menu("Abrir", systemImage: "folder") {
            Button("Abrir archivo…", systemImage: "doc.text", action: openFile)
            Button("Open Folder…", systemImage: "folder") {
                openWindow.openChosenFolder()
            }
            Divider()
            Menu("Abrir recientes", systemImage: "clock") {
                RecentItemsMenuContent(list: recents.list)
            }
        } primaryAction: {
            openFile()
        }
        .help("Abrir un archivo o una carpeta")
    }

    private func openFile() {
        Task { await OpenFileAction.run() }
    }
}

enum OpenFileAction {
    /// AppKit is required here: `DocumentGroup` has no SwiftUI action that shows its open panel,
    /// and the document controller opens the file in the same kind of window as File > Open.
    /// Returns `false` if the person cancels.
    @discardableResult
    static func run() async -> Bool {
        guard let files = await NSDocumentController.shared.beginOpenPanel(), !files.isEmpty else { return false }
        for file in files {
            await open(file)
        }
        return true
    }

    /// Opens the file in a document window, or brings its window forward if it's already open.
    /// Returns `false`, after explaining why, if it can't.
    @discardableResult
    static func open(_ file: URL) async -> Bool {
        let controller = NSDocumentController.shared
        do {
            _ = try await controller.openDocument(withContentsOf: file, display: true)
            return true
        } catch {
            controller.presentError(error)
            return false
        }
    }
}
