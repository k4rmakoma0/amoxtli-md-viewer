import XCTest
@testable import Amoxtli

final class CodeHighlighterTests: XCTestCase {
    private struct Token: Equatable, CustomStringConvertible {
        let text: String
        let kind: CodeTokenKind
        var description: String { "\(kind):\(text)" }
    }

    private func tokens(_ code: String, _ language: CodeLanguage) -> [Token] {
        CodeHighlighter.tokens(in: code, language: language).map {
            Token(text: (code as NSString).substring(with: $0.range), kind: $0.kind)
        }
    }

    private func texts(_ code: String, _ language: CodeLanguage, _ kind: CodeTokenKind) -> [String] {
        tokens(code, language).filter { $0.kind == kind }.map(\.text)
    }

    // MARK: - Languages

    func testFenceNamesAndAliases() {
        XCTAssertEqual(CodeLanguage(fenceInfo: "swift"), .swift)
        XCTAssertEqual(CodeLanguage(fenceInfo: "JS"), .javascript)
        XCTAssertEqual(CodeLanguage(fenceInfo: "ts"), .typescript)
        XCTAssertEqual(CodeLanguage(fenceInfo: "py title=\"a.py\""), .python)
        XCTAssertEqual(CodeLanguage(fenceInfo: "bash"), .shell)
        XCTAssertEqual(CodeLanguage(fenceInfo: "zsh"), .shell)
        XCTAssertEqual(CodeLanguage(fenceInfo: "xml"), .html)
        XCTAssertEqual(CodeLanguage(fenceInfo: "json{1,3}"), .json)
        XCTAssertNil(CodeLanguage(fenceInfo: ""))
        XCTAssertNil(CodeLanguage(fenceInfo: "cobol"))
    }

    func testEveryLanguageReadsBackFromItsFenceName() {
        for language in CodeLanguage.allCases {
            XCTAssertEqual(CodeLanguage(fenceInfo: language.fenceName), language)
        }
    }

    // MARK: - Swift

    func testSwiftKeywordsTypesStringsAndNumbers() {
        let code = #"let name: String = "Ana" + 42"#
        XCTAssertEqual(tokens(code, .swift), [
            Token(text: "let", kind: .keyword),
            Token(text: "String", kind: .type),
            Token(text: "\"Ana\"", kind: .string),
            Token(text: "42", kind: .number),
        ])
    }

    func testSwiftAttributesAndDirectives() {
        XCTAssertEqual(texts("@MainActor final class A {}\n#if DEBUG", .swift, .keyword), ["@MainActor", "final", "class", "#if"])
    }

    func testSwiftComments() {
        let code = "let a = 1 // let b\n/* var\n c */ var d"
        XCTAssertEqual(texts(code, .swift, .comment), ["// let b", "/* var\n c */"])
        XCTAssertEqual(texts(code, .swift, .keyword), ["let", "var"])
    }

    func testMultilineString() {
        let code = "let s = \"\"\"\nlet \"x\"\n\"\"\"\nlet t"
        XCTAssertEqual(texts(code, .swift, .string), ["\"\"\"\nlet \"x\"\n\"\"\""])
        XCTAssertEqual(texts(code, .swift, .keyword), ["let", "let"])
    }

