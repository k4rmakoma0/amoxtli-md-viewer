import Foundation
import Observation

/// Turns the text being edited into the rendered model, its table of contents and its stats.
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
    /// Edits go through `update`, which keeps it, so typing doesn't jump back to the top.
    private(set) var loadCount = 0
    @ObservationIgnored private var renderedSource: String?
    @ObservationIgnored private let parser: any MarkdownParsing

    init(parser: any MarkdownParsing = MarkdownParser()) {
        self.parser = parser
    }

    /// Shows a newly opened document from the top.
    func load(_ content: Result<String, MarkdownDocumentError>) async {
        state = .loading
        renderedSource = nil
        switch content {
        case .success(let source):
            await render(source)
            if !Task.isCancelled { loadCount += 1 }
        case .failure(let error):
            loadCount += 1
            apply(.failure(error))
        }
    }

    /// Renders an edit of the current document. Keeps showing the previous result until the new
    /// one is ready, and does nothing if the text didn't change.
    func update(_ source: String) async {
        guard source != renderedSource else { return }
        let isFirstRender = renderedSource == nil
        await render(source)
        if isFirstRender, !Task.isCancelled { loadCount += 1 }
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
