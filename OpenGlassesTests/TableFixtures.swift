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
