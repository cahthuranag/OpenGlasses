import Foundation

/// Each body row of an extracted table as one sentence, stored as a passage of its own (Plan JJ
/// P0), so the embedder and the lexical ranking can find a cell by its row header and the token
/// route can find the table by its label:
///
/// "Table 99 (Conductor ratings), row QXRT, three conductors: 30 in Rating group 1, 35 in Rating
/// group 2 — page 12"
///
/// A row passage is `DocumentChunker.Kind.tableRow` with `figure` set to the table's label. It is
/// text the app wrote from the table, not text printed on the page, so it is never a drawing,
/// never highlighted on the page and never opens a page by itself (`FigureAutoOpenPolicy`).
enum TableRowPassage {

    /// Row passages kept per table. A table longer than this is still stored whole in
    /// `doc_tables`; only its passages stop, and the caller logs how many were left out.
    static let rowCap = 400

    /// The sentence for one row, or nil for a row with no value in it.
    static func sentence(for row: ManualTable.Row, in table: ManualTable) -> String? {
        var values: [String] = []
        for (index, cell) in row.cells.enumerated() where !cell.isEmpty {
            let column = index < table.columns.count ? table.columns[index] : nil
            let name = column.map(\.name).flatMap { $0.isEmpty ? nil : $0 } ?? "column \(index + 1)"
            values.append("\(cell.text) in \(name)")
        }
        guard !values.isEmpty else { return nil }
        let rowName = row.path.isEmpty ? "" : ", row " + row.path.joined(separator: ", ")
        return "\(table.displayName)\(rowName): \(values.joined(separator: ", ")) \u{2014} page \(row.page.spoken)"
    }

    /// The row passages of `tables` as chunks numbered from `index`, at most `cap` per table, and
    /// how many rows the cap left out.
    static func chunks(for tables: [ManualTable], startingAt index: Int,
                       cap: Int = rowCap) -> (chunks: [DocumentChunker.Chunk], dropped: Int) {
        var chunks: [DocumentChunker.Chunk] = []
        var dropped = 0
        for table in tables {
            var kept = 0
            for row in table.rows {
                guard let text = sentence(for: row, in: table) else { continue }
                guard kept < cap else { dropped += 1; continue }
                chunks.append(DocumentChunker.Chunk(index: index + chunks.count, text: text,
                                                    page: row.page.physical, section: nil,
                                                    kind: .tableRow, figure: table.label))
                kept += 1
            }
        }
        return (chunks, dropped)
    }
}
