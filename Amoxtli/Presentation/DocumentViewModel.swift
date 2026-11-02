import Foundation
import Observation

@Observable
final class DocumentViewModel {
    enum State: Equatable {
        case loading
        case loaded(MarkdownModel)
        case failed(MarkdownDocumentError)
    }

    private(set) var state: State = .loading
    private(set) var tableOfContents: [TOCEntry] = []
    private(set) var readingStats: ReadingStats?
    /// Changes on every load, so each loaded document starts with a fresh scroll position.
    private(set) var loadCount = 0
    @ObservationIgnored private let parser: any MarkdownParsing

    init(parser: any MarkdownParsing = MarkdownParser()) {
        self.parser = parser
    }

    func load(_ content: Result<String, MarkdownDocumentError>) async {
        state = .loading
        switch content {
        case .success(let source):
            let result = await Self.parse(source, with: parser)
            guard !Task.isCancelled else { return }
            apply(result)
        case .failure(let error):
            apply(.failure(error))
        }
    }

    func load(contentsOf file: URL) async {
        state = .loading
        let content = await Self.read(file)
        guard !Task.isCancelled else { return }
        await load(content)
    }

    private func apply(_ result: Result<ParsedDocument, MarkdownDocumentError>) {
        loadCount += 1
        switch result {
        case .success(let document):
            tableOfContents = document.tableOfContents
            readingStats = document.readingStats
            state = .loaded(document.model)
        case .failure(let error):
            tableOfContents = []
            readingStats = nil
            state = .failed(error)
        }
    }

    private struct ParsedDocument: Sendable {
        let model: MarkdownModel
        let tableOfContents: [TOCEntry]
        let readingStats: ReadingStats
    }

    @concurrent
    private static func read(_ file: URL) async -> Result<String, MarkdownDocumentError> {
        MarkdownDocument(data: try? Data(contentsOf: file)).content
    }

    @concurrent
    private static func parse(
        _ source: String,
        with parser: any MarkdownParsing
    ) async -> Result<ParsedDocument, MarkdownDocumentError> {
        do {
            let model = try parser.parse(source)
            return .success(ParsedDocument(
                model: model,
                tableOfContents: TOCBuilder.entries(for: model.blocks),
                readingStats: ReadingStats(blocks: model.blocks)
            ))
        } catch {
            return .failure(.unparsable)
        }
    }
}
