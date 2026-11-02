import SwiftUI

struct FolderCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
                openWindow.openChosenFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}

extension OpenWindowAction {
    /// Asks for a folder and opens it in a window of its own. Returns `false` if the person cancels.
    @discardableResult
    func openChosenFolder() -> Bool {
        guard let bookmark = FolderPicker().chooseFolder() else { return false }
        self(value: bookmark)
        return true
    }
}
