import XCTest
@testable import OpenGlasses

/// Plan JJ P4 — the pure part of `Scripts/chains-validate`, on an invented fixture vault: the P2
/// fixture tables (Tables 99, 98, 97 and 90, and a Table 92 whose grid was not read) and invented
/// chains files. Every table, row, rule and value is made up; nothing is a fact from any book.
final class ChainsValidateCoreTests: XCTestCase {

    private var tables: [ManualTable] { RuleChainFixtures.tables().map(\.table) }

    private func report(_ chains: String, listed: [String]? = ["safety.md", "chains.md"]) -> ChainsValidate.Report {
        ChainsValidate.check(.init(fileName: "chains.md", contents: chains, listedFiles: listed, tables: tables))
    }

    /// One chain that resolves, and one with a missing table, an unresolved row, an unresolved
    /// column, an unread table and a step that does not read.
    private let fixture = """
    # Rule chains

    ## Good chain
    Answers: a value from the invented tables.

    ```chain
    ask conductors (conductors) range 1..9: How many conductors?
    ask group range 1..3: Which rating group?
    ask ambient (°C) range 0..40: What ambient?
    lookup band = Table 90 row {conductors} column Band rule exact
    cite Rule QR-12
    lookup factor = Table 98 row {ambient} column Rating group {group} › {band} rule at_least
    cite Rule QR-14
    lookup fixed = Table 99 row QXRT three conductors column Rating group 2 rule exact
    lookup size = Table 99 column Rating group {group} cell 37.5 rule at_least
    say "{fixed} {size} {factor}"
    ```

    ## Troubled chain
    Answers: everything that can go wrong.

    ```chain
    ask key (text): Which row?
    lookup absent = Table 95 row {key} column Value rule exact
    lookup wrongrow = Table 99 row QX4 column Rating group 2 rule exact
    lookup wrongcolumn = Table 99 row QMX90 two conductors column Rating group 4 rule exact
    lookup unread = Table 92 row {key} column Value rule exact
    lookup broken = Table 99 row QXRT
    say "{absent}"
    ```
    """

    func testItReportsAMissingTableAnUnresolvedRowAndColumnAProblemByLineAndTheManifest() throws {
        let report = self.report(fixture, listed: ["safety.md"])
        XCTAssertEqual(report.manifest, .doesNotList)
        XCTAssertEqual(report.headings, 2)
        XCTAssertEqual(report.chains.map(\.name), ["Good chain"], "the troubled chain does not parse")
        XCTAssertEqual(report.chains.first?.steps, 8)
        XCTAssertEqual(report.chains.first?.lookups, 4)
        XCTAssertEqual(report.tablesStored, 5)
        XCTAssertEqual(report.tablesRead, 4)

        // The step that does not read, by its line and kind.
        let brokenLine = fixture.components(separatedBy: "\n").firstIndex { $0.contains("lookup broken") }! + 1
        XCTAssertEqual(report.problems.map(\.line), [brokenLine])
        XCTAssertEqual(report.problems.first?.kind, "lookup_does_not_read")
        XCTAssertEqual(report.problems.first?.chain, "Troubled chain")

        // Every lookup, the troubled chain's included.
        let byName = Dictionary(uniqueKeysWithValues: report.lookups.map { (lookupName($0.line), $0) })
        XCTAssertEqual(report.lookups.count, 8, "the broken line is not a lookup that reads")

        XCTAssertEqual(byName["band"]?.tableState, .read)
        XCTAssertEqual(byName["band"]?.row?.resolution, .fromValue)
        XCTAssertEqual(byName["band"]?.column.resolution, .resolved)
        XCTAssertEqual(byName["factor"]?.column.resolution, .patternMatches)
        XCTAssertEqual(byName["fixed"]?.row?.resolution, .resolved)
        XCTAssertEqual(byName["fixed"]?.column.resolution, .resolved)
        XCTAssertEqual(byName["size"]?.cell?.resolution, .resolved, "a cell of at least 37.5 is printed")
        XCTAssertEqual(byName["size"]?.column.resolution, .patternMatches)

        XCTAssertEqual(byName["absent"]?.tableState, .missing)
        XCTAssertEqual(byName["absent"]?.column.resolution, .notChecked)
        XCTAssertEqual(byName["wrongrow"]?.row?.resolution, .unresolved)
        XCTAssertEqual(byName["wrongrow"]?.column.resolution, .resolved)
        XCTAssertEqual(byName["wrongcolumn"]?.row?.resolution, .resolved)
        XCTAssertEqual(byName["wrongcolumn"]?.column.resolution, .unresolved)
        XCTAssertEqual(byName["unread"]?.tableState, .unread)
    }

