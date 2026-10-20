import PDFKit
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JJ P0 — a captioned table read off a page into headers, rows, cells and notes. Every table
/// is invented (`TableFixtureLayouts`); the pure tests feed positioned words, the end-to-end ones a
/// PDF drawn in the test, read back through PDFKit's text layer exactly as an import reads one.
final class TableExtractorTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TableExtractorTests-\(UUID().uuidString)", isDirectory: true)
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

    private func readPDF(_ pages: [TableFixtureLayouts.Page], printed: [Int: String] = [:]) throws -> PDFTableReader.Result {
        let url = try TableFixtures.write(TableFixtures.pdf(pages), named: "tables-\(UUID().uuidString).pdf", in: tempRoot)
        return try XCTUnwrap(PDFTableReader.read(url: url, printedLabels: printed))
    }

    // MARK: - A simple grid

    func testASimpleGridExtractsItsHeadersRowsAndCells() throws {
        let table = try only(TableFixtureLayouts.simpleGrid())
        XCTAssertEqual(table.label, "Table 99")
        XCTAssertEqual(table.title, "Conductor ratings")
        XCTAssertEqual(table.rowHeaders, ["Designation", "Conductors"], "both leading text columns head the rows")
        XCTAssertEqual(table.columns.map(\.name), ["Rating group 1", "Rating group 2", "Rating group 3"])
        XCTAssertEqual(table.rows.map(\.path), [["QXRT", "two conductors"], ["QXRT", "three conductors"],
                                                ["QMX90", "two conductors"], ["QMX90", "three conductors"]],
                       "a designation printed once heads the rows under it")
        XCTAssertEqual(table.rows[1].cells.map(\.value), [30, 35, 40])
        XCTAssertEqual(table.rows[1].cells.map(\.text), ["30", "35", "40"])
        XCTAssertTrue(table.notes.isEmpty)
        XCTAssertFalse(table.continues)
    }

    func testATwoLevelHeaderGivesEachColumnItsPath() throws {
        let table = try only(TableFixtureLayouts.twoLevelHeader())
        XCTAssertEqual(table.columns.map(\.path), [
            ["Rating group 1", "Band A"], ["Rating group 1", "Band B"], ["Rating group 1", "Band C"],
            ["Rating group 2", "Band A"], ["Rating group 2", "Band B"], ["Rating group 2", "Band C"],
        ])
        XCTAssertEqual(table.columns[4].name, "Rating group 2 › Band B")
        XCTAssertEqual(table.rowHeaders, ["Ambient (°C)"], "a range like 7-9 is a row header, not a number")
        XCTAssertEqual(table.rows.map(\.path), [["7-9"], ["10-12"], ["13-15"], ["16-18"]])
        XCTAssertEqual(table.rows[2].cells[4].value, 0.86)
    }

    func testUnitsInTheHeaderAndInACellParse() throws {
        let table = try only(TableFixtureLayouts.unitsInHeader())
        XCTAssertEqual(table.columns.map(\.unit), ["m", "V", nil])
        let first = try XCTUnwrap(table.rows.first)
        XCTAssertEqual(first.cells[0], ManualTable.Cell(text: "12.5", value: 12.5, unit: "m"))
        XCTAssertEqual(first.cells[1], ManualTable.Cell(text: "0.8", value: 0.8, unit: "V"))
        XCTAssertEqual(first.cells[2], ManualTable.Cell(text: "16 A", value: 16, unit: "A"), "a cell's own unit")
    }

    func testFootnoteMarkersAttachToCellsAndTheNotesAreKept() throws {
        let table = try only(TableFixtureLayouts.footnotes())
        let cells = table.rows.map { $0.cells[0] }
        XCTAssertEqual(cells.map(\.value), [40, 45, 50], "a marker never changes the number")
        XCTAssertEqual(cells.map(\.markers), [["*"], ["1"], ["a"]])
        XCTAssertEqual(cells.map(\.text), ["40*", "45\u{00B9}", "50 (a)"], "the text is as printed")
        XCTAssertEqual(table.notes, [
            ManualTable.Note(marker: "*", text: "Value for a dry location."),
            ManualTable.Note(marker: "1", text: "Use only with rating group 2."),
            ManualTable.Note(marker: "a", text: "Applies inside an enclosure."),
        ])
    }

    func testAContinuedTableMergesWithEachRowsPage() throws {
        let pages = TableFixtureLayouts.continued()
        let first = try only(pages[0], physical: 4)
        let second = try only(pages[1], physical: 5)
        XCTAssertFalse(first.continues)
        XCTAssertTrue(second.continues, "the caption read (Continued)")
        let merged = TableExtractor.merge([first, second])
        XCTAssertEqual(merged.count, 1)
        let table = try XCTUnwrap(merged.first)
        XCTAssertEqual(table.title, "Spacing", "the first page's caption and headers")
        XCTAssertFalse(table.continues)
        XCTAssertEqual(table.rows.map(\.path), [["QA1"], ["QA2"], ["QA3"], ["QA4"], ["QA5"], ["QA6"]])
        XCTAssertEqual(table.rows.map(\.page.physical), [4, 4, 4, 5, 5, 5])
        XCTAssertEqual(table.pages.map(\.physical), [4, 5])
        XCTAssertEqual(table.columns.first?.unit, "mm")
    }

    func testAContinuationWithNothingBeforeItStaysOnItsOwn() throws {
        let second = try only(TableFixtureLayouts.continued()[1], physical: 9)
        let merged = TableExtractor.merge([second])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].continues, "marked as continuing a table that was not found")
        let unrelated = try only(TableFixtureLayouts.simpleGrid(), physical: 8)
        XCTAssertEqual(TableExtractor.merge([unrelated, second]).count, 2, "a different label never joins")
    }

    // MARK: - What is not a table

    func testADrawingWithNumbersExtractsNothing() {
        XCTAssertTrue(TableExtractor.extractAll(words: TableFixtureLayouts.words(TableFixtureLayouts.drawingFigure()),
                                                page: .init(physical: 1)).isEmpty,
                      "a figure caption is not a table caption")
        let loose = TableExtractor.extractAll(words: TableFixtureLayouts.words(TableFixtureLayouts.drawingUnderTableCaption()),
                                              page: .init(physical: 1))
        XCTAssertEqual(loose.map(\.outcome.failure), [.tooFewRows])
        let dense = TableExtractor.extractAll(
            words: TableFixtureLayouts.words(TableFixtureLayouts.drawingUnderTableCaption(pitch: 12)),
            page: .init(physical: 1))
        XCTAssertEqual(dense.map(\.outcome.failure), [.varyingColumnCount],
                       "labels close enough to read as rows still never line up into columns")
    }

    func testACaptionOverProseExtractsNothingAndSaysSo() {
        let found = TableExtractor.extractAll(words: TableFixtureLayouts.words(TableFixtureLayouts.captionOverProse()),
                                              page: .init(physical: 1))
        XCTAssertEqual(found.map(\.caption.label), ["Table 92"])
        XCTAssertEqual(found.map(\.outcome.failure), [.tooFewRows])
    }

    func testAPageWithNoWordsHasNoTextLayer() {
        let caption = TableExtractor.Caption(label: "Table 99", title: "", continues: false)
        XCTAssertEqual(TableExtractor.extract(words: [], caption: caption, page: .init(physical: 1)),
                       .failed(.noTextLayer))
        XCTAssertEqual(TableExtractor.extract(words: TableFixtureLayouts.words(TableFixtureLayouts.unitsInHeader()),
                                              caption: caption, page: .init(physical: 1)),
                       .failed(.captionNotFound))
    }

    func testCellsSpanningColumnsBeyondTheToleranceAreRefused() {
        var page: TableFixtureLayouts.Page = [TableFixtureLayouts.Item(text: "TABLE 90 Spans", x: 50, y: 60, size: 10, bold: true)]
        page += [("Designation", 50.0), ("Group 1", 200), ("Group 2", 300)].map {
            TableFixtureLayouts.Item(text: $0.0, x: $0.1, y: 90, bold: true)
        }
        for (index, name) in ["QA1", "QA2", "QA3", "QA4"].enumerated() {
            let y = 106 + Double(index) * 14
            page.append(.init(text: name, x: 50, y: y))
            if index.isMultiple(of: 2) {
                page.append(.init(text: "10", x: 200, y: y))
                page.append(.init(text: "12", x: 300, y: y))
            } else {
                // One value printed across both columns, as a merged cell is.
                page.append(.init(text: "applies to both groups alike", x: 200, y: y))
            }
        }
        let found = TableExtractor.extractAll(words: TableFixtureLayouts.words(page), page: .init(physical: 1))
        XCTAssertEqual(found.map(\.outcome.failure), [.mergedCells])
    }

    // MARK: - Captions and cells

    /// One direction only: every table caption `ManualStructure` names a chunk by is a caption
    /// here, with the same label. The extractor also reads plain captions on a page with no bold,
    /// which the chunker never names.
    func testEveryChunkerTableCaptionIsAnExtractorCaption() {
        let cases: [(String, Bool)] = [("TABLE 99 Conductor ratings", true), ("Table 96", true),
                                       ("TABLE 96 (Continued)", true), ("See Table 99 for values", false),
                                       ("TABLE 99 Conductor ratings", false), ("FIGURE 94 Terminal block", true)]
        for (text, bold) in cases {
            let typed = ManualStructure.caption(ManualStructure.TypedLine(raw: text, size: 10, bold: bold))
            let words = TableFixtureLayouts.words([TableFixtureLayouts.Item(text: text, x: 50, y: 60, size: 10, bold: bold)])
            let positioned = TableExtractor.lines(of: words).first.flatMap { TableExtractor.caption(of: $0) }
            if let typed, typed.label.hasPrefix("Table") {
                XCTAssertEqual(positioned?.label, typed.label, text)
            }
            if !bold {
                XCTAssertNil(positioned, "on a page that sets anything in bold, a plain line is not a caption: \(text)")
            }
        }
        let continued = TableExtractor.lines(of: TableFixtureLayouts.words(
            [TableFixtureLayouts.Item(text: "TABLE 96 (Continued)", x: 50, y: 60, size: 10, bold: true)]))
        XCTAssertEqual(continued.first.flatMap { TableExtractor.caption(of: $0) },
                       TableExtractor.Caption(label: "Table 96", title: "", continues: true))
    }

    // MARK: - A text layer with no bold

    func testAPlainCaptionOverAGridExtractsOnAPageWithNoBold() throws {
        let table = try only(TableFixtureLayouts.singleFontGrid())
        XCTAssertEqual(table.label, "Table 95")
        XCTAssertEqual(table.title, "Spacing limits")
        XCTAssertEqual(table.rowHeaders, ["Designation"], "the header is read without weight")
        XCTAssertEqual(table.columns.map(\.name), ["Limit (A)", "Spacing (mm)"])
        XCTAssertEqual(table.columns.map(\.unit), ["A", "mm"])
        XCTAssertEqual(table.rows.map(\.path), [["QA7"], ["QA8"], ["QA9"], ["QA11"]])
        XCTAssertEqual(table.rows[2].cells.map(\.value), [23, 38])
    }

    func testAWrappedTitleOnAPageWithNoBoldIsReadAsTheTitle() throws {
        let table = try only(TableFixtureLayouts.singleFontWrappedTitle())
        XCTAssertEqual(table.title, "Invented spacing limits for the invented designations set out in this example, "
                       + "arranged for a test of a title that wraps")
        XCTAssertEqual(table.columns.map(\.name), ["Limit (A)", "Spacing (mm)"])
        XCTAssertEqual(table.rows.map(\.path), [["QB2"], ["QB3"], ["QB5"]])
    }

    func testThePlainCaptionLineIsNotACaptionWhereThePageCarriesBold() {
        let words = TableFixtureLayouts.words(TableFixtureLayouts.singleFontGrid(boldElsewhere: true))
        XCTAssertTrue(TableExtractor.captions(in: words).isEmpty)
        XCTAssertTrue(TableExtractor.extractAll(words: words, page: .init(physical: 1)).isEmpty)
    }

    func testProseThatBeginsWithATableReferenceExtractsNothing() {
        let found = TableExtractor.extractAll(words: TableFixtureLayouts.words(TableFixtureLayouts.proseTableReference()),
                                              page: .init(physical: 1))
        XCTAssertEqual(found.map(\.caption.label), ["Table 95"],
                       "the long line is a sentence; only the short line stands alone")
        XCTAssertEqual(found.map(\.outcome.failure), [.tooFewRows], "and no grid follows it")
        let line = { (text: String) in
            TableExtractor.lines(of: TableFixtureLayouts.words([.init(text: text, x: 50, y: 60)])).first
                .flatMap { TableExtractor.caption(of: $0, pageHasBold: false) }
        }
        XCTAssertNil(line("Table 95 lists the limits. The rows below are invented."), "a sentence ends before the line does")
        XCTAssertNil(line("See Table 95"), "a reference that does not begin the line")
        XCTAssertEqual(line("TABLE 95 (Continued)"), TableExtractor.Caption(label: "Table 95", title: "", continues: true))
    }

    func testAPlainCaptionExtractsFromAPDFWithNoBoldInItsTextLayer() throws {
        let result = try readPDF([TableFixtures.prosePage(), TableFixtureLayouts.singleFontGrid(),
                                  TableFixtureLayouts.proseTableReference()])
        XCTAssertEqual(result.captioned, 2, "the table and the short prose line")
        XCTAssertEqual(result.extracted, 1)
        XCTAssertEqual(result.failures, [.tooFewRows: 1])
        XCTAssertEqual(result.tables.first?.rows.compactMap { $0.cells.first?.value }, [14, 17, 23, 29])
    }

    func testCellsParseNumbersUnitsAndMarkers() {
        func cell(_ text: String, unit: String? = nil) -> ManualTable.Cell {
            TableExtractor.parseCell(text, markers: [], columnUnit: unit)
        }
        XCTAssertEqual(cell("1,5").value, 1.5, "a decimal comma")
        XCTAssertEqual(cell("12,000").value, 12_000, "a thousands separator")
        XCTAssertNil(cell("1/0").value, "a designation, not a number")
        XCTAssertNil(cell("7-9").value, "a range is a row header")
        XCTAssertEqual(cell("\u{2212}3").value, -3, "a typeset minus")
        XCTAssertEqual(cell("2.5 mm\u{00B2}"), ManualTable.Cell(text: "2.5 mm\u{00B2}", value: 2.5, unit: "mm\u{00B2}"),
                       "a squared unit is a unit, not a footnote")
        XCTAssertEqual(cell("40\u{00B9}").markers, ["1"])
        XCTAssertEqual(cell("40\u{00B9}").value, 40)
        XCTAssertEqual(cell("35**", unit: "A"), ManualTable.Cell(text: "35**", value: 35, unit: "A", markers: ["**"]))
        XCTAssertEqual(cell("\u{2014}", unit: "A"), ManualTable.Cell(text: "\u{2014}"), "no number, no unit")
        XCTAssertEqual(TableExtractor.unit(in: ["Rating group 2", "Size [mm\u{00B2}]"]), "mm\u{00B2}")
        XCTAssertNil(TableExtractor.unit(in: ["Rating group 2 (see note)"]), "words in brackets are not a unit")
    }

    // MARK: - Row passages

    func testEachRowRendersAsOneSentenceNamingTheTableTheRowAndItsPage() throws {
        var table = try only(TableFixtureLayouts.simpleGrid(), physical: 3)
        table.rows = table.rows.map { row in var row = row; row.page.printed = "12"; return row }
        XCTAssertEqual(TableRowPassage.sentence(for: table.rows[1], in: table),
                       "Table 99 (Conductor ratings), row QXRT, three conductors: 30 in Rating group 1, "
                       + "35 in Rating group 2, 40 in Rating group 3 \u{2014} page 12")
        let rendered = TableRowPassage.chunks(for: [table], startingAt: 7)
        XCTAssertEqual(rendered.chunks.map(\.index), [7, 8, 9, 10], "numbered after the document's own text")
        XCTAssertTrue(rendered.chunks.allSatisfy { $0.kind == .tableRow && $0.figure == "Table 99" && $0.page == 3 })
        XCTAssertEqual(rendered.dropped, 0)
    }

    func testRowPassagesAreCappedPerTable() throws {
        let table = try only(TableFixtureLayouts.longTable(rows: 12))
        XCTAssertEqual(table.rows.count, 12)
        let capped = TableRowPassage.chunks(for: [table, table], startingAt: 0, cap: 5)
        XCTAssertEqual(capped.chunks.count, 10, "five from each table")
        XCTAssertEqual(capped.dropped, 14)
        XCTAssertEqual(TableRowPassage.rowCap, 400)
    }

    func testARowWithNoValueHasNoPassage() {
        let table = ManualTable(label: "Table 99", title: "", page: .init(physical: 1),
                                columns: [.init(path: ["Rating group 1"])],
                                rows: [.init(path: ["QXRT"], cells: [.init(text: "")], page: .init(physical: 1))])
        XCTAssertNil(TableRowPassage.sentence(for: table.rows[0], in: table))
        XCTAssertTrue(TableRowPassage.chunks(for: [table], startingAt: 0).chunks.isEmpty)
    }

    func testATableRoundTripsThroughJSON() throws {
        let table = try only(TableFixtureLayouts.footnotes())
        let decoded = try JSONDecoder().decode(ManualTable.self, from: JSONEncoder().encode(table))
        XCTAssertEqual(decoded, table)
    }

    // MARK: - End to end on a PDF's text layer

    func testTheGridExtractsFromARealPDFTextLayer() throws {
        let result = try readPDF([TableFixtures.prosePage(), TableFixtureLayouts.simpleGrid()], printed: [2: "12"])
        XCTAssertEqual(result.captioned, 1)
        XCTAssertEqual(result.extracted, 1)
        XCTAssertTrue(result.failures.isEmpty)
        let table = try XCTUnwrap(result.tables.first)
        XCTAssertEqual(table.page, ManualTable.Page(physical: 2, printed: "12"))
        XCTAssertEqual(table.columns.map(\.name), ["Rating group 1", "Rating group 2", "Rating group 3"])
        XCTAssertEqual(table.rows.map(\.path).last, ["QMX90", "three conductors"])
        XCTAssertEqual(table.rows.flatMap { $0.cells.compactMap(\.value) },
                       [25, 30, 35, 30, 35, 40, 40, 45, 50, 45, 50, 55])
        XCTAssertEqual(TableRowPassage.sentence(for: table.rows[1], in: table),
                       "Table 99 (Conductor ratings), row QXRT, three conductors: 30 in Rating group 1, "
                       + "35 in Rating group 2, 40 in Rating group 3 \u{2014} page 12")
    }

    func testTheImportReadsPrintedPageNumbersFromTheFooter() throws {
        let url = try TableFixtures.write(TableFixtures.pdf([TableFixtureLayouts.simpleGrid(printed: "12")]),
                                          named: "printed.pdf", in: tempRoot)
        let result = try XCTUnwrap(VaultDocumentExtractor.tables(from: url))
        XCTAssertEqual(result.tables.first?.page, ManualTable.Page(physical: 1, printed: "12"))
        XCTAssertNil(VaultDocumentExtractor.tables(from: tempRoot.appendingPathComponent("notes.md")),
                     "a text import has no positions to read")
    }

    func testAContinuedTableMergesAcrossTwoPDFPages() throws {
        let result = try readPDF(TableFixtureLayouts.continued(), printed: [1: "40", 2: "41"])
        XCTAssertEqual(result.captioned, 1, "a continuation is the same table")
        XCTAssertEqual(result.extracted, 1)
        let table = try XCTUnwrap(result.tables.first)
        XCTAssertEqual(table.rows.map { $0.page.printed }, ["40", "40", "40", "41", "41", "41"])
        XCTAssertEqual(table.rows.compactMap { $0.cells.first?.value }, [10, 12, 14, 16, 18, 20])
    }

    func testFootnotesSurviveTheTextLayer() throws {
        let table = try XCTUnwrap(try readPDF([TableFixtureLayouts.footnotes()]).tables.first)
        XCTAssertEqual(table.rows.map { $0.cells[0].markers }, [["*"], ["1"], ["a"]],
                       "a raised digit is read apart from the number it marks")
        XCTAssertEqual(table.rows.map { $0.cells[0].value }, [40, 45, 50])
        XCTAssertEqual(table.notes.map(\.marker), ["*", "1", "a"])
    }

    func testPagesThatAreNotTablesExtractNothingAndAreCounted() throws {
        let scan = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 400, height: 200))
            NSAttributedString(string: "TABLE 89 Scanned", attributes: [.font: UIFont.boldSystemFont(ofSize: 14)])
                .draw(at: CGPoint(x: 10, y: 10))
        }
        let data = UIGraphicsPDFRenderer(bounds: TableFixtures.pageSize).pdfData { context in
            for page in [TableFixtureLayouts.drawingFigure(), TableFixtureLayouts.drawingUnderTableCaption(pitch: 12),
                         TableFixtureLayouts.captionOverProse()] {
                context.beginPage()
                for item in page {
                    let font = UIFont(name: item.bold ? "Helvetica-Bold" : "Helvetica", size: item.size)!
                    NSAttributedString(string: item.text, attributes: [.font: font]).draw(at: CGPoint(x: item.x, y: item.y))
                }
            }
            context.beginPage()
            scan.draw(in: CGRect(x: 50, y: 60, width: 400, height: 200))
        }
        let url = try TableFixtures.write(data, named: "not-tables.pdf", in: tempRoot)
        let result = try XCTUnwrap(PDFTableReader.read(url: url))
        XCTAssertEqual(result.extracted, 0)
        XCTAssertEqual(result.captioned, 2, "the drawing under a table caption and the caption over prose")
        XCTAssertEqual(result.failures, [.varyingColumnCount: 1, .tooFewRows: 1])
        XCTAssertEqual(result.pagesWithoutText, 1, "the scanned page has no text layer to read")
    }
}

