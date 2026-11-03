import AppKit

/// Shows the new version of open documents whose files changed in another app, as long as they
/// have nothing unsaved. Documents with unsaved changes are left alone: `NSDocument` itself asks
/// before saving over a file that changed.
///
/// AppKit is required here: `DocumentGroup` has no API to reload a document from disk.
struct ExternalDocumentChanges {
    private let dates: any FileDating

    init(dates: any FileDating = FileSystemDates()) {
        self.dates = dates
    }

    func reloadChanged(_ documents: [NSDocument]) {
        for document in documents {
            guard let file = document.fileURL, let type = document.fileType else { continue }
            let change = ExternalChange.check(
                readAt: document.fileModificationDate,
                onDisk: dates.modificationDate(of: file),
                hasUnsavedChanges: document.isDocumentEdited
            )
            if change == .reload {
                try? document.revert(toContentsOf: file, ofType: type)
            }
        }
    }
}
