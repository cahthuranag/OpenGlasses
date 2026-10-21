import CoreGraphics
import XCTest
@testable import OpenGlasses

/// Plan JN P0 — a table printed as a picture, read from what a recogniser saw: reader A (recognised
/// words through the text extractor's own rules), reader B (the recogniser's grid of cells), the
/// stored model's new fields, and the header rule both readers share. Every table is invented
/// (`RecognisedTableFixtures`).
final class RecognisedTableTests: XCTestCase {

    private typealias F = RecognisedTableFixtures
    private let page = ManualTable.Page(physical: 7, printed: "31")

    private func readerA(_ words: [RecognisedWord], file: StaticString = #filePath, line: UInt = #line) throws -> ManualTable {
        let reading = RecognisedWords.table(RecognisedPage(words: words), captionWords: F.q7CaptionWords(),
                                            caption: F.q7Caption, page: page)
        return try XCTUnwrap(reading.outcome.table, "\(reading.outcome)", file: file, line: line)
    }

    private func readerB(_ cells: [RecognisedPage.Cell], file: StaticString = #filePath, line: UInt = #line) throws -> ManualTable {
        let reading = RecognisedGrid.table(RecognisedPage(tables: [.init(cells: cells)]), caption: F.q7Caption, page: page)
        return try XCTUnwrap(reading.outcome.table, "\(reading.outcome)", file: file, line: line)
    }

    private func failure(_ cells: [RecognisedPage.Cell]) -> TableExtractor.Failure? {
        RecognisedGrid.table(RecognisedPage(tables: [.init(cells: cells)]), caption: F.q7Caption, page: page).outcome.failure
    }

    // MARK: - Reader A: words into the extractor

    func testPositionedWordsTakeTheirSizeFromTheBoxAndAreNeverBold() {
        let word = RecognisedWord("QXRT", rect: CGRect(x: 10, y: 20, width: 30, height: 11.5), confidence: 0.4)
        let positioned = RecognisedWords.positioned([word])
        XCTAssertEqual(positioned, [PositionedWord("QXRT", rect: word.rect, size: 11.5, bold: false)])
    }

    func testReaderAReadsRecognisedWordsThroughTheExtractor() throws {
        let table = try readerA(F.q7Words())
        XCTAssertEqual(table.label, "Table Q7")
        XCTAssertEqual(table.title, "Invented clearances")
        XCTAssertEqual(table.page, page)
        XCTAssertEqual(table.rowHeaders, ["Designation"])
        XCTAssertEqual(table.columns.map(\.name), ["Clearance (mm)", "Spacing (mm)", "Limit (A)"])
        XCTAssertEqual(table.columns.map(\.unit), ["mm", "mm", "A"])
        XCTAssertEqual(table.rows.map(\.path), [["QXRT"], ["QMX90"], ["QZ12"], ["QA7"]])
        XCTAssertEqual(table.rows[2].cells.map(\.value), [18, 40, 25])
        XCTAssertEqual(table.rows[2].cells[0].unit, "mm")
        guard case .recognised(let reader, let mean) = table.source else { return XCTFail("\(table.source)") }
        XCTAssertEqual(reader, .words)
        XCTAssertEqual(mean, 0.97, accuracy: 0.0001)
        XCTAssertFalse(table.rows.flatMap(\.cells).contains(where: \.uncertain), "the readers mark nothing; certainty does")
    }

    func testReaderAReadsTheCaptionInOneWeightAndTiesEachCellToItsWords() throws {
        var words = F.q7Words()
        let sixteen = try XCTUnwrap(words.first { $0.text == "16" })
        words.append(F.marker("1", after: sixteen))
        let reading = RecognisedWords.table(RecognisedPage(words: words), captionWords: F.q7CaptionWords(bold: true),
                                            caption: F.q7Caption, page: page)
        let table = try XCTUnwrap(reading.outcome.table, "a bold caption over unweighted words still reads one weight")
        XCTAssertEqual(table.rows[0].cells[2].text, "16\u{00B9}")
        XCTAssertEqual(table.rows[0].cells[2].markers, ["1"], "a marker read as a word of its own")
        XCTAssertEqual(table.rows[0].cells[2].value, 16)
        XCTAssertEqual(reading.cells.count, 4)
        XCTAssertEqual(reading.cells[0][2].words.map(\.text), ["16", "1"])
        XCTAssertEqual(reading.cells[3][1].words.map(\.text), ["45"])
        guard case .box = reading.cells[3][1].place else { return XCTFail("a words reading is placed by box") }
    }

