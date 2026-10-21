import Foundation

/// One check of a table read from a picture against the page it is printed on (Plan JN P3): a
/// person looked at the page and said what it prints in one cell, or that a row's name or a
/// column's heading was read right.
///
/// A check is keyed by the PDF it was made against (the SHA-256 of the file the table was read
/// from), the table's label, and the row's and column's **header paths** as they were read. Never
/// by position alone: a re-read that adds or drops a row cannot move a check onto another cell.
///
/// **`table-checks.json`**, the file the checks are kept in (in a vault, beside `chains.md`; in the
/// phone's own store for a vault the phone did not author; on the share sheet):
///
/// ```json
/// {
///   "version": 1,
///   "checks": [
///     {
///       "document_sha256": "<64 hex characters: the SHA-256 of the PDF>",
///       "table": "Table Q7",
///       "row": ["QMX90"],
///       "column": ["Spacing (mm)"],
///       "kind": "corrected",
///       "value": "35",
///       "checked_by": "the vault manager",
///       "checked_at": "2026-10-21T09:30:00Z",
///       "origin": "phone"
///     }
///   ]
/// }
/// ```
///
/// - `row` and `column` are the paths as the phone read them (outermost heading first). A cell's
///   check has both; a check of a row's name has `row` only; a check of a column's heading has
///   `column` only.
/// - `kind` is `confirmed` (the page prints what was read) or `corrected` (it prints `value`
///   instead). A row's name or a column's heading can only be `confirmed`.
/// - `value` is what the page prints in the cell, as printed, footnote marker included; empty when
///   the page prints nothing there. For a name or a heading it is not read.
/// - `checked_by` names who checked: the phone's name for whoever manages the vault, or the
///   reviewer the organisation's file names. `checked_at` is ISO 8601.
/// - `origin` is `phone` for a check made on a phone, and absent for one written by anyone else
///   (the organisation's office, by hand).
///
/// A version other than 1 is not read. An entry that does not read is warned of and skipped; one
/// for a PDF the vault does not hold is warned of and kept, and applies if that PDF is loaded.
struct TableCheck: Codable, Equatable, Hashable {

    enum Kind: String, Codable, CaseIterable {
        /// The page prints what was read.
        case confirmed
        /// The page prints `value` instead of what was read.
        case corrected
    }

    /// Where the check was made.
    enum Origin: String, Codable {
        /// On a phone, by whoever manages the vault there.
        case phone
        /// Written into a vault's file by anyone else: the organisation's office, or by hand.
        case vaultFile = "vault_file"
    }

    /// What a check is about.
    enum Target: Equatable, Hashable {
        case cell(row: [String], column: [String])
        case rowKey([String])
        case columnHeading([String])
    }

    /// The SHA-256 of the PDF the table was read from, lower-case hex.
    var documentHash: String
    /// The table's label as printed ("Table Q7").
    var table: String
    var row: [String]?
    var column: [String]?
    var kind: Kind
    var value: String
    var by: String
    var at: Date
    var origin: Origin

    init(documentHash: String, table: String, row: [String]?, column: [String]?, kind: Kind, value: String,
         by: String, at: Date, origin: Origin) {
        self.documentHash = documentHash
        self.table = table
        self.row = row
        self.column = column
        self.kind = kind
        self.value = value
        self.by = by
        self.at = at
        self.origin = origin
    }

