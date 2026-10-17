import PDFKit
import UIKit
@testable import OpenGlasses

/// Fixture PDFs for Plan IN P0–P2, drawn in the test so CI needs no licensed manual.
///
/// The shapes a code book actually has: clause-numbered prose in two columns, words hyphenated at
/// line ends, roman-numeral front matter before page 1, and a scanned page with no text layer.
enum PassageFixtures {

    static let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792)

    static let depthSentence = "The minimum depth of cover for an underground cable at a commercial site shall be 500 mm."
    static let protectionSentence = "Mechanical protection shall be provided where that depth cannot be achieved."
    static let markerSentence = "A marker tape shall be laid 150 mm above the cable along its whole route."
    static let earthingSentence = "Every exposed conductive part shall be connected to the main earthing terminal."
    static let bondingSentence = "Equipotential bonding conductors shall be sized in accordance with the table that follows."

    /// The hyphenated page's sentence, as the chunker sees it once the line ends are read.
    static let hyphenatedSentence = "Where cables are installed underground, the minimum depth of cover shall be 500 mm for a commercial site."

    private static let body = UIFont(name: "Helvetica", size: 10) ?? .systemFont(ofSize: 10)
    private static let heading = UIFont(name: "Helvetica-Bold", size: 10) ?? .boldSystemFont(ofSize: 10)

    private static func draw(_ text: String, font: UIFont = body, in rect: CGRect) {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black]).draw(in: rect)
    }

    private static func line(_ text: String, font: UIFont = body, at point: CGPoint) {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black]).draw(at: point)
    }

    /// Filler that makes a column long enough to be read as prose, with nothing in it the tests
    /// look for.
    static func filler(_ seed: String, sentences: Int) -> String {
        (1...sentences).map { "Note \(seed)-\($0) describes general arrangements for installers and inspectors on site." }
            .joined(separator: " ")
    }

    /// A standard-like page: clause headings in bold, two columns, the clause's requirement in the
    /// left column and an unrelated clause in the right.
    static func twoColumnStandard() -> Data {
        UIGraphicsPDFRenderer(bounds: pageSize).pdfData { context in
            context.beginPage()
            let left = CGRect(x: 48, y: 64, width: 240, height: 660)
            let right = CGRect(x: 324, y: 64, width: 240, height: 660)
            line("3.9.4 Underground wiring", font: heading, at: CGPoint(x: left.minX, y: left.minY))
            draw([filler("A", sentences: 2), depthSentence, protectionSentence, markerSentence,
                  filler("B", sentences: 3)].joined(separator: " "),
                 in: left.offsetBy(dx: 0, dy: 18))
            line("5.6.2 Earthing arrangements", font: heading, at: CGPoint(x: right.minX, y: right.minY))
            draw([filler("C", sentences: 2), earthingSentence, bondingSentence, filler("D", sentences: 3)]
                .joined(separator: " "), in: right.offsetBy(dx: 0, dy: 18))
        }
    }

    /// A page whose requirement is broken across lines with hyphens, the way a typeset book prints.
    static func hyphenatedPage() -> Data {
        UIGraphicsPDFRenderer(bounds: pageSize).pdfData { context in
            context.beginPage()
            var y: CGFloat = 64
            let lines = [
                "3.9.4.2 Depth of burial",
                "General arrangements for installers and inspectors on site are de-",
                "scribed in the notes that follow this clause. Where cables are in-",
                "stalled underground, the minimum depth of cover shall be 500 mm for a commer-",
                "cial site. Mechanical protection shall be provided where that depth",
                "cannot be achieved by the installer on the day.",
            ]
            for (index, text) in lines.enumerated() {
                line(text, font: index == 0 ? heading : body, at: CGPoint(x: 48, y: y))
                y += 14
            }
        }
    }

    /// Two pages: a text page, then a scanned page — an image of text with no text layer.
    static func textThenScannedPage() -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 200)).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 500, height: 200))
            NSAttributedString(string: depthSentence, attributes: [.font: UIFont.systemFont(ofSize: 14)])
                .draw(in: CGRect(x: 10, y: 10, width: 480, height: 180))
        }
        return UIGraphicsPDFRenderer(bounds: pageSize).pdfData { context in
            context.beginPage()
            draw([filler("E", sentences: 3), depthSentence, filler("F", sentences: 3)].joined(separator: " "),
                 in: CGRect(x: 48, y: 64, width: 516, height: 600))
            context.beginPage()
            image.draw(in: CGRect(x: 48, y: 64, width: 500, height: 200))
        }
    }

    /// Roman-numeral front matter, then the body numbered from 1, the number printed in the footer.
    static let frontMatterFooters = ["i", "ii", "iii", "1", "2", "3"]

    static func romanFrontMatter() -> Data {
        UIGraphicsPDFRenderer(bounds: pageSize).pdfData { context in
            for (index, footer) in frontMatterFooters.enumerated() {
                context.beginPage()
                draw(filler("P\(index)", sentences: 6), in: CGRect(x: 48, y: 100, width: 516, height: 500))
                line(footer, at: CGPoint(x: 300, y: pageSize.height - 40))
            }
        }
    }

    /// One page of a code book for the show-me tests: a heading, a requirement and filler.
    static func codeBook(pages: [(heading: String, requirement: String)]) -> Data {
        UIGraphicsPDFRenderer(bounds: pageSize).pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                line(page.heading, font: heading, at: CGPoint(x: 48, y: 64))
                draw([filler("G\(index)", sentences: 6), page.requirement, filler("H\(index)", sentences: 6)]
                    .joined(separator: " "), in: CGRect(x: 48, y: 84, width: 516, height: 640))
            }
        }
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// The UTF-16 range of `sentence` in `pageText`, allowing any run of whitespace — and a line-end
    /// hyphen — where the sentence has a space or nothing. What an exact highlight must cover.
    static func expectedRange(of sentence: String, in pageText: String) -> NSRange? {
        let words = sentence.split(separator: " ").map { word -> String in
            // A word may be broken by "-" plus whitespace anywhere inside it.
            word.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"(?:-\s*)?"#)
        }
        let pattern = words.joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: pageText, range: NSRange(location: 0, length: (pageText as NSString).length))?.range
    }
}
