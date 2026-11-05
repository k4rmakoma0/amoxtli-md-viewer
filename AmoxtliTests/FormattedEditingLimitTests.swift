import XCTest
@testable import Amoxtli

final class FormattedEditingLimitTests: XCTestCase {
    func testAllowsUpToTheLimit() {
        XCTAssertTrue(FormattedEditingLimit.allows(""))
        XCTAssertTrue(FormattedEditingLimit.allows(String(repeating: "a", count: FormattedEditingLimit.maximumBytes)))
        XCTAssertFalse(FormattedEditingLimit.allows(String(repeating: "a", count: FormattedEditingLimit.maximumBytes + 1)))
    }

    /// The limit is the size of the file, so a character written with several bytes counts each.
    func testCountsBytesAsTheFileDoes() {
        let half = FormattedEditingLimit.maximumBytes / 2
        XCTAssertTrue(FormattedEditingLimit.allows(String(repeating: "ñ", count: half)))
        XCTAssertFalse(FormattedEditingLimit.allows(String(repeating: "ñ", count: half + 1)))
    }
}
