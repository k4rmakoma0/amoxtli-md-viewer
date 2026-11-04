import Foundation

nonisolated enum CodeTokenKind: Equatable, Sendable {
    case keyword, type, string, number, comment
    /// Object keys, CSS properties and shell variables.
    case property
    /// HTML and XML tags.
    case tag
    /// HTML attributes, Python decorators.
    case attribute
}

nonisolated struct CodeToken: Equatable, Sendable {
    /// UTF-16 offsets into the code.
    let range: NSRange
    let kind: CodeTokenKind
}

/// Finds the parts of a code block to color. A small lexer per language family, written for
/// highlighting, not for parsing: it knows comments, strings, numbers and words, so unusual
/// code is colored approximately rather than wrongly in a way that matters.
nonisolated enum CodeHighlighter {
    static func tokens(in code: String, language: CodeLanguage) -> [CodeToken] {
        let characters = Array(code.utf16)
        switch language {
        case .html:
            var lexer = MarkupLexer(characters: characters)
            return lexer.tokens()
        default:
            var lexer = CodeLexer(characters: characters, syntax: Syntax.of(language))
            return lexer.tokens()
        }
    }
}

// MARK: - Languages

private nonisolated struct Syntax {
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    /// Longest first, so `"""` wins over `"`.
    var strings: [(delimiter: String, isMultiline: Bool, hasEscapes: Bool)] = [("\"", false, true)]
    var keywords: Set<String> = []
    var types: Set<String> = []
    var caseInsensitive = false
    var capitalizedWordsAreTypes = false
    /// The prefix of a word that is a keyword in full, as `@` for Swift attributes.
    var keywordPrefixes: Set<UInt16> = []
    var decoratorPrefix: UInt16?
    /// Characters a word may also contain, as `$` in JavaScript.
    var extraWordCharacters: Set<UInt16> = []
    var stringPrefixes: Set<String> = []
    var hasShellVariables = false
    var commentNeedsWordBoundary = false
    var keysAreProperties = false
    var cssProperties = false

    static func of(_ language: CodeLanguage) -> Syntax {
        switch language {
        case .swift: swift
        case .python: python
        case .javascript: javascript
        case .typescript: typescript
        case .json: json
        case .css: css
        case .sql: sql
        case .shell: shell
        case .html: Syntax()
        }
    }

    private static let swift = Syntax(
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        strings: [("\"\"\"", true, true), ("\"", false, true)],
        keywords: [
            "actor", "any", "as", "associatedtype", "async", "await", "borrowing", "break", "case", "catch",
            "class", "consuming", "continue", "convenience", "default", "defer", "deinit", "didSet", "do",
            "dynamic", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for",
            "func", "get", "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is",
            "lazy", "let", "macro", "mutating", "nil", "nonisolated", "nonmutating", "open", "operator",
            "optional", "override", "package", "private", "protocol", "public", "repeat", "required",
            "rethrows", "return", "self", "Self", "sending", "set", "some", "static", "struct", "subscript",
            "super", "switch", "throw", "throws", "true", "try", "typealias", "unowned", "var", "weak",
            "where", "while", "willSet",
        ],
        capitalizedWordsAreTypes: true,
        keywordPrefixes: [0x40, 0x23]
    )

    private static let python = Syntax(
        lineComments: ["#"],
        strings: [("\"\"\"", true, true), ("'''", true, true), ("\"", false, true), ("'", false, true)],
        keywords: [
            "and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del",
            "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in",
            "is", "lambda", "match", "None", "nonlocal", "not", "or", "pass", "raise", "return", "self",
            "True", "try", "while", "with", "yield",
        ],
        types: ["int", "float", "str", "bool", "list", "dict", "set", "tuple", "bytes", "object"],
        capitalizedWordsAreTypes: true,
        decoratorPrefix: 0x40,
        stringPrefixes: ["r", "b", "f", "u", "rb", "br", "fr", "rf"]
    )

    private static let javascriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default",
        "delete", "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "get",
        "if", "import", "in", "instanceof", "let", "new", "null", "of", "return", "set", "static", "super",
        "switch", "this", "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield",
    ]

    private static let javascript = Syntax(
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        strings: [("`", true, true), ("\"", false, true), ("'", false, true)],
        keywords: javascriptKeywords,
        capitalizedWordsAreTypes: true,
        extraWordCharacters: [0x24]
    )

    private static let typescript = Syntax(
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        strings: [("`", true, true), ("\"", false, true), ("'", false, true)],
        keywords: javascriptKeywords.union([
            "abstract", "as", "asserts", "declare", "enum", "implements", "infer", "interface", "is", "keyof",
            "module", "namespace", "override", "private", "protected", "public", "readonly", "satisfies",
            "type", "unique",
        ]),
        types: ["any", "boolean", "never", "number", "object", "string", "symbol", "unknown", "bigint"],
        capitalizedWordsAreTypes: true,
        decoratorPrefix: 0x40,
        extraWordCharacters: [0x24]
    )

    private static let json = Syntax(
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        keywords: ["true", "false", "null"],
        keysAreProperties: true
    )

    private static let css = Syntax(
        blockComment: ("/*", "*/"),
        strings: [("\"", false, true), ("'", false, true)],
        keywords: ["important"],
        keywordPrefixes: [0x40],
        extraWordCharacters: [0x2D],
        cssProperties: true
    )

    private static let sql = Syntax(
        lineComments: ["--"],
        blockComment: ("/*", "*/"),
        strings: [("'", false, false)],
        keywords: [
            "add", "all", "alter", "and", "as", "asc", "begin", "between", "by", "case", "check", "commit",
            "constraint", "create", "default", "delete", "desc", "distinct", "drop", "else", "end", "exists",
            "foreign", "from", "full", "group", "having", "if", "in", "index", "inner", "insert", "into", "is",
            "join", "key", "left", "like", "limit", "not", "null", "offset", "on", "or", "order", "outer",
            "primary", "references", "returning", "right", "rollback", "select", "set", "table", "then",
            "transaction", "union", "unique", "update", "values", "view", "when", "where", "with",
        ],
        types: [
            "bigint", "blob", "boolean", "char", "date", "decimal", "double", "float", "int", "integer",
            "json", "numeric", "real", "serial", "text", "time", "timestamp", "uuid", "varchar",
        ],
        caseInsensitive: true
    )

    private static let shell = Syntax(
        lineComments: ["#"],
        strings: [("\"", true, true), ("'", true, false)],
        keywords: [
            "break", "case", "continue", "do", "done", "echo", "elif", "else", "esac", "exit", "export", "fi",
            "for", "function", "if", "in", "local", "readonly", "return", "select", "set", "shift", "source",
            "then", "unset", "until", "while",
        ],
        extraWordCharacters: [0x2D],
        hasShellVariables: true,
        commentNeedsWordBoundary: true
    )
}

