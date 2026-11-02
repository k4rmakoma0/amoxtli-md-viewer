import SwiftUI

/// What the sidebar shows. Only folder windows have the file list.
enum SidebarTab: String, CaseIterable {
    case contents, files

    var title: LocalizedStringKey {
        switch self {
        case .contents: "Índice"
        case .files: "Archivos"
        }
    }

    var help: LocalizedStringKey {
        switch self {
        case .contents: "Muestra los encabezados del documento"
        case .files: "Muestra los archivos Markdown de la carpeta"
        }
    }

    var menuTitle: LocalizedStringKey {
        switch self {
        case .contents: "Mostrar índice"
        case .files: "Mostrar archivos"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .contents: "1"
        case .files: "2"
        }
    }
}

/// Lets the View menu bring a sidebar tab into view in the active window.
struct SidebarTabAction {
    let availableTabs: [SidebarTab]
    let show: (SidebarTab) -> Void
}

extension FocusedValues {
    @Entry var sidebarTabAction: SidebarTabAction?
}
