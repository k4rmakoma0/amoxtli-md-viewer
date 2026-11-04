import SwiftUI

/// The formatting tools and the mode picker. People can rearrange or remove them with
/// View > Customize Toolbar.
///
/// Each tool is an item of its own, and spacers set the groups apart. A narrow window then
/// moves tools into the overflow menu one at a time, from the right, and the rest stay against
/// the trailing edge. A group in a single item would leave its whole width empty instead.
struct EditorToolbar: CustomizableToolbarContent {
    @Binding var mode: EditorMode
    let editor: EditorController

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
        ToolbarSpacer(.fixed)
        ToolItem(tool: .bold, editor: editor)
        ToolItem(tool: .italic, editor: editor)
        ToolItem(tool: .underline, editor: editor)
        ToolItem(tool: .strikethrough, editor: editor)
        ToolItem(tool: .inlineCode, editor: editor)
        ToolbarSpacer(.fixed)
        ToolItem(tool: .bulletList, editor: editor)
        ToolItem(tool: .numberedList, editor: editor)
        ToolItem(tool: .quote, editor: editor)
        ToolbarSpacer(.fixed)
        ToolItem(tool: .link, editor: editor)
        ToolItem(tool: .codeBlock, editor: editor)
        ToolItem(tool: .table, editor: editor)
        ToolItem(tool: .horizontalRule, editor: editor)
    }
}

private struct ToolItem: CustomizableToolbarContent {
    let tool: FormatTool
    let editor: EditorController

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: tool.toolbarID) {
            Button(tool.title, systemImage: tool.systemImage) { editor.perform(tool) }
                .help(tool.title)
                .disabled(!editor.isAttached)
        }
    }
}

private extension FormatTool {
    /// Stable, so a customized toolbar keeps its arrangement across launches.
    var toolbarID: String {
        switch self {
        case .bodyText: "bodyText"
        case .heading(let level): "heading\(level)"
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .inlineCode: "inlineCode"
        case .quote: "quote"
        case .bulletList: "bulletList"
        case .numberedList: "numberedList"
        case .link: "link"
        case .codeBlock: "codeBlock"
        case .table: "table"
        case .horizontalRule: "horizontalRule"
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
    let editor: EditorController

    var body: some View {
        Menu {
            ForEach(FormatTool.styles, id: \.self) { tool in
                Button(tool.title) { editor.perform(tool) }
            }
        } label: {
            Label("Estilo", systemImage: "paragraphsign")
        }
        .help("Convierte las líneas seleccionadas en texto o en un título")
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
