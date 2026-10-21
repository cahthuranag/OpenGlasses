import CoreGraphics
import XCTest
@testable import OpenGlasses

/// Plan JN P1 — a misread row key or column heading points a lookup at another row's or column's
/// values, so they are judged as a value cell is, and a lookup that leans on one, or on an
/// uncertain cell, gives no value. Also the letters added to the confusable set. Every table is
/// invented (`RecognisedTableFixtures`).
final class HeadingCertaintyTests: XCTestCase {

    private typealias F = RecognisedTableFixtures
    private let page = ManualTable.Page(physical: 7, printed: "31")
    private let floor: Float = 0.6

    private func assessed(_ recognised: RecognisedPage, secondPass: RecognisedPage? = nil,
                          file: StaticString = #filePath, line: UInt = #line) throws -> (ManualTable, CellCertainty.Assessment) {
        let reading = RecognisedGrid.table(recognised, caption: F.q7Caption, page: page)
        let assessment = CellCertainty.assess(reading, floor: floor, secondPass: secondPass)
        return (try XCTUnwrap(assessment.outcome.table, "\(assessment.outcome)", file: file, line: line), assessment)
    }

    /// Table Q7's grid with one cell's words read at `confidence`.
    private func grid(lowAt row: Int, _ column: Int, confidence: Float = 0.3) -> RecognisedPage {
        var page = F.q7Grid()
        page.tables[0].cells = page.tables[0].cells.map { cell in
            guard cell.rowRange == row...row, cell.columnRange == column...column else { return cell }
            var cell = cell
            cell.words = cell.words.map { var word = $0; word.confidence = confidence; return word }
            return cell
        }
        return page
    }

    /// A grid keyed by numbers: "Size" over the keys 10, 12, 14, 16, and three value columns
    /// numbered 40, 55 and 70 under one heading over them, as a book prints them.
    private func numberKeyed(keys: [String] = ["10", "12", "14", "16"], headings: [String] = ["40", "55", "70"]) -> RecognisedPage {
        var cells = [F.cell(0...1, 0...0, "Size"), F.cell(0...0, 1...3, "Invented band")]
        cells += headings.enumerated().map { F.cell(1, $0.offset + 1, $0.element) }
        for (index, key) in keys.enumerated() {
            cells += [F.cell(index + 2, 0, key), F.cell(index + 2, 1, "2\(index)"), F.cell(index + 2, 2, "3\(index)"),
                      F.cell(index + 2, 3, "4\(index)")]
        }
        return RecognisedPage(tables: [.init(cells: cells)])
    }

    // MARK: - Row keys

    func testAClearGridHasNoUncertainKeyOrHeading() throws {
        let (table, assessment) = try assessed(F.q7Grid(), secondPass: F.q7Grid())
        XCTAssertFalse(table.rows.contains(where: \.keyUncertain))
        XCTAssertFalse(table.columns.contains(where: \.uncertain))
        XCTAssertEqual(assessment.uncertainKeys, 0)
        XCTAssertEqual(assessment.uncertainColumns, 0)
    }

    func testARowKeyUnderTheFloorMarksTheRowsKeyAndNotItsCells() throws {
        let (table, assessment) = try assessed(grid(lowAt: 2, 0))
        XCTAssertEqual(table.rows.map(\.keyUncertain), [false, true, false, false])
        XCTAssertFalse(table.rows[1].cells.contains(where: \.uncertain), "its values read clearly")
        XCTAssertEqual(table.rows[1].path, ["QMX90"], "the key is kept as read")
        XCTAssertEqual(assessment.uncertainKeys, 1)
    }

    func testARowKeyTheSecondPassReadsDifferentlyIsUncertain() throws {
        let second = F.replacing(F.q7Grid(), row: 3, column: 0, with: "QZ1Z")
        let (table, _) = try assessed(F.q7Grid(), secondPass: second)
        XCTAssertEqual(table.rows.map(\.keyUncertain), [false, false, true, false])
    }

    func testAConfusableGlyphInANumberKeyIsUncertain() throws {
        let (table, _) = try assessed(numberKeyed(keys: ["10", "12", "1S", "16"]))
        XCTAssertEqual(table.rows.map(\.keyUncertain), [false, false, true, false])
        let (letters, _) = try assessed(numberKeyed(keys: ["QXRT", "QMX90", "QZ12", "QA7"]))
        XCTAssertFalse(letters.rows.contains(where: \.keyUncertain), "designations are not numbers to doubt")
    }

