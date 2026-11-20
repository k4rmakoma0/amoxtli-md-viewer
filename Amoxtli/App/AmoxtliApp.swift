import SwiftUI

@main
struct AmoxtliApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
                .environment(appDelegate.recents)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            DefaultAppCommands(flow: appDelegate.defaultAppFlow)
            LinkCommands()
            FolderCommands()
            FormatCommands()
            EditorModeCommands()
            TypographyCommands()
            SidebarCommands()
            SidebarTabCommands()
        }

        WindowGroup(for: Data.self) { $bookmark in
            FolderWindowView(bookmark: $bookmark)
                .environment(appDelegate.recents)
                .onAppear {
                    if bookmark == nil {
                        bookmark = appDelegate.launch.takeFolder()
                    }
                }
        }
        .defaultSize(width: 1320, height: 760)
        .defaultLaunchBehavior(appDelegate.launch.presentsFolderWindow ? .presented : .suppressed)
        .commandsRemoved()

        Window("Bienvenida", id: WelcomeView.windowID) {
            WelcomeView()
                .environment(appDelegate.recents)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(appDelegate.launch.presentsWelcome ? .presented : .suppressed)

        Settings {
            SettingsView()
                .environment(appDelegate.recents)
        }
    }
}
