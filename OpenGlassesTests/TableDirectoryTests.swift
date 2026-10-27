import XCTest
@testable import OpenGlasses

/// Plan JW P1b — finding a table from plain words. Every table, title, heading and value here is
/// invented (widgets, housings, sprockets); nothing is taken from any book.
final class TableDirectoryTests: XCTestCase {

    // MARK: - Fixtures

    private static func table(_ label: String, _ title: String, rowHeading: String, columns: [[String]],
                              unit: String? = nil, rows: [String] = ["2", "4", "6"]) -> ManualTable {
        let page = ManualTable.Page(physical: 3)
        return ManualTable(
            label: label, title: title, page: page, rowHeaders: [rowHeading],
            columns: columns.map { ManualTable.Column(path: $0, unit: unit) },
            rows: rows.enumerated().map { index, key in
                ManualTable.Row(path: [key], cells: columns.indices.map { column in
                    let value = 10 * (index + 1) + column
                    return ManualTable.Cell(text: "\(value)", value: Double(value), unit: unit)
                }, page: page)
            })
    }

    private static let shared = table("Table 99", "Widget ratings, up to three widgets sharing one housing",
                                      rowHeading: "Widget gauge", columns: [["Load", "Grade 1"], ["Load", "Grade 2"]], unit: "kg")
    private static let single = table("Table 97", "Widget ratings, a single widget in an open frame",
                                      rowHeading: "Widget gauge", columns: [["Load", "Grade 1"], ["Load", "Grade 2"]], unit: "kg")
    private static let warm = table("Table 98A", "Correction multipliers for housings above 30 degrees",
                                    rowHeading: "Housing temperature, °C", columns: [["Multiplier"]], rows: ["35", "40", "45"])
    private static let crowded = table("Table 98B", "Correction multipliers for more than three widgets in one housing",
                                       rowHeading: "Number of widgets", columns: [["Multiplier"]], rows: ["4-6", "7-9"])
    private static let clearance = table("Table 96", "Minimum clearance around a sprocket frame (See Clause 99-100.)",
                                         rowHeading: "Frame width, mm", columns: [["Clearance (mm)"]], rows: ["100", "300"])
    private static let springs = table("Table 95", "Spring tension by coil length",
                                       rowHeading: "Coil length (mm)", columns: [["Tension (kg)"]], rows: ["20", "40"])

    private static let tables = [shared, single, warm, crowded, clearance, springs]

    private func catalogue(document: String? = "Invented Widget Handbook") -> [TableReference.Entry] {
        Self.tables.map { TableReference.Entry(table: $0, documentName: document) }
    }

    private func first(_ question: String) -> String? {
        TableDirectory.ranked(question, in: catalogue()).first?.entry.label
    }

    // MARK: - Ranking

    func testPlainWordsFindTheTableByItsTitleHeadingsAndUnits() {
        XCTAssertEqual(first("how much load can a gauge 4 widget take at grade 2 with three widgets in one housing?"), "Table 99")
        XCTAssertEqual(first("what can a single gauge 6 widget carry in an open frame, grade 1"), "Table 97")
        XCTAssertEqual(first("what multiplier do I use when the housing is at 40 degrees"), "Table 98A")
        XCTAssertEqual(first("what's the multiplier for seven widgets in one housing"), "Table 98B")
        XCTAssertEqual(first("how much clearance do I need around a 300 mm sprocket frame"), "Table 96")
        XCTAssertEqual(first("what tension should a spring with a 40 mm coil have"), "Table 95")
    }