    func testTheOutputNamesOnlyWhatTheChainsFileWrote() {
        let names = ChainsValidate.render(report(fixture, listed: nil), names: true).joined(separator: "\n")
        XCTAssertTrue(names.contains("listed_in_manifest=no_manifest"), names)
        XCTAssertTrue(names.contains("problems=1 by kind: lookup_does_not_read=1"), names)
        XCTAssertTrue(names.contains("table=missing \"Table 95\""), names)
        XCTAssertTrue(names.contains("row=unresolved \"QX4\""), names)
        XCTAssertTrue(names.contains("column=unresolved \"Rating group 4\""), names)
        XCTAssertTrue(names.contains("lookups=8 · tables read=6 unread=1 missing=1"), names)
        // Nothing from the book: no title, no heading or row the chains did not write, no cell.
        for fromTheBook in ["Conductor ratings", "Correction factors", "Grouping bands", "Band B", "QMX90 › two",
                            "Rating group 3", "0.86", "Invented Book A", "Wiring notes"] {
            XCTAssertFalse(names.contains(fromTheBook), "\(fromTheBook) is the book's, not the chains file's:\n\(names)")
        }

        let counts = ChainsValidate.render(report(fixture), names: false).joined(separator: "\n")
        for written in ["Table 95", "QX4", "Rating group 4", "Good chain", "Troubled chain", "chains.md"] {
            XCTAssertFalse(counts.contains(written), "counts only: \(written)\n\(counts)")
        }
        XCTAssertTrue(counts.contains("lookup_does_not_read"), counts)
        XCTAssertTrue(counts.contains("listed_in_manifest=yes"), counts)
    }

    func testTheExampleResolvesThroughoutAndItsLookupsAreTheParsersOwn() throws {
        let report = self.report(RuleChainFixtures.chainsMarkdown)
        XCTAssertEqual(report.problems, [])
        XCTAssertEqual(report.manifest, .lists)
        XCTAssertEqual(report.chains.map(\.steps), [9, 10, 9])
        let parsed = ChainParser.parse(RuleChainFixtures.chainsMarkdown).chains.flatMap(\.steps).compactMap { step -> Int? in
            if case .lookup = step.kind { return step.line }
            return nil
        }
        XCTAssertEqual(report.lookups.map(\.line), parsed, "the scan finds the lookups the parser reads")
        for check in report.lookups {
            XCTAssertEqual(check.tableState, .read, "line \(check.line)")
            let good: Set<ChainsValidate.Resolution> = [.resolved, .patternMatches, .fromValue]
            XCTAssertTrue(good.contains(check.column.resolution), "line \(check.line): \(check.column)")
            if let row = check.row { XCTAssertTrue(good.contains(row.resolution), "line \(check.line): \(row)") }
        }
        let rendered = ChainsValidate.render(report, names: false)
        XCTAssertTrue(rendered.contains("[CHAINS]   lookups that resolve throughout=7 of 7"), rendered.joined(separator: "\n"))
    }

    func testAColumnNotNamedOnAWideTableAndANumberBetweenRowsAreCaught() {
        let file = """
        ## Edges
        Answers: two lookups the runner would stop on.

        - lookup whole = Table 99 row QXRT two conductors rule exact
        - lookup between = Table 98 row 9.5 column Rating group 1 › Band A rule exact
        - lookup above = Table 98 row 9.5 column Rating group 1 › Band A rule at_least
        - say "{whole} {between} {above}"
        """
        let checks = report(file).lookups
        XCTAssertEqual(checks.map(\.column.resolution), [.notNamed, .resolved, .resolved])
        XCTAssertEqual(checks.compactMap(\.row?.resolution), [.resolved, .betweenRows, .resolved])
    }

    func testEveryParserProblemHasAKind() {
        let broken = """
        ```chain
        ask stray: outside a chain
        ```

        ## Kinds
        Answers: one of each.

        ```chain
        cite Rule QR-1
        frobnicate x
        ask a (A) range 9..1: Backwards?
        ask b (text) range 1..2: Words with a range?
        ask c (A):
        lookup d = Table 99 row QXRT rule nearest
        convert e = a to parsecs
        calc f = g * 2
        calc a = 1
        calc twice = 1
        calc twice = 2
        lookup h = Table {a} row QXRT column Rating group 1 rule exact
        say "{a.row}"
        say "{a.colour}"
        say "{a"
        check a > ? "x" : "y"
        say unquoted
        ```

        ## Kinds
        Answers: a second chain of the same name.

        ```chain
        say "hello"
        ```

        ## Unclosed
        ```chain
        say "never closed"
        """
        let kinds = Set(report(broken).problems.map(\.kind))
        XCTAssertFalse(kinds.contains("other"), "\(report(broken).problems.filter { $0.kind == "other" }.map(\.message))")
        for kind in ["steps_outside_chain", "cite_without_step", "unknown_step", "range_backwards", "text_with_range",
                     "empty_question", "unknown_rule", "unknown_unit", "used_before_set", "set_twice",
                     "table_from_value", "attribute_not_a_lookup", "unknown_attribute", "bad_braces",
                     "expression_does_not_read", "say_does_not_read", "unclosed_block"] {
            XCTAssertTrue(kinds.contains(kind), "\(kind) in \(kinds.sorted())")
        }
    }

    /// The name a lookup line sets, from the fixture.
    private func lookupName(_ line: Int) -> String {
        let text = (fixture.components(separatedBy: "\n")[line - 1]).trimmingCharacters(in: .whitespaces)
        return String(text.dropFirst("lookup ".count).prefix { $0 != " " })
    }
}
