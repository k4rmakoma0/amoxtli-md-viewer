import AppKit

/// The language of the code block that was clicked, and how to change it.
struct CodeLanguageChoice {
    /// The info string as written, `nil` without one.
    let current: String?
    let choose: (String?) -> Void
}

/// The context menu of both editors: the clipboard, the formatting tools and Select All. In a
/// code block of the formatted editor, also its language.
enum EditingContextMenu {
    static func make(for textView: NSTextView, controller: EditorController?, codeLanguage: CodeLanguageChoice? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        menu.addItem(standardItem(String(localized: "Cortar"), action: #selector(NSText.cut(_:)), target: textView))
        menu.addItem(standardItem(String(localized: "Copiar"), action: #selector(NSText.copy(_:)), target: textView))
        menu.addItem(standardItem(String(localized: "Pegar"), action: #selector(NSText.paste(_:)), target: textView))
        menu.addItem(.separator())
        menu.addItem(formatItem(controller: controller))
        if let codeLanguage {
            menu.addItem(languageItem(codeLanguage))
        }
        menu.addItem(.separator())
        menu.addItem(standardItem(String(localized: "Seleccionar todo"), action: #selector(NSText.selectAll(_:)), target: textView))
        return menu
    }

    private static func standardItem(_ title: String, action: Selector, target: NSTextView) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }

    private static func formatItem(controller: EditorController?) -> NSMenuItem {
        let submenu = NSMenu()
        for (index, group) in FormatTool.menuGroups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            for tool in group {
                submenu.addItem(toolItem(tool, controller: controller))
            }
        }
        let item = NSMenuItem(title: String(localized: "Formato"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// No language, then the known ones by name. A language written in the file that isn't
    /// one of them shows as chosen, so it's clear the block has one.
    static func languageItem(_ choice: CodeLanguageChoice) -> NSMenuItem {
        let submenu = NSMenu()
        let known = choice.current.flatMap(CodeLanguage.init(fenceInfo:))
        let label = CodeLanguage.label(forFenceInfo: choice.current)
        if known == nil, let label {
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.state = .on
            submenu.addItem(item)
        }
        submenu.addItem(languageOption(String(localized: "Ninguno"), isChosen: label == nil) { choice.choose(nil) })
        submenu.addItem(.separator())
        for language in CodeLanguage.allCases.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
            submenu.addItem(languageOption(language.title, isChosen: language == known) { choice.choose(language.fenceName) })
        }
        let item = NSMenuItem(title: String(localized: "Lenguaje"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private static func languageOption(_ title: String, isChosen: Bool, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler: handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.state = isChosen ? .on : .off
        return item
    }

    private static func toolItem(_ tool: FormatTool, controller: EditorController?) -> NSMenuItem {
        let action = MenuAction { [weak controller] in
            controller?.perform(tool)
        }
        let item = NSMenuItem(title: tool.title, action: #selector(MenuAction.invoke), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.image = NSImage(systemSymbolName: tool.systemImage, accessibilityDescription: nil)
        return item
    }
}
