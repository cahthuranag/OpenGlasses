import Foundation
#if canImport(OpenGlasses)
@testable import OpenGlasses
#endif

/// Invented tables for Plan JJ P0, laid out as text at known positions so a test can draw them
/// into a real PDF text layer (`TableFixtures`) or hand them to the extractor as positioned words.
///
/// Every label, designation and value here is made up — "Table 99", "QXRT", "rating group" — and
/// nothing is a fact from any book. Pure Foundation, no UIKit, so the same layouts can be drawn
/// on a Mac beside the extractor's own sources.
enum TableFixtureLayouts {

    /// One run of text: where its top-left corner sits on a US Letter page (top-down points), its
    /// point size, and whether it is bold.
    struct Item: Equatable {
        var text: String
        var x: Double
        var y: Double
        var size: Double = 9
        var bold = false
    }

    typealias Page = [Item]

    static let pageWidth = 612.0
    static let pageHeight = 792.0

    private static func caption(_ text: String, y: Double = 60) -> Item {
        Item(text: text, x: 50, y: y, size: 10, bold: true)
    }

    private static func row(_ y: Double, _ cells: [(String, Double)], size: Double = 9, bold: Bool = false) -> [Item] {
        cells.filter { !$0.0.isEmpty }.map { Item(text: $0.0, x: $0.1, y: y, size: size, bold: bold) }
    }

    /// A printed page number in the footer band, so the page has a printed label.
    private static func footer(_ number: String) -> Item {
        Item(text: number, x: 300, y: pageHeight - 40, size: 9)
    }

    /// A short paragraph above the table, so the page reads like a page of a book.
    private static func lead(_ y: Double = 30) -> Item {
        Item(text: "The values below are invented for a test and describe nothing real.", x: 50, y: y)
    }

    // MARK: - A simple grid with two row-header columns

    static let ratingColumns: [(String, Double)] = [("Designation", 50), ("Conductors", 140),
                                                    ("Rating group 1", 250), ("Rating group 2", 350),
                                                    ("Rating group 3", 450)]

    /// Table 99, a grid whose designation is printed once over the two rows under it.
    static func simpleGrid(printed: String = "12") -> Page {
        var items = [lead(), caption("TABLE 99 Conductor ratings")]
        items += row(90, ratingColumns, bold: true)
        let body: [[String]] = [
            ["QXRT", "two conductors", "25", "30", "35"],
            ["", "three conductors", "30", "35", "40"],
            ["QMX90", "two conductors", "40", "45", "50"],
            ["", "three conductors", "45", "50", "55"],
        ]
        for (index, cells) in body.enumerated() {
            items += row(106 + Double(index) * 14, zip(cells, [50, 140, 270, 370, 470]).map { ($0, $1) })
        }
        items.append(footer(printed))
        return items
    }

    // MARK: - A two-level column header

    /// Table 98: group headings each centred over three columns, the columns' own headings under
    /// them.
    static func twoLevelHeader() -> Page {
        var items = [caption("TABLE 98 Correction factors")]
        items.append(Item(text: "Rating group 1", x: 222, y: 90, bold: true))
        items.append(Item(text: "Rating group 2", x: 402, y: 90, bold: true))
        items += row(104, [("Ambient (°C)", 50), ("60", 200), ("75", 250), ("90", 300),
                           ("60", 380), ("75", 430), ("90", 480)], bold: true)
        let body: [[String]] = [
            ["21-25", "1.04", "1.02", "1.01", "1.05", "1.03", "1.02"],
            ["26-30", "1.00", "1.00", "1.00", "1.00", "1.00", "1.00"],
            ["31-35", "0.94", "0.96", "0.97", "0.93", "0.95", "0.96"],
            ["36-40", "0.88", "0.91", "0.93", "0.86", "0.90", "0.92"],
        ]
        for (index, cells) in body.enumerated() {
            items += row(120 + Double(index) * 14, zip(cells, [50, 200, 250, 300, 380, 430, 480]).map { ($0, $1) })
        }
        return items
    }

    // MARK: - Units in the header and in a cell

    /// Table 97: units in brackets in the headings, and one column whose cells carry their own.
    static func unitsInHeader() -> Page {
        var items = [caption("TABLE 97 Run lengths")]
        items += row(90, [("Size", 50), ("Length (m)", 160), ("Drop (V)", 280), ("Load", 400)], bold: true)
        let body: [[String]] = [
            ["QX4", "12.5", "0.8", "16 A"],
            ["QX6", "20", "1.1", "25 A"],
            ["QX10", "32.5", "1.4", "32 A"],
        ]
        for (index, cells) in body.enumerated() {
            items += row(106 + Double(index) * 14, zip(cells, [50, 160, 280, 400]).map { ($0, $1) })
        }
        return items
    }

    // MARK: - A table continued over two pages