    var target: Target? {
        switch (row, column) {
        case (let row?, let column?): return .cell(row: row, column: column)
        case (let row?, nil): return .rowKey(row)
        case (nil, let column?): return .columnHeading(column)
        case (nil, nil): return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case documentHash = "document_sha256"
        case table, row, column, kind, value
        case by = "checked_by"
        case at = "checked_at"
        case origin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentHash = try container.decode(String.self, forKey: .documentHash)
        table = try container.decode(String.self, forKey: .table)
        row = try container.decodeIfPresent([String].self, forKey: .row)
        column = try container.decodeIfPresent([String].self, forKey: .column)
        kind = try container.decode(Kind.self, forKey: .kind)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        by = try container.decode(String.self, forKey: .by)
        at = try container.decode(Date.self, forKey: .at)
        origin = try container.decodeIfPresent(Origin.self, forKey: .origin) ?? .vaultFile
    }

    /// `origin` is written only for a check made on a phone, so a file the office writes reads
    /// back the way it was written.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(documentHash, forKey: .documentHash)
        try container.encode(table, forKey: .table)
        try container.encodeIfPresent(row, forKey: .row)
        try container.encodeIfPresent(column, forKey: .column)
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
        try container.encode(by, forKey: .by)
        try container.encode(at, forKey: .at)
        if origin == .phone { try container.encode(origin, forKey: .origin) }
    }
}

/// Who checked one cell, and what they said it prints — what the check view and a lookup show.
struct TableCheckMark: Equatable {
    var value: String
    var by: String
    var at: Date
    var origin: TableCheck.Origin
    var kind: TableCheck.Kind
}

/// What the checks applied to one cell said (Plan JN P3).
enum TableCellCheck: Equatable {
    /// Every check of the cell gives the same value: the cell is that value, and certain.
    case agreed([TableCheckMark])
    /// Checks give different values: the cell is uncertain again, and every value is kept with
    /// who gave it until someone checks it again. Neither wins.
    case disagree([TableCheckMark])

    var marks: [TableCheckMark] {
        switch self {
        case .agreed(let marks), .disagree(let marks): return marks
        }
    }

    /// The latest check of an agreed cell, nil when the checks disagree.
    var agreedMark: TableCheckMark? {
        if case .agreed(let marks) = self { return marks.max { $0.at < $1.at } }
        return nil
    }

    var isDisagreement: Bool {
        if case .disagree = self { return true }
        return false
    }
}

// MARK: - The file

/// `table-checks.json`: read leniently (a bad entry is skipped with a warning, the rest are kept),
/// written in one shape. See [[TableCheck]] for the schema.
enum TableChecksFile {
    static let fileName = "table-checks.json"
    static let version = 1
    /// A file over this is not read.
    static let maximumBytes = 1_048_576
    static let maximumEntries = 5_000
    /// Longest label, path heading or value.
    static let maximumText = 200
    /// Longest `checked_by`.
    static let maximumName = 120
    static let maximumPathDepth = 8

    struct Parsed: Equatable {
        var checks: [TableCheck] = []
        /// What was skipped and why, for the import's warnings. Never cell text.
        var problems: [String] = []
    }

    static func isChecksFile(_ filename: String) -> Bool {
        (filename as NSString).lastPathComponent.lowercased() == fileName
    }

