import Foundation
import Observation

/// The file being edited in a folder window. There is no `NSDocument` behind it, so it saves on
/// its own: a moment after the last edit, before switching files and when the window goes away.
@Observable
final class FolderFileEditor {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(MarkdownDocumentError)
    }

    private(set) var state: State = .idle
    private(set) var file: URL?
    /// Set when a save fails, until the next one succeeds or the person dismisses it.
    var saveFailure: URL?

    var text = "" {
        didSet {
            if state == .loaded, text != oldValue { scheduleAutosave() }
        }
    }

    @ObservationIgnored private(set) var hasUnsavedChanges = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private let files: any MarkdownFileAccessing
    @ObservationIgnored private let autosaveDelay: Duration

    init(files: any MarkdownFileAccessing = MarkdownFiles(), autosaveDelay: Duration = .seconds(1)) {
        self.files = files
        self.autosaveDelay = autosaveDelay
    }

    /// Saves the current file, then reads the new one. `nil` leaves nothing open.
    func open(_ file: URL?) async {
        save()
        self.file = file
        guard let file else {
            state = .idle
            return
        }
        state = .loading
        let result = await Self.read(file, with: files)
        guard !Task.isCancelled, self.file == file else { return }
        switch result {
        case .success(let text):
            // Assigned before the state changes, so loading doesn't count as an edit.
            self.text = text
            state = .loaded
        case .failure(let error):
            text = ""
            state = .failed(error)
        }
    }

    /// Writes pending changes right away. Files that failed to load are never written.
    func save() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard hasUnsavedChanges, state == .loaded, let file else { return }
        do {
            try files.write(text, to: file)
            hasUnsavedChanges = false
            saveFailure = nil
        } catch {
            saveFailure = file
        }
    }

    private func scheduleAutosave() {
        hasUnsavedChanges = true
        autosaveTask?.cancel()
        autosaveTask = Task { [autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    @concurrent
    private static func read(_ file: URL, with files: any MarkdownFileAccessing) async -> Result<String, MarkdownDocumentError> {
        files.read(file)
    }
}