    func testReaderAWithoutTheCaptionOnThePageFindsNoTable() {
        let reading = RecognisedWords.table(RecognisedPage(words: F.q7Words()), captionWords: [],
                                            caption: F.q7Caption, page: page)
        XCTAssertEqual(reading.outcome.failure, .captionNotFound)
    }

    // MARK: - Reader B: the recogniser's grid

    func testBothReadersAgreeOnTheSameInventedTable() throws {
        let fromWords = try readerA(F.q7Words())
        let fromGrid = try XCTUnwrap(RecognisedGrid.table(F.q7Grid(), caption: F.q7Caption, page: page).outcome.table)
        XCTAssertEqual(fromGrid.rowHeaders, fromWords.rowHeaders)
        XCTAssertEqual(fromGrid.columns, fromWords.columns)
        XCTAssertEqual(fromGrid.rows, fromWords.rows)
        XCTAssertEqual(fromGrid.title, fromWords.title)
        guard case .recognised(.documentGrid, _) = fromGrid.source else { return XCTFail("\(fromGrid.source)") }
    }

    func testASpannedGroupHeadingBecomesALevelOfEachColumnsPath() throws {
        let cells = [
            F.cell(0...1, 0...0, "Designation"),
            F.cell(0...0, 1...2, "Rating group 1"), F.cell(0...0, 3...4, "Rating group 2"),
            F.cell(1, 1, "Band A"), F.cell(1, 2, "Band B"), F.cell(1, 3, "Band A"), F.cell(1, 4, "Band B"),
        ] + F.grid([[], [],
                    ["QXRT", "1.13", "1.09", "1.12", "1.08"], ["QMX90", "0.99", "0.98", "0.98", "0.97"],
                    ["QZ12", "0.83", "0.87", "0.82", "0.86"]])
        let table = try readerB(cells)
        XCTAssertEqual(table.columns.map(\.path), [["Rating group 1", "Band A"], ["Rating group 1", "Band B"],
                                                   ["Rating group 2", "Band A"], ["Rating group 2", "Band B"]])
        XCTAssertEqual(table.rowHeaders, ["Designation"], "a heading spanning both header rows is one level")
        XCTAssertEqual(table.rows.map(\.path), [["QXRT"], ["QMX90"], ["QZ12"]])
        XCTAssertEqual(table.rows[1].cells[2].value, 0.98)
    }

    func testARowHeaderSpanningRowsBecomesALevelOfEachRowsPath() throws {
        let cells = F.grid([["Designation", "Conductors", "Limit group 1", "Limit group 2"]]) + [
            F.cell(1...2, 0...0, "QXRT"), F.cell(1, 1, "two conductors"), F.cell(1, 2, "25"), F.cell(1, 3, "30"),
            F.cell(2, 1, "three conductors"), F.cell(2, 2, "30"), F.cell(2, 3, "35"),
            F.cell(3...4, 0...0, "QMX90"), F.cell(3, 1, "two conductors"), F.cell(3, 2, "40"), F.cell(3, 3, "45"),
            F.cell(4, 1, "three conductors"), F.cell(4, 2, "45"), F.cell(4, 3, "50"),
        ]
        let table = try readerB(cells)
        XCTAssertEqual(table.rowHeaders, ["Designation", "Conductors"])
        XCTAssertEqual(table.rows.map(\.path), [["QXRT", "two conductors"], ["QXRT", "three conductors"],
                                                ["QMX90", "two conductors"], ["QMX90", "three conductors"]])
        XCTAssertEqual(table.rows[3].cells.map(\.value), [45, 50])
    }

    func testACellAloneAcrossARowHeadsTheRowsUnderIt() throws {
        let cells = F.grid([F.q7Header, F.q7Body[0], F.q7Body[1]])
            + [F.cell(3...3, 0...3, "Outdoor runs")]
            + F.grid([[], [], [], [], F.q7Body[2], F.q7Body[3]])
        let table = try readerB(cells)
        XCTAssertEqual(table.rows.map(\.path), [["QXRT"], ["QMX90"], ["Outdoor runs", "QZ12"], ["Outdoor runs", "QA7"]])
    }

    func testABlankRowHeaderIsNotFilledFromTheRowAbove() throws {
        let cells = F.grid([["Designation", "Conductors", "Limit group 1"],
                            ["QXRT", "two conductors", "25"], ["", "three conductors", "30"],
                            ["QMX90", "two conductors", "40"]])
        let table = try readerB(cells)
        XCTAssertEqual(table.rows.map(\.path), [["QXRT", "two conductors"], ["three conductors"], ["QMX90", "two conductors"]],
                       "a blank in a picture may be a missed cell; no key is guessed into it")
    }

