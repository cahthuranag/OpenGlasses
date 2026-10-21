import CoreGraphics
import Foundation
@testable import OpenGlasses

/// Invented pictured tables for Plan JN P0, as a recogniser would hand them over: words with boxes
/// and confidences, and grids of cells by row and column range. Every label, designation and value
/// is made up ("Table Q7", "QXRT", "QMX90") and describes nothing real.
enum RecognisedTableFixtures {

    /// The recognised words of one run of text set at `x`, `y` (top-down page points), each word
    /// as wide as a typical sans-serif sets it, as `TableFixtureLayouts.words` lays them out.
    static func words(_ text: String, x: Double, y: Double, size: Double = 9, confidence: Float = 0.97) -> [RecognisedWord] {
        var out: [RecognisedWord] = []
        var left = x
        for word in text.split(separator: " ") {
            let width = Double(word.count) * size * 0.55
            out.append(RecognisedWord(String(word), rect: CGRect(x: left, y: y, width: width, height: size),
                                      confidence: confidence))
            left += width + size * 0.28
        }
        return out
    }

    /// A raised footnote marker set small just after the word `after` ends.
    static func marker(_ text: String, after word: RecognisedWord, confidence: Float = 0.97) -> RecognisedWord {
        RecognisedWord(text, rect: CGRect(x: word.rect.maxX + 0.5, y: word.rect.minY - 2,
                                          width: Double(text.count) * 5.5 * 0.55, height: 5.5),
                       confidence: confidence)
    }

    // MARK: - Table Q7, one invented table both readers read

    static let q7Caption = TableExtractor.Caption(label: "Table Q7", title: "Invented clearances", continues: false)
    static let q7Header = ["Designation", "Clearance (mm)", "Spacing (mm)", "Limit (A)"]
    static let q7Body = [["QXRT", "12", "30", "16"], ["QMX90", "14", "35", "20"],
                         ["QZ12", "18", "40", "25"], ["QA7", "22", "45", "32"]]
    static let q7HeaderX: [Double] = [50, 160, 280, 400]
    static let q7BodyX: [Double] = [50, 170, 290, 410]

    /// The caption as the PDF's text layer prints it, in bold.
    static func q7CaptionWords(bold: Bool = true) -> [PositionedWord] {
        TableFixtureLayouts.words([TableFixtureLayouts.Item(text: "TABLE Q7 Invented clearances", x: 50, y: 60,
                                                            size: 10, bold: bold)])
    }

    /// Table Q7's grid as recognised words: the header line, then the four rows. `confidence`
    /// overrides one cell's words by its body row and column; `replace` one cell's text.
    static func q7Words(confidence: Float = 0.97, low: (row: Int, column: Int, confidence: Float)? = nil,
                        replace: (row: Int, column: Int, text: String)? = nil, shift: Double = 0) -> [RecognisedWord] {
        var out: [RecognisedWord] = []
        for (column, text) in q7Header.enumerated() {
            out += words(text, x: q7HeaderX[column] + shift, y: 90 + shift, confidence: confidence)
        }
        for (row, cells) in q7Body.enumerated() {
            for (column, text) in cells.enumerated() {
                let printed = replace.map { $0.row == row && $0.column == column ? $0.text : text } ?? text
                let level = low.map { $0.row == row && $0.column == column ? $0.confidence : confidence } ?? confidence
                out += words(printed, x: q7BodyX[column] + shift, y: 106 + Double(row) * 14 + shift, confidence: level)
            }
        }
        return out
    }

    // MARK: - Grids of cells

    /// A cell at `rows` × `columns`, its words set where a grid of 110-point columns and 14-point
    /// rows would print them.
    static func cell(_ rows: ClosedRange<Int>, _ columns: ClosedRange<Int>, _ text: String,
                     confidence: Float = 0.97) -> RecognisedPage.Cell {
        let words = text.isEmpty ? [] : self.words(text, x: 50 + 110 * Double(columns.lowerBound),
                                                   y: 90 + 14 * Double(rows.lowerBound), confidence: confidence)
        return RecognisedPage.Cell(rows: rows, columns: columns, words: words)
    }

    static func cell(_ row: Int, _ column: Int, _ text: String, confidence: Float = 0.97) -> RecognisedPage.Cell {
        cell(row...row, column...column, text, confidence: confidence)
    }

    /// A plain grid: one cell per row and column, row by row.
    static func grid(_ rows: [[String]], confidence: Float = 0.97) -> [RecognisedPage.Cell] {
        rows.enumerated().flatMap { row, texts in
            texts.enumerated().map { column, text in cell(row, column, text, confidence: confidence) }
        }
    }

    /// Table Q7 as a recogniser's grid: the header row, then the four rows.
    static func q7Grid(confidence: Float = 0.97) -> RecognisedPage {
        RecognisedPage(tables: [RecognisedPage.Table(cells: grid([q7Header] + q7Body, confidence: confidence))])
    }

    /// `page`'s first table with the cell at `row`, `column` read as `text` (or removed).
    static func replacing(_ page: RecognisedPage, row: Int, column: Int, with text: String?) -> RecognisedPage {
        var page = page
        var cells = page.tables[0].cells.filter { !($0.rowRange == row...row && $0.columnRange == column...column) }
        if let text { cells.append(cell(row, column, text)) }
        page.tables[0].cells = cells
        return page
    }
}