    /// Table 96 over two pages: the second page's caption reads "(Continued)" and repeats the
    /// header.
    static func continued() -> [Page] {
        func half(_ caption: String, _ rows: [[String]], printed: String) -> Page {
            var items = [Self.caption(caption)]
            items += row(90, [("Designation", 50), ("Spacing (mm)", 200)], bold: true)
            for (index, cells) in rows.enumerated() {
                items += row(106 + Double(index) * 14, zip(cells, [50, 210]).map { ($0, $1) })
            }
            items.append(footer(printed))
            return items
        }
        return [
            half("TABLE 96 Spacing", [["QA1", "10"], ["QA2", "12"], ["QA3", "14"]], printed: "40"),
            half("TABLE 96 (Continued)", [["QA4", "16"], ["QA5", "18"], ["QA6", "20"]], printed: "41"),
        ]
    }

    // MARK: - Footnotes

    /// Table 95: an asterisk, a superscript digit and a lettered marker on cells, and the notes
    /// printed under the table.
    static func footnotes() -> Page {
        var items = [caption("TABLE 95 Rating limits")]
        items += row(90, [("Designation", 50), ("Limit (A)", 200)], bold: true)
        items += row(106, [("QXRT", 50), ("40*", 210)])
        items += row(120, [("QMX90", 50), ("45", 210)])
        // A superscript 1, smaller and raised, right after the 45.
        items.append(Item(text: "1", x: 221, y: 118, size: 6))
        items += row(134, [("QZ12", 50), ("50 (a)", 210)])
        items.append(Item(text: "* Value for a dry location.", x: 50, y: 156, size: 8))
        items.append(Item(text: "1", x: 50, y: 168, size: 5.5))
        items.append(Item(text: "Use only with rating group 2.", x: 55, y: 170, size: 8))
        items.append(Item(text: "(a) Applies inside an enclosure.", x: 50, y: 182, size: 8))
        return items
    }

    // MARK: - Pages that are not tables

    /// A drawing with numbers on it, captioned as a figure: no table caption, nothing to extract.
    static func drawingFigure() -> Page {
        [Item(text: "FIGURE 94 Terminal block", x: 50, y: 60, size: 10, bold: true)] + scatteredLabels()
    }

    /// The same labels under a table caption: they do not resolve to a grid. `pitch` is the
    /// spacing of the label rows; set close, they read as rows whose columns never line up.
    static func drawingUnderTableCaption(pitch: Double = 30) -> Page {
        [caption("TABLE 93 Terminal layout")] + scatteredLabels(pitch: pitch)
    }

    private static func scatteredLabels(pitch: Double = 30) -> [Item] {
        let y = { (row: Double) in 100 + row * pitch }
        return [
            Item(text: "L1", x: 80, y: y(0), size: 7), Item(text: "24", x: 300, y: y(0), size: 7),
            Item(text: "N", x: 150, y: y(1), size: 7), Item(text: "120", x: 420, y: y(1), size: 7),
            Item(text: "T2", x: 500, y: y(1), size: 7),
            Item(text: "6", x: 60, y: y(2), size: 7), Item(text: "GND", x: 260, y: y(2), size: 7),
            Item(text: "35", x: 120, y: y(3), size: 7), Item(text: "X4", x: 330, y: y(3), size: 7),
            Item(text: "12", x: 470, y: y(3), size: 7), Item(text: "7", x: 540, y: y(3), size: 7),
            Item(text: "S3", x: 200, y: y(4), size: 7),
        ]
    }

    /// A table caption over a paragraph: a caption with no grid under it.
    static func captionOverProse() -> Page {
        [caption("TABLE 92 Wiring notes"),
         Item(text: "Each terminal in this invented example is described in the paragraph that follows,", x: 50, y: 90),
         Item(text: "which runs on for several lines and carries no columns of any kind at all, so a", x: 50, y: 104),
         Item(text: "reader sees prose where the caption promised a table of values to look up.", x: 50, y: 118)]
    }

    /// A long table, for the row-passage cap.
    static func longTable(rows count: Int) -> Page {
        var items = [caption("TABLE 91 Long list", y: 20)]
        items += row(36, [("Item", 50), ("Value", 200)], bold: true)
        for index in 0..<count {
            items += row(50 + Double(index) * 11, [("QL\(index + 1)", 50), ("\(index + 1)", 210)], size: 8)
        }
        return items
    }

    // MARK: - As positioned words

    /// The page as the extractor's input, each item split into words at the advance a typical
    /// sans-serif gives its letters — what the pure tests feed `TableExtractor` without a PDF.
    static func words(_ page: Page) -> [PositionedWord] {
        var words: [PositionedWord] = []
        for item in page {
            var x = item.x
            for word in item.text.split(separator: " ") {
                let width = Double(word.count) * item.size * 0.55
                words.append(PositionedWord(String(word), x: x, y: item.y, size: item.size, bold: item.bold,
                                            width: width))
                x += width + item.size * 0.28
            }
        }
        return words
    }
}
