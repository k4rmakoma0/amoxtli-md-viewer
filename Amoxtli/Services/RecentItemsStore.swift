import Foundation

/// Keeps the recent list in `UserDefaults`, so it survives relaunches.
struct RecentItemsStore {
    private static let itemsKey = "recentItems"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// A list that can't be read, say from a future version, starts over empty.
    func load() -> RecentList {
        guard let data = defaults.data(forKey: Self.itemsKey),
              let items = try? JSONDecoder().decode([RecentItem].self, from: data) else {
            return RecentList()
        }
        return RecentList(items: items)
    }

    func save(_ list: RecentList) {
        guard !list.items.isEmpty, let data = try? JSONEncoder().encode(list.items) else {
            defaults.removeObject(forKey: Self.itemsKey)
            return
        }
        defaults.set(data, forKey: Self.itemsKey)
    }
}

/// What the app does when it starts.
struct LaunchPreferences {
    static let reopensLastItemKey = "reopensLastItem"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On unless the person turned it off, like the toggle in Settings shows it.
    var reopensLastItem: Bool {
        defaults.object(forKey: Self.reopensLastItemKey) as? Bool ?? true
    }
}

nonisolated protocol RecentItemLocating: Sendable {
    func bookmark(for url: URL) -> Data?
    func locate(_ item: RecentItem) -> RecentItemLocation
}

/// Finds recent items through their security-scoped bookmarks. Files and folders share the
/// bookmark code of opened folders.
nonisolated struct RecentItemLocator: RecentItemLocating {
    private let bookmarks: any FolderBookmarking

    init(bookmarks: any FolderBookmarking = SecurityScopedBookmarks()) {
        self.bookmarks = bookmarks
    }

    func bookmark(for url: URL) -> Data? {
        try? bookmarks.makeBookmark(for: url)
    }

    /// A bookmark that no longer resolves, or that leads to the Trash or to something of another
    /// kind, means the item is gone.
    func locate(_ item: RecentItem) -> RecentItemLocation {
        guard let resolved = try? bookmarks.resolve(item.bookmark), !TrashLocation.contains(resolved.url) else {
            return .missing
        }
        let scope = SecurityScope(url: resolved.url)
        let exists = withExtendedLifetime(scope) { Self.exists(resolved.url, as: item.kind) }
        guard exists else { return .missing }
        return .available(resolved.url, bookmark: resolved.refreshedBookmark ?? item.bookmark)
    }

    private static func exists(_ url: URL, as kind: RecentItem.Kind) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue == (kind == .folder)
    }
}
