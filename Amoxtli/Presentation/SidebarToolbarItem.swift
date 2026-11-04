import SwiftUI

/// Declared in the window's customizable toolbar, so all windows agree on its item set.
struct SidebarToolbarItem: CustomizableToolbarContent {
    @Binding var isPresented: Bool

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "sidebar", placement: .navigation) {
            Button("Barra lateral", systemImage: "sidebar.left") {
                isPresented.toggle()
            }
        }
    }
}
