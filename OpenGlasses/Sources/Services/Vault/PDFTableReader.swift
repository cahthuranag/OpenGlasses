import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Reads the captioned tables out of a PDF's text layer (Plan JJ P0): each page's words with their
/// boxes, handed to the pure [[TableExtractor]], and continued tables joined across pages.
///
/// Positions are read only for a page whose text mentions a table at all — reading a box for every
/// word of a thousand-page book to find forty tables would cost the import far more than the
/// tables are worth — and they are dropped as soon as the page's tables are out. Nothing here
/// changes the text a manual is chunked and searched by.
///
/// Builds on macOS too, so the private measurement runner reads a PDF exactly as the phone does.
enum PDFTableReader {

    /// What one PDF's tables came out as.
    struct Result: Equatable {
        var tables: [ManualTable] = []
        /// Table captions found. A "(Continued)" caption that joined the table it continues is not
        /// counted again; one that did not join (or did not extract) is.
        var captioned = 0
        /// Captions whose page did not resolve to a grid, by why.
        var failures: [TableExtractor.Failure: Int] = [:]
        /// Pages with no text layer, where no caption can be read at all.
        var pagesWithoutText = 0
        /// Captions whose page did not resolve to a grid, each kept by its label, title, page and
        /// failure (Plan JJ P1), so a lookup can name the page of a table it cannot read.
        var unextracted: [ManualTable] = []
        /// Lines that read as a caption and are an entry in a list of tables, left out because the
        /// document captions the same label elsewhere (Plan JJ P5). Not counted in `captioned`.
        var listedEntries = 0
        /// Tables read from a picture of them (Plan JN P1), by `pictureReader`.
        var recognised = 0
        /// Tables read from a picture whose cells were mostly unclear, kept as unread
        /// (`unclear_in_picture`).
        var unclearInPicture = 0
        /// The cells, row keys and column headings of the tables read from a picture that were
        /// marked uncertain.
        var uncertainCells = 0
        var uncertainKeys = 0
        var uncertainColumns = 0
        /// The reading the pictures went through, when any was recognised.
        var pictureReader: ManualTable.Source.Reader?
        /// Recognised regions whose checkpoint could not be saved (Plan JN P2): the import carries
        /// on, and a relaunch would recognise them again. Counted, never silent.
        var checkpointSaveFailures = 0
        /// Continuing captions with no grid of their own ("(Concluded)" over the table's notes)
        /// joined to the table they carry on, or left out because that table's own caption was
        /// kept unread (Plan JW P0). Not counted in `captioned`, never a failure.
        var concludingPieces = 0

        var extracted: Int { tables.count }

        /// What a document stores: the tables read, then the captions that could not be.
        var stored: [ManualTable] { tables + unextracted }
    }

