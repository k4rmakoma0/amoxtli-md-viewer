import AppKit
import SwiftUI

/// Shown when the app starts with nothing to open. The system's launch panel can only choose
/// files, so this window puts a new document, a file and a folder equally at hand. It closes
/// once any of them opens.
struct WelcomeView: View {
    static let windowID = "welcome"

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.newDocument) private var newDocument

    var body: some View {
        VStack(spacing: 28) {
            header
            VStack(spacing: 10) {
                Button(action: createDocument) {
                    Label("Nuevo documento", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: openFile) {
                    Label("Abrir archivo…", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: openFolder) {
                    Label("Open Folder…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.extraLarge)
            .frame(width: 260)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 40)
    }

    private func createDocument() {
        newDocument { MarkdownDocument() }
        dismissWindow(id: Self.windowID)
    }

    private func openFile() {
        Task {
            if await OpenFileAction.run() {
                dismissWindow(id: Self.windowID)
            }
        }
    }

    private func openFolder() {
        if openWindow.openChosenFolder() {
            dismissWindow(id: Self.windowID)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            // AppKit is required here: SwiftUI has no view for the app's own icon.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text(verbatim: "Amoxtli")
                .font(.largeTitle.bold())
            Text("Editor de Markdown")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WelcomeView()
}
