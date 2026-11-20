import XCTest
@testable import Amoxtli

final class RecentListTests: XCTestCase {
    private func file(_ path: String) -> RecentItem {
        RecentItem(kind: .file, url: URL(fileURLWithPath: path), bookmark: Data(path.utf8))
    }

    func testNewestComesFirst() {
        var list = RecentList()
        list.record(file("/notas/a.md"))
        list.record(file("/notas/b.md"))
        XCTAssertEqual(list.items.map(\.name), ["b.md", "a.md"])
        XCTAssertEqual(list.last?.name, "b.md")
    }

    func testOpeningAgainMovesToTheTopWithoutRepeating() {
        var list = RecentList()
        list.record(file("/notas/a.md"))
        list.record(file("/notas/b.md"))
        list.record(file("/notas/a.md"))
        XCTAssertEqual(list.items.map(\.name), ["a.md", "b.md"])
    }

    func testKeepsTheLastTen() {
        var list = RecentList()
        for index in 1...12 {
            list.record(file("/notas/\(index).md"))
        }
        XCTAssertEqual(list.items.count, RecentList.limit)
        XCTAssertEqual(list.items.first?.name, "12.md")
        XCTAssertEqual(list.items.last?.name, "3.md")
    }

    func testSavedItemsAreTrimmedAndKeepTheirNewestCopy() {
        let items = [file("/a.md"), file("/b.md"), file("/a.md")] + (1...10).map { file("/\($0).md") }
        let list = RecentList(items: items)
        XCTAssertEqual(list.items.count, RecentList.limit)
        XCTAssertEqual(list.items.prefix(2).map(\.name), ["a.md", "b.md"])
    }

    func testSamePlaceWrittenDifferentlyIsOneItem() {
        var list = RecentList()
        list.record(file("/notas/sub/../a.md"))
        list.record(file("/notas/a.md"))
        XCTAssertEqual(list.items.count, 1)
    }

    func testFileAndFolderCanShareTheList() {
        var list = RecentList()
        list.record(file("/notas/a.md"))
        list.record(RecentItem(kind: .folder, url: URL(fileURLWithPath: "/notas"), bookmark: Data()))
        XCTAssertEqual(list.items.map(\.kind), [.folder, .file])
    }

    func testRemoveAndRemoveAll() {
        var list = RecentList(items: [file("/a.md"), file("/b.md")])
        list.remove(file("/a.md"))
        XCTAssertEqual(list.items.map(\.name), ["b.md"])
        list.removeAll()
        XCTAssertTrue(list.items.isEmpty)
        XCTAssertNil(list.last)
    }

    func testRepeatedNamesShowTheirFolder() {
        let list = RecentList(items: [file("/proyectos/amoxtli/README.md"), file("/proyectos/web/readme.md"), file("/notas/a.md")])
        XCTAssertEqual(list.title(for: list.items[0]), "README.md — amoxtli")
        XCTAssertEqual(list.title(for: list.items[1]), "readme.md — web")
        XCTAssertEqual(list.title(for: list.items[2]), "a.md")
    }

    func testTrashIsRecognized() {
        XCTAssertTrue(TrashLocation.contains(URL(fileURLWithPath: "/Users/ana/.Trash/a.md")))
        XCTAssertTrue(TrashLocation.contains(URL(fileURLWithPath: "/Volumes/USB/.Trashes/501/a.md")))
        XCTAssertFalse(TrashLocation.contains(URL(fileURLWithPath: "/Users/ana/Trash/a.md")))
        XCTAssertFalse(TrashLocation.contains(URL(fileURLWithPath: "/Users/ana/notas/a.md")))
    }

    func testLaunchPlanBringsBackWhatStillExists() {
        let item = file("/notas/a.md")
        let moved = URL(fileURLWithPath: "/otras/a.md")
        XCTAssertEqual(LaunchPlan(last: item, location: .available(moved, bookmark: Data())), .file(moved))
        XCTAssertEqual(LaunchPlan(last: item, location: .missing), .welcome)

        let folder = RecentItem(kind: .folder, url: URL(fileURLWithPath: "/notas"), bookmark: Data("viejo".utf8))
        let refreshed = Data("nuevo".utf8)
        XCTAssertEqual(LaunchPlan(last: folder, location: .available(folder.url, bookmark: refreshed)), .folder(bookmark: refreshed))
        XCTAssertEqual(LaunchPlan(last: folder, location: .missing), .welcome)
    }
}

/// Stands in for the bookmarks, so tests decide where each item is.
final class FakeRecentItemLocator: RecentItemLocating, @unchecked Sendable {
    var locations: [URL: RecentItemLocation] = [:]
    var canBookmark = true

    func bookmark(for url: URL) -> Data? {
        canBookmark ? Data(url.path.utf8) : nil
    }

    func locate(_ item: RecentItem) -> RecentItemLocation {
        locations[item.url] ?? .available(item.url, bookmark: item.bookmark)
    }
}

@MainActor
final class RecentItemsModelTests: XCTestCase {
    private var defaults = UserDefaults()
    private var suiteName = ""
    private let locator = FakeRecentItemLocator()
    private var systemClears = 0

