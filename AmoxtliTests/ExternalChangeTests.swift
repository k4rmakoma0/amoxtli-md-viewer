import XCTest
@testable import Amoxtli

final class ExternalChangeTests: XCTestCase {
    private let read = Date(timeIntervalSince1970: 100)
    private let later = Date(timeIntervalSince1970: 200)

    func testSameDateIsNoChange() {
        XCTAssertEqual(ExternalChange.check(readAt: read, onDisk: read, hasUnsavedChanges: true), .none)
    }

    func testNewerFileReloadsWhenNothingIsUnsaved() {
        XCTAssertEqual(ExternalChange.check(readAt: read, onDisk: later, hasUnsavedChanges: false), .reload)
    }

    func testNewerFileWithUnsavedChangesIsAConflict() {
        XCTAssertEqual(ExternalChange.check(readAt: read, onDisk: later, hasUnsavedChanges: true), .conflict)
    }

    func testMissingFileIsRemoved() {
        XCTAssertEqual(ExternalChange.check(readAt: read, onDisk: nil, hasUnsavedChanges: false), .removed)
    }

    func testNeverReadIsNoChange() {
        XCTAssertEqual(ExternalChange.check(readAt: nil, onDisk: later, hasUnsavedChanges: false), .none)
    }

    func testRealFileDatesFollowWrites() throws {
        let file = try makeTemporaryFolder().addFile("nota.md")
        let dates = FileSystemDates()
        let before = try XCTUnwrap(dates.modificationDate(of: file))
        Thread.sleep(forTimeInterval: 0.05)
        try Data("# Otro".utf8).write(to: file)
        XCTAssertNotEqual(dates.modificationDate(of: file), before)
        XCTAssertNil(dates.modificationDate(of: file.deletingLastPathComponent().appending(path: "no-existe.md")))
    }
}
