import CoreGraphics
import Foundation
import PDFKit

/// Recognises a region of a page drawn as an image, for a table printed as a picture (Plan JN P1).
/// The seam that keeps the reading headless-testable: which regions to send, how many times, what is
/// kept and how a recognition becomes a table are all decided around this one call, and tests inject
/// a fake. The production reader is [[VisionTableReader]], on the device.
protocol PictureTableReader: Sendable {
    /// `image` is `render.region` of the page drawn at `render.scale`. The recognition comes back in
    /// page space ([[PictureRegion]]`.pageRect`): words with their top-down page boxes, and, for the
    /// document reading, the tables the recogniser found as cells by row and column.
    func recognise(_ image: CGImage, render: PictureRegion.Render, reading: ManualTable.Source.Reader) async -> RecognisedPage
}

/// When, where and how a table printed as a picture is read at import (Plan JN P1).
///
/// **Text first.** A caption is read from a picture only where the text layer gave no grid under it
/// (`no_text_in_table`, or `too_few_rows` with a tall stretch of page the text layer leaves empty
/// right under it — a picture set straight under the caption), and a page with no text layer only
/// when its own recognition carries a table caption. A table the text layer gave is never re-read.
///
/// **Two passes, one reader.** Each region is drawn at `scales` and recognised twice by the reading
/// `preferred` names; the second pass is what [[CellCertainty]] compares cell by cell. The other
/// reading is not run.
///
/// **Nothing leaves the phone, nothing is logged.** Images are drawn, recognised and dropped; the
/// recognition is kept only in the import's checkpoint (`PictureTableCheckpoint`), beside EF's, so
/// a relaunch does not recognise a region twice.
enum PictureTableReading {

    /// The reading that makes the grid, settled by Plan JN P1's measurement on the private book.
    static let preferred: ManualTable.Source.Reader = .documentGrid

    /// The least word confidence a clear cell may have, settled by the same measurement.
    static let floor: Float = 0.5

    /// The least word confidence a clear cell may have on a photographed page (Plan JN P4): a
    /// picture of a picture, with skew, glare and curl a PDF's drawn page does not have, so its
    /// floor is its own and is not inherited from the PDF case. **Provisional**: set to the PDF
    /// floor until it is measured on the binder pages of the photographed-manuals device guide
    /// (`docs/field-assist/photographed-manuals.md`; device pass owed). Nothing here measured it.
    static let capturedFloor: Float = 0.5

    /// Pixels per point for the reading pass and the agreement pass. Under thermal pressure both
    /// step down, as EF's page recognition steps its resolution down, so the import finishes rather
    /// than stalls; the two stay apart, and the scale is part of the checkpoint key.
    static func scales(for thermal: ProcessInfo.ThermalState) -> (first: Double, second: Double) {
        switch thermal {
        case .nominal, .fair: return (3, 2.5)
        case .serious, .critical: return (2.5, 2)
        @unknown default: return (2.5, 2)
        }
    }

    /// The longest side, in pixels, a region is drawn at; a taller region is drawn smaller, both
    /// passes by the same factor.
    static let maximumPixels = 4_000.0

    /// How tall, in lines of the caption's type, the empty stretch under a `too_few_rows` caption
    /// must be for its region to be read as a picture: a table of three rows and a heading.
    static let tooFewRowsMinimumLines = 5.0

    // MARK: - Candidates

    /// A region the reading found a recogniser could read.
    struct Candidate: Equatable {
        enum Kind: Equatable {
            /// The region under a caption whose grid the text layer did not give.
            case caption(TableExtractor.Caption)
            /// A page with no text layer, read whole to find its captions.
            case page
        }

        /// The page, 1-based.
        var physical: Int
        var kind: Kind
        /// Top-down page points.
        var region: CGRect
    }

