import SwiftUI

/// A formatting tool as the toolbar and the menus show it.
enum FormatTool: Hashable {
    case bodyText
    case heading(Int)
    case bold, italic, underline, strikethrough, inlineCode
    case quote, bulletList, numberedList
    case link, codeBlock, table, horizontalRule

    static let styles: [FormatTool] = [.bodyText] + FormatCommand.headingLevels.map(FormatTool.heading)
    static let inline: [FormatTool] = [.bold, .italic, .underline, .strikethrough, .inlineCode]
    static let blocks: [FormatTool] = [.bulletList, .numberedList, .quote]
    static let insertions: [FormatTool] = [.link, .codeBlock, .table, .horizontalRule]
    /// The tools grouped as the menus list them.
    static let menuGroups: [[FormatTool]] = [styles, inline, blocks, insertions]

    /// `nil` for tools that ask for insertion options first.
    var command: FormatCommand? {
        switch self {
        case .bodyText: .heading(0)
        case .heading(let level): .heading(level)
        case .bold: .bold
        case .italic: .italic
        case .underline: .underline
        case .strikethrough: .strikethrough
        case .inlineCode: .inlineCode
        case .quote: .quote
        case .bulletList: .bulletList
        case .numberedList: .numberedList
        case .link: nil
        case .codeBlock: .codeBlock
        case .table: nil
        case .horizontalRule: .horizontalRule
        }
    }

    var title: String {
        switch self {
        case .bodyText: String(localized: "Texto")
        case .heading(let level): String(localized: "Título \(level)")
        case .bold: String(localized: "Negrita")
        case .italic: String(localized: "Cursiva")
        case .underline: String(localized: "Subrayado")
        case .strikethrough: String(localized: "Tachado")
        case .inlineCode: String(localized: "Código")
        case .quote: String(localized: "Cita")
        case .bulletList: String(localized: "Lista con viñetas")
        case .numberedList: String(localized: "Lista numerada")
        case .link: String(localized: "Enlace…")
        case .codeBlock: String(localized: "Bloque de código")
        case .table: String(localized: "Tabla…")
        case .horizontalRule: String(localized: "Línea divisoria")
        }
    }

    var systemImage: String {
        switch self {
        case .bodyText: "text.alignleft"
        case .heading: "paragraphsign"
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .quote: "text.quote"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .link: "link"
        case .codeBlock: "curlybraces"
        case .table: "tablecells"
        case .horizontalRule: "minus"
        }
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .bodyText: KeyboardShortcut("7")
        case .heading(let level): KeyboardShortcut(KeyEquivalent(Character("\(level)")))
        case .bold: KeyboardShortcut("b")
        case .italic: KeyboardShortcut("i")
        case .underline: KeyboardShortcut("u")
        case .strikethrough: KeyboardShortcut("x", modifiers: [.command, .shift])
        case .inlineCode: KeyboardShortcut("e")
        case .quote: KeyboardShortcut("'")
        case .bulletList: KeyboardShortcut("8", modifiers: [.command, .shift])
        case .numberedList: KeyboardShortcut("7", modifiers: [.command, .shift])
        case .link: KeyboardShortcut("k")
        case .codeBlock: KeyboardShortcut("c", modifiers: [.command, .option])
        case .table, .horizontalRule: nil
        }
    }
}
