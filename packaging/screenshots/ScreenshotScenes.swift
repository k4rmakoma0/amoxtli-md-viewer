import AppKit
import SwiftUI

/// The App Store scenes. Not part of the app: `make-screenshots.sh` copies this file into the
/// app's sources for one build, runs it with `-ScreenshotScenes YES` and removes it again.
/// Each scene prints `SHOT SCENE <name> <window number>` and waits while the script captures
/// that window.
@MainActor
final class ScreenshotScenes {
    private let sceneDuration: TimeInterval = 9

    private let fieldNotes = """
    # Field Notes

    A small handbook for the team. Everything lives in plain **Markdown** files, so it stays *readable* anywhere, and nobody has to learn the <u>symbols</u>.

    ## Getting started

    Clone the project and run the setup script. See the [Swift documentation](https://www.swift.org/documentation/) if this is your first time.

    ```swift
    let notes = try Notebook(at: folder)
    for page in notes.pages {
        print(page.title)
    }
    ```

    ## Conventions

    - One topic per file
    - Short, descriptive titles
    - Link related pages
      - Use relative names
      - Keep them up to date

    > Write for the person who will read this a year from now.

    ## Project status

    | Area | Owner | Status |
    |:--|:--|--:|
    | Editor | Ana | Done |
    | Search | Luis | In progress |
    | Sync | Mei | Planned |

    ## Next steps

    1. Review the open questions
    2. Publish the first draft
    3. Collect feedback from the team

    ## Resources

    Read the [style guide](https://www.swift.org/documentation/api-design-guidelines/) before you start writing.

    """

    private func need<T>(_ value: T?) -> T {
        guard let value else { print("SHOT missing \(T.self)"); exit(1) }
        return value
    }

