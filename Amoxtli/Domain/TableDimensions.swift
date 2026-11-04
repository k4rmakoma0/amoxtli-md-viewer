import Foundation

/// Total table dimensions. The first row is the Markdown header.
nonisolated struct TableDimensions: Hashable, Sendable {
    static let columnRange = 1...20
    static let rowRange = 1...100
    static let standard = TableDimensions(validatedColumns: 2, rows: 2)

    let columns: Int
    let rows: Int

    init?(columns: Int, rows: Int) {
        guard Self.columnRange.contains(columns), Self.rowRange.contains(rows) else { return nil }
        self.init(validatedColumns: columns, rows: rows)
    }

    private init(validatedColumns columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    var headers: [String] {
        (1...columns).map { String(localized: "Columna \($0)") }
    }
}
