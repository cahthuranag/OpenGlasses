import CoreGraphics
import XCTest
@testable import OpenGlasses

/// Plan JN P0 — how clearly a pictured table's cells were read: the confidence floor, glyphs a
/// digit is mistaken for, two passes that disagree, and the share of clear cells under which the
/// table is `unclear_in_picture`. Every table is invented (`RecognisedTableFixtures`).
final class CellCertaintyTests: XCTestCase {

    private typealias F = RecognisedTableFixtures
    private let page = ManualTable.Page(physical: 7)
    private let floor: Float = 0.6

    private func gridReading(_ recognised: RecognisedPage) -> RecognisedReading {
        RecognisedGrid.table(recognised, caption: F.q7Caption, page: page)
    }

    private func assessed(_ recognised: RecognisedPage, secondPass: RecognisedPage? = nil,
                          file: StaticString = #filePath, line: UInt = #line) throws -> ManualTable {
        let outcome = CellCertainty.assess(gridReading(recognised), floor: floor, secondPass: secondPass).outcome
        return try XCTUnwrap(outcome.table, "\(outcome)", file: file, line: line)
    }

    /// Body row and value column of every uncertain cell.
    private func uncertain(_ table: ManualTable) -> [[Int]] {
        table.rows.indices.flatMap { row in
            table.rows[row].cells.indices.filter { table.rows[row].cells[$0].uncertain }.map { [row, $0] }
        }
    }

    func testAClearTableHasNoUncertainCells() throws {
        let assessment = CellCertainty.assess(gridReading(F.q7Grid()), floor: floor, secondPass: F.q7Grid())
        let table = try XCTUnwrap(assessment.outcome.table)
        XCTAssertEqual(uncertain(table), [])
        XCTAssertEqual(assessment.uncertain, 0)
        XCTAssertEqual(assessment.byReason, [:])
    }

    func testAWordUnderTheFloorMakesItsCellUncertainAndKeepsItsText() throws {
        var recognised = F.q7Grid()
        recognised.tables[0].cells.removeAll { $0.rowRange == 2...2 && $0.columnRange == 2...2 }
        recognised.tables[0].cells.append(F.cell(2, 2, "35", confidence: 0.4))
        let assessment = CellCertainty.assess(gridReading(recognised), floor: floor)
        let table = try XCTUnwrap(assessment.outcome.table)
        XCTAssertEqual(uncertain(table), [[1, 1]])
        XCTAssertEqual(table.rows[1].cells[1].text, "35", "the text is kept for the page to be checked against")
        XCTAssertEqual(assessment.byReason, [.lowConfidence: 1])
    }

    func testAConfusableGlyphInANumberColumnIsFlaggedNeverCorrected() throws {
        var recognised = F.replacing(F.q7Grid(), row: 1, column: 2, with: "3O")
        recognised = F.replacing(recognised, row: 3, column: 1, with: "l8")
        recognised = F.replacing(recognised, row: 4, column: 3, with: "3.2")
        let table = try assessed(recognised)
        XCTAssertEqual(uncertain(table), [[0, 1], [2, 0], [3, 2]])
        XCTAssertEqual(table.rows[0].cells[1].text, "3O", "never turned into 30")
        XCTAssertEqual(table.rows[2].cells[0].text, "l8")
        XCTAssertEqual(table.rows[3].cells[2].text, "3.2", "a point the column's numbers never print")
    }

    func testConfusableRulesLeaveTextColumnsDecimalsAndSharedUnitsAlone() {
        func cell(_ text: String) -> ManualTable.Cell { TableExtractor.parseCell(text, markers: [], columnUnit: nil) }
        let words = ["permitted", "not permitted", "QB2"].map(cell)
        XCTAssertFalse(CellCertainty.holdsConfusableGlyph(cell("QZ12"), column: words), "a column of words")
        let decimals = ["0.86", "0.99", "1.13"].map(cell)
        XCTAssertFalse(CellCertainty.holdsConfusableGlyph(cell("0.83"), column: decimals))
        XCTAssertTrue(CellCertainty.holdsConfusableGlyph(cell("0,83"), column: decimals), "a comma among points")
        let seconds = ["10s", "15s", "20s"].map(cell)
        XCTAssertFalse(CellCertainty.holdsConfusableGlyph(cell("5s"), column: seconds), "a unit the column shares")
        XCTAssertTrue(CellCertainty.holdsConfusableGlyph(cell("S5s"), column: seconds))
        let numbers = ["30", "35", "40"].map(cell)
        XCTAssertTrue(CellCertainty.holdsConfusableGlyph(cell("O"), column: numbers), "a letter alone where a digit goes")
        XCTAssertTrue(CellCertainty.holdsConfusableGlyph(cell("2Z"), column: numbers))
        XCTAssertFalse(CellCertainty.holdsConfusableGlyph(cell("45*"), column: numbers), "a marker is not a glyph")
        XCTAssertFalse(CellCertainty.holdsConfusableGlyph(cell("50 (a)"), column: numbers))
    }