    override func setUp() async throws {
        suiteName = "RecentItemsModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeModel() -> RecentItemsModel {
        RecentItemsModel(store: RecentItemsStore(defaults: defaults), locator: locator) { [weak self] in
            self?.systemClears += 1
        }
    }

    private let note = URL(fileURLWithPath: "/notas/a.md")
    private let folder = URL(fileURLWithPath: "/notas")

    func testRecordsFilesAndFoldersNewestFirst() {
        let model = makeModel()
        model.recordFile(at: note)
        model.recordFolder(at: folder, bookmark: Data("carpeta".utf8))
        XCTAssertEqual(model.items.map(\.kind), [.folder, .file])
        XCTAssertEqual(model.items.last?.bookmark, Data(note.path.utf8))
    }

    func testFileThatCannotBeBookmarkedIsNotRemembered() {
        locator.canBookmark = false
        let model = makeModel()
        model.recordFile(at: note)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testListSurvivesARelaunch() {
        makeModel().recordFile(at: note)
        XCTAssertEqual(makeModel().items.map(\.url), [note])
    }

    func testUnreadableSavedListStartsEmpty() {
        defaults.set(Data("no es JSON".utf8), forKey: "recentItems")
        XCTAssertTrue(makeModel().items.isEmpty)
    }

    func testMovedItemIsRememberedWhereItIsNow() throws {
        let model = makeModel()
        model.recordFile(at: note)
        model.recordFile(at: URL(fileURLWithPath: "/notas/b.md"))
        let moved = URL(fileURLWithPath: "/archivo/a.md")
        locator.locations[note] = .available(moved, bookmark: Data("nuevo".utf8))

        let item = try XCTUnwrap(model.items.last)
        XCTAssertEqual(model.locate(item), .available(moved, bookmark: Data("nuevo".utf8)))
        XCTAssertEqual(model.items.map(\.url), [moved, URL(fileURLWithPath: "/notas/b.md")])
        XCTAssertEqual(model.items.first?.bookmark, Data("nuevo".utf8))
    }

    func testMissingItemStaysUntilRemoved() throws {
        let model = makeModel()
        model.recordFile(at: note)
        locator.locations[note] = .missing
        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(model.locate(item), .missing)
        XCTAssertEqual(model.items.count, 1)

        model.remove(item)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(makeModel().items.isEmpty)
    }

    func testClearForgetsEverythingAndTheSystemList() {
        let model = makeModel()
        model.recordFile(at: note)
        model.recordFolder(at: folder, bookmark: Data())
        model.clear()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(makeModel().items.isEmpty)
        XCTAssertEqual(systemClears, 1)
    }
}

@MainActor
final class LaunchReopeningTests: XCTestCase {
    private var defaults = UserDefaults()
    private var suiteName = ""
    private let locator = FakeRecentItemLocator()
    private let note = URL(fileURLWithPath: "/notas/a.md")
    private let folderBookmark = Data("carpeta".utf8)

    override func setUp() async throws {
        suiteName = "LaunchReopeningTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeRecents() -> RecentItemsModel {
        RecentItemsModel(store: RecentItemsStore(defaults: defaults), locator: locator, clearSystemRecents: {})
    }

    private func launch(_ recents: RecentItemsModel, isEnabled: Bool = true) -> LaunchReopening {
        LaunchReopening(recents: recents, preferences: LaunchPreferences(defaults: defaults), isEnabled: isEnabled)
    }

    func testReopeningIsOnUntilTurnedOff() {
        XCTAssertTrue(LaunchPreferences(defaults: defaults).reopensLastItem)
        defaults.set(false, forKey: LaunchPreferences.reopensLastItemKey)
        XCTAssertFalse(LaunchPreferences(defaults: defaults).reopensLastItem)
    }

    func testNothingRecentShowsTheWelcomeWindow() {
        let launch = launch(makeRecents())
        XCTAssertEqual(launch.plan, .welcome)
        XCTAssertTrue(launch.presentsWelcome)
        XCTAssertFalse(launch.presentsFolderWindow)
        XCTAssertNil(launch.takeFile())
    }

    func testTurnedOffShowsTheWelcomeWindow() {
        let recents = makeRecents()
        recents.recordFile(at: note)
        defaults.set(false, forKey: LaunchPreferences.reopensLastItemKey)
        XCTAssertEqual(launch(recents).plan, .welcome)
    }

    func testTestsNeverReopen() {
        let recents = makeRecents()
        recents.recordFile(at: note)
        XCTAssertEqual(launch(recents, isEnabled: false).plan, .welcome)
    }

    func testLastFileComesBackOnceInsteadOfTheWelcomeWindow() {
        let recents = makeRecents()
        recents.recordFile(at: note)
        let launch = launch(recents)
        XCTAssertEqual(launch.plan, .file(note))
        XCTAssertFalse(launch.presentsWelcome)
        XCTAssertFalse(launch.presentsFolderWindow)

        XCTAssertEqual(launch.takeFile(), note)
        XCTAssertNil(launch.takeFile())
        XCTAssertFalse(launch.presentsWelcome, "The welcome window stays away while the file loads")

        launch.finishReopeningFile()
        XCTAssertTrue(launch.presentsWelcome)
    }

