import Foundation
import PDFKit

/// The tables printed on a photographed manual's pages (Plan JN P4): read from the captured
/// revision's own page images by the same path a scanned PDF page takes (Plan JN P1), and stored
/// with the captured document's passages — derived, like its search index, so the captured bundle
/// and what it delivers are unchanged.
///
/// - **Which pages.** Only a page whose recognised text (IF's, already redacted) carries a table
///   caption line by `ManualStructure.caption`. That page's words are recognised once, its captions
///   found by the extractor's own rule for a page set in one weight, and the region under each read
///   by the preferred reading twice (the agreement pass) and judged by [[CellCertainty]] against
///   `PictureTableReading.capturedFloor`. A caption with no table under it is kept as a pointer to
///   its page.
/// - **Which page numbers.** IF's own page map: the captured PDF has one page per photograph in
///   capture order, so a table's physical page is its photograph's capture index — the page a
///   photographed-manual citation opens — and its printed page is the number IF detected on it,
///   when it detected one. Picture areas are in that PDF page's own top-down points.
/// - **Redaction before persistence.** Every string a table keeps passes `SecretPatterns.redact`,
///   as IF's text checkpoints do. A cell, row name or heading the redaction changed is unclear and
///   is never given; only the redacted text is kept. Nothing is checkpointed: a photographed page's
///   recognition is never written anywhere, and an interrupted reading is done again (the captured
///   document is not published until its tables are read, so a relaunch indexes it from the start,
///   as IF's index recovery does).
/// - **Checks.** A captured revision is keyed in `table-checks.json`'s `document_sha256` by its
///   bundle digest (the SHA-256 of its canonical manifest, which names its PDF's and text's
///   digests), the identity IF's citations and reviewed copies bind to. Its checks are the phone's
///   own and live in the phone's [[TableCheckStore]] under the vault it was photographed against.
enum CapturedManualTables {
    typealias C = CapturedManualContract

    // MARK: - Which pages

    /// The pages (capture indices) whose recognised text carries a table caption line.
    static func pagesNamingTables(_ pages: [(number: Int, text: String)]) -> Set<Int> {
        Set(pages.filter { page in
            page.text.split(whereSeparator: \.isNewline).contains { line in
                let typed = ManualStructure.TypedLine(raw: String(line), size: 10, bold: true)
                return ManualStructure.caption(typed)?.label.hasPrefix("Table ") == true
            }
        }.map(\.number))
    }

