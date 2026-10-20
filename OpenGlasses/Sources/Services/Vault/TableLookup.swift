import Foundation

/// One cell of an extracted table, found by table, row and column, with where it came from (Plan JJ
/// P1). What `table_lookup` answers with.
///
/// **It says what it found and no more** (decision 2). A cell comes back with its row's and its
/// column's full header paths, its units, the notes it, its row or its column point to, and the
/// page it is printed on. An asked number that falls between two rows returns both rows and says
/// so: nothing is interpolated, rounded, or moved to "the next size up" — which row a rule wants is
/// a chain step's parameter or the technician's call. A table, row or column the words fit more
/// than one way lists the candidates and asks. A table whose caption was found and whose grid could
/// not be read says so, with its page, so the technician can be shown it.
///
/// Pure: the stored tables in, an outcome out. The tool renders it for the model.
enum TableLookup {

    /// A stored table and the document it came from.
    struct Source: Equatable {
        let documentId: String
        let documentName: String
        let table: ManualTable

        init(documentId: String, documentName: String, table: ManualTable) {
            self.documentId = documentId
            self.documentName = documentName
            self.table = table
        }
    }

    struct Request: Equatable {
        /// A label ("Table 99", "table ninety-nine") or the words of a title.
        var table: String
        /// A row header value, a number, or the words of a row header.
        var row: String
        /// A column header path ("Rating group 2 › Band B") or its words. Nil reads the whole row
        /// unless the table has one value column.
        var column: String?
        /// The document the technician named, by title or part of it.
        var document: String?

        init(table: String, row: String, column: String? = nil, document: String? = nil) {
            self.table = table
            self.row = row
            self.column = column
            self.document = document
        }
    }

    /// The part of a request that could not be settled.
    enum Part: String, Equatable {
        case document, table, row, column
    }

    /// The rows and columns a lookup read.
    struct Found: Equatable {
        let source: Source
        /// One row, or the two that bracket an asked number (`between`).
        let rows: [ManualTable.Row]
        /// Indexes into `source.table.columns`: one when a column was asked for or the table has
        /// only one, every column otherwise.
        let columns: [Int]
        /// The asked number when it fell between `rows[0]` and `rows[1]`.
        let between: Double?
        /// Pages of the same table, in the same document, whose grid could not be read — rows
        /// printed there are not in this lookup.
        let unreadPages: [ManualTable.Page]
    }

    enum Outcome: Equatable {
        case found(Found)
        /// More than one fits; ask which. `candidates` are names to say.
        case ambiguous(Part, asked: String, candidates: [String])
        /// Nothing fits. `available` names what does exist, to offer.
        case notFound(Part, asked: String, available: [String])
        /// The table's caption was found and its grid was not read: the page can be shown.
        case notExtracted(Source)
        /// The searched manuals hold no tables at all.
        case noTables
    }

    // MARK: - Resolving

    static func resolve(_ request: Request, in sources: [Source]) -> Outcome {
        guard !sources.isEmpty else { return .noTables }
        var pool = sources
        if let document = request.document?.trimmingCharacters(in: .whitespacesAndNewlines), !document.isEmpty {
            let exact = sources.filter { $0.documentName.localizedCaseInsensitiveContains(document) }
            pool = exact.isEmpty ? sources.filter { ManualDocumentChoice.matches($0.documentName, requested: document) } : exact
            guard !pool.isEmpty else {
                return .notFound(.document, asked: document, available: orderedUnique(sources.map(\.documentName)))
            }
        }

        // The table: by label, then by title words.
        let candidates: [Source]
        if let label = TableReference.labels(in: request.table).first ?? bareLabel(request.table) {
            candidates = pool.filter { $0.table.label.caseInsensitiveCompare(label) == .orderedSame }
            guard !candidates.isEmpty else {
                return .notFound(.table, asked: label, available: availableTables(pool))
            }
        } else {
            candidates = byTitle(request.table, in: pool)
            guard !candidates.isEmpty else {
                return .notFound(.table, asked: request.table, available: availableTables(pool))
            }
        }
        // One table per document: the grid that was read wins over a page of it that was not.
        let documents = orderedUnique(candidates.map(\.documentId))
        let tables = Set(candidates.map { "\($0.documentId)#\($0.table.label.lowercased())" })
        guard documents.count == 1, tables.count == 1 else {
            return .ambiguous(.table, asked: request.table,
                              candidates: orderedUnique(candidates.map { "\($0.table.displayName) in \($0.documentName)" }))
        }
        let read = candidates.filter(\.table.isExtracted)
        guard let source = read.first else { return .notExtracted(candidates[0]) }
        let unread = candidates.filter { !$0.table.isExtracted }.map(\.table.page)
        let table = source.table

        // The column first, so a row that fails to resolve can still be reported for it.
        let columns: [Int]
        switch resolveColumn(request.column, in: table) {
        case .resolved(let found): columns = found
        case .ambiguous(let names): return .ambiguous(.column, asked: request.column ?? "", candidates: names)
        case .none: return .notFound(.column, asked: request.column ?? "", available: table.columns.map(columnName))
        }

        switch resolveRow(request.row, in: table) {
        case .rows(let rows):
            return .found(Found(source: source, rows: rows, columns: columns, between: nil, unreadPages: unread))
        case .between(let lower, let upper, let value):
            return .found(Found(source: source, rows: [lower, upper], columns: columns, between: value,
                                unreadPages: unread))
        case .ambiguous(let rows):
            return .ambiguous(.row, asked: request.row, candidates: rows.map(rowName))
        case .outside(let range):
            return .notFound(.row, asked: request.row, available: range)
        case .none:
            return .notFound(.row, asked: request.row, available: Array(table.rows.prefix(12)).map(rowName))
        }
    }

