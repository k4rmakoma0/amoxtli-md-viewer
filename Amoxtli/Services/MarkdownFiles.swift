import Foundation

nonisolated protocol MarkdownFileAccessing: Sendable {
    func read(_ file: URL) -> Result<String, MarkdownDocumentError>
    func write(_ text: String, to file: URL) throws
}

/// Reads and writes the files of an opened folder, which live outside `DocumentGroup`.
nonisolated struct MarkdownFiles: MarkdownFileAccessing {
    func read(_ file: URL) -> Result<String, MarkdownDocumentError> {
        MarkdownDecoder.decode(try? Data(contentsOf: file))
    }

    /// Atomic, so a failed write never leaves half a file behind.
    func write(_ text: String, to file: URL) throws {
        try Data(text.utf8).write(to: file, options: .atomic)
    }
}
