import Foundation

nonisolated struct ResolvedFolder: Sendable {
    let url: URL
    /// Replacement for a bookmark that still resolves but that the system reports as stale.
    let refreshedBookmark: Data?
}

nonisolated protocol FolderBookmarking: Sendable {
    func makeBookmark(for folder: URL) throws(FolderError) -> Data
    func resolve(_ bookmark: Data) throws(FolderError) -> ResolvedFolder
}

nonisolated struct SecurityScopedBookmarks: FolderBookmarking {
    func makeBookmark(for folder: URL) throws(FolderError) -> Data {
        do {
            return try folder.bookmarkData(options: .withSecurityScope)
        } catch {
            throw .unreadable
        }
    }

    func resolve(_ bookmark: Data) throws(FolderError) -> ResolvedFolder {
        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
        } catch {
            throw .staleBookmark
        }
        return ResolvedFolder(url: url, refreshedBookmark: isStale ? try refreshedBookmark(for: url) : nil)
    }

    private func refreshedBookmark(for url: URL) throws(FolderError) -> Data {
        let scope = SecurityScope(url: url)
        do {
            return try withExtendedLifetime(scope) { () throws(FolderError) -> Data in
                try makeBookmark(for: url)
            }
        } catch {
            throw .staleBookmark
        }
    }
}

/// Keeps a folder accessible to the sandbox for as long as this object is alive.
nonisolated final class SecurityScope: Sendable {
    private let url: URL
    private let isAccessing: Bool

    /// The system returns `false` for URLs without a scope, such as those already inside the
    /// container. That isn't an error: if access really is denied, reading the folder will fail.
    init(url: URL) {
        self.url = url
        isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