    /// Waits without blocking the main actor, so the app's own tasks (parsing the index,
    /// scanning the folder) keep running.
    private func spin(_ seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let found = find(type, in: sub) { return found } }
        return nil
    }

    private func findAll<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { findAll(type, in: $0) }
    }

    private func setMode(_ segment: Int, in window: NSWindow) {
        guard let frame = window.contentView?.superview,
              let picker = findAll(NSSegmentedControl.self, in: frame).first(where: { $0.segmentCount == 3 }) else {
            return print("SHOT no picker")
        }
        picker.selectedSegment = segment
        _ = picker.sendAction(picker.action, to: picker.target)
    }

    private func splitViewController(in controller: NSViewController?) -> NSSplitViewController? {
        guard let controller else { return nil }
        if let split = controller as? NSSplitViewController { return split }
        for child in controller.children { if let found = splitViewController(in: child) { return found } }
        return nil
    }

    /// 1180 × 731 points, centered, active: the composed screenshots expect this size.
    private func place(_ window: NSWindow) {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 1180, height: 731)
        window.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: true)
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.makeKeyAndOrderFront(nil)
    }

    private func announce(_ name: String, _ window: NSWindow) async {
        await spin(1.5)
        if !NSApp.isActive || !window.isKeyWindow { print("SHOT warning \(name) is not the active window") }
        print("SHOT SCENE \(name) \(window.windowNumber)")
        await spin(sceneDuration)
    }

    private func open(_ file: URL) async -> NSDocument? {
        let (document, _) = (try? await NSDocumentController.shared.openDocument(withContentsOf: file, display: true)) ?? (nil, false)
        await spin(1.5)
        return document
    }

    private func writeSample() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Shots-\(UUID().uuidString)/Field Notes", directoryHint: .isDirectory)
        let files: [String: String] = [
            "Field Notes.md": fieldNotes,
            "Changelog.md": "# Changelog\n\n## 2.0\n\n- Edit with formatting\n",
            "Guides/Installation.md": "# Installation\n\nDownload the app and open it.\n",
            "Guides/Style Guide.md": "# Style Guide\n\nKeep it short.\n",
            "Guides/Writing Tips.md": "# Writing Tips\n\nOne idea per paragraph.\n",
            "Meetings/Kickoff.md": "# Kickoff\n\n- Goals\n- Timeline\n",
            "Meetings/Weekly Review.md": "# Weekly Review\n\nWhat went well.\n",
            "Research/Reading List.md": "# Reading List\n\n1. *The Elements of Style*\n",
        ]
        for (path, text) in files {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return folder
    }

    func run() async throws {
        // The typography preferences are shared with the installed app; they go back as they were.
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: Typography.fontKey), defaults.object(forKey: Typography.sizeKey))
        defer {
            defaults.set(saved.0, forKey: Typography.fontKey)
            defaults.set(saved.1, forKey: Typography.sizeKey)
        }
        defaults.set("system", forKey: Typography.fontKey)
        defaults.set(13, forKey: Typography.sizeKey)
        NSApp.appearance = NSAppearance(named: .aqua)
        let folder = try writeSample()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let file = folder.appending(path: "Field Notes.md")

        // 1. Writing with formatting, a word selected.
        let document = need(await open(file))
        let window = need(document.windowControllers.first?.window)
        place(window)
        await spin(1)
        let content = need(window.contentView)
        let rich = need(find(RichTextView.self, in: content))
        window.makeFirstResponder(rich)
        rich.setSelectedRange((rich.string as NSString).range(of: "readable"))
        await announce("1-write", window)

        // 2. Split view, without the sidebar, the caret in the source.
        setMode(2, in: window)
        await spin(1)
        splitViewController(in: window.contentViewController)?.toggleSidebar(nil)
        await spin(1)
        if let source = find(SourceTextView.self, in: content) {
            window.makeFirstResponder(source)
            let range = (source.string as NSString).range(of: "plain **Markdown**")
            source.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
        }
        await announce("2-split", window)
        setMode(1, in: window)
        splitViewController(in: window.contentViewController)?.toggleSidebar(nil)
        document.close()
        await spin(1)

        // 3. A folder, with Field Notes.md chosen in the file list.
        let bookmark = try SecurityScopedBookmarks().makeBookmark(for: folder)
        let host = NSHostingController(rootView: FolderWindowView(bookmark: .constant(bookmark)))
        host.sceneBridgingOptions = .all
        let folderWindow = NSWindow(contentViewController: host)
        folderWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        folderWindow.isReleasedWhenClosed = false
        place(folderWindow)
        await spin(2)
        // Wide enough for the whole file names.
        if let split = findAll(NSSplitView.self, in: need(folderWindow.contentView?.superview)).first {
            split.setPosition(270, ofDividerAt: 0)
        }
        await spin(1)
        // The second row of the file list. A click, as SwiftUI only hears selection changes
        // that come from events.
        let point = NSPoint(x: 91, y: folderWindow.frame.height - 132)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: folderWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                folderWindow.sendEvent(event)
            }
        }
        await spin(2)
        if let folderRich = find(RichTextView.self, in: need(folderWindow.contentView)) {
            folderWindow.makeFirstResponder(folderRich)
            let range = (folderRich.string as NSString).range(of: "Project status")
            folderRich.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
        } else {
            print("SHOT warning no file is open in the folder window")
        }
        await announce("3-folder", folderWindow)
        folderWindow.close()

        // 4. Dark, in serif, from Conventions down, with a link's address showing.
        defaults.set("serif", forKey: Typography.fontKey)
        defaults.set(14, forKey: Typography.sizeKey)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await spin(1)
        let darkDocument = need(await open(file))
        let darkWindow = need(darkDocument.windowControllers.first?.window)
        place(darkWindow)
        await spin(1)
        let darkRich = need(find(RichTextView.self, in: need(darkWindow.contentView)))
        let entries = TOCBuilder.entries(for: (try? MarkdownParser().parse(fieldNotes))?.blocks ?? [])
        if let conventions = entries.first(where: { $0.title == "Conventions" }) {
            darkRich.revealHeading(conventions, among: entries)
        }
        darkWindow.makeFirstResponder(nil)
        darkRich.links?.hover(URL(string: "https://www.swift.org/documentation/api-design-guidelines/"))
        await announce("4-dark", darkWindow)
        darkDocument.close()
        print("SHOT DONE")
    }
}
