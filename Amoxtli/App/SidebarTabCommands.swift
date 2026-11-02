import SwiftUI

/// View menu items that show the sidebar on a given tab, since the segmented control only takes
/// keyboard focus when Keyboard Navigation is on.
struct SidebarTabCommands: Commands {
    @FocusedValue(\.sidebarTabAction) private var action

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                Button(tab.menuTitle) {
                    action?.show(tab)
                }
                .keyboardShortcut(tab.shortcut, modifiers: [.command, .option])
                .disabled(!(action?.availableTabs.contains(tab) ?? false))
            }
        }
    }
}
