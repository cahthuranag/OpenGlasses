import Foundation

// The table extractor over one PDF on a Mac, exactly as an import reads it on the phone
// (`PDFTableReader` + `TableExtractor`). Prints counts only — never a table's label, title, row,
// column or value, and never the document's name. See README.md.

@main
struct TableExtractEval {
    static func main() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = CommandLine.arguments.dropFirst().first ?? environment["TABLE_EXTRACT_EVAL_PDF"] else {
            FileHandle.standardError.write(Data("usage: table-extract-eval /path/to/document.pdf\n".utf8))
            exit(2)
        }
        let label = environment["TABLE_EXTRACT_EVAL_LABEL"] ?? "document"
        let started = Date()
        guard let result = PDFTableReader.read(url: URL(fileURLWithPath: path)) else {
            print("[TABLES] \(label): not a PDF PDFKit can open")
            exit(1)
        }
        let seconds = Date().timeIntervalSince(started)
        let share = result.captioned > 0 ? Double(result.extracted) / Double(result.captioned) : 0
        print(String(format: "[TABLES] %@ captioned=%d extracted=%d (%.2f) pages_without_text=%d seconds=%.1f",
                     label, result.captioned, result.extracted, share, result.pagesWithoutText, seconds))
        let failures = TableExtractor.Failure.allCases
            .map { "\($0.rawValue)=\(result.failures[$0] ?? 0)" }
            .joined(separator: " ")
        print("[TABLES]   failures: \(failures)")
        // Shape of what extracted, as distributions of counts — nothing from inside a table.
        let rows = result.tables.map(\.rows.count).sorted()
        let columns = result.tables.map(\.columns.count).sorted()
        let continued = result.tables.filter { $0.pages.count > 1 }.count
        let withNotes = result.tables.filter { !$0.notes.isEmpty }.count
        let cells = result.tables.flatMap { $0.rows.flatMap(\.cells) }.filter { !$0.isEmpty }
        let numeric = cells.filter { $0.value != nil }.count
        func median(_ values: [Int]) -> Int { values.isEmpty ? 0 : values[values.count / 2] }
        print("[TABLES]   extracted: rows median=\(median(rows)) max=\(rows.last ?? 0) "
              + "columns median=\(median(columns)) max=\(columns.last ?? 0) "
              + "over_pages=\(continued) with_notes=\(withNotes) "
              + String(format: "numeric_cells=%.2f", cells.isEmpty ? 0 : Double(numeric) / Double(cells.count)))
    }
}
