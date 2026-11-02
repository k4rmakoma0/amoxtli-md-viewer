import XCTest
@testable import Amoxtli

final class ReadingStatsTests: XCTestCase {
    private func stats(_ source: String) throws -> ReadingStats {
        ReadingStats(blocks: try MarkdownParser().parse(source).blocks)
    }

    func testCountsHeadingsParagraphsListsQuotesAndTables() throws {
        let source = """
        # Dos palabras

        Un párrafo con **cinco** palabras.

        - uno
          - dos tres

        > cita citada

        | a | b |
        |---|---|
        | c | d |
        """
        XCTAssertEqual(try stats(source).wordCount, 2 + 5 + 3 + 2 + 4)
    }

    func testLeavesOutCodeImagesAndBreaks() throws {
        let source = "```swift\nlet a = 1\n```\n\n![alt](https://example.com/a.png)\n\n---"
        XCTAssertEqual(try stats(source).wordCount, 0)
    }

    func testPunctuationIsNotAWord() throws {
        XCTAssertEqual(try stats("Hola, mundo — ¡ya!").wordCount, 3)
    }

    func testCountsLanguagesWithoutSpaces() throws {
        XCTAssertGreaterThan(try stats("今日は良い天気です").wordCount, 1)
    }

    func testEmptyDocumentHasNoWords() {
        XCTAssertEqual(ReadingStats(blocks: []).wordCount, 0)
    }

    func testUnderAMinuteHasNoMinutes() {
        XCTAssertNil(ReadingStats(wordCount: 0).readingMinutes)
        XCTAssertNil(ReadingStats(wordCount: ReadingStats.wordsPerMinute - 1).readingMinutes)
    }

    func testMinutesAreRounded() {
        XCTAssertEqual(ReadingStats(wordCount: ReadingStats.wordsPerMinute).readingMinutes, 1)
        XCTAssertEqual(ReadingStats(wordCount: 290).readingMinutes, 1)
        XCTAssertEqual(ReadingStats(wordCount: 300).readingMinutes, 2)
        XCTAssertEqual(ReadingStats(wordCount: 2_000).readingMinutes, 10)
    }
}
