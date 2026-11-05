import Foundation

/// The formatted editor builds the whole document at once and writes all of its Markdown on
/// every keystroke, so past a size it would freeze the app. Larger documents are read and
/// edited in the source, which only restyles the lines that change.
nonisolated enum FormattedEditingLimit {
    /// In UTF-8 bytes, as the file takes on disk. A document this size opens formatted in about
    /// a second and takes about a third of a second per keystroke; one of 7 MB took ten seconds
    /// to open and two and a half per keystroke.
    static let maximumBytes = 1_000_000

    static func allows(_ text: String) -> Bool {
        text.utf8.count <= maximumBytes
    }
}