    func testCandidatesCarryAScoreAndAMarginAndClearTheThreshold() throws {
        let offered = TableDirectory.candidates(
            for: "how much load can a gauge 4 widget take at grade 2 with three widgets in one housing?", in: catalogue())
        let best = try XCTUnwrap(offered.first)
        XCTAssertEqual(best.entry.label, "Table 99")
        XCTAssertGreaterThanOrEqual(best.score, TableDirectory.minimumScore)
        XCTAssertGreaterThan(best.margin, 0)
        // "Three widgets sharing one housing" sets it well ahead of the single-widget table: one.
        XCTAssertEqual(offered.map(\.entry.label), ["Table 99"])

        // Words both rating tables print alike: both are offered, and never more than two.
        let both = TableDirectory.candidates(for: "what load is a gauge 4 widget rated for at grade 2", in: catalogue())
        XCTAssertEqual(both.map(\.entry.label), ["Table 99", "Table 97"])
        XCTAssertEqual(both.first?.margin ?? -1, 0, accuracy: 1e-9)

        // One shared word is coincidence: nothing is offered.
        XCTAssertEqual(TableDirectory.candidates(for: "what is the maximum fan speed", in: catalogue()), [])
        XCTAssertEqual(TableDirectory.candidates(for: "how big is the frame", in: catalogue()), [])
    }

    func testAPluralTitleMeetsASingularQuestionAndAUnitMeetsItsSpelling() {
        let batteries = TableReference.Entry(table: Self.table("Table 94", "Invented batteries and their spare capacities",
                                                               rowHeading: "Cell", columns: [["Hours"]]))
        XCTAssertEqual(TableDirectory.ranked("spare capacity of the battery", in: catalogue() + [batteries]).first?.entry.label,
                       "Table 94")
        XCTAssertTrue(TableDirectory.terms("a housing at 30 degrees C").contains("30°c"))
        XCTAssertTrue(TableDirectory.terms("above 30 °C").contains("30°c"))
        XCTAssertTrue(TableDirectory.terms("forty percent").contains("unit:%"))
        XCTAssertTrue(TableDirectory.headingTerms(["kg"]).contains("unit:kg"))
    }

    func testATableContinuedUnderTheSameCaptionIsOneTable() {
        let continued = TableReference.Entry(label: "Table 99", title: "", documentName: "Invented Widget Handbook",
                                             headings: ["Widget gauge", "Load › Grade 3"])
        let merged = TableDirectory.merged(catalogue() + [continued])
        XCTAssertEqual(merged.filter { $0.label == "Table 99" }.count, 1)
        XCTAssertEqual(merged.first { $0.label == "Table 99" }?.title, Self.shared.title)
    }

    // MARK: - The value question

    func testAValueQuestionIsRecognisedByGenericWords() {
        for turn in ["how much load can a gauge 4 widget take", "what's the multiplier factor at 40 degrees",
                     "minimum clearance for the frame", "what size spring do I need", "what is it good for at grade 2",
                     "tension at 40 mm"] {
            XCTAssertTrue(TableDirectory.asksForValue(turn), turn)
        }
        for turn in ["how do I take the cover off the housing", "who made this widget", "open the handbook",
                     "is the sprocket frame painted"] {
            XCTAssertFalse(TableDirectory.asksForValue(turn), turn)
        }
    }

    // MARK: - The hint

    func testTheHintNamesTheTablesAndHowToReadThem() throws {
        let hint = try XCTUnwrap(TableDirectory.hint(for: "what load is a gauge 4 widget rated for at grade 2", in: catalogue()))
        XCTAssertTrue(hint.hasPrefix("Tables that may answer this: Table 99 — Widget ratings, up to three widgets sharing one housing; "
                                     + "Table 97 — Widget ratings, a single widget in an open frame."), hint)
        XCTAssertTrue(hint.hasSuffix("Read the value with table_lookup (table, row, column), and ask the technician for any input the table needs."), hint)
        // One document: its name is not repeated on every table.
        XCTAssertFalse(hint.contains("Invented Widget Handbook"), hint)
        XCTAssertLessThan(hint.count, 400, "the hint stays one compact line")
        XCTAssertFalse(hint.contains("\n"))
    }

    func testTheHintNamesTheDocumentWhenTablesComeFromSeveral() throws {
        let other = TableReference.Entry(table: Self.table("Table 93", "Invented paint drying times", rowHeading: "Coat",
                                                           columns: [["Hours"]]), documentName: "Invented Paint Guide")
        let hint = try XCTUnwrap(TableDirectory.hint(for: "what multiplier do I use when the housing is at 40 degrees",
                                                     in: catalogue() + [other]))
        XCTAssertTrue(hint.contains("Table 98A — Correction multipliers for housings above 30 degrees (Invented Widget Handbook)"), hint)
    }

