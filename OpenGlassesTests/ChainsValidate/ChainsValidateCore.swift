import Foundation
#if canImport(OpenGlasses)
@testable import OpenGlasses
#endif

/// The chains validator (Plan JJ P4): a vault's `chains.md` checked against the tables its own
/// PDFs print, before anyone carries it to a phone.
///
/// Shared by two runners so both check the same thing:
/// - `ChainsValidateCoreTests` in the simulator, on invented fixture tables;
/// - `Scripts/chains-validate` on a Mac, which compiles this file with the app's real
///   `ChainParser`, `TableLookup`, `TableExtractor` and `PDFTableReader` and reads the vault's
///   PDFs as an import does.
///
/// It reports the chains parsed and their steps, every parse problem by its line and kind, and for
/// every `lookup` — those in a chain with a problem included — whether its table is among the
/// extracted tables, and whether its row and column resolve against that table's headers. **Names
/// come only from the chains file**: a row or column printed is the one the chain wrote, never a
/// header, a cell, a title or a candidate read from the book, so the output of a run over a
/// licensed book carries nothing of the book. `render(_:names: false)` leaves out even those and
/// prints counts and line numbers only.
enum ChainsValidate {

    // MARK: - Input

    struct Input {
        /// The chains file's name as the manifest would list it ("chains.md").
        var fileName: String
        var contents: String
        /// The manifest's `files`, or nil when the vault has no manifest to read.
        var listedFiles: [String]?
        /// Every table the vault's documents store, read or not (`PDFTableReader.Result.stored`).
        var tables: [ManualTable]
    }

    // MARK: - Report

    enum ManifestState: String, Equatable {
        case lists = "yes"
        case doesNotList = "no"
        case noManifest = "no_manifest"
    }

    enum TableState: String, Equatable, CaseIterable {
        /// Extracted to a grid.
        case read
        /// Its caption was found and its grid was not read: the chain stops on it with the page.
        case unread
        /// No document's tables carry the label.
        case missing
    }

    /// How a row, a column or a cell number written in a lookup fares against the table.
    enum Resolution: String, Equatable, CaseIterable {
        /// Written out, and it names one row or column.
        case resolved
        /// Written out, and it fits more than one.
        case ambiguous
        /// A number written out that falls between two rows, under `exact`: the chain would stop.
        case betweenRows = "between_rows"
        /// Written out, or written with values in it, and nothing fits.
        case unresolved
        /// Words with a value in them ("Rating group {group}"): some heading fits the pattern.
        case patternMatches = "pattern_matches"
        /// Nothing but a value ("{size}"): known only when the chain runs.
        case fromValue = "from_a_value"
        /// No column named on a table with more than one: the chain would stop.
        case notNamed = "not_named"
        /// The table is missing or unread, so there are no headings to check against.
        case notChecked = "not_checked"
    }

    struct Part: Equatable {
        /// As the chain wrote it.
        var written: String?
        var resolution: Resolution
    }

    struct LookupCheck: Equatable {
        var chain: String
        var line: Int
        /// The label as the chain names it.
        var table: String
        var tableState: TableState
        /// Nil in the `cell` form.
        var row: Part?
        var column: Part
        /// The number searched for, in the `cell` form.
        var cell: Part?
        /// Why an unread table's grid was not read, as the extractor names it (Plan JJ P5).
        var unreadBecause: TableExtractor.Failure? = nil
        /// Columns of the read table printed with no heading over them.
        var unnamedColumns = 0
        /// The read table's rows and value columns, as counts.
        var readSize: (rows: Int, columns: Int)? = nil

        static func == (a: LookupCheck, b: LookupCheck) -> Bool {
            a.chain == b.chain && a.line == b.line && a.table == b.table && a.tableState == b.tableState
                && a.row == b.row && a.column == b.column && a.cell == b.cell && a.unreadBecause == b.unreadBecause
                && a.unnamedColumns == b.unnamedColumns && a.readSize?.rows == b.readSize?.rows
                && a.readSize?.columns == b.readSize?.columns
        }
    }

