import Foundation

/// A file or folder opened recently. The bookmark gets access to it again after a relaunch,
/// which the sandbox otherwise grants only while the person's choice lasts.
nonisolated struct RecentItem: Codable, Hashable, Identifiable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case file, folder
    }

    let kind: Kind
    /// Where the item was when it was opened. Opening the same place again moves it to the top
    /// instead of adding it twice.
    let url: URL
    let bookmark: Data

    init(kind: Kind, url: URL, bookmark: Data) {
        self.kind = kind
        self.url = url.standardizedFileURL
        self.bookmark = bookmark
    }

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// The files and folders opened most recently, newest first.
nonisolated struct RecentList: Equatable, Sendable {
    static let limit = 10

    private(set) var items: [RecentItem]

    init(items: [RecentItem] = []) {
        self.items = []
        items.reversed().forEach { record($0) }
    }

    var last: RecentItem? { items.first }

    mutating func record(_ item: RecentItem) {
        remove(item)
        items.insert(item, at: 0)
        items = Array(items.prefix(Self.limit))
    }

    mutating func remove(_ item: RecentItem) {
        items.removeAll { $0.id == item.id }
    }

    mutating func removeAll() {
        items.removeAll()
    }

    /// The item's name, followed by its folder's when another item has the same name, as with a
    /// README.md in each project.
    func title(for item: RecentItem) -> String {
        let isAmbiguous = items.contains {
            $0.id != item.id && $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame
        }
        guard isAmbiguous else { return item.name }
        return "\(item.name) — \(item.url.deletingLastPathComponent().lastPathComponent)"
    }
}

/// Where a recent item is now, if it still exists.
nonisolated enum RecentItemLocation: Equatable, Sendable {
    /// The bookmark is the one to keep using: the system may have refreshed it.
    case available(URL, bookmark: Data)
    case missing
}

nonisolated enum TrashLocation {
    /// Bookmarks follow an item into the Trash, but for the person it's been deleted.
    static func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}

/// What opens when the app starts with nothing else to open.
nonisolated enum LaunchPlan: Equatable, Sendable {
    case welcome
    case file(URL)
    case folder(bookmark: Data)

    /// The last item comes back where it is now. If it no longer exists, the welcome window opens
    /// as always.
    init(last item: RecentItem, location: RecentItemLocation) {
        switch (item.kind, location) {
        case (_, .missing): self = .welcome
        case (.file, .available(let url, _)): self = .file(url)
        case (.folder, .available(_, let bookmark)): self = .folder(bookmark: bookmark)
        }
    }
}
