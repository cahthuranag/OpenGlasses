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

        var extracted: Int { tables.count }

        /// What a document stores: the tables read, then the captions that could not be.
        var stored: [ManualTable] { tables + unextracted }
    }

    /// The tables of the PDF at `url`, or nil when it is not a PDF PDFKit can open.
    static func read(url: URL, printedLabels: [Int: String] = [:]) -> Result? {
        guard url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) else { return nil }
        return read(document: document, printedLabels: printedLabels)
    }

    /// `printedLabels` maps a physical page (1-based) to the number printed on it.
    static func read(document: PDFDocument, printedLabels: [Int: String] = [:]) -> Result {
        var result = Result()
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
        for index in 0..<document.pageCount {
            let physical = index + 1
            let waiting = foot
            foot = nil
            guard let page = document.page(at: index) else {
                if let waiting { fail(waiting.caption, waiting.failure, at: waiting.place, listed: false) }
                open = nil
                continue
            }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let waiting { fail(waiting.caption, waiting.failure, at: waiting.place, listed: false) }
                result.pagesWithoutText += 1
                open = nil
                continue
            }
            let carried = open.flatMap { $0.physical == physical - 1 ? $0 : nil }
            guard carried != nil || waiting != nil || text.range(of: "table", options: .caseInsensitive) != nil else {
                open = nil
                continue
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
                    if found.placement == .atFoot {
                        foot = (found.caption, failure, place, words)
                        continue
                    }
                    fail(found.caption, failure, at: place, listed: found.placement == .listed)
                }
            }
            open = next
        }
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
        return result
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
