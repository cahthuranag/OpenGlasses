import CoreGraphics
import Foundation
import Vision

/// The production [[PictureTableReader]] (Plan JN P1): Apple Vision, on the device, nothing sent
/// anywhere. Reads a drawn region either way [[PictureTableReading]] asks:
///
/// - **`documentGrid`** — `RecognizeDocumentsRequest`: the tables the document reading finds, each
///   cell by its row and column range with its own words, plus the region's words.
/// - **`words`** — `RecognizeTextRequest`: every line, split into words by the boxes the
///   recogniser gives each word's characters.
///
/// Both run with **language correction off** — a dictionary turns "5O" into "50" or "SO", exactly
/// the difference a cell must keep — and with no lower limit on text height worth the name, since a
/// table's type is small against a tall region. No custom words are given: Vision uses them only
/// with language correction on, so passing them here would claim a steer that does not happen
/// (Plan JN P2). Boxes come back through `PictureRegion.pageRect`, the one mapping to page space. Nothing
/// is logged: not an image, not a word.
///
/// Builds on macOS too, so the measurement runner reads a picture as the phone does (though Vision
/// on a Mac may read differently; the phone's import is what counts).
struct VisionTableReader: PictureTableReader {

    /// Readings kept per word beyond the best, for the certainty pass.
    var maximumCandidates = 3

    /// The least text height, as a share of the image's, the recogniser looks for: about seven
    /// pixels in a full-page region.
    var minimumTextHeightFraction: Float = 0.003

    init(maximumCandidates: Int = 3) {
        self.maximumCandidates = maximumCandidates
    }

    func recognise(_ image: CGImage, render: PictureRegion.Render, reading: ManualTable.Source.Reader) async -> RecognisedPage {
        switch reading {
        case .documentGrid: return await documentGrid(image, render: render)
        case .words: return await words(image, render: render)
        }
    }

    // MARK: - The document reading

    private func documentGrid(_ image: CGImage, render: PictureRegion.Render) async -> RecognisedPage {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.maximumCandidateCount = maximumCandidates + 1
        request.textRecognitionOptions.minimumTextHeightFraction = minimumTextHeightFraction
        request.barcodeDetectionOptions.enabled = false
        guard let observations = try? await request.perform(on: image) else { return RecognisedPage() }
        var page = RecognisedPage()
        for observation in observations {
            let document = observation.document
            page.words += (document.text.words ?? document.text.lines).flatMap { words(of: $0, render: render) }
            for table in document.tables {
                var cells: [RecognisedPage.Cell] = []
                var seen = Set<String>()
                for row in table.rows {
                    for cell in row {
                        // A spanned cell is listed under every row it spans; it is one cell.
                        let id = "\(cell.rowRange.lowerBound)-\(cell.rowRange.upperBound):\(cell.columnRange.lowerBound)-\(cell.columnRange.upperBound)"
                        guard seen.insert(id).inserted else { continue }
                        let text = cell.content.text
                        let words = (text.words ?? text.lines).flatMap { self.words(of: $0, render: render) }
                        cells.append(RecognisedPage.Cell(rows: cell.rowRange, columns: cell.columnRange, words: words))
                    }
                }
                page.tables.append(RecognisedPage.Table(cells: cells))
            }
        }
        return page
    }

    // MARK: - The words reading

    private func words(_ image: CGImage, render: PictureRegion.Render) async -> RecognisedPage {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeightFraction = minimumTextHeightFraction
        guard let lines = try? await request.perform(on: image) else { return RecognisedPage() }
        return RecognisedPage(words: lines.flatMap { words(of: $0, render: render) })
    }

    // MARK: - Words in page space

    /// An observation's words: one word as it is, a line split at its spaces, each piece boxed by
    /// the recogniser's own box for its characters. The other readings Vision offered are kept
    /// for a word read whole; a piece of a line keeps none, since another reading of the line need
    /// not split at the same places.
    private func words(of observation: RecognizedTextObservation, render: PictureRegion.Render) -> [RecognisedWord] {
        let candidates = observation.topCandidates(maximumCandidates + 1)
        guard let best = candidates.first else { return [] }
        let string = best.string
        let pieces = string.split(whereSeparator: \.isWhitespace)
        if pieces.count <= 1 {
            let text = string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return [] }
            return [RecognisedWord(text, rect: pageRect(of: observation, render: render), confidence: best.confidence,
                                   candidates: candidates.dropFirst().map(\.string).filter { $0 != text })]
        }
        return pieces.compactMap { piece -> RecognisedWord? in
            let range = piece.startIndex..<piece.endIndex
            guard let box = best.boundingBox(for: range) else { return nil }
            return RecognisedWord(String(piece), rect: pageRect(of: box, render: render), confidence: best.confidence)
        }
    }

    private func pageRect(of quad: some QuadrilateralProviding, render: PictureRegion.Render) -> CGRect {
        let xs = [quad.topLeft.x, quad.topRight.x, quad.bottomLeft.x, quad.bottomRight.x]
        let ys = [quad.topLeft.y, quad.topRight.y, quad.bottomLeft.y, quad.bottomRight.y]
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        // Vision's box: normalised to the image, origin at its bottom left.
        return PictureRegion.pageRect(ofNormalised: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                                      in: render)
    }
}