    func testTwoPassesThatDisagreeMakeTheCellUncertain() throws {
        var second = F.replacing(F.q7Grid(), row: 3, column: 2, with: "46")
        second = F.replacing(second, row: 1, column: 3, with: nil)
        let assessment = CellCertainty.assess(gridReading(F.q7Grid()), floor: floor, secondPass: second)
        let table = try XCTUnwrap(assessment.outcome.table)
        XCTAssertEqual(uncertain(table), [[0, 2], [2, 1]], "read differently, and not read at all")
        XCTAssertEqual(table.rows[2].cells[1].text, "40", "the first pass's text is kept")
        XCTAssertEqual(assessment.byReason, [.passesDisagree: 2])
    }

    func testTwoPassesOverWordsAreMatchedByBox() throws {
        let first = RecognisedWords.table(RecognisedPage(words: F.q7Words()), captionWords: F.q7CaptionWords(),
                                          caption: F.q7Caption, page: page)
        let second = RecognisedPage(words: F.q7Words(replace: (row: 1, column: 3, text: "2O"), shift: 0.4))
        let table = try XCTUnwrap(CellCertainty.assess(first, floor: floor, secondPass: second).outcome.table)
        XCTAssertEqual(uncertain(table), [[1, 2]], "the second pass, set a little apart, agrees everywhere else")
    }

    func testAWordsReadingUnderTheFloorIsUncertainToo() throws {
        let reading = RecognisedWords.table(RecognisedPage(words: F.q7Words(low: (row: 3, column: 2, confidence: 0.3))),
                                            captionWords: F.q7CaptionWords(), caption: F.q7Caption, page: page)
        let table = try XCTUnwrap(CellCertainty.assess(reading, floor: floor).outcome.table)
        XCTAssertEqual(uncertain(table), [[3, 1]])
    }

    func testABlankCellIsUncertainAndDoesNotCountAgainstTheShare() throws {
        let recognised = F.replacing(F.q7Grid(), row: 2, column: 1, with: "")
        let assessment = CellCertainty.assess(gridReading(recognised), floor: floor)
        let table = try XCTUnwrap(assessment.outcome.table)
        XCTAssertEqual(uncertain(table), [[1, 0]], "a blank and a missed cell look alike in a picture")
        XCTAssertEqual(assessment.byReason, [.blank: 1])
    }

    func testTooFewClearCellsIsUnclearInPicture() {
        // Twelve value cells: six unclear is half and still a table; seven is not.
        func reading(unclear: Int) -> RecognisedReading {
            var recognised = F.q7Grid()
            let places = (1...4).flatMap { row in (1...3).map { (row, $0) } }.prefix(unclear)
            for (row, column) in places {
                let text = F.q7Body[row - 1][column]
                recognised.tables[0].cells.removeAll { $0.rowRange == row...row && $0.columnRange == column...column }
                recognised.tables[0].cells.append(F.cell(row, column, text, confidence: 0.2))
            }
            return gridReading(recognised)
        }
        XCTAssertNotNil(CellCertainty.assess(reading(unclear: 6), floor: floor).outcome.table)
        let unclear = CellCertainty.assess(reading(unclear: 7), floor: floor)
        XCTAssertEqual(unclear.outcome, .failed(.unclearInPicture), "kept as an unread table, not a sparse one")
        XCTAssertEqual(unclear.uncertain, 7)
        XCTAssertEqual(CellCertainty.minimumCertainShare, 0.5)
    }

    func testAReadingWithNoTablePassesThrough() {
        let reading = RecognisedGrid.table(RecognisedPage(), caption: F.q7Caption, page: page)
        XCTAssertEqual(CellCertainty.assess(reading, floor: floor).outcome, .failed(.noTextInTable))
    }
}
