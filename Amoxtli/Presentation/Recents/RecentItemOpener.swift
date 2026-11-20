import AppKit
import SwiftUI

/// Opens an item of the recent list where it belongs: a file in a document window, a folder in
/// a window of its own.
struct RecentItemOpener {
    let recents: RecentItemsModel
    let openWindow: OpenWindowAction

    /// Returns `false` if the item no longer exists or couldn't open. A missing item leaves the
    /// list, and the person is told why.
    @discardableResult
    func open(_ item: RecentItem) async -> Bool {
        switch recents.locate(item) {
        case .missing:
            recents.remove(item)
            showMissing(item)
            return false
        case .available(let url, let bookmark):
            switch item.kind {
            case .file:
                return await OpenFileAction.open(url)
            case .folder:
                openWindow(value: bookmark)
                return true
            }
        }
    }

    /// AppKit is required here: the menu can be used with no window open to attach a SwiftUI
    /// alert to.
    private func showMissing(_ item: RecentItem) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "No se encontró «\(item.name)»")
        alert.informativeText = String(localized: "Puede que se haya movido o eliminado. Se quitó de los recientes.")
        alert.runModal()
    }
}
