import SwiftUI

/// The Format menu, with every formatting tool and its shortcut.
struct FormatCommands: Commands {
    @FocusedValue(\.sourceEditor) private var editor

    var body: some Commands {
        CommandMenu("Formato") {
            ForEach(Array(FormatTool.menuGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { tool in
                    Button(tool.title, systemImage: tool.systemImage) {
                        editor?.perform(tool)
                    }
                    .keyboardShortcut(tool.shortcut)
                    .disabled(!(editor?.isAttached ?? false))
                }
            }
        }
    }
}

/// View menu items that switch between the source, the formatted document and both.
struct EditorModeCommands: Commands {
    @FocusedValue(\.editorMode) private var mode

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(EditorMode.allCases, id: \.self) { option in
                Button(option.menuTitle) {
                    mode?.wrappedValue = option
                }
                .keyboardShortcut(option.shortcut, modifiers: [.command, .control])
                .disabled(mode == nil)
            }
            Divider()
        }
    }
}
