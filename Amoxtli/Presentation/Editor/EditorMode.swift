import SwiftUI

/// How the window shows the document: as Markdown source, formatted, or both side by side.
enum EditorMode: String, CaseIterable {
    case source, formatted, split

    var title: LocalizedStringKey {
        switch self {
        case .source: "Fuente"
        case .formatted: "Formato"
        case .split: "Dividido"
        }
    }

    var help: LocalizedStringKey {
        switch self {
        case .source: "Muestra el Markdown sin formato"
        case .formatted: "Muestra el documento con formato"
        case .split: "Muestra el Markdown y el documento con formato lado a lado"
        }
    }

    var menuTitle: LocalizedStringKey {
        switch self {
        case .source: "Mostrar fuente"
        case .formatted: "Mostrar con formato"
        case .split: "Mostrar dividido"
        }
    }

    var systemImage: String {
        switch self {
        case .source: "number"
        case .formatted: "doc.richtext"
        case .split: "rectangle.split.2x1"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .source: "1"
        case .formatted: "2"
        case .split: "3"
        }
    }

    var showsSource: Bool { self != .formatted }
}

extension FocusedValues {
    /// The mode of the active window, for the View menu.
    @Entry var editorMode: Binding<EditorMode>?
    /// The editors of the active window, for the Format menu.
    @Entry var editorController: EditorController?
}