    func testAHeadingOverRowsIsPartOfTheirKey() throws {
        let cells = [F.cell(0, 0, "Designation"), F.cell(0, 1, "Limit (A)"),
                     F.cell(1, 0, "QA1"), F.cell(1, 1, "10"),
                     F.cell(2, 0, "Invented group", confidence: 0.2),
                     F.cell(3, 0, "QA2"), F.cell(3, 1, "12"), F.cell(4, 0, "QA3"), F.cell(4, 1, "14"),
                     F.cell(5, 0, "QA4"), F.cell(5, 1, "16")]
        let (table, _) = try assessed(RecognisedPage(tables: [.init(cells: cells)]))
        XCTAssertEqual(table.rows.map(\.path), [["QA1"], ["Invented group", "QA2"], ["Invented group", "QA3"],
                                                ["Invented group", "QA4"]])
        XCTAssertEqual(table.rows.map(\.keyUncertain), [false, true, true, true],
                       "an unclear heading over rows makes each of their keys unclear")
    }

    // MARK: - Column headings

    func testAColumnHeadingUnderTheFloorMarksTheColumn() throws {
        let (table, assessment) = try assessed(grid(lowAt: 0, 2))
        XCTAssertEqual(table.columns.map(\.uncertain), [false, true, false])
        XCTAssertEqual(assessment.uncertainColumns, 1)
        XCTAssertFalse(table.rows.flatMap(\.cells).contains(where: \.uncertain))
    }

    func testAConfusableGlyphInANumberHeadingIsUncertain() throws {
        // A heading read "5S" between "40" and "70" (judged on the table's own headings; the
        // grid's numbered-heading row needs numbers to be read as headings at all).
        let reading = RecognisedGrid.table(numberKeyed(), caption: F.q7Caption, page: page)
        var table = try XCTUnwrap(reading.outcome.table)
        XCTAssertEqual(table.columns.map(\.path), [["Invented band", "40"], ["Invented band", "55"], ["Invented band", "70"]])
        XCTAssertEqual(CellCertainty.assessHeadings(&table, reading: reading, floor: floor, secondPass: nil).columns, 0)
        table.columns[1].path[1] = "5S"
        XCTAssertEqual(CellCertainty.assessHeadings(&table, reading: reading, floor: floor, secondPass: nil).columns, 1)
        XCTAssertEqual(table.columns.map(\.uncertain), [false, true, false])
    }

    func testAHeadingTheSecondPassReadsDifferentlyIsUncertain() throws {
        let second = F.replacing(F.q7Grid(), row: 0, column: 3, with: "Limit (4)")
        let (table, _) = try assessed(F.q7Grid(), secondPass: second)
        XCTAssertEqual(table.columns.map(\.uncertain), [false, false, true])
    }

    // MARK: - Reader A's keys and headings

    func testReaderATiesEachKeyAndHeadingToItsWords() throws {
        let reading = RecognisedWords.table(RecognisedPage(words: F.q7Words()), captionWords: F.q7CaptionWords(),
                                            caption: F.q7Caption, page: page)
        XCTAssertEqual(reading.rowKeys.count, 4)
        XCTAssertTrue(reading.rowKeys.allSatisfy { $0.count == 1 && !$0[0].words.isEmpty }, "\(reading.rowKeys)")
        XCTAssertEqual(reading.columnHeadings.count, 3)
        XCTAssertTrue(reading.columnHeadings.allSatisfy { !$0.isEmpty && !$0[0].words.isEmpty })
        let clear = CellCertainty.assess(reading, floor: floor, secondPass: RecognisedPage(words: F.q7Words()))
        XCTAssertEqual(clear.uncertainKeys, 0)
        XCTAssertEqual(clear.uncertainColumns, 0)

        let low = RecognisedWords.table(RecognisedPage(words: F.q7Words(low: (row: 1, column: 0, confidence: 0.2))),
                                        captionWords: F.q7CaptionWords(), caption: F.q7Caption, page: page)
        let table = try XCTUnwrap(CellCertainty.assess(low, floor: floor).outcome.table)
        XCTAssertEqual(table.rows.map(\.keyUncertain), [false, true, false, false])
    }

