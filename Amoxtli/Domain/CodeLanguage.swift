import Foundation

/// The languages code blocks are highlighted in, read from a fence's info string.
nonisolated enum CodeLanguage: String, CaseIterable, Sendable {
    case swift, python, javascript, typescript, json, html, css, sql, shell

    /// The first word of a fence's info string, as in ```` ```swift ````. Common aliases count;
    /// anything else is a language without highlighting.
    init?(fenceInfo: String) {
        let name = fenceInfo.trimmingCharacters(in: .whitespaces)
            .prefix { !$0.isWhitespace && $0 != "{" && $0 != "," }
            .lowercased()
        switch name {
        case "swift": self = .swift
        case "python", "py", "python3": self = .python
        case "javascript", "js", "jsx", "mjs", "cjs", "node": self = .javascript
        case "typescript", "ts", "tsx": self = .typescript
        case "json", "jsonc", "json5": self = .json
        case "html", "htm", "xml", "xhtml", "svg", "plist": self = .html
        case "css", "scss", "less": self = .css
        case "sql", "mysql", "postgresql", "postgres", "sqlite": self = .sql
        case "shell", "sh", "bash", "zsh", "console", "shellscript": self = .shell
        default: return nil
        }
    }

    /// How the language is named in menus and on the block. These are proper names.
    var title: String {
        switch self {
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .json: "JSON"
        case .html: "HTML"
        case .css: "CSS"
        case .sql: "SQL"
        case .shell: "Shell"
        }
    }

    /// What is written after the fence.
    var fenceName: String { rawValue }

    /// The name shown on a code block: the language's proper name when it is known, else the
    /// info string's first word as written; `nil` without one.
    static func label(forFenceInfo info: String?) -> String? {
        guard let info else { return nil }
        if let language = CodeLanguage(fenceInfo: info) { return language.title }
        let word = info.trimmingCharacters(in: .whitespaces).prefix { !$0.isWhitespace && $0 != "{" && $0 != "," }
        return word.isEmpty ? nil : String(word)
    }
}