// MARK: - Code

private nonisolated struct CodeLexer {
    let characters: [UInt16]
    let syntax: Syntax
    private var position = 0
    private var result: [CodeToken] = []
    private var braceDepth = 0

    init(characters: [UInt16], syntax: Syntax) {
        self.characters = characters
        self.syntax = syntax
    }

    mutating func tokens() -> [CodeToken] {
        while position < characters.count {
            let start = position
            if scanComment() || scanString() || scanNumber() || scanWord() || scanVariable() {
                continue
            }
            let character = characters[start]
            if character == 0x7B { braceDepth += 1 }
            if character == 0x7D { braceDepth = max(0, braceDepth - 1) }
            position += 1
        }
        return result
    }

    private mutating func add(_ kind: CodeTokenKind, from start: Int) {
        if position > start {
            result.append(CodeToken(range: NSRange(location: start, length: position - start), kind: kind))
        }
    }

    private func matches(_ text: String, at index: Int) -> Bool {
        let units = Array(text.utf16)
        guard index + units.count <= characters.count else { return false }
        return characters[index..<(index + units.count)].elementsEqual(units)
    }

    private func isWordCharacter(_ character: UInt16) -> Bool {
        isLetter(character) || isDigit(character) || character == 0x5F || syntax.extraWordCharacters.contains(character)
    }

    private func isLetter(_ character: UInt16) -> Bool {
        (0x41...0x5A).contains(character) || (0x61...0x7A).contains(character) || character > 0x7F
    }

    private func isDigit(_ character: UInt16) -> Bool {
        (0x30...0x39).contains(character)
    }

    private func isSpaceOrStart(_ index: Int) -> Bool {
        index == 0 || [0x20, 0x09, 0x0A, 0x0D, 0x3B, 0x7C, 0x26].contains(characters[index - 1])
    }

    // Comments

    private mutating func scanComment() -> Bool {
        let start = position
        if let block = syntax.blockComment, matches(block.open, at: position) {
            position += block.open.utf16.count
            while position < characters.count, !matches(block.close, at: position) { position += 1 }
            position = min(characters.count, position + block.close.utf16.count)
            add(.comment, from: start)
            return true
        }
        for prefix in syntax.lineComments where matches(prefix, at: position) {
            // In a shell, `#` only starts a comment at the start of a word: `a#b` is a word.
            if syntax.commentNeedsWordBoundary, !isSpaceOrStart(position) { continue }
            while position < characters.count, characters[position] != 0x0A { position += 1 }
            add(.comment, from: start)
            return true
        }
        return false
    }

    // Strings

    private mutating func scanString(from start: Int? = nil) -> Bool {
        let tokenStart = start ?? position
        guard let rule = syntax.strings.first(where: { matches($0.delimiter, at: position) }) else { return false }
        let delimiter = Array(rule.delimiter.utf16)
        position += delimiter.count
        while position < characters.count {
            if rule.hasEscapes, characters[position] == 0x5C {
                position = min(characters.count, position + 2)
                continue
            }
            if characters[position] == 0x0A, !rule.isMultiline { break }
            if matches(rule.delimiter, at: position) {
                position += delimiter.count
                break
            }
            position += 1
        }
        add(isKey(after: position) ? .property : .string, from: tokenStart)
        return true
    }

    /// A JSON or object key is a string followed by a colon.
    private func isKey(after index: Int) -> Bool {
        guard syntax.keysAreProperties else { return false }
        var next = index
        while next < characters.count, [0x20, 0x09].contains(characters[next]) { next += 1 }
        return next < characters.count && characters[next] == 0x3A
    }

    // Numbers

    private mutating func scanNumber() -> Bool {
        let start = position
        let character = characters[position]
        let startsWithPoint = character == 0x2E && position + 1 < characters.count && isDigit(characters[position + 1])
        let isHexColor = syntax.cssProperties && character == 0x23 && position + 1 < characters.count && isHexDigit(characters[position + 1])
        guard isDigit(character) || startsWithPoint || isHexColor else { return false }
        // A digit inside a word is part of it, but `-` before a number is a sign.
        if start > 0 {
            let previous = characters[start - 1]
            guard !isLetter(previous), !isDigit(previous), previous != 0x5F else { return false }
        }
        position += 1
        while position < characters.count {
            let next = characters[position]
            let isExponentSign = (next == 0x2B || next == 0x2D) && [0x65, 0x45].contains(characters[position - 1]) && !isHexColor
            guard isWordCharacter(next) || next == 0x2E || next == 0x25 || isExponentSign else { break }
            position += 1
        }
        add(.number, from: start)
        return true
    }

    private func isHexDigit(_ character: UInt16) -> Bool {
        isDigit(character) || (0x41...0x46).contains(character) || (0x61...0x66).contains(character)
    }

    // Words

    private mutating func scanWord() -> Bool {
        let start = position
        let character = characters[position]
        let hasKeywordPrefix = syntax.keywordPrefixes.contains(character)
        let hasDecoratorPrefix = syntax.decoratorPrefix == character
        // `-` starts words such as `--color` or `-n`, but `-4px` is a number.
        let startsNumber = position + 1 < characters.count && isDigit(characters[position + 1])
        let isExtraStart = syntax.extraWordCharacters.contains(character) && !isDigit(character) && !startsNumber
        guard isLetter(character) || character == 0x5F || isExtraStart || hasKeywordPrefix || hasDecoratorPrefix else { return false }
        guard start == 0 || !isWordCharacter(characters[start - 1]) else {
            position += 1
            return true
        }
        position += 1
        while position < characters.count, isWordCharacter(characters[position]) { position += 1 }
        if position - start == 1, hasKeywordPrefix || hasDecoratorPrefix {
            return true
        }
        let word = String(decoding: characters[start..<position], as: UTF16.self)
        // Python's `f"…"` and `r'…'`: the prefix belongs to the string.
        if syntax.stringPrefixes.contains(word.lowercased()), position < characters.count,
           syntax.strings.contains(where: { matches($0.delimiter, at: position) }) {
            return scanString(from: start)
        }
        if let kind = kind(of: word, hasKeywordPrefix: hasKeywordPrefix, hasDecoratorPrefix: hasDecoratorPrefix) {
            add(kind, from: start)
        }
        return true
    }

    private func kind(of word: String, hasKeywordPrefix: Bool, hasDecoratorPrefix: Bool) -> CodeTokenKind? {
        if hasDecoratorPrefix { return .attribute }
        if hasKeywordPrefix { return .keyword }
        let lookup = syntax.caseInsensitive ? word.lowercased() : word
        if syntax.cssProperties {
            return braceDepth > 0 && isKeyLike(after: position) ? .property : (syntax.keywords.contains(lookup) ? .keyword : nil)
        }
        if syntax.keywords.contains(lookup) { return .keyword }
        if syntax.types.contains(lookup) { return .type }
        if syntax.capitalizedWordsAreTypes, let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) {
            return .type
        }
        return nil
    }

    private func isKeyLike(after index: Int) -> Bool {
        var next = index
        while next < characters.count, [0x20, 0x09].contains(characters[next]) { next += 1 }
        return next < characters.count && characters[next] == 0x3A
    }

    // Shell variables: `$HOME`, `${name}`, `$1`, `$@`.

    private mutating func scanVariable() -> Bool {
        guard syntax.hasShellVariables, characters[position] == 0x24, position + 1 < characters.count else { return false }
        let start = position
        position += 1
        if characters[position] == 0x7B {
            while position < characters.count, characters[position] != 0x7D, characters[position] != 0x0A { position += 1 }
            position = min(characters.count, position + 1)
        } else if isWordCharacter(characters[position]) {
            while position < characters.count, isWordCharacter(characters[position]), characters[position] != 0x2D { position += 1 }
        } else if [0x40, 0x2A, 0x23, 0x3F, 0x24, 0x21].contains(characters[position]) {
            position += 1
        } else {
            return true
        }
        add(.property, from: start)
        return true
    }
}

