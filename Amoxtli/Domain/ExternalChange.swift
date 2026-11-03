import Foundation

/// What to do when the file on disk may have changed since it was read, as when it's edited in
/// another app.
nonisolated enum ExternalChange: Equatable, Sendable {
    /// The file is as it was read.
    case none
    /// It changed and there is nothing unsaved here: show the new version.
    case reload
    /// It changed and there are unsaved changes here: the person decides which one to keep.
    case conflict
    /// It is gone.
    case removed

    static func check(readAt loaded: Date?, onDisk current: Date?, hasUnsavedChanges: Bool) -> ExternalChange {
        guard let loaded else { return .none }
        guard let current else { return .removed }
        guard current != loaded else { return .none }
        return hasUnsavedChanges ? .conflict : .reload
    }
}
