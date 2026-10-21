import CoreGraphics
import Foundation

/// Where on a page a pictured table is, and how a recogniser's boxes come back to the page (Plan JN
/// P0). Pure: a page's text-layer words in, a rectangle in page points out, so the region a
/// recogniser is given is decided without a PDF, and only that region — never the page — is read.
enum PictureRegion {

    /// The share of the page's height at its foot where a page number and running footer print —
    /// the band `VaultDocumentExtractor.pageNumberBand` reads a printed page number from
    /// ([[PrintedPageBand]]). A pictured table stops above it.
    static let footerBand = 0.09

    /// The least height, in lines of the caption's type, a stretch of page under a caption must
    /// leave free of text to hold a table.
    static let minimumHeightLines = 3.0

    /// The rectangle to recognise for the table `caption` heads, in top-down page points: from under
    /// the caption and its title to the next text line, or to the footer band, whichever comes
    /// first. Lines set close under the caption (a title that wrapped, a sentence that leads into
    /// the table) belong to the caption's block and are passed over, so the region is the first
    /// stretch at least `minimumHeightLines` tall that the text layer leaves empty. Nil when the
    /// caption is not on the page, or another caption or the footer comes before any such stretch.
    /// The region spans the page's width: a picture's own margins are the recogniser's to ignore.
    static func below(caption: TableExtractor.Caption, words: [PositionedWord], pageBounds: CGRect,
                      footerBand: Double = footerBand) -> CGRect? {
        let lines = TableExtractor.lines(of: words)
        let captions = TableExtractor.captionLines(in: lines, pageHasBold: TableExtractor.hasBold(words))
        guard let found = captions.first(where: { $0.caption.label.caseInsensitiveCompare(caption.label) == .orderedSame })
        else { return nil }
        let footerTop = Double(pageBounds.maxY) - footerBand * Double(pageBounds.height)
        let minimum = minimumHeightLines * max(lines[found.index].size, 1)
        let otherCaptions = Set(captions.map(\.index)).subtracting([found.index])
        var bottom = lines[found.index + found.titleLines].bottom
        func region(to top: Double) -> CGRect {
            CGRect(x: pageBounds.minX, y: CGFloat(bottom), width: pageBounds.width, height: CGFloat(top - bottom))
        }
        for index in (found.index + 1 + found.titleLines)..<lines.count {
            let line = lines[index]
            let top = min(line.top, footerTop)
            if top - bottom >= minimum { return region(to: top) }
            if line.top >= footerTop || otherCaptions.contains(index) { return nil }
            bottom = max(bottom, line.bottom)
        }
        return footerTop - bottom >= minimum ? region(to: footerTop) : nil
    }

    /// A region drawn as an image for a recogniser: `scale` pixels to the point, the image's pixel
    /// size the region's rounded up, its top left at the region's.
    struct Render: Equatable {
        var region: CGRect
        var scale: Double
        var pixelWidth: Int
        var pixelHeight: Int

        init(region: CGRect, scale: Double) {
            self.region = region
            self.scale = scale
            pixelWidth = Int((Double(region.width) * scale).rounded(.up))
            pixelHeight = Int((Double(region.height) * scale).rounded(.up))
        }
    }

    /// A recogniser's box — normalised 0–1 to the rendered image, origin at its **bottom** left, as
    /// Vision gives one — as a box in **top-down** page points, as [[PositionedWord]] and
    /// [[RecognisedWord]] keep one. The one place the two spaces meet.
    static func pageRect(ofNormalised box: CGRect, in render: Render) -> CGRect {
        let width = Double(render.pixelWidth) / render.scale
        let height = Double(render.pixelHeight) / render.scale
        return CGRect(x: Double(render.region.minX) + Double(box.minX) * width,
                      y: Double(render.region.minY) + (1 - Double(box.maxY)) * height,
                      width: Double(box.width) * width,
                      height: Double(box.height) * height)
    }

    /// A box in top-down page points, measured from the media box's top left as a region is, as a
    /// box in the PDF's own page space (origin at the media box's bottom left, y upwards): where an
    /// annotation outlining it is drawn (Plan JN P2).
    static func pdfRect(ofPageRect rect: CGRect, mediaBox: CGRect) -> CGRect {
        CGRect(x: mediaBox.minX + rect.minX, y: mediaBox.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
