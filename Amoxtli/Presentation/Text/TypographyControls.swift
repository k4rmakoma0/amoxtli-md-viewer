import SwiftUI

/// The typeface choices and size steps, shared by the toolbar menu and the View menu.
struct TypographyControls: View {
    let preferences: TypographyPreferences

    var body: some View {
        Picker("Tipo de letra", selection: preferences.$font) {
            ForEach(ReadingFont.allCases, id: \.self) { font in
                Text(font.title).tag(font)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Button("Aumentar tamaño", systemImage: "textformat.size.larger", action: preferences.makeLarger)
            .keyboardShortcut("+")
            .disabled(preferences.size.larger == nil)
        Button("Reducir tamaño", systemImage: "textformat.size.smaller", action: preferences.makeSmaller)
            .keyboardShortcut("-")
            .disabled(preferences.size.smaller == nil)
        Button("Tamaño normal", action: preferences.resetSize)
            .keyboardShortcut("0")
            .disabled(preferences.size == .standard)
    }
}
