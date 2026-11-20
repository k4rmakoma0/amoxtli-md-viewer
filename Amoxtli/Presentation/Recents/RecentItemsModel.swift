import AppKit
import Observation

/// The recent list every window shares: it remembers what opens, finds it again and forgets it.
@Observable
final class RecentItemsModel {
    private(set) var list: RecentList

    @ObservationIgnored private let store: RecentItemsStore
    @ObservationIgnored private let locator: any RecentItemLocating
    @ObservationIgnored private let clearSystemRecents: () -> Void
    /// Files reopened from here stay accessible for the rest of the session: their document
    /// reads, saves and watches them while it's open.
    @ObservationIgnored private var fileScopes: [URL: SecurityScope] = [:]

    /// AppKit is required for the default: the system's Open Recent menu, which `DocumentGroup`
    /// adds and SwiftUI can't change, belongs to the document controller.
    init(
        store: RecentItemsStore = RecentItemsStore(),
        locator: any RecentItemLocating = RecentItemLocator(),
        clearSystemRecents: @escaping () -> Void = { NSDocumentController.shared.clearRecentDocuments(nil) }
    ) {
        self.store = store
        self.locator = locator
        self.clearSystemRecents = clearSystemRecents
        list = store.load()
    }

    var items: [RecentItem] { list.items }

    /// A file that can't be bookmarked isn't remembered, since it couldn't be opened again.
    func recordFile(at url: URL) {
        guard let bookmark = locator.bookmark(for: url) else { return }
        record(RecentItem(kind: .file, url: url, bookmark: bookmark))
    }

    func recordFolder(at url: URL, bookmark: Data) {
        record(RecentItem(kind: .folder, url: url, bookmark: bookmark))
    }

    /// Where the item is now. An item that moved, or whose bookmark the system refreshed, is
    /// remembered as it is now, at the top, since it's about to open.
    func locate(_ item: RecentItem) -> RecentItemLocation {
        let location = locator.locate(item)
        guard case .available(let url, let bookmark) = location else { return location }
        let current = RecentItem(kind: item.kind, url: url, bookmark: bookmark)
        if current != item {
            list.remove(item)
            record(current)
        }
        // Access comes from the resolved URL itself: a copy, even a standardized one, lacks it.
        if item.kind == .file, fileScopes[current.url] == nil {
            fileScopes[current.url] = SecurityScope(url: url)
        }
        return location
    }

    func remove(_ item: RecentItem) {
        list.remove(item)
        store.save(list)
    }

    /// Also clears the system's Open Recent menu, so no list keeps what the person asked to forget.
    func clear() {
        list.removeAll()
        store.save(list)
        clearSystemRecents()
    }

    private func record(_ item: RecentItem) {
        list.record(item)
        store.save(list)
    }
}
