import Foundation
import Observation

/// Turns the text being edited into its table of contents and its reading stats.
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
    @ObservationIgnored private var renderedSource: String?
    @ObservationIgnored private let parser: any MarkdownParsing

    init(parser: any MarkdownParsing = MarkdownParser()) {
        self.parser = parser
    }

    /// Reads a newly opened document.
    func load(_ content: Result<String, MarkdownDocumentError>) async {
        state = .loading
        renderedSource = nil
        switch content {
        case .success(let source):
            await render(source)
        case .failure(let error):
            apply(.failure(error))
        }
    }

    /// Renders an edit of the current document. Keeps showing the previous result until the new
    /// one is ready, and does nothing if the text didn't change.
    func update(_ source: String) async {
        guard source != renderedSource else { return }
        await render(source)
    }

    private func render(_ source: String) async {
        guard source.contains(where: { !$0.isWhitespace }) else {
            renderedSource = source
            apply(.failure(.empty))
            return
        }
        let result = await Self.parse(source, with: parser)
        guard !Task.isCancelled else { return }
        renderedSource = source
        apply(result)
    }

    private func apply(_ result: Result<ParsedDocument, MarkdownDocumentError>) {
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
