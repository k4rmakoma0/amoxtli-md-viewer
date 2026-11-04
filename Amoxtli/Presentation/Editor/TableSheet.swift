import SwiftUI

/// Asks for dimensions before inserting a table into the active editor.
struct TableSheet: View {
    let onInsert: (TableDimensions) -> Void

    @State private var columns = String(TableDimensions.standard.columns)
    @State private var rows = String(TableDimensions.standard.rows)
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field { case columns, rows }

    private var dimensions: TableDimensions? {
        guard let columns = Int(columns.trimmingCharacters(in: .whitespaces)),
              let rows = Int(rows.trimmingCharacters(in: .whitespaces)) else { return nil }
        return TableDimensions(columns: columns, rows: rows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insertar tabla")
                .font(.headline)
            Form {
                TextField("Columnas", text: $columns)
                    .focused($focusedField, equals: .columns)
                TextField("Filas", text: $rows)
                    .focused($focusedField, equals: .rows)
            }
            Text("La primera fila es el encabezado.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if dimensions == nil {
                Text("Usa entre 1 y 20 columnas y entre 1 y 100 filas.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insertar", action: insert)
                    .keyboardShortcut(.defaultAction)
                    .disabled(dimensions == nil)
            }
        }
        .padding(20)
        .frame(width: 340)
        .defaultFocus($focusedField, .columns)
    }

    private func insert() {
        guard let dimensions else { return }
        dismiss()
        onInsert(dimensions)
    }
}
