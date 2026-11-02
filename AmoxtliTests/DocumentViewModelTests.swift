import XCTest
@testable import Amoxtli

@MainActor
final class DocumentViewModelTests: XCTestCase {
    private struct FailingParser: MarkdownParsing {
        struct Failure: Error {}

        func parse(_ source: String) throws -> MarkdownModel {
            throw Failure()
        }
    }

    func testStartsLoading() {
        XCTAssertEqual(DocumentViewModel().state, .loading)
    }

    func testValidContentLoadsModel() async throws {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success("párrafo"))
        let expected = try MarkdownParser().parse("párrafo")
        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testDocumentErrorIsExposed() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.failure(.invalidEncoding))
        XCTAssertEqual(viewModel.state, .failed(.invalidEncoding))
    }

    func testParserFailureIsExposed() async {
        let viewModel = DocumentViewModel(parser: FailingParser())
        await viewModel.load(.success("párrafo"))
        XCTAssertEqual(viewModel.state, .failed(.unparsable))
    }

    func testReloadRecoversFromFailure() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.failure(.empty))
        await viewModel.load(.success("párrafo"))
        guard case .loaded = viewModel.state else {
            return XCTFail("Se esperaba el estado loaded, no \(viewModel.state)")
        }
    }

    func testTableOfContentsComesFromLoadedDocument() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success("# Uno\n\n## Dos"))
        XCTAssertEqual(viewModel.tableOfContents.map(\.title), ["Uno", "Dos"])
    }

    func testFailureClearsTableOfContents() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success("# Uno"))
        await viewModel.load(.failure(.empty))
        XCTAssertEqual(viewModel.tableOfContents, [])
    }

    func testReadingStatsComeFromLoadedDocument() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success("# Uno\n\ndos tres"))
        XCTAssertEqual(viewModel.readingStats, ReadingStats(wordCount: 3))
    }

    func testFailureClearsReadingStats() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success("# Uno"))
        await viewModel.load(.failure(.empty))
        XCTAssertNil(viewModel.readingStats)
    }

    func testEveryLoadChangesTheLoadCount() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success("# Uno"))
        let first = viewModel.loadCount
        await viewModel.load(.success("# Uno"))
        XCTAssertNotEqual(viewModel.loadCount, first)
    }

    func testLoadingFileReadsIt() async throws {
        let file = try makeTemporaryFolder().addFile("nota.md", contents: Data("# Uno".utf8))
        let viewModel = DocumentViewModel()
        await viewModel.load(contentsOf: file)
        XCTAssertEqual(viewModel.state, .loaded(try MarkdownParser().parse("# Uno")))
    }

    func testLoadingMissingFileIsUnreadable() async throws {
        let viewModel = DocumentViewModel()
        await viewModel.load(contentsOf: try makeTemporaryFolder().url.appending(path: "no-existe.md"))
        XCTAssertEqual(viewModel.state, .failed(.unreadable))
    }

    func testLoadingInvalidFileReportsTheEncoding() async throws {
        let file = try makeTemporaryFolder().addFile("nota.md", contents: Data([0xFF, 0xFE, 0xFD]))
        let viewModel = DocumentViewModel()
        await viewModel.load(contentsOf: file)
        XCTAssertEqual(viewModel.state, .failed(.invalidEncoding))
    }

    func testLoadingEmptyFileIsEmpty() async throws {
        let file = try makeTemporaryFolder().addFile("nota.md", contents: Data())
        let viewModel = DocumentViewModel()
        await viewModel.load(contentsOf: file)
        XCTAssertEqual(viewModel.state, .failed(.empty))
    }
}
