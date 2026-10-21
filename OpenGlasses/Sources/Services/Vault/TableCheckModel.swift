import Foundation

/// What the check view of one table read from a picture shows and writes (Plan JN P3). Pure: the
/// table as it was read and the checks that apply in, the grid's states and the checks a tap makes
/// out, so the screen holds no rule of its own.
struct TableCheckModel: Equatable {

    /// One cell, heading or row name as the grid shows it.
    enum State: Equatable {
        /// Read clearly and not checked yet.
        case read
        /// Not clear enough to give, and not checked.
        case uncertain
        /// Checked against the page; the latest check.
        case checked(TableCheckMark)
        /// Checks give different values; every one, oldest first.
        case disagree([TableCheckMark])
    }

    let documentHash: String
    /// The table as it was read, before any check.
    let original: ManualTable
    /// The checks that apply to it, from wherever they are kept.
    private(set) var checks: [TableCheck]
    /// The table with the checks applied.
    private(set) var table: ManualTable

    init(table: ManualTable, documentHash: String, checks: [TableCheck]) {
        self.documentHash = documentHash
        self.original = table
        self.checks = checks.filter { TableChecks.addresses($0, table: table, documentHash: documentHash) }
        self.table = TableChecks.apply(self.checks, to: table, documentHash: documentHash).table
    }

    /// The same table with `checks` in place of the ones it had.
    func with(checks: [TableCheck]) -> TableCheckModel {
        TableCheckModel(table: original, documentHash: documentHash, checks: checks)
    }

    var status: TableChecks.Status? { TableChecks.status(of: table) }

    /// Checks addressed to this table that match no row or column in it, kept and not applied.
    var unmatched: [TableCheck] {
        TableChecks.apply(checks, to: original, documentHash: documentHash).unmatched
    }

    /// Whether the view offers "Share checks". A photographed manual's checks are keyed by its
    /// capture revision's digest, which no other phone holds, so a shared file would only import as
    /// unmatched checks: offered for vault tables only.
    static func offersSharing(photographed: Bool) -> Bool { !photographed }

    // MARK: The grid

    func cell(row: Int, column: Int) -> ManualTable.Cell? {
        guard row < table.rows.count, column < table.rows[row].cells.count else { return nil }
        return table.rows[row].cells[column]
    }

    /// What was read in a cell, before any check.
    func readText(row: Int, column: Int) -> String? {
        guard row < original.rows.count, column < original.rows[row].cells.count else { return nil }
        return original.rows[row].cells[column].text
    }

    func state(row: Int, column: Int) -> State {
        guard let cell = cell(row: row, column: column) else { return .read }
        switch cell.check {
        case .agreed?: return cell.check?.agreedMark.map(State.checked) ?? .read
        case .disagree(let marks)?: return .disagree(marks)
        case nil: return cell.uncertain ? .uncertain : .read
        }
    }

    /// A row's name: uncertain until confirmed, read otherwise. Confirmed only clears it.
    func rowKeyIsUncertain(_ row: Int) -> Bool { row < table.rows.count && table.rows[row].keyUncertain }

    func headingIsUncertain(_ column: Int) -> Bool { column < table.columns.count && table.columns[column].uncertain }

    // MARK: Making checks

    /// The check a person makes by saying what the page prints in a cell: confirmed when it is what
    /// was read, corrected otherwise. Nil off the grid.
    func check(row: Int, column: Int, value: String, by: String, at: Date) -> TableCheck? {
        guard row < original.rows.count, column < original.columns.count,
              let read = readText(row: row, column: column) else { return nil }
        let typed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: TableCheck.Kind = TableChecks.normalised(typed) == TableChecks.normalised(read) ? .confirmed : .corrected
        return TableCheck(documentHash: documentHash, table: original.label, row: original.rows[row].path,
                          column: original.columns[column].path, kind: kind, value: typed, by: by, at: at, origin: .phone)
    }

    /// Confirming a row's name as read.
    func confirmRowKey(_ row: Int, by: String, at: Date) -> TableCheck? {
        guard row < original.rows.count else { return nil }
        return TableCheck(documentHash: documentHash, table: original.label, row: original.rows[row].path, column: nil,
                          kind: .confirmed, value: original.rows[row].path.joined(separator: ManualTable.Column.pathSeparator),
                          by: by, at: at, origin: .phone)
    }

    /// Confirming a column's heading as read.
    func confirmHeading(_ column: Int, by: String, at: Date) -> TableCheck? {
        guard column < original.columns.count else { return nil }
        return TableCheck(documentHash: documentHash, table: original.label, row: nil, column: original.columns[column].path,
                          kind: .confirmed, value: original.columns[column].name, by: by, at: at, origin: .phone)
    }

    /// "Mark table checked": a confirmation of every cell read clearly and not checked yet. An
    /// uncertain cell, a disagreeing one, and an unclear name or heading are left for a person to
    /// look at one by one.
    func confirmRemaining(by: String, at: Date) -> [TableCheck] {
        var out: [TableCheck] = []
        for row in table.rows.indices {
            for column in table.columns.indices where state(row: row, column: column) == .read {
                if let read = readText(row: row, column: column),
                   let check = check(row: row, column: column, value: read, by: by, at: at) {
                    out.append(check)
                }
            }
        }
        return out
    }

    /// How many cells, names and headings still need a person: uncertain or disagreeing.
    var needsLooking: Int {
        var count = table.rows.indices.filter(rowKeyIsUncertain).count + table.columns.indices.filter(headingIsUncertain).count
        for row in table.rows.indices {
            for column in table.columns.indices {
                switch state(row: row, column: column) {
                case .uncertain, .disagree: count += 1
                default: break
                }
            }
        }
        return count
    }
}
