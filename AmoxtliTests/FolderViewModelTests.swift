import XCTest
@testable import Amoxtli

@MainActor
final class FolderViewModelTests: XCTestCase {
    private struct FakeBookmarks: FolderBookmarking {
        var result: Result<ResolvedFolder, FolderError>

        func makeBookmark(for folder: URL) throws(FolderError) -> Data {
            Data(folder.path.utf8)
        }

        func resolve(_ bookmark: Data) throws(FolderError) -> ResolvedFolder {
            try result.get()
        }
    }

    private final class CountingScanner: FolderScanning, @unchecked Sendable {
        private(set) var scanCount = 0

        func scan(_ folder: URL) throws(FolderError) -> [MarkdownFolderSection] {
            scanCount += 1
            return try FolderScanner().scan(folder)
        }
    }

    private let bookmark = Data("marcador".utf8)

    private func viewModel(
        folder: URL,
        refreshedBookmark: Data? = nil,
        scanner: any FolderScanning = FolderScanner()
    ) -> FolderViewModel {
        let resolved = ResolvedFolder(url: folder, refreshedBookmark: refreshedBookmark)
        return FolderViewModel(bookmarks: FakeBookmarks(result: .success(resolved)), scanner: scanner)
    }

    func testStartsLoading() {
        XCTAssertEqual(FolderViewModel().state, .loading)
    }

    func testFolderWithMarkdownIsLoaded() async throws {
        let folder = try makeTemporaryFolder()
        try folder.addFile("nota.md")
        let viewModel = viewModel(folder: folder.url)
        await viewModel.open(bookmark)
        guard case .loaded(let sections) = viewModel.state else {
            return XCTFail("Se esperaba loaded, no \(viewModel.state)")
        }
        XCTAssertEqual(sections.flatMap(\.files).map(\.name), ["nota.md"])
        XCTAssertEqual(viewModel.folderName, folder.url.lastPathComponent)
        XCTAssertEqual(viewModel.folderURL, folder.url)
        XCTAssertEqual(viewModel.bookmark, bookmark)
    }

    func testFolderWithoutMarkdownIsEmpty() async throws {
        let folder = try makeTemporaryFolder()
        try folder.addFile("nota.txt")
        let viewModel = viewModel(folder: folder.url)
        await viewModel.open(bookmark)
        XCTAssertEqual(viewModel.state, .empty)
    }

    func testBookmarkThatCannotResolveFailsAsStale() async {
        let viewModel = FolderViewModel(bookmarks: FakeBookmarks(result: .failure(.staleBookmark)))
        await viewModel.open(bookmark)
        XCTAssertEqual(viewModel.state, .failed(.staleBookmark))
        XCTAssertNil(viewModel.folderName)
        XCTAssertNil(viewModel.folderURL)
    }

    func testUnreadableFolderFails() async throws {
        let missing = try makeTemporaryFolder().url.appending(path: "no-existe")
        let viewModel = viewModel(folder: missing)
        await viewModel.open(bookmark)
        XCTAssertEqual(viewModel.state, .failed(.unreadable))
    }

    func testRefreshedBookmarkReplacesTheOriginal() async throws {
        let refreshed = Data("renovado".utf8)
        let viewModel = viewModel(folder: try makeTemporaryFolder().url, refreshedBookmark: refreshed)
        await viewModel.open(bookmark)
        XCTAssertEqual(viewModel.bookmark, refreshed)
    }

    func testReopeningTheSameBookmarkDoesNotScanAgain() async throws {
        let refreshed = Data("renovado".utf8)
        let scanner = CountingScanner()
        let viewModel = viewModel(folder: try makeTemporaryFolder().url, refreshedBookmark: refreshed, scanner: scanner)
        await viewModel.open(bookmark)
        await viewModel.open(refreshed)
        XCTAssertEqual(scanner.scanCount, 1)
    }

    func testRetryingAfterAFailureScansAgain() async throws {
        let scanner = CountingScanner()
        let missing = try makeTemporaryFolder().url.appending(path: "no-existe")
        let viewModel = viewModel(folder: missing, scanner: scanner)
        await viewModel.open(bookmark)
        await viewModel.open(bookmark)
        XCTAssertEqual(scanner.scanCount, 2)
    }

    func testOpeningAnotherFolderClearsTheSelection() async throws {
        let folder = try makeTemporaryFolder()
        let file = try folder.addFile("nota.md")
        let viewModel = viewModel(folder: folder.url)
        await viewModel.open(bookmark)
        viewModel.selection = file
        await viewModel.open(Data("otra".utf8))
        XCTAssertNil(viewModel.selection)
    }

    func testSelectedFileComesFromTheScan() async throws {
        let folder = try makeTemporaryFolder()
        try folder.addFile("docs/nota.md")
        let viewModel = viewModel(folder: folder.url)
        await viewModel.open(bookmark)
        XCTAssertNil(viewModel.selectedFile)
        guard case .loaded(let sections) = viewModel.state, let file = sections.first?.files.first else {
            return XCTFail("Se esperaba un archivo")
        }
        viewModel.selection = file.id
        XCTAssertEqual(viewModel.selectedFile, file)
    }

    func testRealBookmarkRoundTripsInTheSandbox() throws {
        let folder = try makeTemporaryFolder()
        let bookmarks = SecurityScopedBookmarks()
        let resolved = try bookmarks.resolve(try bookmarks.makeBookmark(for: folder.url))
        XCTAssertEqual(resolved.url.standardizedFileURL.resolvingSymlinksInPath(), folder.url.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testGarbageBookmarkIsStale() {
        XCTAssertThrowsError(try SecurityScopedBookmarks().resolve(Data("basura".utf8))) { error in
            XCTAssertEqual(error as? FolderError, .staleBookmark)
        }
    }
}
