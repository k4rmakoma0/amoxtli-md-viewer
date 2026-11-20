import SwiftUI

/// The last files and folders, and a way to forget them. Goes inside a menu, whose label is up
/// to each place that shows it.
struct RecentItemsMenuContent: View {
    /// Given by the view that holds the menu rather than read here: a toolbar's menu only
    /// updates when that view does.
    let list: RecentList
    /// Runs once an item has opened.
    var onOpen: () -> Void = {}

    @Environment(RecentItemsModel.self) private var recents
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !list.items.isEmpty {
            ForEach(list.items) { item in
                Button(list.title(for: item), systemImage: item.kind.systemImage) {
                    open(item)
                }
            }
            Divider()
        }
        Button("Borrar historial", action: recents.clear)
            .disabled(list.items.isEmpty)
    }

    private func open(_ item: RecentItem) {
        Task {
            if await RecentItemOpener(recents: recents, openWindow: openWindow).open(item) {
                onOpen()
            }
        }
    }
}

extension RecentItem.Kind {
    var systemImage: String {
        switch self {
        case .file: "doc.text"
        case .folder: "folder"
        }
    }
}
