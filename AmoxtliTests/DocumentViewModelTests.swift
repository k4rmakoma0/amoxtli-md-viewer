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

    /// Holds one parse until released, as a large document would, and records every text parsed.
    private final class GatedParser: MarkdownParsing, @unchecked Sendable {
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        private let gatedCall: Int
        private var sources: [String] = []

        init(gatedCall: Int = 1) {
            self.gatedCall = gatedCall
        }

        var parsed: [String] { lock.withLock { sources } }

        func parse(_ source: String) throws -> MarkdownModel {
            let isGated = lock.withLock {
                sources.append(source)
                return sources.count == gatedCall
            }
            if isGated {
                gate.wait()
                gate.signal()
            }
            return try MarkdownParser().parse(source)
        }

        func release() {
            gate.signal()
        }

        func waitUntilParsing() async {
            while parsed.count < gatedCall { await Task.yield() }
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

    func testEditsDuringAParseWaitAndOnlyTheLatestIsParsed() async throws {
        let parser = GatedParser()
        let viewModel = DocumentViewModel(parser: parser)
        let first = Task { await viewModel.update("# Uno") }
        await parser.waitUntilParsing()
        await viewModel.update("# Dos")
        await viewModel.update("# Tres")
        parser.release()
        await first.value
        XCTAssertEqual(parser.parsed, ["# Uno", "# Tres"])
        XCTAssertEqual(viewModel.tableOfContents.map(\.title), ["Tres"])
    }

    func testReturningToTheTextBeingParsedParsesItOnce() async throws {
        let parser = GatedParser()
        let viewModel = DocumentViewModel(parser: parser)
        let first = Task { await viewModel.update("# Uno") }
        await parser.waitUntilParsing()
        await viewModel.update("# Dos")
        await viewModel.update("# Uno")
        parser.release()
        await first.value
        XCTAssertEqual(parser.parsed, ["# Uno"])
        XCTAssertEqual(viewModel.tableOfContents.map(\.title), ["Uno"])
    }

    func testReturningToTheShownTextDuringAParseShowsItAgain() async throws {
        let parser = GatedParser(gatedCall: 2)
        let viewModel = DocumentViewModel(parser: parser)
        await viewModel.update("# Uno")
        let second = Task { await viewModel.update("# Dos") }
        await parser.waitUntilParsing()
        await viewModel.update("# Uno")
        parser.release()
        await second.value
        XCTAssertEqual(parser.parsed, ["# Uno", "# Dos", "# Uno"])
        XCTAssertEqual(viewModel.tableOfContents.map(\.title), ["Uno"])
    }

    func testAParseOfThePreviousDocumentIsThrownAway() async {
        let parser = GatedParser()
        let viewModel = DocumentViewModel(parser: parser)
        let first = Task { await viewModel.load(.success("# Viejo")) }
        await parser.waitUntilParsing()
        await viewModel.load(.failure(.invalidEncoding))
        parser.release()
        await first.value
        XCTAssertEqual(viewModel.state, .failed(.invalidEncoding))
        XCTAssertEqual(viewModel.tableOfContents, [])
    }
}
