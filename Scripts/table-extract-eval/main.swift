import Foundation
import PDFKit

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
        if environment["TABLE_EXTRACT_EVAL_DIAGNOSE"] != "0" { diagnose(path) }
    }

    /// Where the captions that gave too few rows lost them (Plan JJ P1), in counts: how many body
    /// rows of two or more cells were read (0, 1, 2), where the first run of three such lines
    /// starts under the caption, and whether that run is text-keyed — its first cell text in every
    /// row — or text in every cell.
    static func diagnose(_ path: String) {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { return }
        let reach = TableExtractor.plainTitleMaximumLines + TableExtractor.plainHeaderMaximumLines
        var readings: [TableExtractor.TooFewRows] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string,
                  text.range(of: "table", options: .caseInsensitive) != nil else { continue }
            readings += TableExtractor.diagnoseTooFewRows(words: PDFTableReader.positionedWords(on: page),
                                                         page: ManualTable.Page(physical: index + 1))
        }
        let rows = (0...2).map { n in "\(n)=\(readings.filter { $0.bodyRows == n }.count)" }.joined(separator: " ")
        let noRun = readings.filter { $0.gridStart == nil }.count
        let far = readings.filter { ($0.gridStart ?? 0) > reach }.count
        let near = readings.filter { $0.gridStart.map { $0 <= reach } ?? false }.count
        let firstText = readings.filter { $0.gridStart != nil && $0.firstColumnText }.count
        let allText = readings.filter { $0.gridStart != nil && $0.allCellsText }.count
        print("[TABLES]   too_few_rows=\(readings.count): body_rows \(rows) · grid_run none=\(noRun) "
              + "within_\(reach)_lines=\(near) beyond_\(reach)_lines=\(far) · first_column_text=\(firstText) all_cells_text=\(allText)")
    }
}