    struct ChainSummary: Equatable {
        var name: String
        var line: Int
        var steps: Int
        var lookups: Int
    }

    struct ProblemEntry: Equatable {
        var line: Int
        var chain: String?
        var kind: String
        var message: String
    }

    struct Report: Equatable {
        var fileName: String
        var manifest: ManifestState
        var tablesStored: Int
        var tablesRead: Int
        /// `##` headings in the file: the chains written, with a problem or without.
        var headings: Int
        var chains: [ChainSummary]
        var problems: [ProblemEntry]
        var lookups: [LookupCheck]

        func problemCounts() -> [(kind: String, count: Int)] {
            var counts: [String: Int] = [:]
            for problem in problems { counts[problem.kind, default: 0] += 1 }
            return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
    }

    // MARK: - Checking

    static func check(_ input: Input) -> Report {
        let parsed = ChainParser.parse(input.contents)
        let manifest: ManifestState
        if let listed = input.listedFiles {
            manifest = listed.contains(where: VaultChains.isChainsFile) ? .lists : .doesNotList
        } else {
            manifest = .noManifest
        }
        let scanned = stepLines(input.contents)
        let lookups = scanned.lines.compactMap { step -> LookupCheck? in
            guard let lookup = ChainParser.lookupStep(step.text) else { return nil }
            return check(lookup, chain: step.chain, line: step.line, tables: input.tables)
        }
        let chains = parsed.chains.map { chain in
            ChainSummary(name: chain.name, line: chain.line, steps: chain.steps.count,
                         lookups: chain.steps.filter { if case .lookup = $0.kind { return true } else { return false } }.count)
        }
        return Report(fileName: input.fileName, manifest: manifest,
                      tablesStored: input.tables.count, tablesRead: input.tables.filter(\.isExtracted).count,
                      headings: scanned.headings, chains: chains,
                      problems: parsed.problems.map { ProblemEntry(line: $0.line, chain: $0.chain, kind: kind(of: $0.message),
                                                                   message: $0.message) },
                      lookups: lookups)
    }

