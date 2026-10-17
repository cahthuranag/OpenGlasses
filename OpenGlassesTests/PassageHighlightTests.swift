import PDFKit
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan IN P1 — the highlight in the viewer.
///
/// What the sheet draws for a cited passage, what it says when it cannot draw it, and what
/// VoiceOver reads first — tested on a fixture page rendered in both appearances, because nobody
/// sees this on a roof before it ships.
@MainActor
final class PassageHighlightTests: XCTestCase {

    private func fixturePage() throws -> (PDFDocument, PDFPage, String) {
        let document = try XCTUnwrap(PDFDocument(data: PassageFixtures.twoColumnStandard()))
        let page = try XCTUnwrap(document.page(at: 0))
        return (document, page, try XCTUnwrap(page.string))
    }

    private func cited(_ sentences: [String], number: Int = 1, page: Int = 1) -> CitedPassage {
        let text = sentences.joined(separator: " ")
        var starts: [Int] = []
        var cursor = 0
        for sentence in sentences { starts.append(cursor); cursor += sentence.count + 1 }
        return CitedPassage(number: number, anchor: PassageAnchor(documentId: "d", chunkIndex: number, text: text,
                                                                  page: page, sentenceStarts: starts))
    }

    // MARK: - What the sheet says

    func testAFoundPassageIsMarkedAndSaysNothingElse() throws {
        let (_, _, text) = try fixturePage()
        let marks = PassageMarks(passages: [cited([PassageFixtures.depthSentence])], page: 1, pageText: text)
        XCTAssertEqual(marks.located.count, 1)
        XCTAssertNil(marks.unmarkedLine)
        XCTAssertFalse(marks.showsNumbers, "one passage on the page needs no number")
        XCTAssertEqual(marks.spokenPassages(in: text)?.hasPrefix("Highlighted: The minimum depth"), true)
    }

    func testAPassageThatCannotBeFoundOpensThePagePlainWithALine() throws {
        let (_, page, text) = try fixturePage()
        let marks = PassageMarks(passages: [cited(["A sentence this page does not print anywhere at all."])],
                                 page: 1, pageText: text)
        XCTAssertEqual(marks.unmarkedLine, "The passage couldn't be marked on this page.")
        XCTAssertNil(marks.spokenPassages(in: text))
        XCTAssertNil(PassageHighlighter.apply(marks, to: page))
        XCTAssertFalse(page.annotations.contains { $0.userName == PassageHighlighter.annotationTag },
                       "decision 3: nothing is drawn for a passage that was not found")

        let scanned = PassageMarks(passages: [cited([PassageFixtures.depthSentence])], page: 1, pageText: nil)
        XCTAssertEqual(scanned.marks.first?.location, .notLocatable(.noTextLayer))
        XCTAssertEqual(scanned.unmarkedLine, "The passage couldn't be marked on this page.")
    }

    func testAPageReachedWithoutAPassageSaysNothing() throws {
        let (_, _, text) = try fixturePage()
        let marks = PassageMarks(passages: [cited([PassageFixtures.depthSentence], page: 2)], page: 1, pageText: text)
        XCTAssertFalse(marks.hasPassages)
        XCTAssertNil(marks.unmarkedLine)
    }

    func testSeveralPassagesOnOnePageAreNumberedAsTheAnswerNumberedThem() throws {
        let (_, page, text) = try fixturePage()
        let marks = PassageMarks(passages: [cited([PassageFixtures.depthSentence], number: 1),
                                            cited([PassageFixtures.earthingSentence], number: 3)],
                                 page: 1, pageText: text)
        XCTAssertTrue(marks.showsNumbers)
        XCTAssertEqual(marks.located.map(\.number), [1, 3])
        XCTAssertTrue(marks.spokenPassages(in: text)?.contains("Passage 3: Every exposed conductive part") == true)
        PassageHighlighter.apply(marks, to: page)
        let labels = page.annotations.filter { $0.userName == PassageHighlighter.annotationTag && $0.type == "FreeText" }
        XCTAssertEqual(labels.compactMap(\.contents).sorted(), ["1", "3"])
    }

    // MARK: - What is drawn

