import XCTest
@testable import Amoxtli

@MainActor
final class FolderFileEditorTests: XCTestCase {
    /// Files in memory, counting writes.
    private final class FakeFiles: MarkdownFileAccessing, @unchecked Sendable {
        private let lock = NSLock()
        private var contents: [URL: Result<String, MarkdownDocumentError>]
        private var dates: [URL: Date] = [:]
        private var writtenFiles: [URL] = []
        var failsToWrite = false

        init(_ contents: [URL: Result<String, MarkdownDocumentError>]) {
            self.contents = contents
        }

        var writes: [URL] { lock.withLock { writtenFiles } }

        func text(of file: URL) -> String? {
            lock.withLock { try? contents[file]?.get() }
        }

        func read(_ file: URL) -> Result<String, MarkdownDocumentError> {
            lock.withLock { contents[file] ?? .failure(.unreadable) }
        }

        func modificationDate(of file: URL) -> Date? {
            lock.withLock { contents[file] == nil ? nil : dates[file, default: .distantPast] }
        }

        func write(_ text: String, to file: URL) throws {
            try lock.withLock {
                if failsToWrite { throw CocoaError(.fileWriteNoPermission) }
                contents[file] = .success(text)
                dates[file] = Date()
                writtenFiles.append(file)
            }
        }

        /// Another app writing the file.
        func changeOnDisk(_ file: URL, to text: String?) {
            lock.withLock {
                contents[file] = text.map { .success($0) }
                dates[file] = Date()
            }
        }
    }

    private let first = URL(filePath: "/carpeta/uno.md")
    private let second = URL(filePath: "/carpeta/dos.md")
    private let broken = URL(filePath: "/carpeta/roto.md")

    private func makeFiles() -> FakeFiles {
        FakeFiles([first: .success("# Uno"), second: .success("# Dos"), broken: .failure(.invalidEncoding)])
    }

    func testOpeningReadsTheFile() async {
        let editor = FolderFileEditor(files: makeFiles())
        await editor.open(first)
        XCTAssertEqual(editor.state, .loaded)
        XCTAssertEqual(editor.text, "# Uno")
    }

    func testLoadingIsNotAnEdit() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files)
        await editor.open(first)
        editor.save()
        XCTAssertEqual(files.writes, [])
    }

    func testSaveWritesEdits() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files)
        await editor.open(first)
        editor.text = "# Uno editado"
        editor.save()
        XCTAssertEqual(files.text(of: first), "# Uno editado")
        XCTAssertFalse(editor.hasUnsavedChanges)
    }

    func testEditsAreSavedAfterAPause() async throws {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files, autosaveDelay: .milliseconds(10))
        await editor.open(first)
        editor.text = "# Autoguardado"
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(files.text(of: first), "# Autoguardado")
    }

    func testSwitchingFilesSavesThePreviousOne() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files, autosaveDelay: .seconds(60))
        await editor.open(first)
        editor.text = "# Cambiado"
        await editor.open(second)
        XCTAssertEqual(files.text(of: first), "# Cambiado")
        XCTAssertEqual(editor.text, "# Dos")
    }

    func testUndecodableFileIsNeverWritten() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files)
        await editor.open(broken)
        editor.text = "texto"
        editor.save()
        XCTAssertEqual(editor.state, .failed(.invalidEncoding))
        XCTAssertEqual(files.writes, [])
    }

    func testFailedSaveIsReported() async {
        let files = makeFiles()
        files.failsToWrite = true
        let editor = FolderFileEditor(files: files)
        await editor.open(first)
        editor.text = "texto"
        editor.save()
        XCTAssertEqual(editor.saveFailure, first)
        XCTAssertTrue(editor.hasUnsavedChanges)
    }

    func testOpeningNothingIsIdle() async {
        let editor = FolderFileEditor(files: makeFiles())
        await editor.open(first)
        await editor.open(nil)
        XCTAssertEqual(editor.state, .idle)
    }

    func testRealFilesRoundTrip() async throws {
        let file = try makeTemporaryFolder().addFile("nota.md", contents: Data("# Uno".utf8))
        let editor = FolderFileEditor()
        await editor.open(file)
        editor.text = "# Uno ñ 🌮"
        editor.save()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Uno ñ 🌮")
    }

    // MARK: - Changes made elsewhere

    func testFileChangedElsewhereIsShownWhenNothingIsUnsaved() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files)
        await editor.open(first)
        files.changeOnDisk(first, to: "# Uno desde otra app")
        editor.checkForExternalChanges()
        XCTAssertEqual(editor.text, "# Uno desde otra app")
        XCTAssertFalse(editor.hasUnsavedChanges)
        XCTAssertNil(editor.conflict)
    }

    func testFileChangedElsewhereWithUnsavedChangesAsks() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files, autosaveDelay: .seconds(60))
        await editor.open(first)
        editor.text = "# Mío"
        files.changeOnDisk(first, to: "# Suyo")
        editor.checkForExternalChanges()
        XCTAssertEqual(editor.conflict, first)
        XCTAssertEqual(editor.text, "# Mío")
    }

    func testSaveNeverWritesOverAFileChangedElsewhere() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files, autosaveDelay: .seconds(60))
        await editor.open(first)
        editor.text = "# Mío"
        files.changeOnDisk(first, to: "# Suyo")
        editor.save()
        XCTAssertEqual(files.text(of: first), "# Suyo")
        XCTAssertEqual(editor.conflict, first)
    }

    func testKeepingMineWritesIt() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files, autosaveDelay: .seconds(60))
        await editor.open(first)
        editor.text = "# Mío"
        files.changeOnDisk(first, to: "# Suyo")
        editor.save()
        editor.resolveConflict(keepingMine: true)
        XCTAssertEqual(files.text(of: first), "# Mío")
        XCTAssertNil(editor.conflict)
    }

    func testUsingTheDiskVersionShowsIt() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files, autosaveDelay: .seconds(60))
        await editor.open(first)
        editor.text = "# Mío"
        files.changeOnDisk(first, to: "# Suyo")
        editor.save()
        editor.resolveConflict(keepingMine: false)
        XCTAssertEqual(editor.text, "# Suyo")
        XCTAssertFalse(editor.hasUnsavedChanges)
    }

    func testRemovedFileWithUnsavedChangesAsks() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files, autosaveDelay: .seconds(60))
        await editor.open(first)
        editor.text = "# Mío"
        files.changeOnDisk(first, to: nil)
        editor.checkForExternalChanges()
        XCTAssertEqual(editor.conflict, first)
    }

    func testOwnSavesAreNotChangesElsewhere() async {
        let files = makeFiles()
        let editor = FolderFileEditor(files: files)
        await editor.open(first)
        editor.text = "# Mío"
        editor.save()
        editor.checkForExternalChanges()
        XCTAssertNil(editor.conflict)
        XCTAssertEqual(editor.text, "# Mío")
    }
}
