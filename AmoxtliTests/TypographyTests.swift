import AppKit
import XCTest
@testable import Amoxtli

final class TextSizeTests: XCTestCase {
    func testStandardIsTheSystemBodySize() {
        XCTAssertEqual(TextSize.standard.points, 13)
        XCTAssertEqual(TextSize.standard.scale, 1)
    }

    func testLargerAndSmallerMoveOneStep() {
        XCTAssertEqual(TextSize.standard.larger?.points, 14)
        XCTAssertEqual(TextSize.standard.smaller?.points, 12)
        XCTAssertEqual(TextSize(points: 16).larger?.points, 18)
    }

    func testLimitsStopTheSteps() {
        XCTAssertNil(TextSize(points: 32).larger)
        XCTAssertNil(TextSize(points: 10).smaller)
    }

    func testStoredValuesSnapToTheClosestStep() {
        XCTAssertEqual(TextSize(rawValue: 17).points, 16)
        XCTAssertEqual(TextSize(rawValue: 500).points, 32)
        XCTAssertEqual(TextSize(rawValue: -3).points, 10)
    }
}

@MainActor
final class TypographyTests: XCTestCase {
    func testBodyUsesTheChosenSize() {
        XCTAssertEqual(Typography(size: TextSize(points: 18)).body.pointSize, 18)
    }

    func testHeadingsScaleWithBodyText() {
        let standard = Typography()
        let larger = Typography(size: TextSize(points: 24))
        XCTAssertEqual(standard.heading(level: 1).pointSize, 26)
        XCTAssertEqual(larger.heading(level: 1).pointSize, 48)
        XCTAssertGreaterThan(standard.heading(level: 2).pointSize, standard.heading(level: 3).pointSize)
    }

    func testHeadingsAreBold() {
        XCTAssertTrue(Typography().heading(level: 4).fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testCodeStaysMonospacedWithAnyTypeface() {
        XCTAssertTrue(Typography(font: .serif).code.isFixedPitch)
    }

    func testMonospacedTypefaceIsFixedPitch() {
        XCTAssertTrue(Typography(font: .monospaced).body.isFixedPitch)
        XCTAssertFalse(Typography(font: .system).body.isFixedPitch)
    }

    func testEachTypefaceGivesADifferentFont() {
        let names = Set(ReadingFont.allCases.map { Typography(font: $0).body.fontName })
        XCTAssertEqual(names.count, ReadingFont.allCases.count)
    }
}