    func testHighlightsAreAddedPerLineTaggedAndRemovedWithoutTouchingThePublishersAnnotations() throws {
        let (document, page, text) = try fixturePage()
        let publishers = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 20, height: 20), forType: .square,
                                       withProperties: nil)
        page.addAnnotation(publishers)
        let marks = PassageMarks(passages: [cited([PassageFixtures.depthSentence, PassageFixtures.protectionSentence])],
                                 page: 1, pageText: text)
        let first = try XCTUnwrap(PassageHighlighter.apply(marks, to: page))
        let highlights = page.annotations.filter { $0.userName == PassageHighlighter.annotationTag }
        XCTAssertGreaterThan(highlights.count, 1, "a passage that wraps is marked line by line")
        XCTAssertTrue(highlights.allSatisfy { $0.type == "Highlight" })
        XCTAssertTrue(highlights.contains { $0.bounds.insetBy(dx: 1, dy: 1).intersects(first) })

        PassageHighlighter.clear(page)
        XCTAssertEqual(page.annotations.count, 1)
        XCTAssertTrue(page.annotations.first === publishers)
        XCTAssertNil(document.documentURL, "the marks live on an in-memory page; nothing is written")
    }

    /// The annotated page, rendered as the viewer draws it in light and in dark: the mark is there
    /// in both, and the type under it is still dark on a light ground.
    func testTheMarkedPageRendersInBothAppearances() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let (_, page, text) = try fixturePage()
            let marks = PassageMarks(passages: [cited([PassageFixtures.depthSentence])], page: 1, pageText: text)
            let line = try XCTUnwrap(PassageHighlighter.apply(marks, to: page))
            var image: UIImage!
            UITraitCollection(userInterfaceStyle: style).performAsCurrent {
                image = render(page)
            }
            // Sample just inside the mark's left edge, between glyphs as often as on them: the
            // brightest pixel along the line is the ground, and on a marked line it is yellow.
            let ground = brightestPixel(in: image, page: page,
                                        along: CGRect(x: line.minX, y: line.midY, width: line.width, height: 1))
            XCTAssertGreaterThan(ground.red, 0.85, "\(style.rawValue): the ground is light")
            XCTAssertLessThan(ground.blue, ground.red - 0.15, "\(style.rawValue): the ground is the highlight's yellow, not white")
            // An unmarked line of the same page stays white.
            let blank = brightestPixel(in: image, page: page,
                                       along: CGRect(x: line.minX, y: line.midY > 400 ? line.midY - 250 : line.midY + 250,
                                                     width: line.width, height: 1))
            XCTAssertGreaterThan(blank.blue, 0.95, "\(style.rawValue): unmarked paper stays white")
        }
    }

    func testTheHighlightTokenClearsContrastInBothSchemes() {
        for pair in OGTheme.contrastAudit where pair.name.contains("highlighted passage") {
            for scheme in OGColorScheme.allCases {
                XCTAssertTrue(ContrastRatio.meetsAA(pair.ratio(in: scheme), size: pair.textSize),
                              "\(pair.name) in \(scheme): \(pair.ratio(in: scheme))")
            }
        }
        XCTAssertEqual(OGTheme.contrastAudit.filter { $0.name.contains("highlighted passage") }.count, 2)
    }

    // MARK: - The text fallback

    func testTheExtractedTextFallbackMarksTheSameRanges() {
        let pageText = "Intro line.\n" + PassageFixtures.depthSentence + "\nMore."
        let model = ManualPageSheetModel(citation: "Code, page 1", documentTitle: "Code", citedPage: 1,
                                         extractedPages: [.init(number: 1, text: pageText)],
                                         citedPassages: [cited([PassageFixtures.depthSentence])])
        XCTAssertEqual(model.route, .extractedText)
        XCTAssertEqual(model.currentTextMarks.located.first?.location.ranges,
                       [(pageText as NSString).range(of: PassageFixtures.depthSentence)])
        XCTAssertEqual(model.passages(onPage: 1).count, 1)
        XCTAssertTrue(model.passages(onPage: 2).isEmpty)
    }

    func testCitedPassagesDoNotChangeWhatTheSheetOpensOrRecords() {
        let plain = ManualPageSheetModel(citation: "Code, page 2", documentTitle: "Code", citedPage: 2,
                                         extractedPages: [.init(number: 1, text: "a"), .init(number: 2, text: "b")])
        let marked = ManualPageSheetModel(citation: "Code, page 2", documentTitle: "Code", citedPage: 2,
                                          extractedPages: [.init(number: 1, text: "a"), .init(number: 2, text: "b")],
                                          citedPassages: [cited(["b"], page: 2)])
        XCTAssertEqual(marked.route, plain.route)
        XCTAssertEqual(marked.paging, plain.paging)
        XCTAssertEqual(marked.headerLine, plain.headerLine)
        // Evidence is still what the page's origin and the technician's confirmation make it.
        XCTAssertEqual(PageEvidencePolicy.classify(origin: .requested, confirmation: .none), .opened)
        XCTAssertEqual(PageEvidencePolicy.classify(origin: .requested, confirmation: .tap), .verified)
    }

    // MARK: - Rendering helpers

    private func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private struct RGB { let red: CGFloat; let green: CGFloat; let blue: CGFloat }

    /// The brightest pixel along a strip given in page space.
    private func brightestPixel(in image: UIImage, page: PDFPage, along strip: CGRect) -> RGB {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return RGB(red: 0, green: 0, blue: 0) }
        let height = page.bounds(for: .mediaBox).height
        let y = Int(height - strip.midY)
        let perRow = cg.bytesPerRow
        let perPixel = cg.bitsPerPixel / 8
        var best = RGB(red: 0, green: 0, blue: 0)
        var bestSum: CGFloat = -1
        for x in stride(from: Int(strip.minX) + 2, to: Int(strip.maxX) - 2, by: 1) where y >= 0 && y < cg.height {
            let offset = y * perRow + x * perPixel
            // BGRA or RGBA: read by the image's own order.
            let isBGR = cg.bitmapInfo.contains(.byteOrder32Little)
            let r = CGFloat(bytes[offset + (isBGR ? 2 : 0)]) / 255
            let g = CGFloat(bytes[offset + 1]) / 255
            let b = CGFloat(bytes[offset + (isBGR ? 0 : 2)]) / 255
            if r + g + b > bestSum { bestSum = r + g + b; best = RGB(red: r, green: g, blue: b) }
        }
        return best
    }
}
