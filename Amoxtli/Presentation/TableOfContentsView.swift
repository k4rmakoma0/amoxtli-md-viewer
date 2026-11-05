import SwiftUI

struct TableOfContentsView: View {
    let entries: [TOCEntry]
    let onSelect: (TOCEntry) -> Void

    @State private var selection: TOCEntry.ID?

    private let indentPerLevel: CGFloat = 12

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Sin índice", systemImage: "list.bullet.indent", description: Text("Este documento no tiene encabezados."))
            } else {
                list
            }
        }
        .onChange(of: entries) {
            selection = nil
        }
    }

    private var list: some View {
        // Worked out once: per row, it went through every entry, which stalled the window for a
        // document with thousands of headings.
        let topLevel = topLevel
        // The binding covers arrow keys. Clicks go through the button, so that clicking the
        // selected entry again still scrolls back to its heading.
        return List(entries, selection: keyboardSelection) { entry in
            Button {
                selection = entry.id
                onSelect(entry)
            } label: {
                Text(verbatim: entry.title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, CGFloat(entry.level - topLevel) * indentPerLevel)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(entry.title), nivel \(entry.level)"))
            .listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
    }

    private var keyboardSelection: Binding<TOCEntry.ID?> {
        Binding {
            selection
        } set: { id in
            selection = id
            if let entry = entries.first(where: { $0.id == id }) {
                onSelect(entry)
            }
        }
    }

    private var topLevel: Int {
        entries.map(\.level).min() ?? 1
    }
}

#Preview {
    TableOfContentsView(
        entries: [
            TOCEntry(id: "uno", title: "Uno", level: 1, blockIndex: 0),
            TOCEntry(id: "dos", title: "Dos", level: 2, blockIndex: 1),
            TOCEntry(id: "tres", title: "Tres", level: 3, blockIndex: 2),
        ],
        onSelect: { _ in }
    )
}