// MARK: - Markup

/// HTML and XML: comments, tags, attribute names and their values.
private nonisolated struct MarkupLexer {
    let characters: [UInt16]
    private var position = 0
    private var result: [CodeToken] = []

    init(characters: [UInt16]) {
        self.characters = characters
    }

    mutating func tokens() -> [CodeToken] {
        while position < characters.count {
            if matches("<!--") {
                let start = position
                while position < characters.count, !matches("-->") { position += 1 }
                position = min(characters.count, position + 3)
                add(.comment, from: start)
            } else if characters[position] == 0x3C, position + 1 < characters.count,
                      isNameStart(characters[position + 1]) || [0x2F, 0x21, 0x3F].contains(characters[position + 1]) {
                scanTag()
            } else {
                position += 1
            }
        }
        return result
    }

    private mutating func add(_ kind: CodeTokenKind, from start: Int) {
        if position > start {
            result.append(CodeToken(range: NSRange(location: start, length: position - start), kind: kind))
        }
    }

    private func matches(_ text: String) -> Bool {
        let units = Array(text.utf16)
        guard position + units.count <= characters.count else { return false }
        return characters[position..<(position + units.count)].elementsEqual(units)
    }

    private func isNameStart(_ character: UInt16) -> Bool {
        (0x41...0x5A).contains(character) || (0x61...0x7A).contains(character) || character > 0x7F
    }

    private func isNameCharacter(_ character: UInt16) -> Bool {
        isNameStart(character) || (0x30...0x39).contains(character) || [0x2D, 0x5F, 0x3A, 0x2E].contains(character)
    }

    /// `<name` and the closing `>` are the tag; inside are attributes and their values.
    private mutating func scanTag() {
        let start = position
        position += 1
        while position < characters.count, [0x2F, 0x21, 0x3F].contains(characters[position]) { position += 1 }
        while position < characters.count, isNameCharacter(characters[position]) { position += 1 }
        add(.tag, from: start)
        while position < characters.count, characters[position] != 0x3E {
            let character = characters[position]
            if isNameStart(character) {
                let nameStart = position
                while position < characters.count, isNameCharacter(characters[position]) { position += 1 }
                add(.attribute, from: nameStart)
            } else if character == 0x22 || character == 0x27 {
                let valueStart = position
                position += 1
                while position < characters.count, characters[position] != character { position += 1 }
                position = min(characters.count, position + 1)
                add(.string, from: valueStart)
            } else if character == 0x2F || character == 0x3F, position + 1 < characters.count, characters[position + 1] == 0x3E {
                let closeStart = position
                position += 2
                add(.tag, from: closeStart)
                return
            } else {
                position += 1
            }
        }
        if position < characters.count {
            let closeStart = position
            position += 1
            add(.tag, from: closeStart)
        }
    }
}