    /// The region to read for a caption that failed with `failure`, or nil when none is worth
    /// reading: `no_text_in_table` with any region `PictureRegion.below` finds, `too_few_rows` only
    /// with one at least `tooFewRowsMinimumLines` tall. Nothing else is read from a picture.
    static func region(for caption: TableExtractor.Caption, failure: TableExtractor.Failure,
                       words: [PositionedWord], pageBounds: CGRect) -> CGRect? {
        guard failure == .noTextInTable || failure == .tooFewRows else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: pageBounds.width, height: pageBounds.height)
        guard let region = PictureRegion.below(caption: caption, words: words, pageBounds: bounds) else { return nil }
        guard failure == .tooFewRows else { return region }
        let lines = TableExtractor.lines(of: words)
        let size = TableExtractor.captionLines(in: lines, pageHasBold: TableExtractor.hasBold(words))
            .first { $0.caption.label.caseInsensitiveCompare(caption.label) == .orderedSame }
            .map { lines[$0.index].size } ?? 10
        return Double(region.height) >= tooFewRowsMinimumLines * max(size, 1) ? region : nil
    }

    /// The caption's own words on the page: its line and the title lines read with it.
    static func captionWords(of caption: TableExtractor.Caption, in words: [PositionedWord]) -> [PositionedWord] {
        let lines = TableExtractor.lines(of: words)
        guard let found = TableExtractor.captionLines(in: lines, pageHasBold: TableExtractor.hasBold(words))
            .first(where: { $0.caption.label.caseInsensitiveCompare(caption.label) == .orderedSame }) else { return [] }
        return lines[found.index...(found.index + found.titleLines)].flatMap(\.words)
    }

    /// A caption on a page with no text layer, read from the page's own recognition, with the
    /// region under it to read as a table.
    struct ScannedCaption: Equatable {
        var caption: TableExtractor.Caption
        var captionWords: [PositionedWord]
        var region: CGRect
    }

    /// The table captions a page with no text layer prints, by its recognised words — the same
    /// caption rule as a text page set in one weight, the same label spelling `ManualStructure`
    /// gives a chunk's figure — each with the region from under it to the next caption or the
    /// footer band. A caption with less than `PictureRegion.minimumHeightLines` of page under it
    /// (an entry in a list of tables) has no region and is left out.
    static func captionRegions(onScannedPage recognised: [RecognisedWord], pageBounds: CGRect) -> [ScannedCaption] {
        let words = RecognisedWords.positioned(recognised)
        let lines = TableExtractor.lines(of: words)
        let captions = TableExtractor.captionLines(in: lines, pageHasBold: false)
        let footerTop = Double(pageBounds.height) * (1 - PictureRegion.footerBand)
        var out: [ScannedCaption] = []
        for (position, found) in captions.enumerated() {
            let top = lines[found.index + found.titleLines].bottom
            let bottom = position + 1 < captions.count ? min(lines[captions[position + 1].index].top, footerTop) : footerTop
            guard bottom - top >= PictureRegion.minimumHeightLines * max(lines[found.index].size, 1) else { continue }
            out.append(ScannedCaption(caption: found.caption,
                                      captionWords: lines[found.index...(found.index + found.titleLines)].flatMap(\.words),
                                      region: CGRect(x: 0, y: top, width: Double(pageBounds.width), height: bottom - top)))
        }
        return out
    }

    // MARK: - Recognitions

    /// Where a region's recognition is kept: its page and the caption it is under.
    struct RegionKey: Hashable {
        var physical: Int
        var label: String

        init(physical: Int, label: String) {
            self.physical = physical
            self.label = label.lowercased()
        }
    }

    /// One region recognised twice: the reading pass and the agreement pass, at their scales.
    struct Recognition: Codable, Equatable {
        var first: RecognisedPage
        var second: RecognisedPage?
        var scales: [Double]
    }

    struct Recognitions: Equatable {
        var regions: [RegionKey: Recognition] = [:]
        /// A page with no text layer, recognised whole to find its captions.
        var pages: [Int: RecognisedPage] = [:]
        /// Regions whose checkpoint save failed (Plan JN P2), for the import's counts.
        var checkpointSaveFailures = 0
    }

    /// What a second reading of the document is given (pure).
    struct Inputs: Equatable {
        var recognitions: Recognitions
        var reading: ManualTable.Source.Reader
        var floor: Float
    }

    /// A picture read as a table: the reading's outcome after certainty, and the grid it was laid
    /// on when the reading was the words one (for a text page that carries it on).
    struct Read: Equatable {
        var outcome: TableExtractor.Outcome
        var grid: TableExtractor.Grid?
        var assessment: CellCertainty.Assessment
    }

    /// `recognition` read as the table `caption` heads, by `inputs.reading`, then judged cell by cell
    /// against its second pass.
    static func read(_ recognition: Recognition, captionWords: [PositionedWord], caption: TableExtractor.Caption,
                     page: ManualTable.Page, inputs: Inputs) -> Read {
        let reading: RecognisedReading
        switch inputs.reading {
        case .documentGrid:
            reading = RecognisedGrid.table(recognition.first, caption: caption, page: page)
        case .words:
            reading = RecognisedWords.table(recognition.first, captionWords: captionWords, caption: caption, page: page)
        }
        let assessment = CellCertainty.assess(reading, floor: inputs.floor, secondPass: recognition.second)
        return Read(outcome: assessment.outcome, grid: assessment.outcome.table == nil ? nil : reading.grid,
                    assessment: assessment)
    }

    // MARK: - Drawing a region

    /// `render.region` (top-down page points) of `page` drawn into a bitmap, white under it, at
    /// `render.scale`, its top left at the region's — what `PictureRegion.pageRect` maps back from.
    /// Drawn with CoreGraphics from the page's own content, so it runs on the phone and on a Mac.
    static func image(of page: PDFPage, render: PictureRegion.Render) -> CGImage? {
        guard render.pixelWidth > 0, render.pixelHeight > 0, let pageRef = page.pageRef,
              let context = CGContext(data: nil, width: render.pixelWidth, height: render.pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: render.pixelWidth, height: render.pixelHeight))
        context.interpolationQuality = .high
        let box = page.bounds(for: .mediaBox)
        let height = Double(render.pixelHeight) / render.scale
        context.scaleBy(x: render.scale, y: render.scale)
        // PDF space has its origin at the bottom left; the image's bottom edge sits `height` under
        // the region's top.
        context.translateBy(x: -(render.region.minX + box.minX), y: -(box.maxY - render.region.minY - height))
        context.drawPDFPage(pageRef)
        return context.makeImage()
    }

    /// The two renders of `region`, the longest side capped at `maximumPixels` for both alike.
    static func renders(of region: CGRect, scales: (first: Double, second: Double)) -> (PictureRegion.Render, PictureRegion.Render) {
        let longest = Double(max(region.width, region.height)) * max(scales.first, scales.second)
        let factor = longest > maximumPixels ? maximumPixels / longest : 1
        return (PictureRegion.Render(region: region, scale: scales.first * factor),
                PictureRegion.Render(region: region, scale: scales.second * factor))
    }

    // MARK: - Recognising at import

    /// What a reading with pictures needs at import: the reader, the reading and floor, the device's
    /// thermal state, read before each region, and the checkpoint.
    struct Context {
        var reader: PictureTableReader
        var reading: ManualTable.Source.Reader = PictureTableReading.preferred
        var floor: Float = PictureTableReading.floor
        var thermal: () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
        var checkpoint: (load: () -> PictureTableCheckpoint, save: (PictureTableCheckpoint) throws -> Void)?
    }

    /// The context an import reads pictures with: `reader`, the preferred reading and floor, the
    /// device's thermal state, and the checkpoint for the PDF of `contentHash` in `directory` (the
    /// vault's overlay folder, beside EF's).
    static func context(_ reader: PictureTableReader, checkpointIn directory: URL, contentHash: String) -> Context {
        Context(reader: reader, checkpoint: (
            load: { PictureTableCheckpoint.load(from: directory, contentHash: contentHash) },
            save: { try $0.save(to: directory) }))
    }

    /// Recognises every candidate the text-layer reading found, checkpointing each region as it is
    /// done and reusing any region already in the checkpoint.
    static func recognise(_ candidates: [Candidate], in document: PDFDocument, context: Context) async -> Recognitions {
        var recognitions = Recognitions()
        var failures = 0
        var state = context.checkpoint?.load() ?? PictureTableCheckpoint(contentHash: "")
        for candidate in candidates {
            guard let page = document.page(at: candidate.physical - 1) else { continue }
            switch candidate.kind {
            case .caption(let caption):
                recognitions.regions[.init(physical: candidate.physical, label: caption.label)] = await recogniseRegion(
                    candidate.region, of: page, physical: candidate.physical, label: caption.label,
                    reading: context.reading, twice: true, context: context, state: &state,
                    failures: &failures)
            case .page:
                // The page's words, read once, only to find its captions.
                guard let whole = await recogniseRegion(candidate.region, of: page, physical: candidate.physical, label: "",
                                                        reading: .words, twice: false, context: context, state: &state,
                                                        failures: &failures) else { continue }
                recognitions.pages[candidate.physical] = whole.first
                let bounds = page.bounds(for: .mediaBox)
                for found in captionRegions(onScannedPage: whole.first.words, pageBounds: bounds) {
                    recognitions.regions[.init(physical: candidate.physical, label: found.caption.label)] = await recogniseRegion(
                        found.region, of: page, physical: candidate.physical, label: found.caption.label,
                        reading: context.reading, twice: true, context: context, state: &state,
                        failures: &failures)
                }
            }
        }
        recognitions.checkpointSaveFailures = failures
        return recognitions
    }

    /// One region: from the checkpoint when it is there at either thermal step, else drawn and
    /// recognised (twice when `twice`), saved, and the image dropped. A save that fails (the phone
    /// locked before first unlock, a full disk) does not stop the import: the region is still read,
    /// and the failure is counted in `failures` for the import's log.
    private static func recogniseRegion(_ region: CGRect, of page: PDFPage, physical: Int, label: String,
                                        reading: ManualTable.Source.Reader, twice: Bool,
                                        context: Context, state: inout PictureTableCheckpoint,
                                        failures: inout Int) async -> Recognition? {
        for thermal in [ProcessInfo.ThermalState.nominal, .serious] {
            let key = PictureTableCheckpoint.key(physical: physical, label: label, reading: reading,
                                                 scale: scales(for: thermal).first)
            if let saved = state.regions[key] { return saved }
        }
        let steps = scales(for: context.thermal())
        let (first, second) = renders(of: region, scales: steps)
        guard let firstImage = image(of: page, render: first) else { return nil }
        let firstPass = await context.reader.recognise(firstImage, render: first, reading: reading)
        var secondPass: RecognisedPage?
        if twice, let secondImage = image(of: page, render: second) {
            secondPass = await context.reader.recognise(secondImage, render: second, reading: reading)
        }
        let recognition = Recognition(first: firstPass, second: secondPass,
                                      scales: twice ? [first.scale, second.scale] : [first.scale])
        state.regions[PictureTableCheckpoint.key(physical: physical, label: label, reading: reading, scale: steps.first)] = recognition
        do { try context.checkpoint?.save(state) } catch { failures += 1 }
        await Task.yield()
        return recognition
    }
}

