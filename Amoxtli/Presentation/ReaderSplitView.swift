import SwiftUI

/// Layout of both window modes: a sidebar on the left and the document on the right.
struct ReaderSplitView<Sidebar: View, Detail: View>: View {
    @Binding var isSidebarPresented: Bool
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 420)
                // The window declares the sidebar button alongside its other customizable
                // items. A separate child toolbar duplicates it across document windows.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            isSidebarPresented ? .all : .detailOnly
        } set: { visibility in
            isSidebarPresented = visibility != .detailOnly
        }
    }
}
