import SwiftUI

/// The Format menu, with every formatting tool and its shortcut, and a checkmark on the
/// formatting in effect.
struct FormatCommands: Commands {
    @FocusedValue(\.editorController) private var editor

    var body: some Commands {
        CommandMenu("Formato") {
            ForEach(Array(FormatTool.menuGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { tool in
                    item(for: tool)
                        .keyboardShortcut(tool.shortcut)
                        .disabled(!(editor?.isAttached ?? false))
                }
            }
        }
    }

    @ViewBuilder
    private func item(for tool: FormatTool) -> some View {
        if let editor {
            FormatToolControl(tool: tool, editor: editor, onlyTurnsOn: FormatTool.styles.contains(tool))
        } else {
            Button(tool.title, systemImage: tool.systemImage) {}
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
