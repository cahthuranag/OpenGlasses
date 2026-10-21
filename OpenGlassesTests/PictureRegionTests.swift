import CoreGraphics
import XCTest
@testable import OpenGlasses

/// Plan JN P0 — the region of a page a pictured table is recognised from, and the one mapping from
/// a recogniser's normalised, bottom-left boxes back to top-down page points. Invented pages only.
final class PictureRegionTests: XCTestCase {

    private typealias Item = TableFixtureLayouts.Item
    private let letter = CGRect(x: 0, y: 0, width: TableFixtureLayouts.pageWidth, height: TableFixtureLayouts.pageHeight)
    private let caption97 = TableExtractor.Caption(label: "Table 97", title: "", continues: false)

    private var footerTop: Double { TableFixtureLayouts.pageHeight * (1 - PictureRegion.footerBand) }

    // MARK: - The region under a caption

    func testTheRegionRunsFromUnderTheCaptionsBlockToTheFooterBand() throws {
        let words = TableFixtureLayouts.words(TableFixtureLayouts.tableWithoutText())
        let region = try XCTUnwrap(PictureRegion.below(caption: caption97, words: words, pageBounds: letter))
        XCTAssertEqual(region.minY, 101, accuracy: 0.001, "under the paragraph set close under the caption")
        XCTAssertEqual(region.maxY, footerTop, accuracy: 0.001, "above the page number's band")
        XCTAssertEqual(region.minX, 0)
        XCTAssertEqual(region.width, letter.width, "the page's width")
    }

    func testTheRegionStopsAtTheNextTextLine() throws {
        let words = TableFixtureLayouts.words([Item(text: "TABLE 97", x: 50, y: 60, size: 10, bold: true),
                                               Item(text: "Invented notes", x: 50, y: 74, size: 10, bold: true),
                                               Item(text: "The text set after the invented picture.", x: 50, y: 400)])
        let region = try XCTUnwrap(PictureRegion.below(caption: caption97, words: words, pageBounds: letter))
        XCTAssertEqual(region.minY, 84, accuracy: 0.001, "under the title read with the caption")
        XCTAssertEqual(region.maxY, 400, accuracy: 0.001)
    }

    func testNoRegionWithoutTheCaptionOrBeforeTheNextCaption() throws {
        let words = TableFixtureLayouts.words([Item(text: "Table 97 Invented resistances", x: 50, y: 60),
                                               Item(text: "Table 98 Invented spacings", x: 50, y: 75)])
        XCTAssertNil(PictureRegion.below(caption: caption97, words: words, pageBounds: letter),
                     "another caption comes before any empty stretch")
        let next = try XCTUnwrap(PictureRegion.below(caption: .init(label: "Table 98", title: "", continues: false),
                                                     words: words, pageBounds: letter))
        XCTAssertEqual(next.minY, 84, accuracy: 0.001)
        XCTAssertNil(PictureRegion.below(caption: .init(label: "Table Q7", title: "", continues: false),
                                         words: words, pageBounds: letter))
        let crowded = TableFixtureLayouts.words([Item(text: "Table 97 Invented resistances", x: 50, y: 700),
                                                 Item(text: "44", x: 300, y: 752)])
        XCTAssertNil(PictureRegion.below(caption: caption97, words: crowded, pageBounds: letter),
                     "too little page left above the footer")
    }

    func testTheFooterBandIsThePageNumberBand() {
        XCTAssertEqual(PictureRegion.footerBand, Double(VaultDocumentExtractor.pageNumberBand))
    }

    // MARK: - Normalised boxes back to page points

    /// The inverse of `PictureRegion.pageRect`: a page box as the recogniser would report it.
    private func normalised(_ rect: CGRect, in render: PictureRegion.Render) -> CGRect {
        let width = Double(render.pixelWidth) / render.scale
        let height = Double(render.pixelHeight) / render.scale
        return CGRect(x: (Double(rect.minX) - Double(render.region.minX)) / width,
                      y: 1 - (Double(rect.maxY) - Double(render.region.minY)) / height,
                      width: Double(rect.width) / width, height: Double(rect.height) / height)
    }

    private func assertEqual(_ a: CGRect, _ b: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.width, b.width), (a.height, b.height)] {
            XCTAssertEqual(Double(x), Double(y), accuracy: 1e-9, message, file: file, line: line)
        }
    }

    func testABoxAtTheImagesBottomLeftIsAtTheRegionsFoot() {
        let render = PictureRegion.Render(region: CGRect(x: 50, y: 100, width: 500, height: 300), scale: 2)
        XCTAssertEqual(render.pixelWidth, 1000)
        XCTAssertEqual(render.pixelHeight, 600)
        assertEqual(PictureRegion.pageRect(ofNormalised: CGRect(x: 0, y: 0, width: 0.1, height: 0.05), in: render),
                    CGRect(x: 50, y: 385, width: 50, height: 15), "origin bottom left becomes top-down")
        assertEqual(PictureRegion.pageRect(ofNormalised: CGRect(x: 0, y: 0, width: 1, height: 1), in: render),
                    render.region, "the whole image is the whole region")
    }

    func testBoxesRoundTripAtSeveralCropsAndScales() {
        let regions = [CGRect(x: 0, y: 101, width: 612, height: 619.72), CGRect(x: 36.5, y: 240.25, width: 300.3, height: 120.7),
                       CGRect(x: 72, y: 72, width: 468, height: 648)]
        let boxes = [CGRect(x: 0, y: 0, width: 12, height: 9), CGRect(x: 40.2, y: 17.9, width: 33.3, height: 8.6)]
        for region in regions {
            for scale in [1.0, 2.0, 2.78, 4.17] {
                let render = PictureRegion.Render(region: region, scale: scale)
                XCTAssertGreaterThanOrEqual(Double(render.pixelWidth) / scale, Double(region.width))
                for offset in boxes {
                    let page = offset.offsetBy(dx: region.minX, dy: region.minY)
                    assertEqual(PictureRegion.pageRect(ofNormalised: normalised(page, in: render), in: render), page,
                                "\(region) at \(scale)")
                }
            }
        }
    }

    func testARoundedUpImageSizeIsAccountedFor() {
        let render = PictureRegion.Render(region: CGRect(x: 10, y: 20, width: 100.3, height: 50.1), scale: 3)
        XCTAssertEqual(render.pixelWidth, 301)
        XCTAssertEqual(render.pixelHeight, 151)
        let right = PictureRegion.pageRect(ofNormalised: CGRect(x: 1, y: 0, width: 0, height: 0), in: render)
        XCTAssertEqual(Double(right.minX), 10 + 301.0 / 3, accuracy: 1e-9, "the image's edge, past the region's by the rounding")
        XCTAssertEqual(Double(right.minY), 20 + 151.0 / 3, accuracy: 1e-9)
    }
}