    /// "99" or "No. 99" asked for as the table.
    private static func bareLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(of: #"^(?:no\.?\s*|#)?(\d{1,4})$"#, options: [.regularExpression, .caseInsensitive]),
              let number = Int(trimmed[match].filter(\.isNumber)) else { return nil }
        return TableReference.label(number: number)
    }

    /// The tables whose titles share the most of the asked words — all of them on a tie.
    private static func byTitle(_ words: String, in pool: [Source]) -> [Source] {
        let asked = significantWords(words).subtracting(["table", "tables"])
        guard !asked.isEmpty else { return [] }
        let scored = pool.map { ($0, asked.intersection(significantWords($0.table.title)).count) }
        guard let best = scored.map(\.1).max(), best > 0 else { return [] }
        return scored.filter { $0.1 == best }.map(\.0)
    }

    private static func availableTables(_ pool: [Source]) -> [String] {
        Array(orderedUnique(pool.map(\.table.displayName)).prefix(12))
    }

    // MARK: Columns

    private enum ColumnMatch { case resolved([Int]), ambiguous([String]), none }

    private static func resolveColumn(_ asked: String?, in table: ManualTable) -> ColumnMatch {
        let all = Array(table.columns.indices)
        guard let asked = asked?.trimmingCharacters(in: .whitespacesAndNewlines), !asked.isEmpty else {
            return .resolved(all)
        }
        guard !all.isEmpty else { return .none }
        let key = normalised(asked)
        // By path: the whole path, or the end of it ("Band B" under one group only).
        let byPath = all.filter { index in
            suffixes(table.columns[index].path).contains(key)
        }
        if byPath.count == 1 { return .resolved(byPath) }
        if byPath.count > 1 {
            let whole = byPath.filter { normalised(table.columns[$0].path.joined(separator: " ")) == key }
            return whole.count == 1 ? .resolved(whole) : .ambiguous(byPath.map { columnName(table.columns[$0]) })
        }
        // By words.
        switch bestByWords(asked, among: all.map { table.columns[$0].path }) {
        case .one(let index): return .resolved([all[index]])
        case .several(let indexes): return .ambiguous(indexes.map { columnName(table.columns[all[$0]]) })
        case .none: return .none
        }
    }

    // MARK: Rows

    private enum RowMatch {
        case rows([ManualTable.Row])
        case between(ManualTable.Row, ManualTable.Row, Double)
        case ambiguous([ManualTable.Row])
        /// A number outside the rows' range; the range, to say.
        case outside([String])
        case none
    }

