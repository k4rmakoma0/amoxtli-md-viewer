import SwiftUI

@main
struct AmoxtliApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            DefaultAppCommands(flow: appDelegate.defaultAppFlow)
            LinkCommands()
            ReadOnlyDocumentCommands()
            FolderCommands()
            SidebarCommands()
            SidebarTabCommands()
        }

        WindowGroup(for: Data.self) { $bookmark in
            FolderWindowView(bookmark: $bookmark)
        }
        .defaultSize(width: 1320, height: 760)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()

        Window("Bienvenida", id: WelcomeView.windowID) {
            WelcomeView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
    }
}
