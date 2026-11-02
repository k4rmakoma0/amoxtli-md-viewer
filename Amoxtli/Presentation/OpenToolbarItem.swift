import AppKit
import SwiftUI

/// "Open" split button: a click opens a file, and its menu also offers a folder.
struct OpenToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            OpenMenu()
        }
    }
}

private struct OpenMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu("Abrir", systemImage: "folder") {
            Button("Abrir archivo…", systemImage: "doc.text", action: openFile)
            Button("Open Folder…", systemImage: "folder") {
                openWindow.openChosenFolder()
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
        let controller = NSDocumentController.shared
        guard let files = await controller.beginOpenPanel(), !files.isEmpty else { return false }
        for file in files {
            do {
                _ = try await controller.openDocument(withContentsOf: file, display: true)
            } catch {
                controller.presentError(error)
            }
        }
        return true
    }
}