    /// Two editions of one book print the same tables: the second place goes to another table, not
    /// to the first one's other edition, and the hint names both editions on the one table.
    func testTwoEditionsOfATableAreOneCandidateNamingBoth() throws {
        let both = catalogue(document: "Invented Widget Handbook 2026") + catalogue(document: "Invented Widget Handbook 2023")
        let question = "what load is a gauge 4 widget rated for at grade 2"
        let offered = TableDirectory.candidates(for: question, in: both)
        XCTAssertEqual(offered.map(\.entry.label), ["Table 99", "Table 97"])
        let hint = try XCTUnwrap(TableDirectory.hint(for: question, in: both))
        XCTAssertTrue(hint.contains("Table 99 — Widget ratings, up to three widgets sharing one housing "
                                    + "(Invented Widget Handbook 2026, Invented Widget Handbook 2023)"), hint)
        XCTAssertEqual(hint.components(separatedBy: "Table 99").count - 1, 1, hint)
    }

    func testNoHintWhenATableIsNamedOrTheTurnAsksNoValueOrNothingFits() {
        // By number, spoken, and by every word of its title with "table".
        XCTAssertNil(TableDirectory.hint(for: "in table 99, how much load at gauge 4, grade 2", in: catalogue()))
        XCTAssertNil(TableDirectory.hint(for: "table ninety-eight A at 40 degrees, what multiplier", in: catalogue()))
        XCTAssertNil(TableDirectory.hint(for: "what does the spring tension by coil length table give for 40 mm", in: catalogue()))
        // Not a value question.
        XCTAssertNil(TableDirectory.hint(for: "how do I take the cover off the widget housing", in: catalogue()))
        // A value question no table fits.
        XCTAssertNil(TableDirectory.hint(for: "what is the maximum fan speed", in: catalogue()))
        // No tables.
        XCTAssertNil(TableDirectory.hint(for: "how much load can a gauge 4 widget take", in: []))
    }

    func testALongTitleIsShortenedAndItsCrossReferenceLeftOut() {
        XCTAssertEqual(TableDirectory.shortened(Self.clearance.title), "Minimum clearance around a sprocket frame")
        let long = "Invented loads for widgets of every gauge mounted in housings of painted sheet, sealed or vented, "
            + "with the lids closed and the fans running at the lowest setting"
        let short = TableDirectory.shortened(long)
        XCTAssertLessThanOrEqual(short.count, TableDirectory.titleLimit + 1)
        XCTAssertTrue(short.hasSuffix("…"), short)
        XCTAssertTrue(long.hasPrefix(String(short.dropLast())), short)
    }

    // MARK: - table_lookup by words

    private var sources: [TableLookup.Source] {
        Self.tables.map { TableLookup.Source(documentId: "w", documentName: "Invented Widget Handbook", table: $0) }
    }

    func testTableLookupResolvesTitleWordsThroughTheSameScore() throws {
        let outcome = TableLookup.resolve(.init(table: "widget ratings, three widgets sharing one housing", row: "4",
                                                column: "Grade 2"), in: sources)
        guard case .found(let found) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(found.source.table.label, "Table 99")
        XCTAssertEqual(found.rows.first?.cells[found.columns[0]].text, "21")

        let warm = TableLookup.resolve(.init(table: "multipliers for warm housings, degrees", row: "40"), in: sources)
        guard case .found(let hot) = warm else { return XCTFail("\(warm)") }
        XCTAssertEqual(hot.source.table.label, "Table 98A")
    }

    func testTableLookupAsksWhenTheWordsFitTwoTablesAlike() {
        guard case .ambiguous(.table, _, let candidates) = TableLookup.resolve(.init(table: "widget ratings", row: "4"),
                                                                               in: sources) else {
            return XCTFail("two tables share those title words equally")
        }
        XCTAssertEqual(Set(candidates), ["\(Self.shared.displayName) in Invented Widget Handbook",
                                         "\(Self.single.displayName) in Invented Widget Handbook"])
    }
}
