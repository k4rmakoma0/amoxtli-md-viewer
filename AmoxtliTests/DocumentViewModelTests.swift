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

    func testEmptyTextIsAnEmptyDocument() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success(" \n"))
        XCTAssertEqual(viewModel.state, .failed(.empty))
    }

    func testUpdateRendersEdits() async throws {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success("# Uno"))
        await viewModel.update("# Uno\n\n## Dos")
        XCTAssertEqual(viewModel.tableOfContents.map(\.title), ["Uno", "Dos"])
    }

    func testUpdateBeforeAnyLoadShowsTheDocument() async throws {
        let viewModel = DocumentViewModel()
        await viewModel.update("párrafo")
        XCTAssertEqual(viewModel.state, .loaded(try MarkdownParser().parse("párrafo")))
    }

    func testUpdateFromEmptyShowsTheDocument() async {
        let viewModel = DocumentViewModel()
        await viewModel.load(.success(""))
        await viewModel.update("# Uno")
        XCTAssertEqual(viewModel.tableOfContents.map(\.title), ["Uno"])
    }
}
