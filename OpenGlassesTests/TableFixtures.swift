import PDFKit
import UIKit
@testable import OpenGlasses

/// Draws `TableFixtureLayouts` pages into a real PDF, so the table extractor is tested end to end
/// on PDFKit's own text layer — positions, sizes and weights as the phone reads them from a
/// loaded manual. Every table is invented.
enum TableFixtures {

    static let pageSize = CGRect(x: 0, y: 0, width: TableFixtureLayouts.pageWidth,
                                 height: TableFixtureLayouts.pageHeight)

    private static func font(_ item: TableFixtureLayouts.Item) -> UIFont {
        let name = item.bold ? "Helvetica-Bold" : "Helvetica"
        return UIFont(name: name, size: item.size)
            ?? (item.bold ? .boldSystemFont(ofSize: item.size) : .systemFont(ofSize: item.size))
    }

    /// One PDF page per layout page, each item drawn with its top-left corner at its position.
    static func pdf(_ pages: [TableFixtureLayouts.Page]) -> Data {
        UIGraphicsPDFRenderer(bounds: pageSize).pdfData { context in
            for page in pages {
                context.beginPage()
                for item in page {
                    NSAttributedString(string: item.text,
                                       attributes: [.font: font(item), .foregroundColor: UIColor.black])
                        .draw(at: CGPoint(x: item.x, y: item.y))
                }
            }
        }
    }

    /// One page that the PDF turns a quarter clockwise to show (Plan JW follow-up): `shown` laid
    /// out as the page is shown — `pageHeight` wide and `pageWidth` tall — and drawn on its side,
    /// so it reads upright once the page's `/Rotate` is set to 90 (`turnedDocument`); `own`
    /// drawn the page's own way up, as a running head or footer is.
    static func turned(shown: TableFixtureLayouts.Page, own: TableFixtureLayouts.Page) -> Data {
        UIGraphicsPDFRenderer(bounds: pageSize).pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            for item in shown {
                cg.saveGState()
                // A point (x, y) as shown sits at (y, height − x) on the page's own top-down space,
                // and the shown page's rightward runs up the page.
                cg.translateBy(x: item.y, y: pageSize.height - item.x)
                cg.rotate(by: -.pi / 2)
                NSAttributedString(string: item.text, attributes: [.font: font(item), .foregroundColor: UIColor.black])
                    .draw(at: .zero)
                cg.restoreGState()
            }
            for item in own {
                NSAttributedString(string: item.text, attributes: [.font: font(item), .foregroundColor: UIColor.black])
                    .draw(at: CGPoint(x: item.x, y: item.y))
            }
        }
    }

    /// `turned` read back as a document whose page is turned a quarter clockwise to show.
    static func turnedDocument(shown: TableFixtureLayouts.Page, own: TableFixtureLayouts.Page) -> PDFDocument? {
        guard let document = PDFDocument(data: turned(shown: shown, own: own)) else { return nil }
        document.page(at: 0)?.rotation = 90
        return document
    }

    /// A page of prose with nothing tabular on it, for a document with a table among its pages.
    static func prosePage() -> TableFixtureLayouts.Page {
        (0..<12).map { index in
            TableFixtureLayouts.Item(text: "Paragraph line \(index + 1) of an invented manual describes general care of the unit.",
                                     x: 50, y: 80 + Double(index) * 14)
        }
    }

    static func write(_ data: Data, named name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
