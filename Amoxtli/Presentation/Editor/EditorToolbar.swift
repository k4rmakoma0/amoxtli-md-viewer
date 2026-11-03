import SwiftUI

/// The formatting tools and the mode picker. People can rearrange or remove them with
/// View > Customize Toolbar.
struct EditorToolbar: CustomizableToolbarContent {
    @Binding var mode: EditorMode
    let editor: SourceEditorController

    var body: some CustomizableToolbarContent {
        // Leading, next to Open: a narrow window moves the trailing items into the overflow
        // menu, and switching to the source is how editing starts.
        ToolbarItem(id: "mode", placement: .navigation) {
            ModePicker(mode: $mode)
        }
        ToolbarItem(id: "typography") {
            TypographyMenu()
        }
        ToolbarItem(id: "style") {
            StyleMenu(editor: editor)
        }
        ToolbarItem(id: "inline") {
            ToolGroup(title: "Estilo de texto", tools: FormatTool.inline, editor: editor)
        }
        ToolbarItem(id: "blocks") {
            ToolGroup(title: "Listas y citas", tools: FormatTool.blocks, editor: editor)
        }
        ToolbarItem(id: "insert") {
            ToolGroup(title: "Insertar", tools: FormatTool.insertions, editor: editor)
        }
    }
}

private struct TypographyMenu: View {
    private let preferences = TypographyPreferences()

    var body: some View {
        Menu {
            TypographyControls(preferences: preferences)
        } label: {
            Label("Tipo de letra y tamaño", systemImage: "textformat")
        }
        .help("Cambia el tipo de letra y el tamaño del texto")
    }
}

private struct StyleMenu: View {
    let editor: SourceEditorController

    var body: some View {
        Menu {
            ForEach(FormatTool.styles, id: \.self) { tool in
                Button(tool.title) { editor.perform(tool) }
            }
        } label: {
            Label("Estilo", systemImage: "textformat.size")
        }
        .help("Convierte las líneas seleccionadas en texto o en un título")
        .disabled(!editor.isAttached)
    }
}

private struct ToolGroup: View {
    let title: LocalizedStringKey
    let tools: [FormatTool]
    let editor: SourceEditorController

    var body: some View {
        ControlGroup {
            ForEach(tools, id: \.self) { tool in
                Button(tool.title, systemImage: tool.systemImage) { editor.perform(tool) }
                    .help(tool.title)
            }
        } label: {
            Text(title)
        }
        .disabled(!editor.isAttached)
    }
}

private struct ModePicker: View {
    @Binding var mode: EditorMode

    var body: some View {
        Picker("Modo", selection: $mode) {
            ForEach(EditorMode.allCases, id: \.self) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .help(mode.help)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .help("Elige cómo ver el documento")
    }
}