/// The recognised regions of one document, kept as they are recognised so an import that is
/// interrupted does not recognise a region twice (Plan JN P1) — EF's `OCRCheckpoint`, for tables.
/// Keyed by the PDF's content hash (the file name), then by page, caption, reading and scale, so a
/// replaced file never reuses another file's regions. Lives beside EF's in the vault's `_ocr`
/// folder, under the same protection class EF's checkpoint has (until the phone's first unlock
/// after a restart, so an import that runs on with the phone locked can still save) and kept out
/// of backups, and is removed with it once the document is stored or forgotten.
struct PictureTableCheckpoint: Codable, Equatable {
    var contentHash: String
    var regions: [String: PictureTableReading.Recognition] = [:]

    init(contentHash: String, regions: [String: PictureTableReading.Recognition] = [:]) {
        self.contentHash = contentHash
        self.regions = regions
    }

    static func key(physical: Int, label: String, reading: ManualTable.Source.Reader, scale: Double) -> String {
        "\(physical)|\(label.lowercased())|\(reading.rawValue)|\(scale)"
    }

    static func url(in directory: URL, contentHash: String) -> URL {
        // EF's `OCRCheckpoint.directoryName`, spelled here so the Mac runners need no UIKit.
        directory.appendingPathComponent("_ocr", isDirectory: true)
            .appendingPathComponent("\(contentHash)-tables.json")
    }

