import SwiftUI

/// Layout of both window modes: a sidebar on the left and the document on the right. Whether the
/// sidebar shows is saved per window.
struct ReaderSplitView<Sidebar: View, Detail: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    @SceneStorage("isSidebarPresented") private var isSidebarPresented = true

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 420)
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
