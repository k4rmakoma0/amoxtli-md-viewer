import Foundation
import Observation

/// The file being edited in a folder window. There is no `NSDocument` behind it, so it saves on
/// its own: a moment after the last edit, before switching files and when the window goes away.
/// It never writes over a version of the file that changed elsewhere since it was read.
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
    /// Set when the file changed elsewhere while there were unsaved changes here.
    private(set) var conflict: URL?

    var text = "" {
        didSet {
            if state == .loaded, !isReading, text != oldValue { scheduleAutosave() }
        }
    }

    @ObservationIgnored private(set) var hasUnsavedChanges = false
    @ObservationIgnored private var readAt: Date?
    /// Set while text read from disk is assigned, so it doesn't count as an edit.
    @ObservationIgnored private var isReading = false
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
        conflict = nil
        self.file = file
        guard let file else {
            state = .idle
            return
        }
        state = .loading
        let result = await Self.read(file, with: files)
        guard !Task.isCancelled, self.file == file else { return }
        show(result)
    }

    private func show(_ result: (content: Result<String, MarkdownDocumentError>, date: Date?)) {
        readAt = result.date
        hasUnsavedChanges = false
        switch result.content {
        case .success(let text):
            isReading = true
            self.text = text
            isReading = false
            state = .loaded
        case .failure(let error):
            text = ""
            state = .failed(error)
        }
    }

    /// Writes pending changes right away. Files that failed to load are never written, and a
    /// file that changed elsewhere isn't written over: the person is asked first.
    func save() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard hasUnsavedChanges, state == .loaded, let file, conflict == nil else { return }
        switch ExternalChange.check(readAt: readAt, onDisk: files.modificationDate(of: file), hasUnsavedChanges: true) {
        case .conflict, .removed:
            conflict = file
        case .none, .reload:
            write(to: file)
        }
    }

    /// Looks at the file again, as when the app comes back to the front: a new version is shown
    /// if nothing here is unsaved, and the person is asked otherwise.
    func checkForExternalChanges() {
        guard state == .loaded, let file, conflict == nil else { return }
        let date = files.modificationDate(of: file)
        switch ExternalChange.check(readAt: readAt, onDisk: date, hasUnsavedChanges: hasUnsavedChanges) {
        case .none:
            break
        case .reload:
            show((files.read(file), date))
        case .conflict, .removed:
            autosaveTask?.cancel()
            conflict = file
        }
    }

    /// Settles a conflict by writing the version here or by showing the one on disk.
    func resolveConflict(keepingMine: Bool) {
        guard let file = conflict else { return }
        conflict = nil
        if keepingMine {
            write(to: file)
        } else {
            show((files.read(file), files.modificationDate(of: file)))
        }
    }

    private func write(to file: URL) {
        do {
            try files.write(text, to: file)
            hasUnsavedChanges = false
            readAt = files.modificationDate(of: file)
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
    private static func read(_ file: URL, with files: any MarkdownFileAccessing) async -> (content: Result<String, MarkdownDocumentError>, date: Date?) {
        (files.read(file), files.modificationDate(of: file))
    }
}
