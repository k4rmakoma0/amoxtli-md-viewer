import Foundation
import Observation

@Observable
final class FolderViewModel {
    enum State: Equatable {
        case loading
        case loaded([MarkdownFolderSection])
        case empty
        case failed(FolderError)
    }

    private(set) var state: State = .loading
    private(set) var folderURL: URL?
    /// The bookmark in use. It differs from the one passed to `open` when the system refreshed it.
    private(set) var bookmark: Data?
    var selection: MarkdownFile.ID?

    @ObservationIgnored private var scope: SecurityScope?
    @ObservationIgnored private let bookmarks: any FolderBookmarking
    @ObservationIgnored private let scanner: any FolderScanning

    init(bookmarks: any FolderBookmarking = SecurityScopedBookmarks(), scanner: any FolderScanning = FolderScanner()) {
        self.bookmarks = bookmarks
        self.scanner = scanner
    }

    func open(_ bookmark: Data) async {
        guard bookmark != self.bookmark else { return }
        state = .loading
        selection = nil
        let result = await Self.scan(bookmark, bookmarks: bookmarks, scanner: scanner)
        guard !Task.isCancelled else { return }
        apply(result, for: bookmark)
    }

    var folderName: String? { folderURL?.lastPathComponent }

    var selectedFile: MarkdownFile? {
        guard case .loaded(let sections) = state else { return nil }
        return sections.lazy.flatMap(\.files).first { $0.id == selection }
    }

    private func apply(_ result: Result<ScannedFolder, FolderError>, for bookmark: Data) {
        switch result {
        case .success(let folder):
            scope = folder.scope
            folderURL = folder.url
            self.bookmark = folder.refreshedBookmark ?? bookmark
            state = folder.sections.isEmpty ? .empty : .loaded(folder.sections)
        case .failure(let error):
            scope = nil
            folderURL = nil
            self.bookmark = nil
            state = .failed(error)
        }
    }

    private struct ScannedFolder: Sendable {
        let url: URL
        let sections: [MarkdownFolderSection]
        let scope: SecurityScope
        let refreshedBookmark: Data?
    }

    @concurrent
    private static func scan(
        _ bookmark: Data,
        bookmarks: any FolderBookmarking,
        scanner: any FolderScanning
    ) async -> Result<ScannedFolder, FolderError> {
        do throws(FolderError) {
            let folder = try bookmarks.resolve(bookmark)
            let scope = SecurityScope(url: folder.url)
            return .success(ScannedFolder(
                url: folder.url,
                sections: try scanner.scan(folder.url),
                scope: scope,
                refreshedBookmark: folder.refreshedBookmark
            ))
        } catch {
            return .failure(error)
        }
    }
}
