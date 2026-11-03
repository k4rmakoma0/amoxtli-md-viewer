import Foundation

nonisolated protocol FileDating: Sendable {
    /// `nil` when the file doesn't exist or can't be reached.
    func modificationDate(of file: URL) -> Date?
}

nonisolated protocol MarkdownFileAccessing: FileDating {
    func read(_ file: URL) -> Result<String, MarkdownDocumentError>
    func write(_ text: String, to file: URL) throws
}

nonisolated struct FileSystemDates: FileDating {
    func modificationDate(of file: URL) -> Date? {
        // The same value `NSDocument` keeps, read fresh: URLs cache resource values.
        var fresh = file
        fresh.removeAllCachedResourceValues()
        return try? fresh.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

/// Reads and writes the files of an opened folder, which live outside `DocumentGroup`.
nonisolated struct MarkdownFiles: MarkdownFileAccessing {
    func read(_ file: URL) -> Result<String, MarkdownDocumentError> {
        MarkdownDecoder.decode(try? Data(contentsOf: file))
    }

    func modificationDate(of file: URL) -> Date? {
        FileSystemDates().modificationDate(of: file)
    }

    /// Atomic, so a failed write never leaves half a file behind.
    func write(_ text: String, to file: URL) throws {
        try Data(text.utf8).write(to: file, options: .atomic)
    }
}
