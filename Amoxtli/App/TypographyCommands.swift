import SwiftUI

/// View menu items for the typeface and the text size, which apply to every window.
struct TypographyCommands: Commands {
    private let preferences = TypographyPreferences()

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            TypographyControls(preferences: preferences)
        }
    }
}
