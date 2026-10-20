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

        var extracted: Int { tables.count }
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
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.pagesWithoutText += 1
                continue
            }
            guard text.range(of: "table", options: .caseInsensitive) != nil else { continue }
            let physical = index + 1
            let words = positionedWords(on: page)
            for found in TableExtractor.extractAll(words: words,
                                                   page: ManualTable.Page(physical: physical,
                                                                          printed: printedLabels[physical])) {
                switch found.outcome {
                case .table(let table):
                    pieces.append(table)
                    if !table.continues { result.captioned += 1 }
                case .failed(let failure):
                    result.captioned += 1
                    result.failures[failure, default: 0] += 1
                }
            }
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
