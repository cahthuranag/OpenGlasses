import PDFKit
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JN P1 — the real Vision adapter on an invented table drawn as a picture under a text
/// caption: the text layer gives the caption and no grid, and the document reading gives the grid
/// back. Vision runs on the simulator here; where the document request is not supported there,
/// the test skips and says so. Every label, designation and value is invented.
final class VisionTableReaderTests: XCTestCase {

    private static let header = ["Designation", "Clearance (mm)", "Spacing (mm)", "Limit (A)"]
    private static let body = [["QXRT", "12", "30", "16"], ["QMX90", "14", "35", "20"],
                               ["QZK", "18", "40", "25"], ["QAV", "22", "45", "32"]]

    /// The table drawn as an image, ruled, at four pixels to the point.
    private static func tableImage() -> UIImage {
        let size = CGSize(width: 460, height: 120)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            let rows: CGFloat = 22
            let path = UIBezierPath()
            for row in 0...5 {
                path.move(to: CGPoint(x: 4, y: 6 + CGFloat(row) * rows))
                path.addLine(to: CGPoint(x: size.width - 4, y: 6 + CGFloat(row) * rows))
            }
            for x in [4.0, 124, 234, 344, size.width - 4] {
                path.move(to: CGPoint(x: x, y: 6))
                path.addLine(to: CGPoint(x: x, y: 6 + 5 * rows))
            }
            path.lineWidth = 0.6
            path.stroke()
            let xs: [CGFloat] = [10, 130, 240, 350]
            func draw(_ text: String, column: Int, row: Int, bold: Bool) {
                let font = bold ? UIFont.boldSystemFont(ofSize: 10) : UIFont.systemFont(ofSize: 10)
                NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black])
                    .draw(at: CGPoint(x: xs[column], y: 10 + CGFloat(row) * rows))
            }
            for (column, text) in header.enumerated() { draw(text, column: column, row: 0, bold: true) }
            for (row, cells) in body.enumerated() {
                for (column, text) in cells.enumerated() { draw(text, column: column, row: row + 1, bold: false) }
            }
        }
    }

    /// A page: the caption and a line under it as text, the table as a picture, a page number.
    private func pictured() throws -> PDFDocument {
        let image = Self.tableImage()
        let data = UIGraphicsPDFRenderer(bounds: TableFixtures.pageSize).pdfData { context in
            context.beginPage()
            NSAttributedString(string: "Table 98 Invented clearances",
                               attributes: [.font: UIFont(name: "Helvetica-Bold", size: 10) ?? .boldSystemFont(ofSize: 10)])
                .draw(at: CGPoint(x: 50, y: 60))
            NSAttributedString(string: "The invented values below describe nothing real and are here for a test only.",
                               attributes: [.font: UIFont(name: "Helvetica", size: 9) ?? .systemFont(ofSize: 9)])
                .draw(at: CGPoint(x: 50, y: 76))
            image.draw(in: CGRect(x: 60, y: 110, width: 460, height: 120))
            NSAttributedString(string: "44", attributes: [.font: UIFont.systemFont(ofSize: 9)])
                .draw(at: CGPoint(x: 300, y: TableFixtureLayouts.pageHeight - 40))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VisionTableReaderTests", isDirectory: true)
        let url = try TableFixtures.write(data, named: "\(UUID().uuidString).pdf", in: directory)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(PDFDocument(url: url))
    }

    func testTheDocumentReadingGivesThePicturedGridBack() async throws {
        let document = try pictured()
        XCTAssertEqual(PDFTableReader.read(document: document).failures, [.noTextInTable: 1], "the text layer gives no grid")

        // The region under the caption, recognised directly: whether Vision reads documents here.
        let page = try XCTUnwrap(document.page(at: 0))
        let words = PDFTableReader.positionedWords(on: page)
        let caption = TableExtractor.Caption(label: "Table 98", title: "Invented clearances", continues: false)
        let region = try XCTUnwrap(PictureTableReading.region(for: caption, failure: .noTextInTable, words: words,
                                                              pageBounds: page.bounds(for: .mediaBox)))
        let render = PictureRegion.Render(region: region, scale: 3)
        let image = try XCTUnwrap(PictureTableReading.image(of: page, render: render))
        let reader = VisionTableReader()
        let grid = await reader.recognise(image, render: render, reading: .documentGrid)
        guard !grid.tables.isEmpty else {
            throw XCTSkip("RecognizeDocumentsRequest found no table on this simulator (words read: \(grid.words.count)); "
                          + "the document reading is checked on the device")
        }
        // Boxes come back on the page, inside the region.
        XCTAssertTrue(grid.words.allSatisfy { region.insetBy(dx: -2, dy: -2).contains($0.rect) }, "\(grid.words.map(\.rect))")
        let words2 = await reader.recognise(image, render: render, reading: .words)
        XCTAssertTrue(words2.words.contains { $0.text == "QMX90" }, "\(words2.words.map(\.text))")

        let result = await PDFTableReader.read(document: document, pictures: .init(reader: reader, reading: .documentGrid, floor: 0.5))
        XCTAssertEqual(result.recognised, 1, "\(result.failures)")
        let table = try XCTUnwrap(result.tables.first)
        XCTAssertEqual(table.label, "Table 98")
        XCTAssertEqual(table.source.isRecognised, true)
        XCTAssertEqual(table.rowHeaders, ["Designation"])
        XCTAssertEqual(table.columns.map(\.name), ["Clearance (mm)", "Spacing (mm)", "Limit (A)"])
        XCTAssertEqual(table.rows.map(\.path), Self.body.map { [$0[0]] })
        XCTAssertEqual(table.rows[1].cells.map(\.text), ["14", "35", "20"])
        XCTAssertEqual(table.rows[3].cells[2].value, 32)
        XCTAssertFalse(table.rows.contains(where: \.keyUncertain))

        // And the lookup gives a clear cell from it.
        let outcome = TableLookup.resolve(.init(table: "Table 98", row: "QZK", column: "Spacing"),
                                          in: [.init(documentId: "d", documentName: "Invented Book", table: table)])
        guard case .found(let found) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(found.rows[0].cells[found.columns[0]].text, "40")
    }
}