    func testAFootnoteMarkerReadAsItsOwnWordIsTheCellsMarker() throws {
        var cells = F.grid([F.q7Header, F.q7Body[0], F.q7Body[2], F.q7Body[3]])
        cells.removeAll { $0.rowRange == 1...1 && $0.columnRange == 3...3 }
        var marked = F.cell(1, 3, "45")
        marked.words.append(F.marker("1", after: marked.words[0]))
        cells.append(marked)
        cells.removeAll { $0.rowRange == 2...2 && $0.columnRange == 3...3 }
        cells.append(F.cell(2, 3, "40*"))
        let table = try readerB(cells)
        XCTAssertEqual(table.rows[0].cells[2], ManualTable.Cell(text: "45\u{00B9}", value: 45, unit: "A", markers: ["1"]))
        XCTAssertEqual(table.rows[1].cells[2], ManualTable.Cell(text: "40*", value: 40, unit: "A", markers: ["*"]))
    }

    func testNumberedColumnHeadingsUnderASpanningHeadingHeadTheColumns() throws {
        let cells = [F.cell(0...1, 0...0, "Designation"), F.cell(0...0, 1...3, "Conductors in run"),
                     F.cell(1, 1, "1"), F.cell(1, 2, "2"), F.cell(1, 3, "3")]
            + F.grid([[], [], ["QXRT", "1.0", "0.8", "0.7"], ["QMX90", "1.0", "0.85", "0.75"],
                      ["QZ12", "1.0", "0.9", "0.8"], ["QA7", "1.0", "0.95", "0.85"]])
        let table = try readerB(cells)
        XCTAssertEqual(table.columns.map(\.name), ["Conductors in run › 1", "Conductors in run › 2", "Conductors in run › 3"])
        XCTAssertEqual(table.rows.map(\.path), [["QXRT"], ["QMX90"], ["QZ12"], ["QA7"]])
    }

    func testAGridOfWordsTakesItsFirstRowAsTheHeadings() throws {
        let table = try readerB(F.grid([["Designation", "Indoor", "Outdoor"], ["QXRT", "permitted", "not permitted"],
                                        ["QMX90", "permitted", "permitted"], ["QZ12", "not permitted", "permitted"]]))
        XCTAssertEqual(table.columns.map(\.name), ["Indoor", "Outdoor"])
        XCTAssertEqual(table.rows.map(\.path), [["QXRT"], ["QMX90"], ["QZ12"]])
        XCTAssertEqual(table.rows[2].cells.map(\.text), ["not permitted", "permitted"])
    }

    // MARK: - Reader B: what is not a table

    func testAGridWithTooFewRowsFailsTheRowTest() {
        XCTAssertEqual(failure(F.grid([F.q7Header, F.q7Body[0], F.q7Body[1]])), .tooFewRows)
    }

    func testHolesInTheGridFailAsColumnsThatDoNotAgree() {
        var cells = F.grid([F.q7Header] + F.q7Body + [["QB2", "24", "50", "40"]])
        cells.removeAll { ($0.rowRange == 2...2 || $0.rowRange == 4...4) && $0.columnRange == 3...3 }
        XCTAssertEqual(failure(cells), .varyingColumnCount)
    }

    func testValueCellsSpanningColumnsFailAsMergedCells() {
        var cells = F.grid([F.q7Header] + F.q7Body)
        for row in [2, 3] {
            cells.removeAll { $0.rowRange == row...row && $0.columnRange.lowerBound >= 2 }
            cells.append(F.cell(row...row, 2...3, "40"))
        }
        XCTAssertEqual(failure(cells), .mergedCells)
    }

    func testARecognitionWithNoTableStaysNoTextInTable() {
        XCTAssertEqual(RecognisedGrid.table(RecognisedPage(), caption: F.q7Caption, page: page).outcome.failure, .noTextInTable)
        XCTAssertEqual(failure(F.grid([["", ""], ["", ""], ["", ""], ["", ""]])), .noTextInTable)
    }

    // MARK: - The header rule both readers share

