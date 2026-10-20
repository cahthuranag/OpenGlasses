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
        let source: Source, unread: [ManualTable.Page]
        switch resolveTable(request, in: sources) {
        case .failure(let refusal): return refusal.outcome
        case .success(let resolved): (source, unread) = resolved
        }
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

    /// An outcome that ends a lookup before its row is read, as an error so it can travel in a
    /// `Result`.
    struct Refusal: Error { let outcome: Outcome }

    /// The one table a request names — the read grid, with the pages of it that were not read —
    /// or the outcome that says why there is not one.
    static func resolveTable(_ request: Request, in sources: [Source])
        -> Result<(source: Source, unread: [ManualTable.Page]), Refusal> {
        guard !sources.isEmpty else { return .failure(Refusal(outcome: .noTables)) }
        var pool = sources
        if let document = request.document?.trimmingCharacters(in: .whitespacesAndNewlines), !document.isEmpty {
            let exact = sources.filter { $0.documentName.localizedCaseInsensitiveContains(document) }
            pool = exact.isEmpty ? sources.filter { ManualDocumentChoice.matches($0.documentName, requested: document) } : exact
            guard !pool.isEmpty else {
                return .failure(Refusal(outcome: .notFound(.document, asked: document,
                                                           available: orderedUnique(sources.map(\.documentName)))))
            }
        }

        // The table: by label, then by title words.
        let candidates: [Source]
        let printed = pool.map(\.table.label)
        if let label = TableReference.labels(in: request.table, among: printed).first ?? bareLabel(request.table) {
            candidates = pool.filter { $0.table.label.caseInsensitiveCompare(label) == .orderedSame }
            guard !candidates.isEmpty else {
                return .failure(Refusal(outcome: .notFound(.table, asked: label, available: availableTables(pool))))
            }
        } else {
            candidates = byTitle(request.table, in: pool)
            guard !candidates.isEmpty else {
                return .failure(Refusal(outcome: .notFound(.table, asked: request.table, available: availableTables(pool))))
            }
        }
        // One table per document: the grid that was read wins over a page of it that was not.
        let documents = orderedUnique(candidates.map(\.documentId))
        let tables = Set(candidates.map { "\($0.documentId)#\($0.table.label.lowercased())" })
        guard documents.count == 1, tables.count == 1 else {
            return .failure(Refusal(outcome: .ambiguous(.table, asked: request.table, candidates: orderedUnique(
                candidates.map { "\($0.table.displayName) in \($0.documentName)" }))))
        }
        let read = candidates.filter(\.table.isExtracted)
        guard let source = read.first else { return .failure(Refusal(outcome: .notExtracted(candidates[0]))) }
        return .success((source, candidates.filter { !$0.table.isExtracted }.map(\.table.page)))
    }

    /// "99", "No. 99", "95A" or "Q7" asked for as the table.
    private static func bareLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^(?:no\.?\s*|#)?[A-Za-z]{0,2}\d{1,4}[A-Za-z]?$"#,
                            options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return TableReference.labels(in: "table " + trimmed).first
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
        // By path: the whole path, or the end of it ("Band B" under one group only) — as printed,
        // then with the units in brackets left out on both sides (Plan JJ P5: a chain writes
        // "Band A" for a heading printed "Band A (A)").
        for strip in [false, true] {
            let key = normalised(strip ? withoutUnits(asked) : asked)
            guard !key.isEmpty else { continue }
            let byPath = all.filter { index in
                suffixes(table.columns[index].path.map { strip ? withoutUnits($0) : $0 }).contains(key)
            }
            if byPath.count == 1 { return .resolved(byPath) }
            if byPath.count > 1 {
                let whole = byPath.filter {
                    normalised(table.columns[$0].path.map { strip ? withoutUnits($0) : $0 }.joined(separator: " ")) == key
                }
                return whole.count == 1 ? .resolved(whole) : .ambiguous(byPath.map { columnName(table.columns[$0]) })
            }
        }
        // By words, in any order: with the units, then — when they fit no column, or several —
        // without them, so a unit said another way ("amps" for "A") or left out decides nothing.
        let paths = all.map { table.columns[$0].path }
        var match = bestByWords(asked, among: paths)
        if case .one = match {} else {
            let bare = bestByWords(withoutUnits(asked), among: paths.map { $0.map(withoutUnits) })
            switch (match, bare) {
            case (_, .one): match = bare
            case (.none, .several): match = bare
            default: break
            }
        }
        switch match {
        case .one(let index): return .resolved([all[index]])
        case .several(let indexes): return .ambiguous(indexes.map { columnName(table.columns[all[$0]]) })
        case .none: return .none
        }
    }

    /// A heading or asked words with every bracketed unit taken out: "(A)", "[mm²]", "(°C)",
    /// "(amps)" — a bracket of one short word. Words in brackets ("(see note)") stay.
    static func withoutUnits(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s*[\(\[]\s*[^()\[\]\s]{1,10}\s*[\)\]]"#) else { return text }
        let ns = text as NSString
        var out = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let inner = ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: " ()[]"))
            guard inner.contains(where: { $0.isLetter || "%\u{00B0}\u{00B5}\u{03A9}".contains($0) }),
                  let range = Range(match.range, in: out) else { continue }
            out.replaceSubrange(range, with: "")
        }
        return out.trimmingCharacters(in: .whitespaces)
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
            if let range = printedRange(text) { return range }
            let cell = TableExtractor.parseCell(text, markers: [], columnUnit: nil)
            if let value = cell.value, text.range(of: #"^[-+\u{2212}]?[\d.,]+"#, options: .regularExpression) != nil {
                return (value, value, { $0 == value })
            }
        }
        return nil
    }

    private static let rangeNumber = #"(\d+(?:[.,]\d+)?)"#
    private static let rangeUnit = #"(?:\s*[^\s\d.,]{1,6})?"#
    /// "7-9", "7 – 9", "7 to 9", "7 through 9", "from 7 to 9", "7 A to 9 A": both ends included.
    private static let closedRange = try! NSRegularExpression(
        pattern: #"^(?:from\s+)?"# + rangeNumber + rangeUnit + #"\s*(?:-|\x{2013}|\x{2014}|to|through|thru)\s*"#
            + rangeNumber + rangeUnit + #"(?:\s*(?:incl\.?|inclusive))?$"#, options: [.caseInsensitive])
    /// "over 15 up to 18", "above 15 to 18", "more than 15 but not more than 18": above the first
    /// number, up to and including the second.
    private static let openLowRange = try! NSRegularExpression(
        pattern: #"^(?:over|above|more\s+than|greater\s+than|exceeding)\s+"# + rangeNumber + rangeUnit
            + #"\s+(?:(?:and\s+)?up\s+to|to|but\s+not\s+(?:over|more\s+than|exceeding))\s+"# + rangeNumber + rangeUnit + "$",
        options: [.caseInsensitive])

    /// A row key printed as a range (Plan JJ P1, widened in P5 to the ranges a book prints in
    /// words), as the interval it covers.
    private static func printedRange(_ text: String) -> (lower: Double, upper: Double, contains: (Double) -> Bool)? {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func bounds(_ match: NSTextCheckingResult) -> (Double, Double)? {
            let parts = [1, 2].compactMap { Double(ns.substring(with: match.range(at: $0)).replacingOccurrences(of: ",", with: ".")) }
            return parts.count == 2 && parts[0] <= parts[1] ? (parts[0], parts[1]) : nil
        }
        if let match = closedRange.firstMatch(in: text, range: whole), let (low, high) = bounds(match) {
            return (low, high, { $0 >= low && $0 <= high })
        }
        if let match = openLowRange.firstMatch(in: text, range: whole), let (low, high) = bounds(match) {
            return (low, high, { $0 > low && $0 <= high })
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
        case .noTextInTable: return "the table is printed with no text the PDF can give, most likely as a picture"
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

// MARK: - Row rules (Plan JJ P2)

/// What a rule chain's `lookup` step asks of a table beyond P1's lookup: which row a rule wants
/// when the asked number is not a row of its own, and the row whose cell in a column meets a
/// number. The rule is the chain's, written by the organisation (decision 2): the lookup itself
/// still never interpolates, rounds or picks a row on its own.
extension TableLookup {

    enum RowRule: String, CaseIterable, Equatable, Codable {
        /// The row whose key is the number, or a printed range that holds it ("8" in "7-9").
        case exact
        /// That row, else the first row whose key is at or above the number.
        case atLeast = "at_least"
        /// That row, else the last row whose key is at or below the number.
        case atMost = "at_most"
    }

    /// `resolve` with a row rule applied. `exact` is `resolve` unchanged — a number between two
    /// rows comes back with both, and the chain stops on it. `at_least` takes the upper of the two
    /// rows, `at_most` the lower; a number below every row is `at_least` the first, and one above
    /// every row `at_most` the last. Anything else is what `resolve` said.
    static func resolve(_ request: Request, rule: RowRule, in sources: [Source]) -> Outcome {
        let outcome = resolve(request, in: sources)
        guard rule != .exact else { return outcome }
        switch outcome {
        case .found(let found) where found.between != nil && found.rows.count == 2:
            let row = rule == .atLeast ? found.rows[1] : found.rows[0]
            return .found(Found(source: found.source, rows: [row], columns: found.columns, between: nil,
                                unreadPages: found.unreadPages))
        case .notFound(.row, _, _):
            guard let value = number(in: request.row),
                  case .success(let resolved) = resolveTable(request, in: sources),
                  case .resolved(let columns) = resolveColumn(request.column, in: resolved.source.table) else {
                return outcome
            }
            let keyed = resolved.source.table.rows.compactMap { row in
                numericKey(of: row).map { (row: row, lower: $0.lower, upper: $0.upper) }
            }
            var pick: ManualTable.Row?
            if rule == .atLeast, let lowest = keyed.map(\.lower).min(), value < lowest {
                pick = keyed.first { $0.lower == lowest }?.row
            } else if rule == .atMost, let highest = keyed.map(\.upper).max(), value > highest {
                pick = keyed.last { $0.upper == highest }?.row
            }
            guard let pick else { return outcome }
            return .found(Found(source: resolved.source, rows: [pick], columns: columns, between: nil,
                                unreadPages: resolved.unread))
        default:
            return outcome
        }
    }

    /// What searching one column for a number came to.
    enum CellSearch: Equatable {
        /// One row, one column: the cell that meets the rule.
        case found(Found)
        /// The table or the column did not resolve to one; the outcome says why.
        case refused(Outcome)
        /// No cell in the column meets the rule. `range` is what the column's numbers run over.
        case none(Source, column: Int, range: ClosedRange<Double>?)
        /// Under `exact`, more than one cell holds the number.
        case several(Source, column: Int, rows: [ManualTable.Row])
    }

    /// The row whose cell in the named column meets `value` under `rule`: `exact` a cell holding
    /// the number; `at_least` the smallest cell at or above it; `at_most` the largest at or below
    /// it — the first printed of equal cells for `at_least`, the last for `at_most`. The column
    /// must resolve to exactly one. `request.row` is not read.
    static func search(_ request: Request, value: Double, rule: RowRule, in sources: [Source]) -> CellSearch {
        let resolved: (source: Source, unread: [ManualTable.Page])
        switch resolveTable(request, in: sources) {
        case .failure(let refusal): return .refused(refusal.outcome)
        case .success(let found): resolved = found
        }
        let table = resolved.source.table
        let column: Int
        switch resolveColumn(request.column, in: table) {
        case .resolved(let found) where found.count == 1: column = found[0]
        case .resolved(let found):
            return .refused(.ambiguous(.column, asked: request.column ?? "",
                                       candidates: found.map { columnName(table.columns[$0]) }))
        case .ambiguous(let names): return .refused(.ambiguous(.column, asked: request.column ?? "", candidates: names))
        case .none:
            return .refused(.notFound(.column, asked: request.column ?? "", available: table.columns.map(columnName)))
        }
        let numbered = table.rows.compactMap { row -> (row: ManualTable.Row, value: Double)? in
            guard column < row.cells.count, let number = row.cells[column].value else { return nil }
            return (row, number)
        }
        let values = numbered.map(\.value)
        let range = values.min().flatMap { low in values.max().map { low...$0 } }
        let chosen: [ManualTable.Row]
        switch rule {
        case .exact:
            chosen = numbered.filter { $0.value == value }.map(\.row)
            if chosen.count > 1 { return .several(resolved.source, column: column, rows: chosen) }
        case .atLeast:
            let best = numbered.filter { $0.value >= value }.map(\.value).min()
            chosen = best.map { best in numbered.filter { $0.value == best }.prefix(1).map(\.row) } ?? []
        case .atMost:
            let best = numbered.filter { $0.value <= value }.map(\.value).max()
            chosen = best.map { best in numbered.filter { $0.value == best }.suffix(1).map(\.row) } ?? []
        }
        guard let row = chosen.first else { return .none(resolved.source, column: column, range: range) }
        return .found(Found(source: resolved.source, rows: [row], columns: [column], between: nil,
                            unreadPages: resolved.unread))
    }

    /// The row printed after `row`, for "the next row is …".
    static func nextRow(after row: ManualTable.Row, in table: ManualTable) -> ManualTable.Row? {
        guard let index = table.rows.firstIndex(of: row), index + 1 < table.rows.count else { return nil }
        return table.rows[index + 1]
    }
}
