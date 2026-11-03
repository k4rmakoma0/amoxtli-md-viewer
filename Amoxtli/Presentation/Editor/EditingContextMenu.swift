import AppKit

/// The context menu of both editors: the clipboard, the formatting tools and Select All.
enum EditingContextMenu {
    static func make(for textView: NSTextView, controller: EditorController?) -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        menu.addItem(standardItem(String(localized: "Cortar"), action: #selector(NSText.cut(_:)), target: textView))
        menu.addItem(standardItem(String(localized: "Copiar"), action: #selector(NSText.copy(_:)), target: textView))
        menu.addItem(standardItem(String(localized: "Pegar"), action: #selector(NSText.paste(_:)), target: textView))
        menu.addItem(.separator())
        menu.addItem(formatItem(controller: controller))
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