    func testReaderAMarksAKeyItCannotTieToItsWords() throws {
        let reading = RecognisedWords.table(RecognisedPage(words: F.q7Words()), captionWords: F.q7CaptionWords(),
                                            caption: F.q7Caption, page: page)
        var untied = reading
        untied.rowKeys[2] = [.missing]
        let table = try XCTUnwrap(CellCertainty.assess(untied, floor: floor).outcome.table)
        XCTAssertTrue(table.rows[2].keyUncertain)
    }

    // MARK: - Stored only when set

    func testKeyAndHeadingDoubtIsStoredOnlyWhenSetAndOlderJSONReadsClear() throws {
        let clear = ManualTable.Row(path: ["QA1"], cells: [.init(text: "10", value: 10)], page: page)
        let json = String(decoding: try JSONEncoder().encode(clear), as: UTF8.self)
        XCTAssertFalse(json.contains("keyUncertain"))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(ManualTable.Column(path: ["Limit (A)"], unit: "A")),
                              as: UTF8.self).contains("uncertain"))
        var doubtful = clear
        doubtful.keyUncertain = true
        let decoded = try JSONDecoder().decode(ManualTable.Row.self, from: try JSONEncoder().encode(doubtful))
        XCTAssertTrue(decoded.keyUncertain)
        let column = try JSONDecoder().decode(ManualTable.Column.self,
                                              from: try JSONEncoder().encode(ManualTable.Column(path: ["55"], uncertain: true)))
        XCTAssertTrue(column.uncertain)
        let old = #"{"path":["QA1"],"cells":[{"text":"10","value":10,"markers":[]}],"page":{"physical":7}}"#
        XCTAssertFalse(try JSONDecoder().decode(ManualTable.Row.self, from: Data(old.utf8)).keyUncertain)
        XCTAssertFalse(try JSONDecoder().decode(ManualTable.Column.self, from: Data(#"{"path":["55"]}"#.utf8)).uncertain)
    }

    // MARK: - The lookup gives no value

    private func source(_ table: ManualTable) -> TableLookup.Source {
        TableLookup.Source(documentId: "d1", documentName: "Invented Book", table: table)
    }

    private func pictured(_ recognised: RecognisedPage = F.q7Grid()) throws -> ManualTable {
        try assessed(recognised).0
    }

    func testALookupOnAClearPicturedCellGivesIt() throws {
        let outcome = TableLookup.resolve(.init(table: "Table Q7", row: "QMX90", column: "Spacing"), in: [source(try pictured())])
        guard case .found(let found) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(found.rows[0].cells[found.columns[0]].text, "35")
    }

    func testALookupOnAnUncertainKeyAnUncertainColumnOrAnUncertainCellGivesNoValue() throws {
        var table = try pictured()
        table.rows[1].keyUncertain = true
        assertUnclear(TableLookup.resolve(.init(table: "Table Q7", row: "QMX90", column: "Spacing"), in: [source(table)]))

        table = try pictured()
        table.columns[1].uncertain = true
        assertUnclear(TableLookup.resolve(.init(table: "Table Q7", row: "QMX90", column: "Spacing"), in: [source(table)]))
        // The same row read in another column is still given.
        guard case .found = TableLookup.resolve(.init(table: "Table Q7", row: "QMX90", column: "Clearance"), in: [source(table)])
        else { return XCTFail("a clear column of the same table") }

        table = try pictured()
        table.rows[1].cells[1].uncertain = true
        assertUnclear(TableLookup.resolve(.init(table: "Table Q7", row: "QMX90", column: "Spacing"), in: [source(table)]))
        // The whole row asked for holds the uncertain cell: no value from it.
        assertUnclear(TableLookup.resolve(.init(table: "Table Q7", row: "QMX90"), in: [source(table)]))
    }

    func testANumberBetweenRowsIsNotPlacedWhenAnyKeyIsUncertain() throws {
        var table = try pictured(numberKeyed())
        let between = TableLookup.resolve(.init(table: "Table Q7", row: "13", column: "55"), in: [source(table)])
        guard case .found(let found) = between, found.between == 13 else { return XCTFail("\(between)") }
        table.rows[3].keyUncertain = true
        assertUnclear(TableLookup.resolve(.init(table: "Table Q7", row: "13", column: "55"), in: [source(table)]))
        assertUnclear(TableLookup.resolve(.init(table: "Table Q7", row: "13", column: "55"), rule: .atLeast, in: [source(table)]))
        assertUnclear(TableLookup.resolve(.init(table: "Table Q7", row: "20", column: "55"), rule: .atMost, in: [source(table)]))
    }

    func testSearchingAColumnWithAnUncertainCellGivesNoRow() throws {
        var table = try pictured(numberKeyed())
        guard case .found = TableLookup.search(.init(table: "Table Q7", row: "", column: "55"), value: 31, rule: .atLeast,
                                               in: [source(table)]) else { return XCTFail("clear") }
        table.rows[0].cells[1].uncertain = true
        guard case .refused(let refused) = TableLookup.search(.init(table: "Table Q7", row: "", column: "55"), value: 31,
                                                              rule: .atLeast, in: [source(table)]) else { return XCTFail("refused") }
        assertUnclear(refused)
    }

    func testTheRefusalNamesThePageAndGivesNoValue() throws {
        var table = try pictured()
        table.rows[1].cells[1].uncertain = true
        let text = TableLookup.render(TableLookup.resolve(.init(table: "Table Q7", row: "QMX90", column: "Spacing"),
                                                          in: [source(table)]))
        XCTAssertTrue(text.contains("could not be read clearly"), text)
        XCTAssertTrue(text.contains("page 31"), text)
        XCTAssertTrue(text.contains("Do not answer from memory"), text)
        XCTAssertFalse(text.contains("35"), "no value-only token of the cell: \(text)")
    }

    func testAChainStepStopsOnAnUnclearCell() throws {
        var table = try pictured()
        table.rows[1].cells[1].uncertain = true
        let outcome = TableLookup.resolve(.init(table: "Table Q7", row: "QMX90", column: "Spacing"), rule: .exact, in: [source(table)])
        assertUnclear(outcome)
    }

    func testNothingUncertainIsWrittenIntoARowPassage() throws {
        var table = try pictured()
        let clear = try XCTUnwrap(TableRowPassage.sentence(for: table.rows[1], in: table))
        XCTAssertTrue(clear.contains("35 in Spacing (mm)"), clear)
        table.rows[1].cells[1].uncertain = true
        let withoutCell = try XCTUnwrap(TableRowPassage.sentence(for: table.rows[1], in: table))
        XCTAssertFalse(withoutCell.contains("35"), withoutCell)
        XCTAssertTrue(withoutCell.contains("14 in Clearance (mm)"), withoutCell)
        table.columns[0].uncertain = true
        XCTAssertFalse(try XCTUnwrap(TableRowPassage.sentence(for: table.rows[1], in: table)).contains("14"))
        table.rows[1].keyUncertain = true
        XCTAssertNil(TableRowPassage.sentence(for: table.rows[1], in: table), "a row found by a misread key has no passage")
        XCTAssertEqual(TableRowPassage.chunks(for: [table], startingAt: 0).chunks.count, 3)
    }

    private func assertUnclear(_ outcome: TableLookup.Outcome, file: StaticString = #filePath, line: UInt = #line) {
        guard case .unclear(let source, let pages, _) = outcome else { return XCTFail("\(outcome)", file: file, line: line) }
        XCTAssertEqual(source.table.label, "Table Q7", file: file, line: line)
        XCTAssertFalse(pages.isEmpty, file: file, line: line)
    }

    // MARK: - More letters that pass for digits

    func testTheAddedLettersAreConfusableInANumberColumn() {
        let column = ["10", "20", "30", "40"].map { ManualTable.Cell(text: $0, value: Double($0)) }
        for text in ["1D", "Q5", "2G", "b5", "1g", "q0", "T5", "G", "b", "q", "T"] {
            XCTAssertTrue(CellCertainty.holdsConfusableGlyph(ManualTable.Cell(text: text), column: column), text)
        }
        for text in ["35", "40"] {
            XCTAssertFalse(CellCertainty.holdsConfusableGlyph(ManualTable.Cell(text: text, value: Double(text)), column: column), text)
        }
        let words = ["QXRT", "QMX90", "QA7"].map { ManualTable.Cell(text: $0) }
        XCTAssertFalse(CellCertainty.holdsConfusableGlyph(ManualTable.Cell(text: "QZ12"), column: words),
                       "a column of designations is not a column of numbers")
    }
}