    func testEscapedQuoteStaysInTheString() {
        XCTAssertEqual(texts(#"print("a \" b") // c"#, .swift, .string), [#""a \" b""#])
    }

    func testUnclosedStringEndsAtTheLine() {
        let code = "let a = \"abierta\nlet b"
        XCTAssertEqual(texts(code, .swift, .string), ["\"abierta"])
        XCTAssertEqual(texts(code, .swift, .keyword), ["let", "let"])
    }

    func testWordsContainingKeywordsAreNotKeywords() {
        XCTAssertEqual(texts("letter format1 x2", .swift, .keyword), [])
        XCTAssertEqual(texts("letter format1 x2", .swift, .number), [])
    }

    func testNumbers() {
        XCTAssertEqual(texts("a = 3.14 + 0xFF + 1_000 + 1e-3", .swift, .number), ["3.14", "0xFF", "1_000", "1e-3"])
    }

    // MARK: - Other languages

    func testPython() {
        let code = "@cache\ndef f(x: int) -> None:\n    return f\"{x}\"  # fin"
        XCTAssertEqual(texts(code, .python, .attribute), ["@cache"])
        XCTAssertEqual(texts(code, .python, .keyword), ["def", "None", "return"])
        XCTAssertEqual(texts(code, .python, .type), ["int"])
        XCTAssertEqual(texts(code, .python, .string), ["f\"{x}\""])
        XCTAssertEqual(texts(code, .python, .comment), ["# fin"])
    }

    func testPythonDocstring() {
        XCTAssertEqual(texts("'''uno\ndos'''\nx", .python, .string), ["'''uno\ndos'''"])
    }

    func testJavaScriptTemplateAndDollar() {
        let code = "const $el = `a\nb`; // x"
        XCTAssertEqual(texts(code, .javascript, .keyword), ["const"])
        XCTAssertEqual(texts(code, .javascript, .string), ["`a\nb`"])
        XCTAssertEqual(texts(code, .javascript, .comment), ["// x"])
    }

    func testTypeScriptAddsItsKeywordsAndTypes() {
        let code = "interface A { b: number }"
        XCTAssertEqual(texts(code, .typescript, .keyword), ["interface"])
        XCTAssertEqual(texts(code, .typescript, .type), ["A", "number"])
        XCTAssertEqual(texts(code, .javascript, .keyword), [])
    }

    func testJSONKeysAndValues() {
        let code = #"{"name": "Ana", "age": 3, "ok": true, "x": null}"#
        XCTAssertEqual(texts(code, .json, .property), [#""name""#, #""age""#, #""ok""#, #""x""#])
        XCTAssertEqual(texts(code, .json, .string), [#""Ana""#])
        XCTAssertEqual(texts(code, .json, .number), ["3"])
        XCTAssertEqual(texts(code, .json, .keyword), ["true", "null"])
    }

    func testCSS() {
        let code = "/* c */\n.box { color: #fff; margin-top: -4px !important; }\n@media print {}"
        XCTAssertEqual(texts(code, .css, .comment), ["/* c */"])
        XCTAssertEqual(texts(code, .css, .property), ["color", "margin-top"])
        XCTAssertEqual(texts(code, .css, .number), ["#fff", "4px"])
        XCTAssertEqual(texts(code, .css, .keyword), ["important", "@media"])
    }

    func testSQLIsCaseInsensitive() {
        let code = "SELECT id FROM users WHERE name = 'O''Neil' -- fin"
        XCTAssertEqual(texts(code, .sql, .keyword), ["SELECT", "FROM", "WHERE"])
        XCTAssertEqual(texts(code, .sql, .comment), ["-- fin"])
        XCTAssertEqual(texts(code, .sql, .string), ["'O'", "'Neil'"])
    }

    func testShell() {
        let code = "export PATH=\"$HOME/bin\" # ruta\nif [ -n ${name} ]; then echo $1; fi\nurl#frag"
        XCTAssertEqual(texts(code, .shell, .keyword), ["export", "if", "then", "echo", "fi"])
        XCTAssertEqual(texts(code, .shell, .comment), ["# ruta"])
        XCTAssertEqual(texts(code, .shell, .property), ["${name}", "$1"])
        XCTAssertEqual(texts(code, .shell, .string), ["\"$HOME/bin\""])
    }

    func testHTML() {
        let code = "<!-- c -->\n<a href=\"/x\" hidden>Hola</a>\n<br/>"
        XCTAssertEqual(tokens(code, .html), [
            Token(text: "<!-- c -->", kind: .comment),
            Token(text: "<a", kind: .tag),
            Token(text: "href", kind: .attribute),
            Token(text: "\"/x\"", kind: .string),
            Token(text: "hidden", kind: .attribute),
            Token(text: ">", kind: .tag),
            Token(text: "</a", kind: .tag),
            Token(text: ">", kind: .tag),
            Token(text: "<br", kind: .tag),
            Token(text: "/>", kind: .tag),
        ])
    }

    func testTextIsNotTagInHTML() {
        XCTAssertEqual(tokens("a < b y c > d", .html), [])
    }

    // MARK: - Ranges

    func testRangesAreUTF16() {
        let code = "let 👋 = \"ñ😀\""
        let string = CodeHighlighter.tokens(in: code, language: .swift).first { $0.kind == .string }
        XCTAssertEqual(string?.range, NSRange(location: 9, length: 5))
    }

    func testTokensDontOverlapAndStayInside() {
        let samples: [(String, CodeLanguage)] = [
            ("func a() { \"x\" /* y */ 1 }", .swift),
            ("<p class='a'>t</p>", .html),
            ("SELECT 1; -- x", .sql),
            ("a=\"$(b)\" # c", .shell),
            ("\"unclosed", .json),
            ("/* unclosed", .css),
        ]
        for (code, language) in samples {
            let length = (code as NSString).length
            var end = 0
            for token in CodeHighlighter.tokens(in: code, language: language) {
                XCTAssertGreaterThanOrEqual(token.range.location, end, code)
                XCTAssertLessThanOrEqual(NSMaxRange(token.range), length, code)
                end = NSMaxRange(token.range)
            }
        }
    }
}
