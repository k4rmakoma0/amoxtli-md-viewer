import UniformTypeIdentifiers
import XCTest
@testable import Amoxtli

final class MarkdownDocumentTests: XCTestCase {
    func testValidUTF8IsDecoded() {
        XCTAssertEqual(MarkdownDecoder.decode(Data("# Título ñ 🌮".utf8)), .success("# Título ñ 🌮"))
    }

    func testByteOrderMarkIsRemoved() {
        XCTAssertEqual(MarkdownDecoder.decode(Data("\u{FEFF}# Título".utf8)), .success("# Título"))
    }

    func testEmptyDataIsAnEmptyDocument() {
        XCTAssertEqual(MarkdownDecoder.decode(Data()), .success(""))
    }

    func testWhitespaceIsKept() {
        XCTAssertEqual(MarkdownDecoder.decode(Data(" \n\t\n".utf8)), .success(" \n\t\n"))
    }

    func testInvalidBytesAreReportedAsInvalidEncoding() {
        XCTAssertEqual(MarkdownDecoder.decode(Data([0x23, 0x20, 0xFF, 0xFE, 0xC0])), .failure(.invalidEncoding))
    }

    func testMissingContentsAreReportedAsUnreadable() {
        XCTAssertEqual(MarkdownDecoder.decode(nil), .failure(.unreadable))
    }

    func testLargeFileIsDecodedCompletely() {
        let line = "Línea de un archivo grande con **texto**.\n"
        let source = String(repeating: line, count: 200_000)
        XCTAssertGreaterThan(source.utf8.count, 8_000_000)
        XCTAssertEqual(MarkdownDecoder.decode(Data(source.utf8)), .success(source))
    }

    @MainActor
    func testDocumentSavesItsText() throws {
        let document = MarkdownDocument(data: Data("# Uno".utf8))
        document.text += "\n\nDos"
        XCTAssertNil(document.loadError)
        XCTAssertEqual(try document.snapshot(contentType: .markdown), "# Uno\n\nDos")
    }

    @MainActor
    func testUndecodableDocumentRefusesToBeWritten() {
        let document = MarkdownDocument(data: Data([0xFF, 0xFE]))
        XCTAssertEqual(document.loadError, .invalidEncoding)
        XCTAssertThrowsError(try document.snapshot(contentType: .markdown))
    }

    @MainActor
    func testNewDocumentStartsEmpty() {
        XCTAssertEqual(MarkdownDocument().text, "")
    }
}
