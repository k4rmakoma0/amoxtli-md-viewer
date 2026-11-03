import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Editable document. A reference type, so that the text view's own undo registrations are what
/// mark it as edited, as in any AppKit document app.
///
/// Decoding failures are stored instead of thrown so the window can explain the problem, rather
/// than the system refusing to open the file with a generic alert. Such a document can't be
/// edited, and it refuses to be written so the original bytes are never replaced.
final class MarkdownDocument: ReferenceFileDocument {
    nonisolated static let readableContentTypes: [UTType] = [.markdown]
    nonisolated static let writableContentTypes: [UTType] = [.markdown]

    @Published var text: String
    let loadError: MarkdownDocumentError?

    init(text: String = "") {
        self.text = text
        loadError = nil
    }

    nonisolated init(data: Data?) {
        switch MarkdownDecoder.decode(data) {
        case .success(let text):
            self.text = text
            loadError = nil
        case .failure(let error):
            text = ""
            loadError = error
        }
    }

    nonisolated convenience init(configuration: ReadConfiguration) {
        self.init(data: configuration.file.regularFileContents)
    }

    func snapshot(contentType: UTType) throws -> String {
        guard loadError == nil else { throw CocoaError(.fileWriteNoPermission) }
        return text
    }

    nonisolated func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}

/// Turns the bytes of a Markdown file into text. An empty file is valid: it is a document that
/// hasn't been written yet.
nonisolated enum MarkdownDecoder {
    static func decode(_ data: Data?) -> Result<String, MarkdownDocumentError> {
        guard let data else { return .failure(.unreadable) }
        guard let text = String(data: data, encoding: .utf8) else { return .failure(.invalidEncoding) }
        return .success(removingByteOrderMark(from: text))
    }

    private static func removingByteOrderMark(from text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}