    private static func resolveRow(_ asked: String, in table: ManualTable) -> RowMatch {
        let rows = table.rows
        let key = normalised(asked)
        guard !key.isEmpty, !rows.isEmpty else { return .none }

        // 1. Exactly a header: one of the row's headers, or a run of them ("QXRT three conductors").
        let exact = rows.filter { suffixesAndParts($0.path).contains(key) }
        if exact.count == 1 { return .rows(exact) }
        if exact.count > 1 {
            let whole = exact.filter { normalised($0.path.joined(separator: " ")) == key
                || normalised($0.path.dropFirst().joined(separator: " ")) == key }
            return whole.count == 1 ? .rows(whole) : .ambiguous(exact)
        }

        // 2. A number: a row keyed by that number (or a printed range holding it), else the two
        // rows either side of it. Words beside the number narrow the rows first ("QXRT 35").
        if let value = number(in: asked) {
            let others = significantWords(asked.replacingOccurrences(of: numberText(in: asked) ?? "", with: " "))
            // Words no row prints (a unit said after the number) narrow nothing.
            let filtered = rows.filter { others.isSubset(of: significantWords($0.path.joined(separator: " "))) }
            let narrowed = others.isEmpty || filtered.isEmpty ? rows : filtered
            let keyed = narrowed.compactMap { row in numericKey(of: row).map { (row, $0) } }
            if !keyed.isEmpty {
                let hits = keyed.filter { $0.1.contains(value) }.map(\.0)
                if hits.count == 1 { return .rows(hits) }
                if hits.count > 1 { return .ambiguous(hits) }
                let below = keyed.filter { $0.1.upper < value }
                let above = keyed.filter { $0.1.lower > value }
                guard let lowKey = below.map(\.1.upper).max(), let highKey = above.map(\.1.lower).min() else {
                    let low = keyed.map(\.1.lower).min() ?? 0, high = keyed.map(\.1.upper).max() ?? 0
                    return .outside(["the rows run from \(format(low)) to \(format(high))"])
                }
                let lower = below.filter { $0.1.upper == lowKey }.map(\.0)
                let upper = above.filter { $0.1.lower == highKey }.map(\.0)
                guard lower.count == 1, upper.count == 1 else { return .ambiguous(lower + upper) }
                return .between(lower[0], upper[0], value)
            }
        }

        // 3. The nearest words.
        switch bestByWords(asked, among: rows.map(\.path)) {
        case .one(let index): return .rows([rows[index]])
        case .several(let indexes): return .ambiguous(indexes.map { rows[$0] })
        case .none: return .none
        }
    }

    /// The number a row is keyed by: the first of its headers that is a number ("35", "2.5 mm²")
    /// or a printed range ("7-9", "10–12"), as the interval it covers.
    private static func numericKey(of row: ManualTable.Row) -> (lower: Double, upper: Double, contains: (Double) -> Bool)? {
        for header in row.path {
            let text = header.trimmingCharacters(in: .whitespaces)
            if let range = text.range(of: #"^(\d+(?:[.,]\d+)?)\s*[-\x{2013}\x{2014}]\s*(\d+(?:[.,]\d+)?)$"#,
                                      options: .regularExpression) {
                let parts = text[range].split(whereSeparator: { "-\u{2013}\u{2014}".contains($0) })
                    .compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
                if parts.count == 2, parts[0] <= parts[1] {
                    let low = parts[0], high = parts[1]
                    return (low, high, { $0 >= low && $0 <= high })
                }
            }
            let cell = TableExtractor.parseCell(text, markers: [], columnUnit: nil)
            if let value = cell.value, text.range(of: #"^[-+\u{2212}]?[\d.,]+"#, options: .regularExpression) != nil {
                return (value, value, { $0 == value })
            }
        }
        return nil
    }

    /// The first number the asked words carry ("37", "37 A", "2.5"), else nil.
    private static func number(in text: String) -> Double? {
        guard let raw = numberText(in: text) else { return nil }
        return TableExtractor.parseCell(raw, markers: [], columnUnit: nil).value
    }

