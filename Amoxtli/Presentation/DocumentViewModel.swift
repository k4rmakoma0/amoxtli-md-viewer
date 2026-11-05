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
    /// Parsing can't be interrupted, and a large document takes seconds and hundreds of
    /// megabytes, so one parse runs at a time. Text that arrives meanwhile waits, and only the
    /// latest: what was typed in between is never parsed.
    @ObservationIgnored private var parsing: String?
    @ObservationIgnored private var queued: String?
    /// Changes with each document loaded, so a parse of the previous one is thrown away.
    @ObservationIgnored private var generation = 0

    init(parser: any MarkdownParsing = MarkdownParser()) {
        self.parser = parser
    }

    /// Reads a newly opened document.
    func load(_ content: Result<String, MarkdownDocumentError>) async {
        generation += 1
        state = .loading
        renderedSource = nil
        switch content {
        case .success(let source):
            await render(source)
        case .failure(let error):
            queued = nil
            apply(.failure(error))
        }
    }

    /// Renders an edit of the current document. Keeps showing the previous result until the new
    /// one is ready, and does nothing if the text didn't change.
    func update(_ source: String) async {
        // While another text is parsed, this one must still follow it, even if it is the one shown.
        guard source != renderedSource || parsing != nil else { return }
        await render(source)
    }

    /// Returns once the text is rendered, or once it is queued behind the parse that is running,
    /// which then renders it.
    private func render(_ source: String) async {
        // The text being parsed is already the latest again.
        queued = source == parsing ? nil : source
        guard parsing == nil else { return }
        while let next = queued {
            queued = nil
            parsing = next
            await renderNow(next)
            parsing = nil
        }
    }

    private func renderNow(_ source: String) async {
        guard source.contains(where: { !$0.isWhitespace }) else {
            renderedSource = source
            apply(.failure(.empty))
            return
        }
        let generation = generation
        let result = await Self.parse(source, with: parser)
        // A parse that ended after another document was loaded belongs to the previous one.
        guard generation == self.generation else { return }
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