    /// The tables of the PDF at `url`, or nil when it is not a PDF PDFKit can open.
    static func read(url: URL, printedLabels: [Int: String] = [:]) -> Result? {
        guard url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) else { return nil }
        return read(document: document, printedLabels: printedLabels)
    }

    /// `printedLabels` maps a physical page (1-based) to the number printed on it. The text layer
    /// only: exactly what every import read before Plan JN.
    static func read(document: PDFDocument, printedLabels: [Int: String] = [:]) -> Result {
        scan(document: document, printedLabels: printedLabels, pictures: nil).result
    }

    /// One reading of the document. With `pictures` (Plan JN P1), a caption whose grid the text
    /// layer does not give, and a caption on a page with no text layer, is read from the
    /// recognition of the picture under it when one was made; without, this is the text-layer
    /// reading unchanged. Either way the captions a recogniser could read are returned, for
    /// `PictureTableReading` to recognise before a second reading.
    static func scan(document: PDFDocument, printedLabels: [Int: String] = [:],
                     pictures: PictureTableReading.Inputs?) -> (result: Result, candidates: [PictureTableReading.Candidate]) {
        var result = Result()
        var candidates: [PictureTableReading.Candidate] = []
        var pieces: [ManualTable] = []
        // The table the next page may carry on with no caption of its own (Plan JJ P5): which
        // piece, the grid it was read onto, and the page it was last read on.
        var open: (piece: Int, grid: TableExtractor.Grid, physical: Int)?
        // A caption at the foot of a page whose rows may start on the next (Plan JJ P5).
        var foot: (caption: TableExtractor.Caption, failure: TableExtractor.Failure, place: ManualTable.Page,
                   words: [PositionedWord])?
        // Captions that read nothing, each with whether it is an entry in a list of tables.
        var failed: [(table: ManualTable, listed: Bool)] = []
        func fail(_ caption: TableExtractor.Caption, _ failure: TableExtractor.Failure, at place: ManualTable.Page, listed: Bool) {
            failed.append((.unextracted(caption, page: place, failure: failure), listed))
        }
        func scanPage(_ index: Int) {
            let physical = index + 1
            let waiting = foot
            foot = nil
            guard let page = document.page(at: index) else {
                if let waiting { fail(waiting.caption, waiting.failure, at: waiting.place, listed: false) }
                open = nil
                return
            }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let waiting { fail(waiting.caption, waiting.failure, at: waiting.place, listed: false) }
                result.pagesWithoutText += 1
                open = nil
                // A page with no text layer (Plan JN P1): its own recognition says whether it
                // captions a table, and each caption's region is read as a picture.
                let bounds = page.bounds(for: .mediaBox)
                candidates.append(.init(physical: physical, kind: .page,
                                        region: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)))
                guard let pictures, let scanned = pictures.recognitions.pages[physical] else { return }
                let place = ManualTable.Page(physical: physical, printed: printedLabels[physical])
                for found in PictureTableReading.captionRegions(onScannedPage: scanned.words, pageBounds: bounds) {
                    guard let recognition = pictures.recognitions.regions[.init(physical: physical, label: found.caption.label)]
                    else { continue }
                    let read = PictureTableReading.read(recognition, captionWords: found.captionWords,
                                                        caption: found.caption, page: place, inputs: pictures)
                    if var table = read.outcome.table {
                        table.pictureAreas = [.init(physical: physical, rect: found.region)]
                        pieces.append(table)
                        if !table.continues { result.captioned += 1 }
                        count(read, into: &result)
                        open = read.grid.map { (pieces.count - 1, $0, physical) }
                    } else {
                        if read.outcome.failure == .unclearInPicture { count(read, into: &result) }
                        fail(found.caption, read.outcome.failure == .unclearInPicture ? .unclearInPicture : .noTextLayer,
                             at: place, listed: false)
                    }
                }
                return
            }
            let carried = open.flatMap { $0.physical == physical - 1 ? $0 : nil }
            guard carried != nil || waiting != nil || text.range(of: "table", options: .caseInsensitive) != nil else {
                open = nil
                return
            }
            let place = ManualTable.Page(physical: physical, printed: printedLabels[physical])
            let words = positionedWords(on: page)
            var next: (piece: Int, grid: TableExtractor.Grid, physical: Int)?
            func carry(_ more: (rows: [ManualTable.Row], notes: [ManualTable.Note], grid: TableExtractor.Grid), into piece: Int) {
                pieces[piece].rows += more.rows
                for note in more.notes where !pieces[piece].notes.contains(note) { pieces[piece].notes.append(note) }
                next = (piece, more.grid, physical)
            }
            if let waiting {
                if let started = TableExtractor.startingOnNextPage(words: waiting.words, caption: waiting.caption,
                                                                   page: waiting.place, next: words, nextPage: place) {
                    pieces.append(started.table)
                    if !started.table.continues { result.captioned += 1 }
                    next = started.grid.map { (pieces.count - 1, $0, physical) }
                } else {
                    fail(waiting.caption, waiting.failure, at: waiting.place, listed: false)
                }
            } else if let carried, carried.grid.runsToFoot,
                      let more = TableExtractor.continuation(words: words, page: place, grid: carried.grid) {
                carry(more, into: carried.piece)
            }
            for found in TableExtractor.extractGrids(words: words, page: place) {
                switch found.outcome {
                case .table(let table):
                    pieces.append(table)
                    if !table.continues { result.captioned += 1 }
                    next = found.grid.map { (pieces.count - 1, $0, physical) }
                case .failed(let failure):
                    // A "(Continued)" caption whose page does not read on its own: its rows on the
                    // grid of the page before, when they sit on it.
                    if found.caption.continues, let carried,
                       pieces[carried.piece].label.caseInsensitiveCompare(found.caption.label) == .orderedSame,
                       let more = TableExtractor.continuation(words: words, page: place, grid: carried.grid,
                                                              under: found.caption) {
                        carry(more, into: carried.piece)
                        continue
                    }
                    // A grid the text layer does not give, printed as a picture under the caption
                    // (Plan JN P1): read from its recognition, which must pass the extractor's own
                    // tests. A picture that makes no table leaves the caption's own failure.
                    if found.placement != .listed,
                       let region = PictureTableReading.region(for: found.caption, failure: failure, words: words,
                                                               pageBounds: page.bounds(for: .mediaBox)) {
                        candidates.append(.init(physical: physical, kind: .caption(found.caption), region: region))
                        if let pictures,
                           let recognition = pictures.recognitions.regions[.init(physical: physical, label: found.caption.label)] {
                            let read = PictureTableReading.read(
                                recognition, captionWords: PictureTableReading.captionWords(of: found.caption, in: words),
                                caption: found.caption, page: place, inputs: pictures)
                            if var table = read.outcome.table {
                                // Where it was read from, for "show me the table" to outline
                                // (Plan JN P2).
                                table.pictureAreas = [.init(physical: physical, rect: region)]
                                pieces.append(table)
                                if !table.continues { result.captioned += 1 }
                                count(read, into: &result)
                                next = read.grid.map { (pieces.count - 1, $0, physical) }
                                continue
                            }
                            if read.outcome.failure == .unclearInPicture {
                                count(read, into: &result)
                                fail(found.caption, .unclearInPicture, at: place, listed: false)
                                continue
                            }
                        }
                    }
                    // A continuing caption with no grid under it (too few rows, or no text where
                    // one would be) — most often a "(Concluded)" page that carries only the
                    // table's notes (Plan JW P0) — never stands in for the table it concludes:
                    // where that table was read, the piece joins it (its notes with the table's,
                    // within two pages), and where it was captioned and not read, the table's own
                    // caption keeps pointing at its page. Neither is a table of its own nor a
                    // failure. Read after the picture under it, which may print the rows.
                    if found.caption.continues, failure == .tooFewRows || failure == .noTextInTable {
                        if let index = pieces.lastIndex(where: {
                            $0.label.caseInsensitiveCompare(found.caption.label) == .orderedSame
                        }) {
                            if let last = pieces[index].pages.last?.physical, physical - last <= 2 {
                                for note in TableExtractor.notes(under: found.caption, words: words)
                                where !pieces[index].notes.contains(note) {
                                    pieces[index].notes.append(note)
                                }
                            }
                            result.concludingPieces += 1
                            continue
                        }
                        if failed.contains(where: {
                            !$0.listed && $0.table.label.caseInsensitiveCompare(found.caption.label) == .orderedSame
                        }) {
                            result.concludingPieces += 1
                            continue
                        }
                    }
                    if found.placement == .atFoot {
                        foot = (found.caption, failure, place, words)
                        continue
                    }
                    fail(found.caption, failure, at: place, listed: found.placement == .listed)
                }
            }
            open = next
        }
        // PDFKit selections and attributed strings must drain per page on long books.
        for index in 0..<document.pageCount { autoreleasepool { scanPage(index) } }
        if let waiting = foot { fail(waiting.caption, waiting.failure, at: waiting.place, listed: false) }

        // An entry in a list of tables is not a table: dropped where the document captions the
        // same label anywhere else, and kept, pointing at the list, where it does not.
        let elsewhere = Set(pieces.map { $0.label.lowercased() } + failed.filter { !$0.listed }.map { $0.table.label.lowercased() })
        for entry in failed {
            if entry.listed, elsewhere.contains(entry.table.label.lowercased()) {
                result.listedEntries += 1
                continue
            }
            result.captioned += 1
            if let failure = entry.table.failure { result.failures[failure, default: 0] += 1 }
            result.unextracted.append(entry.table)
        }
        result.tables = TableExtractor.merge(pieces)
        // A continuation whose start did not extract is still a table someone captioned.
        result.captioned += result.tables.filter(\.continues).count
        if pictures != nil, result.recognised + result.unclearInPicture > 0 { result.pictureReader = pictures?.reading }
        return (result, candidates)
    }

    /// A picture's reading, in the result's counts (Plan JN P1).
    private static func count(_ read: PictureTableReading.Read, into result: inout Result) {
        if read.outcome.table != nil { result.recognised += 1 } else { result.unclearInPicture += 1 }
        result.uncertainCells += read.assessment.uncertain
        result.uncertainKeys += read.assessment.uncertainKeys
        result.uncertainColumns += read.assessment.uncertainColumns
    }

    // MARK: - Words with their boxes

    /// The page's words, each with its box in top-down page coordinates and the size and weight
    /// of its type. A run of letters is split where the type size changes, so a superscript
    /// footnote marker printed against a number ("45" and a raised "1") stays apart from it.
    static func positionedWords(on page: PDFPage) -> [PositionedWord] {
        guard let string = page.string, !string.isEmpty else { return [] }
        let ns = string as NSString
        let attributed = page.attributedString
        let bounds = page.bounds(for: .mediaBox)
        var words: [PositionedWord] = []
        guard let regex = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        for match in regex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            for piece in splitBySize(match.range, in: attributed) {
                guard let selection = page.selection(for: piece.range) else { continue }
                let box = selection.bounds(for: page)
                guard box.width > 0 || box.height > 0 else { continue }
                // PDF space has its origin at the bottom left; the extractor reads top-down.
                let rect = CGRect(x: box.minX - bounds.minX, y: bounds.maxY - box.maxY,
                                  width: box.width, height: box.height)
                words.append(PositionedWord(ns.substring(with: piece.range), rect: rect,
                                            size: piece.size, bold: piece.bold))
            }
        }
        return words
    }

    /// A word's character range cut where its font size changes, each piece with its size and
    /// weight. Without an attributed string the word is one piece at a nominal size.
    private static func splitBySize(_ range: NSRange, in attributed: NSAttributedString?)
        -> [(range: NSRange, size: Double, bold: Bool)] {
        guard let attributed, NSMaxRange(range) <= attributed.length else { return [(range, 10, false)] }
        var pieces: [(range: NSRange, size: Double, bold: Bool)] = []
        attributed.enumerateAttribute(.font, in: range) { value, run, _ in
            let (size, bold) = fontTraits(value)
            if let last = pieces.last, abs(last.size - size) < 0.5 {
                pieces[pieces.count - 1].range.length += run.length
                pieces[pieces.count - 1].bold = last.bold || bold
            } else {
                pieces.append((run, size, bold))
            }
        }
        return pieces.isEmpty ? [(range, 10, false)] : pieces
    }

    private static func fontTraits(_ value: Any?) -> (size: Double, bold: Bool) {
        #if canImport(UIKit)
        guard let font = value as? UIFont else { return (10, false) }
        return (Double(font.pointSize), ManualStructure.isBold(font))
        #else
        guard let font = value as? NSFont else { return (10, false) }
        if font.fontDescriptor.symbolicTraits.contains(.bold) { return (Double(font.pointSize), true) }
        let name = font.fontName.lowercased()
        return (Double(font.pointSize), ["bold", "black", "heavy", "semibold", "-bd"].contains { name.contains($0) })
        #endif
    }
}