    private static func numberText(in text: String) -> String? {
        text.range(of: #"(?<![\p{L}\p{N}.])\d+(?:[.,]\d+)?(?![\p{N}]|[.,]\d)"#, options: .regularExpression)
            .map { String(text[$0]) }
    }

    // MARK: - Words

    private enum WordsMatch { case one(Int), several([Int]), none }

    /// The header path the asked words fit best. Every number the words carry must be in the path —
    /// a number is never approximated — and then the path holding the most of the other words
    /// wins; two that hold as many are both returned.
    private static func bestByWords(_ asked: String, among paths: [[String]]) -> WordsMatch {
        let words = significantWords(asked)
        guard !words.isEmpty else { return .none }
        let numbers = words.filter { $0.first?.isNumber == true }
        var best = 0
        var hits: [Int] = []
        for (index, path) in paths.enumerated() {
            let have = significantWords(path.joined(separator: " "))
            guard numbers.isSubset(of: have) else { continue }
            let shared = words.intersection(have).count
            guard shared > 0 else { continue }
            if shared > best { best = shared; hits = [index] } else if shared == best { hits.append(index) }
        }
        switch hits.count {
        case 0: return .none
        case 1: return .one(hits[0])
        default:
            // Several hold as many: the one with nothing beyond the asked words is meant.
            let tight = hits.filter { significantWords(paths[$0].joined(separator: " ")).count == best }
            return tight.count == 1 ? .one(tight[0]) : .several(hits)
        }
    }

    /// Words as they are compared: lower-cased, accents folded, "conductors" as "conductor", a
    /// printed range ("7-9") and a decimal ("1.5") kept whole; filler words dropped.
    static func significantWords(_ text: String) -> Set<String> {
        Set(tokens(text).filter { !filler.contains($0) }.map(singular))
    }

    private static let filler: Set<String> = ["the", "of", "for", "in", "and", "row", "column", "at", "with", "to", "on"]

    private static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "\u{2013}", with: "-").replacingOccurrences(of: "\u{2014}", with: "-")
        let pattern = #"\d+(?:[.,]\d+)?(?:\s*-\s*\d+(?:[.,]\d+)?)?|\p{L}[\p{L}\p{N}]*|\p{N}+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = folded as NSString
        return regex.matches(in: folded, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        }
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"), word.first?.isLetter == true else { return word }
        return String(word.dropLast())
    }

    /// A header as compared whole: its words joined by single spaces.
    static func normalised(_ text: String) -> String { tokens(text).map(singular).joined(separator: " ") }

    /// Every run of the path that ends at its end, whole path first ("rating group 2 band b",
    /// "band b").
    private static func suffixes(_ path: [String]) -> Set<String> {
        Set(path.indices.map { normalised(path[$0...].joined(separator: " ")) })
    }

    /// Every contiguous run of the path's parts.
    private static func suffixesAndParts(_ path: [String]) -> Set<String> {
        var out = Set<String>()
        for start in path.indices {
            for end in start..<path.count {
                out.insert(normalised(path[start...end].joined(separator: " ")))
            }
        }
        return out
    }

    // MARK: - Names

    static func rowName(_ row: ManualTable.Row) -> String {
        row.path.isEmpty ? "(unnamed row)" : row.path.joined(separator: ManualTable.Column.pathSeparator)
    }

    static func columnName(_ column: ManualTable.Column) -> String {
        column.name.isEmpty ? "(unnamed column)" : column.name
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - Notes and citation

    /// The notes a found cell set points to: those keyed by a marker on a cell, on its row's
    /// headers or on its column's headings, then the table's unmarked notes, which apply to all of
    /// it. In the order the table prints them.
    static func notes(for found: Found) -> [ManualTable.Note] {
        let table = found.source.table
        var markers = Set<String>()
        for row in found.rows {
            for index in found.columns where index < row.cells.count { markers.formUnion(row.cells[index].markers) }
            for header in row.path { markers.formUnion(TableExtractor.parseCell(header, markers: [], columnUnit: nil).markers) }
        }
        for index in found.columns where index < table.columns.count {
            for heading in table.columns[index].path {
                markers.formUnion(TableExtractor.parseCell(heading, markers: [], columnUnit: nil).markers)
            }
        }
        return table.notes.filter { note in note.marker.map(markers.contains) ?? true }
    }

    /// The pages the found rows are printed on, in order.
    static func pages(of found: Found) -> [ManualTable.Page] {
        var seen: [ManualTable.Page] = []
        for row in found.rows where !seen.contains(row.page) { seen.append(row.page) }
        return seen.isEmpty ? [found.source.table.page] : seen
    }

    /// "page 12 (printed 10)" in the form `VaultRetriever.Passage.citation` writes it, which
    /// `CitationLineParser` reads back to the physical page.
    private static func citedPage(_ page: ManualTable.Page) -> String {
        "page \(page.physical)" + (page.printed.map { " (printed \($0))" } ?? "")
    }

    /// The machine-attached `Source:` line for a table's pages: "Book, page 12 (printed 10), Table
    /// 99", a second page of it as "; page 13, Table 99".
    static func sourceLine(documentName: String, label: String, pages: [ManualTable.Page]) -> String {
        let parts = pages.enumerated().map { index, page in
            (index == 0 ? "\(documentName), " : "") + "\(citedPage(page)), \(label)"
        }
        return "Source: " + parts.joined(separator: "; ")
    }

    /// The citations a result opens: one per page, each naming the table.
    static func citations(documentName: String, label: String, pages: [ManualTable.Page]) -> [Citation] {
        pages.map { Citation(kind: .manual, title: documentName, page: $0.physical, figure: label) }
    }

    /// How a page is said: its printed number when the book prints one, else the PDF's own.
    static func spokenPage(_ page: ManualTable.Page) -> String {
        page.printed.map { "page \($0)" } ?? "PDF page \(page.physical)"
    }

    // MARK: - Rendering

    /// What the model is told. Every answer that names a cell ends with the `Source:` line.
    static func render(_ outcome: Outcome) -> String {
        switch outcome {
        case .noTables:
            return "No table could be read from the loaded manuals, so there is no cell to look up. "
                + "Search with manual_lookup instead, and say the value comes from a passage, not a table."
        case .notFound(.document, let asked, let available):
            return "No manual with tables is titled like \"\(asked)\". Manuals with tables: "
                + available.joined(separator: "; ") + ". Nothing was looked up."
        case .notFound(.table, let asked, let available):
            return "No table matching \"\(asked)\" was read from the loaded manuals. Tables that were read: "
                + available.joined(separator: "; ")
                + ". If the book prints it, its grid may not have been readable: find its page with manual_lookup "
                + "and show it rather than answering from memory."
        case .notFound(.column, let asked, let available):
            return "No column matching \"\(asked)\" in that table. Its columns: " + available.joined(separator: "; ")
                + ". Ask the technician which column, then call again. No value was given."
        case .notFound(.row, let asked, let available):
            return "No row matching \"\(asked)\" in that table"
                + (available.isEmpty ? "." : " (" + available.joined(separator: "; ") + ").")
                + " Do not take the nearest row instead: say the table has no such row, or ask for the row as printed."
        case .ambiguous(let part, let asked, let candidates):
            let what: String
            switch part {
            case .document: what = "manual"
            case .table: what = "table"
            case .row: what = "row"
            case .column: what = "column"
            }
            let retry = part == .table ? "Ask the technician which table or which book (pass 'document'), then call again."
                : "Ask the technician which \(what), then call again with it."
            return "More than one \(what) matches \"\(asked)\": " + candidates.joined(separator: "; ") + ". "
                + retry + " No value was given."
        case .notExtracted(let source):
            let table = source.table
            return "\(table.displayName) is printed on \(spokenPage(table.page)) of \(source.documentName), "
                + "but its grid could not be read from the PDF (\(reason(table.failure))), so there is no cell to give. "
                + "Do not answer from memory. Tell the technician, and offer to show the page with show_source.\n"
                + sourceLine(documentName: source.documentName, label: table.label, pages: [table.page])
        case .found(let found):
            return renderFound(found)
        }
    }

    private static func reason(_ failure: TableExtractor.Failure?) -> String {
        switch failure {
        case .noTextLayer: return "the page has no text layer"
        case .captionNotFound: return "the caption was not found on the page"
        case .tooFewRows: return "fewer than three rows came out of it"
        case .varyingColumnCount: return "its rows do not agree on their columns"
        case .mergedCells: return "it has cells spanning several columns"
        case .rotatedHeaders: return "its headings are set on their side"
        case nil: return "unknown"
        }
    }

    private static func cellText(_ cell: ManualTable.Cell) -> String {
        guard !cell.isEmpty else { return "(nothing printed)" }
        var text = "\"\(cell.text)\""
        if let value = cell.value {
            text += " (the number " + format(value) + (cell.unit.map { " \($0)" } ?? "") + ")"
        }
        return text
    }

    private static func renderFound(_ found: Found) -> String {
        let source = found.source
        let table = source.table
        var lines = ["\(table.displayName), \(source.documentName):"]
        func rowLine(_ row: ManualTable.Row) -> String {
            let cells = found.columns.map { index -> String in
                let cell = index < row.cells.count ? row.cells[index] : ManualTable.Cell(text: "")
                let column = index < table.columns.count ? columnName(table.columns[index]) : "column \(index + 1)"
                return "column \(column): \(cellText(cell))"
            }
            return "row \(rowName(row)) (\(spokenPage(row.page))) — " + cells.joined(separator: "; ")
        }
        if let value = found.between, found.rows.count == 2 {
            lines.append("\(format(value)) is not a row of this table; it falls between two rows:")
            lines += found.rows.map { "- " + rowLine($0) }
            lines.append("Say both rows and that \(format(value)) falls between them. Do not interpolate, round, "
                         + "or pick one: which row applies is the rule's call or the technician's.")
        } else {
            lines += found.rows.map(rowLine)
        }
        let notes = notes(for: found)
        if !notes.isEmpty {
            lines.append("Notes: " + notes.map { note in
                (note.marker.map { "[\(TableExtractor.superscripted($0))] " } ?? "") + note.text
            }.joined(separator: " | "))
        }
        if !found.unreadPages.isEmpty {
            lines.append("Part of this table, on " + found.unreadPages.map(spokenPage).joined(separator: ", ")
                         + ", could not be read, so rows printed there are not in this lookup.")
        }
        lines.append("Read the value out as printed, with its row, column and page. Do not interpolate, round, "
                     + "or move to another row.")
        lines.append(sourceLine(documentName: source.documentName, label: table.label, pages: pages(of: found)))
        return lines.joined(separator: "\n")
    }
}