    /// Reads a file's checks. Every entry that does not read, or reads and breaks a rule, is a
    /// problem naming its position, and is skipped; the rest are kept.
    static func parse(_ data: Data) -> Parsed {
        guard data.count <= maximumBytes else {
            return Parsed(problems: ["\(fileName) is larger than \(maximumBytes / 1_048_576) MB, so it was not read"])
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Parsed(problems: ["\(fileName) is not a JSON object with \"version\" and \"checks\", so it was not read"])
        }
        guard let version = object["version"] as? Int, version == Self.version else {
            let found = (object["version"]).map { "\($0)" } ?? "none"
            return Parsed(problems: ["\(fileName) has version \(found); this app reads version \(Self.version), so it was not read"])
        }
        guard let entries = object["checks"] as? [Any] else {
            return Parsed(problems: ["\(fileName) has no \"checks\" list, so no check was read"])
        }
        var parsed = Parsed()
        if entries.count > maximumEntries {
            parsed.problems.append("\(fileName) has \(entries.count) checks; the first \(maximumEntries) were read")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for (index, entry) in entries.prefix(maximumEntries).enumerated() {
            let position = "\(fileName) entry \(index + 1)"
            guard JSONSerialization.isValidJSONObject(entry),
                  let entryData = try? JSONSerialization.data(withJSONObject: entry) else {
                parsed.problems.append("\(position): is not an object; skipped"); continue
            }
            let check: TableCheck
            do {
                check = try decoder.decode(TableCheck.self, from: entryData)
            } catch {
                parsed.problems.append("\(position): \(decodingProblem(error)); skipped"); continue
            }
            if let problem = problem(of: check) {
                parsed.problems.append("\(position): \(problem); skipped"); continue
            }
            parsed.checks.append(check)
        }
        return parsed
    }

    /// Why a check that decoded still cannot be kept, or nil.
    static func problem(of check: TableCheck) -> String? {
        if check.documentHash.count != 64
            || !check.documentHash.unicodeScalars.allSatisfy({ "0123456789abcdef".unicodeScalars.contains($0) }) {
            return "document_sha256 is not 64 lower-case hex characters"
        }
        let label = check.table.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty || label.count > maximumText { return "table is empty or longer than \(maximumText) characters" }
        guard let target = check.target else { return "it names neither a row nor a column" }
        for path in [check.row, check.column].compactMap({ $0 }) {
            if path.isEmpty || path.count > maximumPathDepth { return "a row or column path is empty or deeper than \(maximumPathDepth)" }
            if path.contains(where: { $0.count > maximumText }) { return "a heading is longer than \(maximumText) characters" }
        }
        if check.value.count > maximumText { return "value is longer than \(maximumText) characters" }
        let name = check.by.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > maximumName { return "checked_by is empty or longer than \(maximumName) characters" }
        if check.by.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            || check.value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "a field holds a control character"
        }
        if check.kind == .corrected, target != .cell(row: check.row ?? [], column: check.column ?? []) {
            return "a row's name or a column's heading can be confirmed, not corrected"
        }
        return nil
    }

    private static func decodingProblem(_ error: Error) -> String {
        switch error as? DecodingError {
        case .keyNotFound(let key, _)?: return "\"\(key.stringValue)\" is missing"
        case .typeMismatch(_, let context)?, .valueNotFound(_, let context)?:
            return "\"\(context.codingPath.last?.stringValue ?? "a field")\" has the wrong type"
        case .dataCorrupted(let context)?:
            return "\"\(context.codingPath.last?.stringValue ?? "a field")\" does not read"
        default: return "does not read"
        }
    }

    /// The file as it is written: version 1, the checks in a stable order, ISO 8601 dates.
    static func encode(_ checks: [TableCheck]) throws -> Data {
        struct File: Encodable {
            let version: Int
            let checks: [TableCheck]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(File(version: version, checks: TableChecks.ordered(checks)))
    }

    /// One warning per PDF the checks are for that the vault does not hold: kept, applied if that
    /// PDF is loaded. Names the hash's first 12 characters and a count, never a value.
    static func unknownDocumentWarnings(_ checks: [TableCheck], known: Set<String>) -> [String] {
        var counts: [String: Int] = [:]
        for check in checks where !known.contains(check.documentHash) { counts[check.documentHash, default: 0] += 1 }
        return counts.keys.sorted().map { hash in
            let count = counts[hash] ?? 0
            return "\(fileName): \(count) check\(count == 1 ? " is" : "s are") for a PDF this vault does not hold "
                + "(\(hash.prefix(12))…); kept, and applied if that PDF is loaded"
        }
    }
}

// MARK: - Applying checks

/// Merges checks into tables read from a picture (Plan JN P3). Pure.
///
/// - A cell every check of which gives the same value takes that value (parsed as an extracted
///   cell is: number, unit, markers) and is no longer uncertain.
/// - A cell checked to two different values is uncertain again, keeps what was read, and carries
///   every value with who gave it. It is never given; neither value wins.
/// - A row's name or a column's heading confirmed is no longer uncertain.
/// - A check that matches no table, row or column (or matches more than one) changes nothing and
///   is reported, never applied elsewhere. Checks never apply to a table off the text layer.
enum TableChecks {