    /// The number IF detected printed on each page, by capture index, where it detected one.
    static func printedLabels(_ m: C.Manifest) -> [Int: String] {
        Dictionary(m.pages.filter { $0.printedPage > 0 }.map { ($0.index, String($0.printedPage)) },
                   uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Reading

    /// What a photographed page is read with: `reader`, the preferred reading, the photographed
    /// floor, the device's thermal state (the scales step down under pressure, as for a PDF), and
    /// no checkpoint.
    static func context(_ reader: PictureTableReader,
                        thermal: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState })
        -> PictureTableReading.Context {
        PictureTableReading.Context(reader: reader, reading: PictureTableReading.preferred,
                                    floor: PictureTableReading.capturedFloor, thermal: thermal, checkpoint: nil)
    }

    /// The tables on `pages` of the captured PDF at `pdf`, redacted. Pages not listed are not
    /// recognised at all. Runs wherever it is called: callers put it on a worker.
    static func read(pdf: URL, pages: Set<Int>, printedLabels: [Int: String],
                     context: PictureTableReading.Context) async -> PDFTableReader.Result {
        guard !pages.isEmpty, let document = PDFDocument(url: pdf) else { return PDFTableReader.Result() }
        return await read(document: document, pages: pages, printedLabels: printedLabels, context: context)
    }

    static func read(document: PDFDocument, pages: Set<Int>, printedLabels: [Int: String],
                     context: PictureTableReading.Context) async -> PDFTableReader.Result {
        var context = context
        // A photographed page's recognition holds what the page printed, unredacted: it is never
        // written, so a relaunch recognises again rather than reading a checkpoint.
        context.checkpoint = nil
        let first = PDFTableReader.scan(document: document, printedLabels: printedLabels, pictures: nil)
        let candidates = first.candidates.filter { candidate in
            candidate.kind == .page && pages.contains(candidate.physical)
        }
        guard !candidates.isEmpty else { return PDFTableReader.Result() }
        let recognitions = await PictureTableReading.recognise(candidates, in: document, context: context)
        let inputs = PictureTableReading.Inputs(recognitions: recognitions, reading: context.reading, floor: context.floor)
        var result = PDFTableReader.scan(document: document, printedLabels: printedLabels, pictures: inputs).result
        result.checkpointSaveFailures = 0
        var redactions = 0
        result.tables = result.tables.compactMap { table in
            let safe = redacted(table)
            redactions += safe.redacted
            return safe.table
        }
        result.unextracted = result.unextracted.compactMap { table in
            let safe = redacted(table)
            redactions += safe.redacted
            return safe.table
        }
        if redactions > 0 {
            PrivacyLog.store(.ragDocuments, .dropped, count: redactions, detail: PrivacyToken("captured_table_text_redacted"))
        }
        return result
    }

    // MARK: - Redaction

    /// `table` with every string it keeps through `SecretPatterns.redact`. A cell whose text the
    /// redaction changed keeps the redacted text, loses its value and unit, and is unclear; a row
    /// whose name changed has an unclear key; a column whose heading changed is unclear. Returns
    /// nil (the table is not kept) in the one case redaction cannot vouch for: anything sensitive
    /// left after it. `redacted` counts the strings changed.
    static func redacted(_ table: ManualTable) -> (table: ManualTable?, redacted: Int) {
        var count = 0
        func clean(_ text: String) -> (text: String, changed: Bool) {
            let safe = SecretPatterns.redact(text).redacted
            if safe != text { count += 1 }
            return (safe, safe != text)
        }
        var out = table
        out.label = clean(out.label).text
        out.title = clean(out.title).text
        out.rowHeaders = out.rowHeaders.map { clean($0).text }
        out.columns = out.columns.map { column in
            var column = column
            let path = column.path.map(clean)
            column.path = path.map(\.text)
            if path.contains(where: \.changed) { column.uncertain = true }
            column.unit = column.unit.map { clean($0).text }
            return column
        }
        out.rows = out.rows.map { row in
            var row = row
            let path = row.path.map(clean)
            row.path = path.map(\.text)
            if path.contains(where: \.changed) { row.keyUncertain = true }
            row.page.printed = row.page.printed.map { clean($0).text }
            row.cells = row.cells.map { cell in
                var cell = cell
                let text = clean(cell.text)
                cell.text = text.text
                cell.markers = cell.markers.map { clean($0).text }
                cell.unit = cell.unit.map { clean($0).text }
                if text.changed {
                    cell.uncertain = true
                    cell.value = nil
                    cell.unit = nil
                }
                return cell
            }
            return row
        }
        out.notes = out.notes.map { note in
            ManualTable.Note(marker: note.marker.map { clean($0).text }, text: clean(note.text).text)
        }
        out.page.printed = out.page.printed.map { clean($0).text }
        guard let json = try? JSONEncoder().encode(out),
              !SecretPatterns.containsSensitive(String(decoding: json, as: UTF8.self)) else { return (nil, count) }
        return (out, count)
    }

    // MARK: - Checks

    /// What a check of a table on the captured revision `m` is keyed by: its bundle digest.
    static func checkHash(_ m: C.Manifest) -> String? {
        (try? C.canonicalBytes(m)).map(C.digest)
    }

    /// Each captured document's check key, by document id.
    static func checkHashes(_ manifests: [C.Manifest]) -> [String: String] {
        Dictionary(manifests.compactMap { m in checkHash(m).map { (m.documentID, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Forget the checks of every revision in `manifests` from the phone's store. Returns how many
    /// went.
    @discardableResult
    static func forgetChecks(of manifests: [C.Manifest], in store: TableCheckStore) -> Int {
        var removed = 0
        for (vaultID, revisions) in Dictionary(grouping: manifests, by: \.vaultID) {
            let hashes = Set(revisions.compactMap(checkHash))
            removed += store.forget(documentHashes: hashes, vaultId: vaultID)
        }
        return removed
    }
}
