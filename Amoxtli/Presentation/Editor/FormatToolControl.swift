import SwiftUI

/// A formatting tool as a control that shows whether its formatting is in effect: a toggle,
/// drawn as a pressed button in the toolbar and with a checkmark in menus. Tools that only
/// insert something stay plain buttons.
struct FormatToolControl: View {
    let tool: FormatTool
    let editor: EditorController
    /// For choices like the paragraph style, where picking the current one keeps it.
    var onlyTurnsOn = false
    var showsIcon = true

    var body: some View {
        if tool.isActive(in: .none) != nil {
            Toggle(isOn: isOn) { label }
        } else {
            Button(action: { editor.perform(tool) }) { label }
        }
    }

    private var isOn: Binding<Bool> {
        Binding {
            editor.isActive(tool)
        } set: { turnsOn in
            if turnsOn || !onlyTurnsOn { editor.perform(tool) }
        }
    }

    @ViewBuilder
    private var label: some View {
        if showsIcon {
            Label(tool.title, systemImage: tool.systemImage)
        } else {
            Text(tool.title)
        }
    }
}