    static func load(from directory: URL, contentHash: String) -> PictureTableCheckpoint {
        guard let data = try? Data(contentsOf: url(in: directory, contentHash: contentHash)),
              let checkpoint = try? JSONDecoder().decode(PictureTableCheckpoint.self, from: data),
              checkpoint.contentHash == contentHash else {
            return PictureTableCheckpoint(contentHash: contentHash)
        }
        return checkpoint
    }

    func save(to directory: URL) throws {
        var url = Self.url(in: directory, contentHash: contentHash)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        // EF's `OCRCheckpoint` writes with the app's default class, which is this one; `complete`
        // made every save made while the phone was locked fail (Plan JN P2).
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    static func remove(from directory: URL, contentHash: String) {
        try? FileManager.default.removeItem(at: url(in: directory, contentHash: contentHash))
    }
}

extension PDFTableReader {

    /// The tables of `document`, those printed as pictures included (Plan JN P1): the text layer
    /// read first; then, when it left captions a recogniser could read, those regions recognised
    /// and the document read again with them. With no `pictures`, or nothing to recognise, the
    /// text-layer reading itself.
    static func read(document: PDFDocument, printedLabels: [Int: String] = [:],
                     pictures: PictureTableReading.Context?) async -> Result {
        let first = scan(document: document, printedLabels: printedLabels, pictures: nil)
        guard let pictures, !first.candidates.isEmpty else { return first.result }
        let recognitions = await PictureTableReading.recognise(first.candidates, in: document, context: pictures)
        let inputs = PictureTableReading.Inputs(recognitions: recognitions, reading: pictures.reading, floor: pictures.floor)
        var result = scan(document: document, printedLabels: printedLabels, pictures: inputs).result
        result.checkpointSaveFailures = recognitions.checkpointSaveFailures
        return result
    }
}