    func testTheOneWeightHeaderRuleIsOneFunction() {
        func row(_ cells: [String]) -> TableExtractor.HeaderRuleRow {
            .init(cells: cells.map { ($0, [String]()) })
        }
        let heading = row(["Designation", "Limit (A)", "Spacing (mm)"])
        let numbers = row(["QA7", "14", "26"])
        let words = row(["QXRT", "permitted", "not permitted"])
        let none: (Int) -> Int = { _ in 0 }
        XCTAssertEqual(TableExtractor.plainHeader(rows: [heading, numbers, numbers, numbers], wrapTitle: none,
                                                  isHeaderLine: { _ in true }).count, 1)
        XCTAssertEqual(TableExtractor.plainHeader(rows: [heading, heading, numbers, numbers, numbers], wrapTitle: none,
                                                  isHeaderLine: { _ in true }).count, 2)
        XCTAssertEqual(TableExtractor.plainHeader(rows: [heading, numbers, numbers, numbers], wrapTitle: none,
                                                  isHeaderLine: { _ in false }).count, 0, "no line may head it")
        XCTAssertEqual(TableExtractor.plainHeader(rows: [heading, words, words, words], wrapTitle: none,
                                                  isHeaderLine: { _ in true }).count, 1, "a grid of words")
        XCTAssertEqual(TableExtractor.plainHeader(rows: [words, words], wrapTitle: none,
                                                  isHeaderLine: { _ in true }).count, 0)
        let wrapped = TableExtractor.plainHeader(rows: [row(["for a test"]), heading, numbers, numbers, numbers],
                                                 wrapTitle: { _ in 1 }, isHeaderLine: { _ in true })
        XCTAssertEqual(wrapped.start, 1)
        XCTAssertEqual(wrapped.count, 2)
    }

    // MARK: - The stored model

    /// A table as stored before Plan JN, keys sorted as `DocumentStore` writes them.
    private let preJN = #"{"columns":[{"path":["Limit (A)"],"unit":"A"}],"continues":false,"label":"Table 95","notes":[{"marker":"*","text":"Value for a dry location."}],"page":{"physical":3,"printed":"12"},"rowHeaders":["Designation"],"rows":[{"cells":[{"markers":["*"],"text":"40*","unit":"A","value":40},{"markers":[],"text":""}],"page":{"physical":3,"printed":"12"},"path":["QXRT"]}],"title":"Rating limits"}"#

    private func sortedJSON(_ table: ManualTable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(String(data: encoder.encode(table), encoding: .utf8))
    }

    func testATableStoredBeforePlanJNDecodesAsATextLayerTableWithCertainCells() throws {
        let table = try JSONDecoder().decode(ManualTable.self, from: Data(preJN.utf8))
        XCTAssertEqual(table.source, .textLayer)
        XCTAssertFalse(table.rows[0].cells.contains(where: \.uncertain))
        XCTAssertEqual(table, ManualTable(
            label: "Table 95", title: "Rating limits", page: .init(physical: 3, printed: "12"), rowHeaders: ["Designation"],
            columns: [.init(path: ["Limit (A)"], unit: "A")],
            rows: [.init(path: ["QXRT"], cells: [.init(text: "40*", value: 40, unit: "A", markers: ["*"]), .init(text: "")],
                         page: .init(physical: 3, printed: "12"))],
            notes: [.init(marker: "*", text: "Value for a dry location.")]))
        XCTAssertEqual(try sortedJSON(table), preJN, "a text-layer table stores the same JSON it stored before")

        let unread = #"{"columns":[],"continues":false,"failure":"no_text_in_table","label":"Table 97","notes":[],"page":{"physical":9},"rowHeaders":[],"rows":[],"title":"Invented resistances"}"#
        let old = try JSONDecoder().decode(ManualTable.self, from: Data(unread.utf8))
        XCTAssertEqual(old.failure, .noTextInTable)
        XCTAssertEqual(old.source, .textLayer)
        XCTAssertEqual(try sortedJSON(old), unread)
    }

    func testARecognisedTableKeepsItsSourceAndUncertainCellsThroughJSON() throws {
        var table = try XCTUnwrap(RecognisedGrid.table(F.q7Grid(confidence: 0.91), caption: F.q7Caption, page: page).outcome.table)
        table.rows[1].cells[0].uncertain = true
        let json = try sortedJSON(table)
        XCTAssertTrue(json.contains(#""uncertain":true"#))
        XCTAssertTrue(json.contains(#""reader":"document_grid""#))
        XCTAssertEqual(try JSONDecoder().decode(ManualTable.self, from: Data(json.utf8)), table)
    }

    func testAnUnclearPictureHasItsOwnReasonInALookup() {
        let table = ManualTable.unextracted(F.q7Caption, page: page, failure: .unclearInPicture)
        let said = TableLookup.render(.notExtracted(.init(documentId: "doc", documentName: "Invented manual", table: table)))
        XCTAssertTrue(said.contains("the table was read from a picture and too few of its cells could be read clearly"), said)
        XCTAssertEqual(TableExtractor.Failure.unclearInPicture.rawValue, "unclear_in_picture")
    }
}