    /// Where a table read from a picture stands.
    enum Status: Equatable {
        /// Some cells, or none, are checked.
        case notChecked(checked: Int, cells: Int)
        /// Every cell is checked, and no row name or column heading is left unclear.
        case checked
        /// Checks of `cells` cells give different values.
        case disagree(cells: Int)
    }

    struct Applied: Equatable {
        var table: ManualTable
        /// Checks addressed to this table that changed it.
        var applied: [TableCheck] = []
        /// Checks addressed to this table that match nothing in it.
        var unmatched: [TableCheck] = []
    }

    /// Headings and values compared with their spacing made plain.
    static func normalised(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func samePath(_ a: [String], _ b: [String]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { normalised($0) == normalised($1) }
    }

    static func sameLabel(_ a: String, _ b: String) -> Bool {
        normalised(a).caseInsensitiveCompare(normalised(b)) == .orderedSame
    }

    /// Whether `check` is about this table of this PDF.
    static func addresses(_ check: TableCheck, table: ManualTable, documentHash: String?) -> Bool {
        guard let documentHash else { return false }
        return check.documentHash == documentHash && sameLabel(check.table, table.label)
    }

    private struct TargetKey: Hashable {
        let row: [String]?
        let column: [String]?
        init(_ check: TableCheck) {
            row = check.row.map { $0.map(TableChecks.normalised) }
            column = check.column.map { $0.map(TableChecks.normalised) }
        }
    }

    /// `checks` applied to `table`, read from the PDF of `documentHash`. With `requireChecked`
    /// (the organisation's `organizationRequiresTableChecks`), a table read from a picture that is
    /// not checked comes back withheld: a lookup on it gives no value.
    static func apply(_ checks: [TableCheck], to table: ManualTable, documentHash: String?,
                      requireChecked: Bool = false) -> Applied {
        let relevant = checks.filter { addresses($0, table: table, documentHash: documentHash) }
        var result = Applied(table: table)
        guard table.source.isRecognised, table.isExtracted else {
            result.unmatched = relevant
            return result
        }
        var groups: [TargetKey: [TableCheck]] = [:]
        var order: [TargetKey] = []
        for check in relevant {
            let key = TargetKey(check)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(check)
        }
        for key in order {
            let group = groups[key] ?? []
            if apply(group, to: &result.table) {
                result.applied += group
            } else {
                result.unmatched += group
            }
        }
        if requireChecked, status(of: result.table) != .checked { result.table.uncheckedWithheld = true }
        return result
    }

    /// One target's checks onto the table. False when the target is not in it exactly once.
    private static func apply(_ group: [TableCheck], to table: inout ManualTable) -> Bool {
        guard let first = group.first, let target = first.target else { return false }
        func rowIndex(_ path: [String]) -> Int? {
            let found = table.rows.indices.filter { samePath(table.rows[$0].path, path) }
            return found.count == 1 ? found[0] : nil
        }
        func columnIndex(_ path: [String]) -> Int? {
            let found = table.columns.indices.filter { samePath(table.columns[$0].path, path) }
            return found.count == 1 ? found[0] : nil
        }
        switch target {
        case .rowKey(let path):
            guard group.allSatisfy({ $0.kind == .confirmed }), let row = rowIndex(path) else { return false }
            table.rows[row].keyUncertain = false
            return true
        case .columnHeading(let path):
            guard group.allSatisfy({ $0.kind == .confirmed }), let column = columnIndex(path) else { return false }
            table.columns[column].uncertain = false
            return true
        case .cell(let rowPath, let columnPath):
            guard let row = rowIndex(rowPath), let column = columnIndex(columnPath),
                  column < table.rows[row].cells.count else { return false }
            let marks = group.map { TableCheckMark(value: $0.value, by: $0.by, at: $0.at, origin: $0.origin, kind: $0.kind) }
                .sorted { $0.at < $1.at }
            let values = Set(group.map { normalised($0.value) })
            var cell = table.rows[row].cells[column]
            if values.count == 1, let value = marks.last?.value {
                if normalised(value) != normalised(cell.text) {
                    cell = TableExtractor.parseCell(value, markers: [], columnUnit: table.columns[column].unit)
                }
                cell.uncertain = false
                cell.check = .agreed(marks)
            } else {
                cell.uncertain = true
                cell.check = .disagree(marks)
            }
            table.rows[row].cells[column] = cell
            return true
        }
    }

    /// Checks applied across many tables, with the checks that matched none of them.
    static func apply(_ checks: [TableCheck], to tables: [(documentHash: String?, table: ManualTable)],
                      requireChecked: Bool = false) -> (tables: [ManualTable], unmatched: [TableCheck]) {
        var out: [ManualTable] = []
        var used = Set<TableCheck>()
        var unmatched: [TableCheck] = []
        for entry in tables {
            let applied = apply(checks, to: entry.table, documentHash: entry.documentHash, requireChecked: requireChecked)
            out.append(applied.table)
            applied.applied.forEach { used.insert($0) }
            unmatched += applied.unmatched
        }
        // A check for no table of these at all — another PDF, or a label not stored.
        let addressedNothing = checks.filter { check in
            !used.contains(check) && !unmatched.contains(check)
        }
        return (out, unmatched + addressedNothing)
    }

    /// Where a table read from a picture stands once checks are applied; nil for a table off the
    /// text layer or one whose grid was not read, which have nothing to check.
    static func status(of table: ManualTable) -> Status? {
        guard table.source.isRecognised, table.isExtracted else { return nil }
        let cells = table.rows.flatMap { row in row.cells.prefix(table.columns.count) }
        let disagree = cells.filter { $0.check?.isDisagreement == true }.count
        if disagree > 0 { return .disagree(cells: disagree) }
        let checked = cells.filter { $0.check?.agreedMark != nil }.count
        if checked == cells.count, !cells.isEmpty,
           !table.rows.contains(where: \.keyUncertain), !table.columns.contains(where: \.uncertain) {
            return .checked
        }
        return .notChecked(checked: checked, cells: cells.count)
    }

    // MARK: Keeping checks

    /// `existing` with `check` recorded: any earlier check of the same target in the same table of
    /// the same PDF is replaced, so checking a cell again settles it.
    static func recording(_ check: TableCheck, into existing: [TableCheck]) -> [TableCheck] {
        existing.filter { other in
            !(other.documentHash == check.documentHash && sameLabel(other.table, check.table)
              && TargetKey(other) == TargetKey(check))
        } + [check]
    }

    /// `existing` without the checks of the PDFs of `documentHashes`.
    static func forgetting(documentHashes: Set<String>, from existing: [TableCheck]) -> [TableCheck] {
        existing.filter { !documentHashes.contains($0.documentHash) }
    }

    /// Two lists as one, an exact duplicate kept once.
    static func merged(_ first: [TableCheck], _ second: [TableCheck]) -> [TableCheck] {
        var seen = Set<TableCheck>()
        return (first + second).filter { seen.insert($0).inserted }
    }

    /// A stable order for a written file: by PDF, table, row, column, then time.
    static func ordered(_ checks: [TableCheck]) -> [TableCheck] {
        checks.sorted { a, b in
            let left = [a.documentHash, a.table, (a.row ?? []).joined(separator: "\u{1F}"),
                        (a.column ?? []).joined(separator: "\u{1F}")]
            let right = [b.documentHash, b.table, (b.row ?? []).joined(separator: "\u{1F}"),
                         (b.column ?? []).joined(separator: "\u{1F}")]
            if left != right { return left.lexicographicallyPrecedes(right) }
            return a.at < b.at
        }
    }

    // MARK: Saying it

    /// "2026-10-21" — the day a check was made, as a lookup says it: the day on the phone's own
    /// clock (Plan JN P4), so a check made just after midnight in New Zealand is not said as the day
    /// before. The check itself is stored as an ISO-8601 instant in UTC; only the saying is local.
    static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    /// "checked by the vault manager on 2026-10-21".
    static func checkedNote(_ mark: TableCheckMark) -> String {
        "checked by \(mark.by) on \(day(mark.at))"
    }
}
