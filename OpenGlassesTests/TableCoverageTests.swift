import PDFKit
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JJ P5 — reading the tables a code book actually prints: labels with a letter, a table
/// continued onto a page with no caption, cells that are marks, two groups side by side under one
/// caption, and the names a chain gives a row or a column. Every label, designation and value is
/// invented (`TableFixtureLayouts`); nothing is a fact from any book.
final class TableCoverageTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TableCoverageTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func only(_ page: TableFixtureLayouts.Page, physical: Int = 1,
                      file: StaticString = #filePath, line: UInt = #line) throws -> ManualTable {
        let found = TableExtractor.extractAll(words: TableFixtureLayouts.words(page),
                                              page: ManualTable.Page(physical: physical))
        XCTAssertEqual(found.count, 1, "one caption on the page", file: file, line: line)
        return try XCTUnwrap(found.first?.outcome.table, "\(String(describing: found.first?.outcome))",
                             file: file, line: line)
    }

    private func readPDF(_ pages: [TableFixtureLayouts.Page]) throws -> PDFTableReader.Result {
        let url = try TableFixtures.write(TableFixtures.pdf(pages), named: "tables-\(UUID().uuidString).pdf", in: tempRoot)
        return try XCTUnwrap(PDFTableReader.read(url: url))
    }

    private func source(_ table: ManualTable) -> TableLookup.Source {
        .init(documentId: "a", documentName: "Invented Book A", table: table)
    }

    private func found(_ outcome: TableLookup.Outcome, file: StaticString = #filePath, line: UInt = #line) throws -> TableLookup.Found {
        guard case .found(let found) = outcome else {
            XCTFail("expected a cell, got \(outcome)", file: file, line: line)
            throw XCTSkip("no cell")
        }
        return found
    }

    // MARK: - Labels with a letter

    func testALetterBesideTheNumberIsPartOfTheLabel() {
        func caption(_ text: String, bold: Bool = true) -> TableExtractor.Caption? {
            TableExtractor.lines(of: TableFixtureLayouts.words([.init(text: text, x: 50, y: 60, size: 10, bold: bold)]))
                .first.flatMap { TableExtractor.caption(of: $0, pageHasBold: bold) }
        }
        XCTAssertEqual(caption("TABLE 95A Invented clearances")?.label, "Table 95A")
        XCTAssertEqual(caption("TABLE 95A Invented clearances")?.title, "Invented clearances")
        XCTAssertEqual(caption("Table 95b Invented clearances")?.label, "Table 95b", "kept as printed")
        XCTAssertEqual(caption("TABLE Q7 Invented band limits")?.label, "Table Q7")
        XCTAssertEqual(caption("Table Q7 Invented band limits", bold: false)?.label, "Table Q7", "on a page set in one weight")
        XCTAssertEqual(caption("TABLE 95A (Continued)"), TableExtractor.Caption(label: "Table 95A", title: "", continues: true))
        XCTAssertEqual(caption("TABLE 16Invented")?.label, "Table 16", "a letter run into a word is not the label's")
        XCTAssertNil(caption("TABLE Q Invented"), "a letter with no number is no label")
    }

    func testTablesThatShareANumberStayApartAndAContinuationJoinsItsOwnLabel() throws {
        let pages = TableFixtureLayouts.letteredLabels()
        let tables = try pages.enumerated().map { try only($1, physical: $0 + 1) }
        XCTAssertEqual(tables.map(\.label), ["Table 95", "Table 95A", "Table 95A", "Table 95B"])
        let merged = TableExtractor.merge(tables)
        XCTAssertEqual(merged.map(\.label), ["Table 95", "Table 95A", "Table 95B"], "95A and 95B never merge, nor with 95")
        XCTAssertEqual(merged[0].rows.map(\.page.physical), [1, 1, 1], "Table 95 takes nothing of 95A")
        XCTAssertEqual(merged[1].rows.map { $0.path[0] }, ["QB1", "QB2", "QB3", "QB4", "QB5", "QB6"])
        XCTAssertEqual(merged[1].rows.map(\.page.physical), [2, 2, 2, 3, 3, 3])
        XCTAssertFalse(merged[1].continues)

        // A continuation of 95A straight after Table 95 has nothing of its own label before it.
        let orphan = TableExtractor.merge([tables[0], try only(pages[2], physical: 2)])
        XCTAssertEqual(orphan.count, 2, "a continuation of 95A never joins 95")
        XCTAssertTrue(orphan[1].continues)

        let read = try readPDF(pages)
        XCTAssertEqual(read.tables.map(\.label), ["Table 95", "Table 95A", "Table 95B"])
        XCTAssertEqual(read.captioned, 3)
    }

    func testALetteredLabelIsRecognisedPrintedSpacedAndSpoken() {
        XCTAssertEqual(TableReference.labels(in: "what does table 95A say"), ["Table 95A"])
        XCTAssertEqual(TableReference.labels(in: "what does table 95a say"), ["Table 95A"])
        XCTAssertEqual(TableReference.labels(in: "look at table 95 B for QXRT"), ["Table 95B"])
        XCTAssertEqual(TableReference.labels(in: "look at table five A"), ["Table 5A"])
        XCTAssertEqual(TableReference.labels(in: "table ninety-five B, row QB2"), ["Table 95B"])
        XCTAssertEqual(TableReference.labels(in: "check table Q7"), ["Table Q7"])
        XCTAssertEqual(TableReference.labels(in: "check table Q seven"), ["Table Q7"])
        XCTAssertEqual(TableReference.labels(in: "table 95A and table 95"), ["Table 95A", "Table 95"])
        XCTAssertEqual(TableReference.labels(in: "table 99X is the model"), ["Table 99X"], "never read as Table 99")
        XCTAssertEqual(TableReference.labels(in: "is table 5 a good place to look"), ["Table 5"], "\"a\" is a word")
        XCTAssertEqual(TableReference.labels(in: "is table 5 a good place to look", among: ["Table 5A"]), ["Table 5A"],
                       "unless the vault prints a Table 5A")
        XCTAssertEqual(TableReference.references(in: "what does table five a say for QB2",
                                                 catalogue: [.init(label: "Table 5A", title: "Invented")]), ["Table 5A"])
        XCTAssertFalse(TableReference.removingReferences(from: "in table 95A, QB1 30").contains("95"))
        for text in ["what is a TBL95A controller", "table and chairs", "the table I built"] {
            XCTAssertEqual(TableReference.labels(in: text), [], text)
        }
    }

    func testALetteredTableIsLookedUpByItsLabelAndAChainNamesIt() throws {
        let tables = TableExtractor.merge(try TableFixtureLayouts.letteredLabels().enumerated().map { try only($1, physical: $0 + 1) })
        let sources = tables.map(source)
        let hit = try found(TableLookup.resolve(.init(table: "Table 95A", row: "QB5"), in: sources))
        XCTAssertEqual(hit.source.table.label, "Table 95A")
        XCTAssertEqual(hit.rows.first?.cells.first?.text, "38")
        XCTAssertEqual(try found(TableLookup.resolve(.init(table: "95B", row: "QC2"), in: sources)).rows.first?.cells.first?.text, "52")
        XCTAssertEqual(try found(TableLookup.resolve(.init(table: "table ninety five b", row: "QC2"), in: sources))
            .source.table.label, "Table 95B")
        XCTAssertEqual(try found(TableLookup.resolve(.init(table: "Table 95", row: "QA2"), in: sources)).source.table.label,
                       "Table 95", "the bare number is its own table")
        guard case .notFound(.row, _, _) = TableLookup.resolve(.init(table: "Table 95", row: "QB5"), in: sources) else {
            return XCTFail("QB5 is a row of 95A, not of 95")
        }
        XCTAssertEqual(ChainDefinition.label("Table 95A"), "Table 95A")
        XCTAssertEqual(ChainDefinition.label("Table Q7"), "Table Q7")
    }

    // MARK: - A continuation with no caption

    func testACaptionlessContinuationWithTheSameColumnsMergesEachRowKeepingItsPage() throws {
        let result = try readPDF(TableFixtureLayouts.captionlessContinuation())
        XCTAssertEqual(result.captioned, 1)
        let table = try XCTUnwrap(result.tables.first)
        XCTAssertEqual(table.label, "Table 96")
        XCTAssertEqual(table.columns.map(\.name), ["Indoor (mm)", "Outdoor (mm)"])
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QA1", "QA2", "QA3", "QA4", "QA5", "QA6"])
        XCTAssertEqual(table.rows.map(\.page.physical), [1, 1, 1, 2, 2, 2])
        XCTAssertEqual(table.rows.compactMap { $0.cells.last?.value }, [20, 24, 28, 32, 36, 40])
        XCTAssertEqual(table.pages.map(\.physical), [1, 2])
    }

    func testARepeatedHeadingOnTheContinuationIsNotARow() throws {
        let table = try XCTUnwrap(try readPDF(TableFixtureLayouts.captionlessContinuation(repeatHeader: true)).tables.first)
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QA1", "QA2", "QA3", "QA4", "QA5", "QA6"])
    }

    func testACaptionlessPageWithOtherColumnsDoesNotMerge() throws {
        let table = try XCTUnwrap(try readPDF(TableFixtureLayouts.captionlessContinuation(sameColumns: false)).tables.first)
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QA1", "QA2", "QA3"])
        XCTAssertEqual(table.pages.map(\.physical), [1])
    }

    func testTheContinuationReadsPurelyOffTheGridOfThePageBefore() throws {
        let pages = TableFixtureLayouts.captionlessContinuation()
        let first = TableExtractor.extractGrids(words: TableFixtureLayouts.words(pages[0]), page: .init(physical: 1))
        let grid = try XCTUnwrap(first.first?.grid, "a read table carries its grid")
        let rows = TableExtractor.continuation(words: TableFixtureLayouts.words(pages[1]), page: .init(physical: 2), grid: grid)
        XCTAssertEqual(rows?.rows.map { $0.path.joined() }, ["QA4", "QA5", "QA6"])
        let other = TableExtractor.continuation(
            words: TableFixtureLayouts.words(TableFixtureLayouts.captionlessContinuation(sameColumns: false)[1]),
            page: .init(physical: 2), grid: grid)
        XCTAssertNil(other, "rows that do not sit on the grid are not a continuation")
        XCTAssertNil(TableExtractor.continuation(words: TableFixtureLayouts.words(TableFixtures.prosePage()),
                                                 page: .init(physical: 2), grid: grid), "prose is not a continuation")
    }

    // MARK: - Marks in the cells

    func testCellsThatAreMarksExtractAsTextWithNoNumber() throws {
        let table = try only(TableFixtureLayouts.tickMarks())
        XCTAssertEqual(table.label, "Table 98")
        XCTAssertEqual(table.rowHeaders, ["Designation"])
        XCTAssertEqual(table.columns.map(\.name), ["North", "South", "East", "West"])
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QXRT", "QMX90", "QZ12", "QA7", "QB2"])
        XCTAssertEqual(table.rows[0].cells.map(\.text), ["X", "X", "", ""])
        XCTAssertEqual(table.rows[2].cells.map(\.text), ["", "\u{2713}", "\u{2713}", "\u{2713}"])
        XCTAssertEqual(table.rows[4].cells.map(\.text), ["\u{2014}", "X", "", "X"])
        XCTAssertTrue(table.rows.allSatisfy { $0.cells.allSatisfy { $0.value == nil } }, "a mark is never a number")
        let hit = try found(TableLookup.resolve(.init(table: "Table 98", row: "QZ12", column: "East"), in: [source(table)]))
        XCTAssertEqual(hit.rows.first?.cells[hit.columns[0]].text, "\u{2713}")
    }

    func testMarksSurviveAPDFTextLayer() throws {
        let table = try XCTUnwrap(try readPDF([TableFixtureLayouts.tickMarks()]).tables.first)
        XCTAssertEqual(table.columns.count, 4)
        XCTAssertEqual(table.rows.map { $0.cells.filter { !$0.isEmpty }.count }, [2, 2, 3, 4, 3])
    }

    // MARK: - Two groups side by side

    func testTwoGroupsSideBySideReadAsOneTableWithTheRightGroupAfterTheLeft() throws {
        let table = try only(TableFixtureLayouts.sideBySide())
        XCTAssertEqual(table.label, "Table Q7")
        XCTAssertEqual(table.rowHeaders, ["Designation"])
        XCTAssertEqual(table.columns.map(\.name), ["Limit (A)"], "one column, not the right group as more columns")
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QA1", "QA2", "QA3", "QA4", "QB1", "QB2", "QB3"])
        XCTAssertEqual(table.rows.compactMap { $0.cells.first?.value }, [10, 12, 14, 16, 20, 22, 24])
        let hit = try found(TableLookup.resolve(.init(table: "Table Q7", row: "QB2", column: "Limit"), in: [source(table)]))
        XCTAssertEqual(hit.rows.first?.cells.first?.text, "22")
    }

    func testSideBySideGroupsUnderTheirOwnHeadingsKeepTheHeadingOnTheirRows() throws {
        let table = try only(TableFixtureLayouts.sideBySide(groupHeadings: true))
        XCTAssertEqual(table.columns.map(\.name), ["Limit (A)"])
        XCTAssertEqual(table.rows.map(\.path).first, ["Rating group 1", "QA1"])
        XCTAssertEqual(table.rows.map(\.path).last, ["Rating group 2", "QB3"])
        let hit = try found(TableLookup.resolve(.init(table: "Table Q7", row: "QB1"), in: [source(table)]))
        XCTAssertEqual(hit.rows.first?.cells.first?.text, "20")
        XCTAssertEqual(try readPDF([TableFixtureLayouts.sideBySide()]).tables.first?.rows.count, 7)
    }

    // MARK: - Headings stacked deep, a list of tables, a caption at the foot of a page

    func testHeadingsStackedDeeperThanAShortHeaderAreReadAsTheHeader() throws {
        let table = try only(TableFixtureLayouts.deepHeadings())
        XCTAssertEqual(table.label, "Table 95B")
        XCTAssertEqual(table.rowHeaders, ["Designation"])
        XCTAssertEqual(table.columns.map(\.name), ["Rating group 1 at the invented ambient (A)",
                                                   "Rating group 2 at the invented ambient (A)",
                                                   "Rating group 3 at the invented ambient (A)"])
        XCTAssertEqual(table.columns.map(\.unit), ["A", "A", "A"])
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QA1", "QA2", "QA3", "QA4"])
        XCTAssertEqual(table.rows[2].cells.map(\.value), [31, 32, 33])
    }

    func testColumnHeadingsPrintedAsNumbersUnderASpanningHeadingHeadTheColumns() throws {
        let table = try only(TableFixtureLayouts.numberedHeadings())
        XCTAssertEqual(table.rowHeaders, ["Designation"])
        XCTAssertEqual(table.columns.map(\.path), [["Conductors in the run", "2"], ["Conductors in the run", "3"],
                                                   ["Conductors in the run", "4 or more"]], "the last may be words")
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QXRT", "QMX90", "QZ12"], "the heading row is not a row")
        let hit = try found(TableLookup.resolve(.init(table: "Table 99", row: "QMX90", column: "3 conductors in the run"),
                                                in: [source(table)]))
        XCTAssertEqual(hit.rows.first?.cells[hit.columns[0]].text, "35")
        // A grid whose columns carry their own headings keeps its first row of numbers as a row.
        XCTAssertEqual(try only(TableFixtureLayouts.simpleGrid()).rows.count, 4)
        XCTAssertEqual(try only(TableFixtureLayouts.twoLevelHeader()).rows.count, 4)
    }

    func testAListOfTablesIsNotCountedAsCaptionsWhenTheTablesArePrinted() throws {
        let read = try readPDF(TableFixtureLayouts.listOfTables())
        XCTAssertEqual(read.tables.map(\.label), ["Table 95A", "Table 95B"])
        XCTAssertEqual(read.captioned, 2, "the list's two lines are not two more captions")
        XCTAssertEqual(read.listedEntries, 2)
        XCTAssertTrue(read.failures.isEmpty)
        XCTAssertTrue(read.unextracted.isEmpty)
        // A list entry whose table is not printed anywhere stays, pointing at the list.
        let alone = try readPDF([TableFixtureLayouts.listOfTables()[0]])
        XCTAssertEqual(alone.unextracted.map(\.label), ["Table 95A", "Table 95B"])
        XCTAssertEqual(alone.listedEntries, 0)
    }

    func testACaptionAtTheFootOfAPageHeadsTheGridAtTheTopOfTheNext() throws {
        let read = try readPDF(TableFixtureLayouts.captionAtFoot())
        XCTAssertEqual(read.captioned, 1)
        XCTAssertTrue(read.failures.isEmpty)
        let table = try XCTUnwrap(read.tables.first)
        XCTAssertEqual(table.label, "Table 96")
        XCTAssertEqual(table.title, "Invented clearances")
        XCTAssertEqual(table.page.physical, 1, "the table starts where its caption is")
        XCTAssertEqual(table.columns.map(\.name), ["Indoor (mm)", "Outdoor (mm)"])
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QA1", "QA2", "QA3", "QA4"])
        XCTAssertEqual(table.rows.map(\.page.physical), [2, 2, 2, 2], "each row on the page it is printed on")
    }

    // MARK: - A table with no text to read

    func testATableWhosePageHasNoTextUnderItsCaptionSaysSo() throws {
        let found = TableExtractor.extractAll(words: TableFixtureLayouts.words(TableFixtureLayouts.tableWithoutText()),
                                              page: .init(physical: 4))
        XCTAssertEqual(found.map(\.outcome.failure), [.noTextInTable])
        XCTAssertEqual(TableExtractor.extractAll(words: TableFixtureLayouts.words(TableFixtureLayouts.captionOverProse()),
                                                 page: .init(physical: 1)).map(\.outcome.failure), [.tooFewRows],
                       "prose to the foot of the page leaves no empty stretch")
        let read = try readPDF([TableFixtureLayouts.tableWithoutText()])
        XCTAssertEqual(read.failures, [.noTextInTable: 1])
        let unread = try XCTUnwrap(read.unextracted.first)
        let text = TableLookup.render(TableLookup.resolve(.init(table: "Table 97", row: "QX4"), in: [source(unread)]))
        XCTAssertTrue(text.contains("most likely as a picture"), text)
        XCTAssertTrue(text.contains("Do not answer from memory"), text)
    }

    func testSideBySideGroupsWhoseHeadingsLandOnDifferentPathsStillReadAsOne() throws {
        let table = try only(TableFixtureLayouts.sideBySideSplitHeadings())
        XCTAssertEqual(table.rowHeaders, ["Designation"])
        XCTAssertEqual(table.columns.map(\.name), ["Maximum › limit (A)"])
        XCTAssertEqual(table.rows.map { $0.path.joined() }, ["QA1", "QA2", "QA3", "QB1", "QB2", "QB3"])
        let hit = try found(TableLookup.resolve(.init(table: "Table Q7", row: "QB3", column: "maximum limit"), in: [source(table)]))
        XCTAssertEqual(hit.rows.first?.cells.first?.text, "24")
    }

    // MARK: - The page of a table that was not read

    func testOnTheFirstPageOfAnUnreadTableOnlyThePassagePrintingItsLabelLeads() {
        func passage(_ index: Int, _ text: String, sim: Float) -> DocumentStore.Passage {
            DocumentStore.Passage(documentId: "a", documentName: "Invented Book A", chunkIndex: index, text: text,
                                  similarity: sim, page: 7, section: nil)
        }
        let clause = DocumentStore.Passage(documentId: "a", documentName: "Invented Book A", chunkIndex: 2,
                                           text: "Rule QR-12 Each invented designation is sized from Table 90 of this example.",
                                           similarity: 0.5, page: 3, section: "Rule QR-12")
        let pageStart = passage(10, "Paragraph lines of the invented manual about general care of the unit.", sim: 0.2)
        let caption = passage(11, "TABLE 90 Invented wiring notes. Each invented terminal is described below.", sim: 0.1)
        let retriever = VaultRetriever(query: { _, _ in [clause] }, tableSearch: { label in
            label == "Table 90" ? [pageStart, caption] : []
        }, policy: RetrievalEvidencePolicy(similarityFloor: 0))
        let passages = retriever.retrieve(.init(turn: "what does table 90 say about general care of the unit")).passages
        XCTAssertEqual(passages.first?.chunkIndex, 11, "the passage that prints the caption leads")
        XCTAssertEqual(passages.filter(\.tableMatch).map(\.chunkIndex), [11], "the page's other passage is not the table's")
        XCTAssertTrue(VaultRetriever.prints("Table 90", in: "see TABLE  90 for it"))
        XCTAssertFalse(VaultRetriever.prints("Table 90", in: "Table 901 and Table 90A"))
    }

    // MARK: - Names a chain gives a column or a row

    /// Invented: two rating groups over three bands, each heading with its unit in brackets, and
    /// rows keyed by printed ranges.
    private let bands = ManualTable(
        label: "Table 95A", title: "Invented band ratings", page: .init(physical: 3, printed: "30"),
        rowHeaders: ["Ambient"],
        columns: [.init(path: ["Rating group 1", "Band A (A)"], unit: "A"),
                  .init(path: ["Rating group 1", "Band B (A)"], unit: "A"),
                  .init(path: ["Rating group 2", "Band C (A)"], unit: "A")],
        rows: [("7-9", [11, 12, 13]), ("10 to 12", [21, 22, 23]), ("13 through 15", [31, 32, 33]),
               ("over 15 up to 18", [41, 42, 43])].map { key, values in
            ManualTable.Row(path: [key], cells: values.map { .init(text: "\($0)", value: Double($0), unit: "A") },
                            page: .init(physical: 3, printed: "30"))
        })

    private func cell(row: String, column: String?, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let hit = try found(TableLookup.resolve(.init(table: "Table 95A", row: row, column: column), in: [source(bands)]),
                            file: file, line: line)
        XCTAssertEqual(hit.rows.count, 1, file: file, line: line)
        XCTAssertEqual(hit.columns.count, 1, file: file, line: line)
        return hit.rows[0].cells[hit.columns[0]].text
    }

    func testAColumnResolvesByItsPathItsLastPartOrItsWordsIgnoringUnitsCaseAndPunctuation() throws {
        XCTAssertEqual(try cell(row: "7-9", column: "Rating group 1 › Band B (A)"), "12", "the full path")
        XCTAssertEqual(try cell(row: "7-9", column: "Rating group 1 > Band B"), "12", "another separator, no unit")
        XCTAssertEqual(try cell(row: "7-9", column: "Band A"), "11", "the last part, unique, without its unit")
        XCTAssertEqual(try cell(row: "7-9", column: "band c"), "13", "case")
        XCTAssertEqual(try cell(row: "7-9", column: "Band B (amps)"), "12", "a unit said another way")
        XCTAssertEqual(try cell(row: "7-9", column: "BAND A, rating group 1"), "11", "words in any order, punctuation")
        XCTAssertEqual(try cell(row: "7-9", column: "group 2 band C [A]"), "13")
    }

    func testAColumnThatFitsSeveralStillAsks() {
        guard case .ambiguous(.column, _, let candidates) = TableLookup.resolve(
            .init(table: "Table 95A", row: "7-9", column: "Rating group 1"), in: [source(bands)]) else {
            return XCTFail("two columns sit under rating group 1")
        }
        XCTAssertEqual(candidates, ["Rating group 1 › Band A (A)", "Rating group 1 › Band B (A)"])
        guard case .notFound(.column, _, _) = TableLookup.resolve(
            .init(table: "Table 95A", row: "7-9", column: "Rating group 3"), in: [source(bands)]) else {
            return XCTFail("no rating group 3: a number in the words is never approximated")
        }
    }

    func testARowResolvesByItsKeyANumberInsideAPrintedRangeOrItsWords() throws {
        XCTAssertEqual(try cell(row: "10 to 12", column: "Band A"), "21", "the key as printed")
        XCTAssertEqual(try cell(row: "8", column: "Band A"), "11", "in a range printed with a dash")
        XCTAssertEqual(try cell(row: "11", column: "Band A"), "21", "in a range printed with \"to\"")
        XCTAssertEqual(try cell(row: "14 °C", column: "Band A"), "31", "in a range printed with \"through\", a unit said")
        XCTAssertEqual(try cell(row: "17", column: "Band A"), "41", "over one number, up to another")
        XCTAssertEqual(try cell(row: "16", column: "Band A"), "41")
        guard case .found(let edge) = TableLookup.resolve(.init(table: "Table 95A", row: "15", column: "Band A"),
                                                          in: [source(bands)]) else { return XCTFail("15 is a row") }
        XCTAssertEqual(edge.rows.map(\.path), [["13 through 15"]], "15 is through 15, not over it")
    }

    func testARowResolvesByItsWordsInAnyOrderAndAnAmbiguousRowAsks() throws {
        let table = try only(TableFixtureLayouts.simpleGrid())
        let rows = try found(TableLookup.resolve(.init(table: "Table 99", row: "three conductors, QXRT",
                                                       column: "Rating group 2"), in: [source(table)]))
        XCTAssertEqual(rows.rows.map(\.path), [["QXRT", "three conductors"]])
        guard case .ambiguous(.row, _, let candidates) = TableLookup.resolve(
            .init(table: "Table 99", row: "QMX90", column: "Rating group 2"), in: [source(table)]) else {
            return XCTFail("QMX90 has two rows")
        }
        XCTAssertEqual(candidates.count, 2)
    }

    // MARK: - The shape report

    func testTheShapeReportRunsOnFixturePDFsAndPrintsCountsOnly() throws {
        let pages = [TableFixtureLayouts.captionOverProse(), TableFixtureLayouts.drawingUnderTableCaption(pitch: 12),
                     TableFixtureLayouts.simpleGrid()] + TableFixtureLayouts.captionlessContinuation()
        let url = try TableFixtures.write(TableFixtures.pdf(pages), named: "shapes.pdf", in: tempRoot)
        let document = try XCTUnwrap(PDFDocument(url: url))
        let report = TableShapeReport.report(
            pageCount: document.pageCount,
            mentionsTable: { document.page(at: $0)?.string?.range(of: "table", options: .caseInsensitive) != nil },
            words: { document.page(at: $0).map(PDFTableReader.positionedWords(on:)) ?? [] })
        XCTAssertEqual(report.shapes.map(\.failure), [.tooFewRows, .varyingColumnCount])
        XCTAssertEqual(report.shapes.map(\.index), [1, 2])
        XCTAssertEqual(report.extracted, 2)
        XCTAssertEqual(report.extractedNextPageSameClusters, 1, "the table whose rows carry on over the next page")
        XCTAssertEqual(report.continuationsRead, 1)
        XCTAssertEqual(report.captionLabelCensus, ["digits": 4])

        // Every word the report prints is the report's own: no label, title, heading or cell.
        let failures = TableExtractor.Failure.allCases.flatMap { $0.rawValue.split(separator: "_").map(String.init) }
        let vocabulary = Set(failures + [
            "SHAPE", "failed", "labels", "digits", "letter", "after", "letters", "before", "caption", "lines", "by", "label",
            "none", "below", "median", "under", "next", "page", "same", "clusters", "first", "repeats", "heading", "two",
            "groups", "headings", "repeat", "single", "char", "non", "numeric", "small", "words", "extracted",
            "continuation", "read", "header", "body", "line", "cells", "text", "again", "yes", "no", "dotted", "hyphenated",
            "roman", "other", "listed", "grid", "at", "top", "running", "to", "foot", "blank",
        ])
        let printed = TableShapeReport.render(report)
        XCTAssertFalse(printed.isEmpty)
        for line in printed {
            XCTAssertTrue(line.hasPrefix("[SHAPE]"), line)
            let words = line.split(whereSeparator: { !$0.isLetter }).map(String.init)
            XCTAssertEqual(words.filter { !vocabulary.contains($0) }, [], line)
        }
    }

    // MARK: - The cell-key scorer

    func testTheCellKeyScorerCountsAnInventedKeyAgainstInventedTables() throws {
        let runLengths = ManualTable(
            label: "Table 97", title: "Invented run lengths", page: .init(physical: 5),
            rowHeaders: ["Size"], columns: [.init(path: ["Length (m)"], unit: "m")],
            rows: [("1.5", 12), ("2.5", 18), ("4", 26)].map { size, length in
                ManualTable.Row(path: [size], cells: [.init(text: "\(length)", value: Double(length), unit: "m")],
                                page: .init(physical: 5))
            })
        let sources = [try only(TableFixtureLayouts.simpleGrid()), bands, runLengths,
                       .unextracted(.init(label: "Table 96", title: "Invented", continues: false), page: .init(physical: 7),
                                    failure: .tooFewRows)].map(source)
        let key = """
        // an invented key over invented tables
        {"q": "one", "table": "Table 99", "row": "QXRT three conductors", "column": "Rating group 2", "expect": "35", "edition": "Book A"}
        {"q": "two", "table": "Table 95A", "row": "11", "column": "Band A", "expect": 21}
        {"q": "three", "table": "Table 95A", "row": "16", "column": "Band A", "expect": "99"}
        {"q": "four", "table": "Table 97", "row": "3", "column": null, "expect": {"below": "2.5", "above": "4"}}
        {"q": "five", "table": "Table 99", "row": "QXRT", "column": "Rating group 1", "expect": {"ask": true, "candidates": ["QXRT two conductors", "QXRT three conductors"]}}
        {"q": "six", "table": "Table 89", "row": "QZ1", "expect": "1"}
        {"q": "seven", "table": "Table 96", "row": "QA1", "expect": "10"}
        not a line of the key
        """
        let parsed = TableLookupEval.parse(key)
        XCTAssertEqual(parsed.questions.count, 7)
        XCTAssertEqual(parsed.unreadable, 1)
        XCTAssertEqual(TableLookupEval.parseCounting(key).unreadable, [.notJSON: 1])
        let odd = """
        {"table": "Table 99", "expect": "1"}
        {"table": "Table 99", "row": "QXRT", "expect": null}
        {"table": "Table 99", "row": "QXRT", "expect": {"between": 3}}
        {"row": "QXRT", "expect": "1"}
        """
        XCTAssertEqual(TableLookupEval.parseCounting(odd).unreadable, [.noRow: 1, .noExpect: 1, .expectShape: 1, .noTable: 1])
        let report = TableLookupEval.score(parsed.questions, unreadable: parsed.unreadable, sources: sources)
        XCTAssertEqual(report, TableLookupEval.Report(
            questions: 7, unreadable: 1, tableRead: 5, tableUnread: 1, tableMissing: 1, tableAmbiguous: 0,
            rowResolved: 3, columnResolved: 5, cellsExpected: 5, cellsMatched: 2, betweenExpected: 1, betweenMatched: 1,
            askExpected: 1, askMatched: 1, askCandidatesAgree: 1))
        let printed = TableLookupEval.render(report, label: "fixture")
        XCTAssertTrue(printed[0].contains("against the unchecked key"), printed[0])
        for line in printed {
            for leaked in ["QXRT", "Table", "Band", "Rating", "invented", "35", "QZ1"] {
                XCTAssertFalse(line.contains(leaked), "\(leaked) in \(line)")
            }
        }
    }

    func testTheValidatorResolvesAChainsColumnByItsWords() {
        let chains = """
        ## Invented band check
        Answers: an invented test.

        ```
        ask ambient (°C) range 0..40: What is the ambient?
        lookup rating = Table 95A row {ambient} column Band A rule exact
        cite Rule QR-12
        lookup other = Table 95A row 11 column rating group 1 › band b rule exact
        cite Rule QR-14
        say "The rating is {rating}, the other {other}."
        ```
        """
        let report = ChainsValidate.check(.init(fileName: "chains.md", contents: chains, listedFiles: ["chains.md"],
                                                tables: [bands]))
        XCTAssertEqual(report.lookups.map(\.column.resolution), [.resolved, .resolved])
        XCTAssertEqual(report.lookups.map { $0.row?.resolution }, [.fromValue, .resolved])
    }
}