    func testLastFolderComesBackOnceInItsWindow() {
        let recents = makeRecents()
        recents.recordFolder(at: URL(fileURLWithPath: "/notas"), bookmark: folderBookmark)
        let launch = launch(recents)
        XCTAssertTrue(launch.presentsFolderWindow)
        XCTAssertFalse(launch.presentsWelcome)
        XCTAssertNil(launch.takeFile())

        XCTAssertEqual(launch.takeFolder(), folderBookmark)
        XCTAssertNil(launch.takeFolder())
        XCTAssertFalse(launch.presentsFolderWindow)
        XCTAssertTrue(launch.presentsWelcome)
    }

    func testMissingLastItemShowsTheWelcomeWindowAndLeavesTheList() {
        let recents = makeRecents()
        recents.recordFile(at: URL(fileURLWithPath: "/notas/b.md"))
        recents.recordFile(at: note)
        locator.locations[note] = .missing

        let launch = launch(recents)
        XCTAssertEqual(launch.plan, .welcome)
        XCTAssertTrue(launch.presentsWelcome)
        XCTAssertEqual(recents.items.map(\.name), ["b.md"])
    }

    func testLaunchThatOpensSomethingElseGivesUpTheFolder() {
        let recents = makeRecents()
        recents.recordFolder(at: URL(fileURLWithPath: "/notas"), bookmark: folderBookmark)
        let launch = launch(recents)
        launch.finishLaunching(isDefault: false)
        XCTAssertTrue(launch.presentsWelcome)
        XCTAssertFalse(launch.presentsFolderWindow)
        XCTAssertNil(launch.takeFolder())
    }

    func testPlainLaunchKeepsTheFolderForItsWindow() {
        let recents = makeRecents()
        recents.recordFolder(at: URL(fileURLWithPath: "/notas"), bookmark: folderBookmark)
        let launch = launch(recents)
        launch.finishLaunching(isDefault: true)
        XCTAssertEqual(launch.takeFolder(), folderBookmark)
    }
}

/// Uses real security-scoped bookmarks, which the sandbox lets the hosted app make for files in
/// its own container.
final class RecentItemLocatorTests: XCTestCase {
    private let locator = RecentItemLocator()

    private func item(_ kind: RecentItem.Kind, at url: URL) throws -> RecentItem {
        RecentItem(kind: kind, url: url, bookmark: try XCTUnwrap(locator.bookmark(for: url)))
    }

    func testExistingFileIsAvailable() throws {
        let file = try makeTemporaryFolder().addFile("nota.md")
        guard case .available(let url, _) = locator.locate(try item(.file, at: file)) else {
            return XCTFail("Se esperaba available")
        }
        XCTAssertEqual(url.standardizedFileURL.resolvingSymlinksInPath(), file.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testMovedFileIsFoundWhereItIsNow() throws {
        let folder = try makeTemporaryFolder()
        let file = try folder.addFile("nota.md")
        let recent = try item(.file, at: file)
        let moved = folder.url.appending(path: "movida.md")
        try FileManager.default.moveItem(at: file, to: moved)
        guard case .available(let url, _) = locator.locate(recent) else {
            return XCTFail("Se esperaba available")
        }
        XCTAssertEqual(url.lastPathComponent, "movida.md")
    }

    func testDeletedFileIsMissing() throws {
        let file = try makeTemporaryFolder().addFile("nota.md")
        let recent = try item(.file, at: file)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(locator.locate(recent), .missing)
    }

    func testExistingFolderIsAvailable() throws {
        let folder = try makeTemporaryFolder()
        guard case .available = locator.locate(try item(.folder, at: folder.url)) else {
            return XCTFail("Se esperaba available")
        }
    }

    func testSomethingOfAnotherKindIsMissing() throws {
        let folder = try makeTemporaryFolder()
        XCTAssertEqual(locator.locate(try item(.file, at: folder.url)), .missing)
    }

    func testItemInTheTrashIsMissing() {
        struct TrashedBookmarks: FolderBookmarking {
            func makeBookmark(for folder: URL) throws(FolderError) -> Data { Data() }
            func resolve(_ bookmark: Data) throws(FolderError) -> ResolvedFolder {
                ResolvedFolder(url: URL(fileURLWithPath: "/Users/ana/.Trash/nota.md"), refreshedBookmark: nil)
            }
        }
        let recent = RecentItem(kind: .file, url: URL(fileURLWithPath: "/Users/ana/nota.md"), bookmark: Data())
        XCTAssertEqual(RecentItemLocator(bookmarks: TrashedBookmarks()).locate(recent), .missing)
    }

    func testBookmarkThatCannotResolveIsMissing() {
        let recent = RecentItem(kind: .file, url: URL(fileURLWithPath: "/notas/a.md"), bookmark: Data("basura".utf8))
        XCTAssertEqual(locator.locate(recent), .missing)
    }
}