    /// Every step line of every chain, read as `ChainParser.parse` reads them: in a fenced block,
    /// as a list item, or indented, under a `##` heading.
    static func stepLines(_ markdown: String) -> (lines: [(chain: String, text: String, line: Int)], headings: Int) {
        var out: [(chain: String, text: String, line: Int)] = []
        var chain: String?
        var headings = 0
        var inFence = false
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, raw) in lines.enumerated() {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence {
                guard let chain, !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }
                out.append((chain, trimmed, offset + 1))
                continue
            }
            if trimmed.hasPrefix("#") {
                if trimmed.prefix(while: { $0 == "#" }).count == 2 {
                    let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                    headings += 1
                    chain = title.isEmpty ? nil : title
                }
                continue
            }
            guard let chain, !trimmed.isEmpty else { continue }
            if let item = listItem(trimmed) {
                out.append((chain, item, offset + 1))
            } else if line.hasPrefix("    ") || line.hasPrefix("\t") {
                out.append((chain, trimmed, offset + 1))
            }
        }
        return (out, headings)
    }

    private static func listItem(_ trimmed: String) -> String? {
        if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
            return trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        }
        if let match = trimmed.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) {
            return String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// One lookup against the tables carrying its label.
    static func check(_ lookup: ChainDefinition.Lookup, chain: String, line: Int, tables: [ManualTable]) -> LookupCheck {
        let label = ChainDefinition.label(lookup.table)
        let labelled = tables.filter { $0.label.caseInsensitiveCompare(label) == .orderedSame }
        let read = labelled.filter(\.isExtracted)
        let state: TableState = !read.isEmpty ? .read : (labelled.isEmpty ? .missing : .unread)
        let sources = read.enumerated().map { index, table in
            TableLookup.Source(documentId: "document-\(index)", documentName: "document \(index + 1)", table: table)
        }
        func part(_ written: String?, _ literal: (String, TableLookup.Source) -> Resolution,
                  headings: (ManualTable) -> [String]) -> Part {
            guard state == .read else { return Part(written: written, resolution: .notChecked) }
            guard let written = written?.trimmingCharacters(in: .whitespaces), !written.isEmpty else {
                return Part(written: nil, resolution: .notChecked)
            }
            if written.contains("{") {
                guard let pattern = pattern(written) else { return Part(written: written, resolution: .fromValue) }
                let fits = read.contains { table in
                    headings(table).contains { pattern.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
                }
                return Part(written: written, resolution: fits ? .patternMatches : .unresolved)
            }
            return Part(written: written, resolution: best(sources.map { literal(written, $0) }))
        }

        // The column: by itself, the row left empty so only the column is read.
        let column: Part
        if let written = lookup.column {
            column = part(written, { asked, source in
                switch TableLookup.resolve(.init(table: label, row: "", column: asked), in: [source]) {
                case .notFound(.column, _, _): return .unresolved
                case .ambiguous(.column, _, _): return .ambiguous
                default: return .resolved
                }
            }, headings: { table in table.columns.flatMap { suffixPaths($0.path) } })
        } else if state != .read {
            column = Part(written: nil, resolution: .notChecked)
        } else {
            // The runner reads a whole row only where the table has one value column.
            let several = read.contains { $0.columns.count > 1 }
            column = Part(written: nil, resolution: several ? .notNamed : .resolved)
        }

        var row: Part?
        var cell: Part?
        if let cellWritten = lookup.cell {
            cell = part(cellWritten, { asked, source in
                guard let value = Double(asked) else { return .unresolved }
                // The column searched: the one written, or each one a column with a value in it fits.
                let columns: [String?]
                if let written = lookup.column, written.contains("{") {
                    let fit = pattern(written)
                    columns = source.table.columns.map { $0.name }.filter { name in
                        fit.map { $0.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil } ?? true
                    }
                } else {
                    columns = [lookup.column]
                }
                let found = columns.map { column -> Resolution in
                    switch TableLookup.search(.init(table: label, row: "", column: column), value: value,
                                              rule: lookup.rule, in: [source]) {
                    case .found: return .resolved
                    case .several: return .ambiguous
                    default: return .unresolved
                    }
                }
                return best(found)
            }, headings: { _ in [] })
            if cell?.resolution == .unresolved, cellWritten.contains("{") {
                cell = Part(written: cellWritten, resolution: .fromValue)
            }
        } else {
            row = part(lookup.row, { asked, source in
                switch TableLookup.resolve(.init(table: label, row: asked, column: nil), rule: lookup.rule, in: [source]) {
                case .found(let found): return found.between != nil ? .betweenRows : .resolved
                case .ambiguous(.row, _, _): return .ambiguous
                default: return .unresolved
                }
            }, headings: { table in table.rows.flatMap { suffixPaths($0.path) } })
        }
        return LookupCheck(chain: chain, line: line, table: lookup.table, tableState: state,
                           row: row, column: column, cell: cell,
                           unreadBecause: state == .unread ? labelled.first?.failure : nil,
                           unnamedColumns: read.first.map { $0.columns.filter { $0.path.isEmpty }.count } ?? 0,
                           readSize: read.first.map { ($0.rows.count, $0.columns.count) })
    }

    /// The best of several documents' answers: one that resolves wins.
    private static func best(_ resolutions: [Resolution]) -> Resolution {
        for wanted in [Resolution.resolved, .ambiguous, .betweenRows] where resolutions.contains(wanted) { return wanted }
        return resolutions.isEmpty ? .notChecked : .unresolved
    }

    /// Every run of a heading path's end ("Rating group 2 › Band B", "Band B"), and its parts.
    private static func suffixPaths(_ path: [String]) -> [String] {
        var out: [String] = []
        for start in path.indices {
            out.append(path[start...].joined(separator: ManualTable.Column.pathSeparator))
            out.append(path[start])
        }
        return out
    }

    /// A template with values in it as a pattern over headings: each `{…}` stands for some text,
    /// the words around it must be there as written (case and spacing aside). Nil when the
    /// template is nothing but values and separators, which only a run can check.
    static func pattern(_ template: String) -> NSRegularExpression? {
        let pieces = template.components(separatedBy: CharacterSet(charactersIn: "{}"))
        // Odd pieces are inside braces.
        var regex = "^"
        var literalWords = false
        for (index, piece) in pieces.enumerated() {
            if index % 2 == 1 { regex += ".+?"; continue }
            if piece.rangeOfCharacter(from: .alphanumerics) != nil { literalWords = true }
            let words = piece.split(whereSeparator: { $0.isWhitespace || $0 == "›" || $0 == ">" })
            var segment = words.map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"[\s›>]+"#)
            if piece.first.map({ $0.isWhitespace || $0 == "›" || $0 == ">" }) == true { segment = #"[\s›>]*"# + segment }
            if piece.last.map({ $0.isWhitespace || $0 == "›" || $0 == ">" }) == true, !words.isEmpty { segment += #"[\s›>]*"# }
            regex += segment
        }
        regex += "$"
        guard literalWords else { return nil }
        return try? NSRegularExpression(pattern: regex, options: [.caseInsensitive])
    }

    // MARK: - Problem kinds

    /// A parse problem's kind, from the parser's own wording.
    static func kind(of message: String) -> String {
        let kinds: [(String, String)] = [
            ("unknown step", "unknown_step"),
            ("runs backwards", "range_backwards"),
            ("an ask for words has no range", "text_with_range"),
            ("says nothing to ask", "empty_question"),
            ("is not one of", "unknown_rule"),
            ("is not a unit the converter knows", "unknown_unit"),
            ("convert a named value", "unknown_unit"),
            ("is used before any step sets it", "used_before_set"),
            ("is already set by line", "set_twice"),
            ("needs a value a lookup set", "attribute_not_a_lookup"),
            ("is not something a value has", "unknown_attribute"),
            ("'cite' attaches", "cite_without_step"),
            ("'cite' needs", "cite_empty"),
            ("the chain says nothing", "says_nothing"),
            ("block is not closed", "unclosed_block"),
            ("the chain has no steps", "no_steps"),
            ("a chain heading needs a name", "unnamed_chain"),
            ("another chain already has this name", "duplicate_name"),
            ("steps outside a chain", "steps_outside_chain"),
            ("the table must be named as printed", "table_from_value"),
            ("a value in braces", "bad_braces"),
            ("the expression does not read", "expression_does_not_read"),
            ("the comparison does not read", "expression_does_not_read"),
            ("a check compares", "check_does_not_read"),
            ("a check is:", "check_does_not_read"),
            ("an ask is:", "ask_does_not_read"),
            ("a lookup is:", "lookup_does_not_read"),
            ("a calc is:", "calc_does_not_read"),
            ("a convert is:", "convert_does_not_read"),
            ("'say' needs", "say_does_not_read"),
        ]
        return kinds.first { message.contains($0.0) }?.1 ?? "other"
    }

    // MARK: - Output

    /// The report as lines. With `names`, a chain's name and the table, row and column a lookup
    /// wrote are printed — all from the chains file. Without, counts and line numbers only.
    static func render(_ report: Report, names: Bool) -> [String] {
        var lines: [String] = []
        func quoted(_ text: String?) -> String { names ? (text.map { " \"\($0)\"" } ?? "") : "" }
        lines.append("[CHAINS] file=\(names ? report.fileName : "chains file") listed_in_manifest=\(report.manifest.rawValue)")
        lines.append("[CHAINS] tables stored=\(report.tablesStored) read=\(report.tablesRead) unread=\(report.tablesStored - report.tablesRead)")
        lines.append("[CHAINS] chains headings=\(report.headings) parsed=\(report.chains.count) "
                     + "with_problems=\(max(0, report.headings - report.chains.count))")
        for chain in report.chains {
            lines.append("[CHAINS]   chain line \(chain.line): steps=\(chain.steps) lookups=\(chain.lookups)\(quoted(chain.name))")
        }
        let counts = report.problemCounts().map { "\($0.kind)=\($0.count)" }.joined(separator: " ")
        lines.append("[CHAINS] problems=\(report.problems.count)" + (counts.isEmpty ? "" : " by kind: \(counts)"))
        for problem in report.problems {
            lines.append("[CHAINS]   line \(problem.line) [\(problem.kind)]"
                         + (names ? " " + (problem.chain.map { "\($0): " } ?? "") + problem.message : ""))
        }
        let lookups = report.lookups
        func tally(_ values: [Resolution]) -> String {
            Resolution.allCases.compactMap { r in
                let n = values.filter { $0 == r }.count
                return n == 0 ? nil : "\(r.rawValue)=\(n)"
            }.joined(separator: " ")
        }
        let tableTally = TableState.allCases.map { s in "\(s.rawValue)=\(lookups.filter { $0.tableState == s }.count)" }
            .joined(separator: " ")
        lines.append("[CHAINS] lookups=\(lookups.count) · tables \(tableTally)")
        let because = TableExtractor.Failure.allCases.compactMap { failure -> String? in
            let n = lookups.filter { $0.unreadBecause == failure }.count
            return n == 0 ? nil : "\(failure.rawValue)=\(n)"
        }
        if !because.isEmpty { lines.append("[CHAINS]   unread because: " + because.joined(separator: " ")) }
        lines.append("[CHAINS]   rows: \(tally(lookups.compactMap(\.row?.resolution)))")
        lines.append("[CHAINS]   columns: \(tally(lookups.map(\.column.resolution)))")
        let cells = lookups.compactMap(\.cell?.resolution)
        if !cells.isEmpty { lines.append("[CHAINS]   cell numbers: \(tally(cells))") }
        let resolvedAll = lookups.filter { check in
            let good: Set<Resolution> = [.resolved, .patternMatches, .fromValue]
            return check.tableState == .read && good.contains(check.column.resolution)
                && (check.row.map { good.contains($0.resolution) } ?? true)
                && (check.cell.map { good.contains($0.resolution) } ?? true)
        }.count
        lines.append("[CHAINS]   lookups that resolve throughout=\(resolvedAll) of \(lookups.count)")
        for check in lookups {
            var line = "[CHAINS]   lookup line \(check.line): table=\(check.tableState.rawValue)\(quoted(check.table))"
            if let row = check.row {
                line += " row=\(row.resolution.rawValue)"
                if Self.isTrouble(row.resolution) { line += quoted(row.written) }
            }
            if let cell = check.cell {
                line += " cell=\(cell.resolution.rawValue)"
                if Self.isTrouble(cell.resolution) { line += quoted(cell.written) }
            }
            line += " column=\(check.column.resolution.rawValue)"
            if Self.isTrouble(check.column.resolution) { line += quoted(check.column.written) }
            if let because = check.unreadBecause { line += " unread_because=\(because.rawValue)" }
            if check.unnamedColumns > 0 { line += " unnamed_columns=\(check.unnamedColumns)" }
            if let size = check.readSize { line += " grid=\(size.rows)x\(size.columns)" }
            lines.append(line)
        }
        return lines
    }

    /// A resolution worth naming the written words for.
    static func isTrouble(_ resolution: Resolution) -> Bool {
        [.unresolved, .ambiguous, .betweenRows, .notNamed].contains(resolution)
    }
}
