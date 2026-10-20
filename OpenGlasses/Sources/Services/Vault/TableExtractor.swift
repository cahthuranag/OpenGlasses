import CoreGraphics
import Foundation

/// One word on a page and where it sits, read off the PDF's text layer (Plan JJ P0).
///
/// Used only to find a table's rows and columns, and never stored: the passages a manual is
/// searched by keep the text [[VaultDocumentExtractor]] has always produced.
struct PositionedWord: Equatable {
    var text: String
    /// The word's box in **top-down** page coordinates: the origin is the page's top left and y
    /// grows downwards, so a line lower on the page has a larger `minY`.
    var rect: CGRect
    /// Point size of the word's font.
    var size: Double
    var bold: Bool

    init(_ text: String, rect: CGRect, size: Double, bold: Bool = false) {
        self.text = text
        self.rect = rect
        self.size = size
        self.bold = bold
    }

    /// A word whose box sits at `x`, with its top at `y`, sized as type of `size` points sets it.
    /// What the pure fixtures build words with.
    init(_ text: String, x: Double, y: Double, size: Double = 9, bold: Bool = false, width: Double? = nil) {
        let w = width ?? Double(text.count) * size * 0.55
        self.init(text, rect: CGRect(x: x, y: y, width: w, height: size), size: size, bold: bold)
    }

    /// Set on its side: a box much taller than it is wide for a word of several letters.
    var isRotated: Bool { text.count >= 3 && rect.height > 2 * rect.width }
}

/// A table extracted from an organisation's own loaded manual or code book (Plan JJ P0): its
/// caption, its column headers as paths, its rows by their header paths, every cell's text with a
/// number and a unit where one parses, and the notes printed under it.
///
/// Derived on the phone at import from the PDF the organisation loaded, stored beside the
/// document's passages, and never shipped, exported, packed or linked (decision 1).
struct ManualTable: Codable, Equatable {

    /// A page the table is on: the PDF's own page number and, where the PDF or its header and
    /// footer say, the number printed on it (Plan IN P0).
    struct Page: Codable, Equatable, Hashable {
        var physical: Int
        var printed: String?

        init(physical: Int, printed: String? = nil) {
            self.physical = physical
            self.printed = printed
        }

        /// The number a reader turns to: the printed one when known.
        var spoken: String { printed ?? String(physical) }
    }

    /// A value column. `path` runs from the outermost group heading to the column's own heading
    /// ("Rating group 2", "75"); empty when the table prints no header over it.
    struct Column: Codable, Equatable {
        var path: [String]
        var unit: String?

        init(path: [String], unit: String? = nil) {
            self.path = path
            self.unit = unit
        }

        static let pathSeparator = " › "
        var name: String { path.joined(separator: Self.pathSeparator) }
    }

    struct Cell: Codable, Equatable {
        /// As printed, footnote marker included.
        var text: String
        /// The number the cell carries, when it is one (marker and unit aside).
        var value: Double?
        /// The cell's own unit, else its column's, when the cell is a number.
        var unit: String?
        /// Footnote markers on the cell: "*", "1" for a superscript one, "a" for "(a)".
        var markers: [String]

        init(text: String, value: Double? = nil, unit: String? = nil, markers: [String] = []) {
            self.text = text
            self.value = value
            self.unit = unit
            self.markers = markers
        }

        var isEmpty: Bool { text.isEmpty }
    }

    struct Row: Codable, Equatable {
        /// The row's group heading (when one is printed above it), then its row-header cells.
        var path: [String]
        /// One per value column, in column order; an empty cell where the table prints none.
        var cells: [Cell]
        /// The page this row is printed on — a table continued over pages keeps each row's own.
        var page: Page
    }

    struct Note: Codable, Equatable {
        /// The marker the note is keyed by ("*", "1", "a"), or nil for an unmarked note.
        var marker: String?
        var text: String
    }

    /// "Table 99".
    var label: String
    var title: String
    /// Where the table starts.
    var page: Page
    /// The headings over the row-header columns ("Designation", "Conductors").
    var rowHeaders: [String]
    var columns: [Column]
    var rows: [Row]
    var notes: [Note]
    /// The caption read "(Continued)" and no earlier page of the table was found to join it to.
    var continues: Bool

    init(label: String, title: String, page: Page, rowHeaders: [String] = [], columns: [Column],
         rows: [Row], notes: [Note] = [], continues: Bool = false) {
        self.label = label
        self.title = title
        self.page = page
        self.rowHeaders = rowHeaders
        self.columns = columns
        self.rows = rows
        self.notes = notes
        self.continues = continues
    }

    /// Every page the table is printed on, in order.
    var pages: [Page] {
        var seen: [Page] = [page]
        for row in rows where !seen.contains(row.page) { seen.append(row.page) }
        return seen
    }

    /// "Table 99 (Conductor ratings)", or the label alone.
    var displayName: String { title.isEmpty ? label : "\(label) (\(title))" }
}

/// Reads a captioned table off a page's positioned words (Plan JJ P0). Pure: words and a caption
/// in, a `ManualTable` or the reason there is none out, so every rule is tested without a PDF.
///
/// **How the grid is found.** Words that share a line become a line, and words close enough to be
/// one phrase become a cell. The lines between the caption (and its title) and the first body row
/// are the header: the leading run of bold lines, or, on a page set in one weight, the lines
/// before the first row of numbers. The body is the run of lines under it, ended by
/// a note, a wide gap or a paragraph. Columns are the union of the body cells' horizontal extents,
/// taken over the rows with the most common number of cells, so a column is wherever the body
/// prints something and a gap is wherever it never does. A heading over several columns becomes a
/// level of the column path; a heading printed alone over a run of rows becomes a level of their
/// row path.
///
/// **What is not a table.** Fewer than three body rows, columns that do not come out as many as
/// the rows have cells, or more than a few rows that do not fit the grid, and the page extracts
/// nothing. A wiring diagram with numbers on it is never a table, and a caption over prose is
/// reported, not guessed at.
enum TableExtractor {

    struct Caption: Equatable {
        /// "Table 99" — the same spelling `ManualStructure.caption` gives the chunk's `figure`.
        var label: String
        var title: String
        /// The caption read "(Continued)".
        var continues: Bool
    }

    /// Why a captioned table did not extract. The classes the private measurement counts.
    enum Failure: String, Codable, CaseIterable, Equatable {
        /// The page has no words at all — a scan, or a photographed page.
        case noTextLayer = "no_text_layer"
        /// The caption named was not found on the page.
        case captionNotFound = "caption_not_found"
        /// Fewer than three rows of two or more cells under the caption.
        case tooFewRows = "too_few_rows"
        /// The rows do not agree on how many columns there are.
        case varyingColumnCount = "varying_column_count"
        /// Rows with a cell spanning several columns, more than the tolerance allows.
        case mergedCells = "merged_cells"
        /// The grid failed and the table sets words on their side, most likely its headings.
        case rotatedHeaders = "rotated_headers"
    }

    enum Outcome: Equatable {
        case table(ManualTable)
        case failed(Failure)

        var table: ManualTable? {
            if case .table(let table) = self { return table }
            return nil
        }

        var failure: Failure? {
            if case .failed(let failure) = self { return failure }
            return nil
        }
    }

    /// Fewer body rows than this and there is no grid to trust.
    static let minimumBodyRows = 3
    /// The share of body rows allowed not to fit the grid (a merged cell, two phrases in one
    /// column) before the page is refused.
    static let misfitTolerance = 0.15

    // MARK: - Lines and phrases

    /// Words that share a line, left to right, with the cells they make.
    struct Line: Equatable {
        var words: [PositionedWord]
        var top: Double
        var bottom: Double
        /// The line's dominant point size.
        var size: Double

        var text: String { words.map(\.text).joined(separator: " ") }

        /// Most of the line's letters are set in bold.
        var isBold: Bool {
            let bold = words.filter(\.bold).reduce(0) { $0 + $1.text.count }
            let all = words.reduce(0) { $0 + $1.text.count }
            return all > 0 && bold * 2 > all
        }

        /// A word set smaller than the line and raised above it — or a mark of one or two
        /// characters set that small, whose box PDFKit may report at the line's full height: a
        /// footnote marker.
        func isSuperscript(_ word: PositionedWord) -> Bool {
            guard word.size < 0.8 * size else { return false }
            return Double(word.rect.maxY) < bottom - 0.15 * (bottom - top) || word.text.count <= 2
        }

        /// The line's words joined into cells: words closer than half the type size are one
        /// phrase; a superscript after a phrase is that phrase's marker.
        var phrases: [Phrase] {
            var out: [Phrase] = []
            let gap = max(2, 0.5 * size)
            for word in words.sorted(by: { $0.rect.minX < $1.rect.minX }) {
                if isSuperscript(word) {
                    let marker = TableExtractor.normalisedMarker(word.text)
                    if var last = out.last, Double(word.rect.minX - last.maxX) <= gap * 2 {
                        last.markers.append(marker)
                        last.maxX = max(last.maxX, Double(word.rect.maxX))
                        out[out.count - 1] = last
                    } else {
                        out.append(Phrase(text: "", minX: Double(word.rect.minX), maxX: Double(word.rect.maxX),
                                          markers: [marker], bold: word.bold, leadingMarker: true))
                    }
                    continue
                }
                if var last = out.last, Double(word.rect.minX) - last.maxX <= gap {
                    last.text += last.text.isEmpty ? word.text : " " + word.text
                    last.maxX = max(last.maxX, Double(word.rect.maxX))
                    out[out.count - 1] = last
                } else {
                    out.append(Phrase(text: word.text, minX: Double(word.rect.minX), maxX: Double(word.rect.maxX),
                                      markers: [], bold: word.bold))
                }
            }
            return out
        }
    }

    /// One cell's worth of words on a line.
    struct Phrase: Equatable {
        var text: String
        var minX: Double
        var maxX: Double
        var markers: [String]
        var bold: Bool
        /// The phrase began with a superscript marker ("¹ Applies to …").
        var leadingMarker = false

        var center: Double { (minX + maxX) / 2 }
        /// The text as printed, its superscript markers written after it as superscripts.
        var printed: String {
            let marks = markers.map(TableExtractor.superscripted).joined()
            return leadingMarker ? (marks + (text.isEmpty ? "" : " " + text)) : text + marks
        }
    }

    /// The page's words grouped into lines, top to bottom. Words set on their side are left out
    /// (they are counted by the caller); a superscript joins the line it is raised above.
    static func lines(of words: [PositionedWord]) -> [Line] {
        let upright = words.filter { !$0.text.isEmpty && $0.rect.height > 0 && !$0.isRotated }
        guard !upright.isEmpty else { return [] }
        let sizes = upright.map(\.size).sorted()
        let median = sizes[sizes.count / 2]
        let normal = upright.filter { $0.size >= 0.8 * median }
        let small = upright.filter { $0.size < 0.8 * median }

        var lines: [Line] = []
        for word in normal.sorted(by: { ($0.rect.midY, $0.rect.minX) < ($1.rect.midY, $1.rect.minX) }) {
            let mid = Double(word.rect.midY)
            if var last = lines.last, mid <= last.bottom, mid >= last.top - 0.5 * last.size {
                last.words.append(word)
                last.top = min(last.top, Double(word.rect.minY))
                last.bottom = max(last.bottom, Double(word.rect.maxY))
                lines[lines.count - 1] = last
            } else {
                lines.append(Line(words: [word], top: Double(word.rect.minY), bottom: Double(word.rect.maxY),
                                  size: word.size))
            }
        }
        // Larger first, so a table set smaller than the page's prose forms its lines before the
        // superscripts on it look for one.
        for word in small.sorted(by: { ($1.size, $0.rect.midY) < ($0.size, $1.rect.midY) }) {
            let mid = Double(word.rect.midY)
            if let index = lines.firstIndex(where: { mid >= $0.top - 0.25 * $0.size && mid <= $0.bottom }) {
                lines[index].words.append(word)
            } else {
                lines.append(Line(words: [word], top: Double(word.rect.minY), bottom: Double(word.rect.maxY),
                                  size: word.size))
            }
        }
        lines.sort { $0.top < $1.top }
        for index in lines.indices {
            lines[index].words.sort { $0.rect.minX < $1.rect.minX }
            let weights = lines[index].words.reduce(into: [Double: Int]()) { $0[$1.size, default: 0] += $1.text.count }
            lines[index].size = weights.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? lines[index].size
        }
        return lines
    }

    // MARK: - Captions

    private static let captionPattern = #"^TABLE\s+(\d+)"#
    private static let figurePattern = #"^FIGURE\s+\d+"#
    private static let continuedPattern = #"[\(\[]?\s*\b(?:continued|cont'd|cont\.)\s*[\)\]]?"#

    /// Longest line read as a caption on a page set in one weight.
    static let plainCaptionMaximumWords = 12

    /// The table caption a line carries, starting `TABLE` (any case) and a number.
    ///
    /// Where the page sets anything in bold, the caption must be bold — the rule
    /// `ManualStructure.caption` applies to typed lines, so every caption that names a chunk's
    /// `figure` is a caption here with the same label, and a cross-reference in a sentence is not
    /// bold and is not a caption. A page whose text layer carries no bold at all (a code book set
    /// in one font, with no weight in its text layer) has no bold to read, so there the caption is
    /// the line that begins `Table N` and stands on its own: at most
    /// `plainCaptionMaximumWords` words, with no sentence ended before its last word. The grid that
    /// must follow is what keeps a short line of prose that begins with a table reference from
    /// extracting anything. `ManualStructure.caption` is unchanged: it names passages and decides
    /// which pages open (Plan IV measured it), and a table found here only on a plain page is not
    /// named there.
    static func caption(of line: Line, pageHasBold: Bool = true) -> Caption? {
        guard let first = line.words.first else { return nil }
        let text = line.text
        if pageHasBold {
            guard first.bold else { return nil }
        } else {
            guard standsAlone(text) else { return nil }
        }
        guard let match = text.range(of: captionPattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let head = String(text[match])
        let number = head.range(of: #"\d+"#, options: .regularExpression).map { String(head[$0]) } ?? ""
        var title = String(text[match.upperBound...])
        var continues = false
        if let range = title.range(of: continuedPattern, options: [.regularExpression, .caseInsensitive]) {
            continues = true
            title.removeSubrange(range)
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " \t.:\u{2014}\u{2013}-"))
        return Caption(label: "Table \(number)", title: title, continues: continues)
    }

    /// A short line that is not a sentence: at most `plainCaptionMaximumWords` words, and no full
    /// stop, question or exclamation mark followed by more words.
    private static func standsAlone(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= plainCaptionMaximumWords else { return false }
        return !words.dropLast().contains { word in
            guard let last = word.last, ".!?".contains(last) else { return false }
            // "No." or an abbreviation with a dot inside is not the end of a sentence.
            return word.count > 2 && !word.dropLast().contains(".")
        }
    }

    /// Whether any word on the page is set in bold.
    static func hasBold(_ words: [PositionedWord]) -> Bool { words.contains(where: \.bold) }

    /// Every table caption on a page, top to bottom, with the title read off the next line when
    /// the caption line carries none.
    static func captions(in words: [PositionedWord]) -> [Caption] {
        captionLines(in: lines(of: words), pageHasBold: hasBold(words)).map(\.caption)
    }

    private static func captionLines(in lines: [Line], pageHasBold: Bool)
        -> [(caption: Caption, index: Int, titleLines: Int)] {
        var found: [(Caption, Int, Int)] = []
        for (index, line) in lines.enumerated() {
            guard var caption = caption(of: line, pageHasBold: pageHasBold) else { continue }
            var titleLines = 0
            // A title on the line below is read only where weight says it is one.
            if pageHasBold, caption.title.isEmpty, index + 1 < lines.count {
                let next = lines[index + 1]
                let phrases = next.phrases
                if next.isBold, phrases.count == 1, next.text.count <= 80, Self.caption(of: next) == nil,
                   next.top - line.bottom < 2 * line.size {
                    var title = next.text
                    if let range = title.range(of: continuedPattern, options: [.regularExpression, .caseInsensitive]) {
                        caption.continues = true
                        title.removeSubrange(range)
                    }
                    caption.title = title.trimmingCharacters(in: .whitespaces)
                    titleLines = 1
                }
            }
            found.append((caption, index, titleLines))
        }
        return found
    }

    // MARK: - Extraction

    /// Every captioned table on a page, each with its outcome.
    static func extractAll(words: [PositionedWord], page: ManualTable.Page) -> [(caption: Caption, outcome: Outcome)] {
        let all = lines(of: words)
        let rotated = words.contains(where: \.isRotated)
        let bold = hasBold(words)
        return captionLines(in: all, pageHasBold: bold).map { found in
            (found.caption, extract(lines: all, at: found.index, titleLines: found.titleLines,
                                    caption: found.caption, page: page, hasRotatedWords: rotated,
                                    pageHasBold: bold))
        }
    }

    /// The table `caption` names on this page.
    static func extract(words: [PositionedWord], caption: Caption, page: ManualTable.Page) -> Outcome {
        let all = lines(of: words)
        guard !all.isEmpty else { return .failed(.noTextLayer) }
        let bold = hasBold(words)
        guard let found = captionLines(in: all, pageHasBold: bold).first(where: { $0.caption.label == caption.label }) else {
            return .failed(.captionNotFound)
        }
        return extract(lines: all, at: found.index, titleLines: found.titleLines, caption: found.caption,
                       page: page, hasRotatedWords: words.contains(where: \.isRotated), pageHasBold: bold)
    }

    private static let noteStart = #"^(\*+|\x{2020}|\x{2021}|\([a-z0-9]\)|\d{1,2}[\).]|[\x{00B9}\x{00B2}\x{00B3}\x{2070}-\x{2079}]+|notes?\b)"#

    /// A line that starts a note under the table: a superscript marker first, or one phrase of
    /// text opening with a marker or "Note", or a marker standing apart from the note it keys. A
    /// row of cells is never a note, so a row header "(a)" does not end the body.
    private static func isNoteLine(_ line: Line) -> Bool {
        let phrases = line.phrases
        guard let first = phrases.first else { return false }
        if first.leadingMarker { return true }
        switch phrases.count {
        case 1:
            return first.text.range(of: noteStart, options: [.regularExpression, .caseInsensitive]) != nil
        case 2:
            return first.text.range(of: noteStart + "$", options: [.regularExpression, .caseInsensitive]) != nil
                && phrases[1].text.count >= 15
        default:
            return false
        }
    }

    /// Most header lines a plain page's table is read with before its first row of numbers.
    static let plainHeaderMaximumLines = 4
    /// Most lines a plain page's caption title is read as wrapping onto.
    static let plainTitleMaximumLines = 3

    /// A row of two or more cells whose cells after the first are at least half numbers.
    private static func isNumericRow(_ line: Line) -> Bool {
        let phrases = line.phrases
        guard phrases.count >= 2 else { return false }
        let rest = phrases.dropFirst()
        let numbers = rest.filter { parseCell($0.text, markers: $0.markers, columnUnit: nil).value != nil }.count
        return numbers * 2 >= rest.count
    }

    /// A line of running prose rather than a row: one long phrase, or a sentence.
    private static func isProse(_ line: Line, phrases: [Phrase]) -> Bool {
        guard phrases.count == 1 else { return false }
        let text = line.text
        return text.count >= 60 || (text.hasSuffix(".") && text.split(separator: " ").count >= 8)
    }

    private static func extract(lines all: [Line], at captionIndex: Int, titleLines: Int, caption: Caption,
                                page: ManualTable.Page, hasRotatedWords: Bool, pageHasBold: Bool) -> Outcome {
        // The table's region: under the caption and its title, up to the next caption or the end.
        let start = captionIndex + 1 + titleLines
        var end = all.count
        for index in start..<all.count {
            let line = all[index]
            if Self.caption(of: line, pageHasBold: pageHasBold) != nil
                || ((pageHasBold ? line.words.first?.bold == true : standsAlone(line.text))
                    && line.text.range(of: figurePattern, options: [.regularExpression, .caseInsensitive]) != nil) {
                end = index
                break
            }
        }
        let region = start < end ? Array(all[start..<end]) : []
        func fail(_ failure: Failure) -> Outcome {
            .failed(hasRotatedWords && failure != .tooFewRows ? .rotatedHeaders : failure)
        }
        guard !region.isEmpty else { return .failed(.tooFewRows) }

        // Header: the leading run of bold lines that are not prose. On a page with no bold at all,
        // the lines before the first row whose cells after the first are mostly numbers — after
        // the lines of a long title that wrapped under the caption, which have no weight to tell
        // them apart and read as prose.
        var title = caption.title
        var headerStart = 0
        var headerCount = 0
        func isHeaderLine(_ line: Line) -> Bool {
            !isProse(line, phrases: line.phrases) && !isNoteLine(line)
        }
        if pageHasBold {
            while headerCount < region.count, region[headerCount].isBold, isHeaderLine(region[headerCount]) {
                headerCount += 1
            }
        } else {
            let reach = plainTitleMaximumLines + plainHeaderMaximumLines
            if let firstRow = region.prefix(reach + 1).firstIndex(where: isNumericRow) {
                var previous = captionIndex
                while headerStart < min(firstRow, plainTitleMaximumLines),
                      region[headerStart].phrases.count == 1, !isNoteLine(region[headerStart]),
                      region[headerStart].top - all[previous].bottom < region[headerStart].size {
                    title += (title.isEmpty ? "" : " ") + region[headerStart].text
                    previous = start + headerStart
                    headerStart += 1
                }
                if firstRow - headerStart <= plainHeaderMaximumLines,
                   region[headerStart..<firstRow].allSatisfy(isHeaderLine) {
                    headerCount = firstRow
                } else {
                    headerCount = headerStart
                }
            }
        }
        // A bold run that swallows the whole region is a table with bold rows, not all header.
        if pageHasBold, headerCount >= region.count - 1 { headerCount = min(headerCount, 1) }
        let header = Array(region[headerStart..<max(headerStart, headerCount)])

        // Body: until a note, a paragraph or a wide gap.
        var body: [Line] = []
        var bodyEnd = max(headerStart, headerCount)
        var gaps: [Double] = []
        for index in bodyEnd..<region.count {
            let line = region[index]
            let phrases = line.phrases
            if isNoteLine(line) || isProse(line, phrases: phrases) { break }
            if let previous = body.last ?? header.last {
                let gap = line.top - previous.bottom
                let typical = gaps.isEmpty ? line.size : gaps.sorted()[gaps.count / 2]
                if gap > max(3 * typical, 1.5 * line.size) { break }
                gaps.append(max(gap, 0))
            }
            body.append(line)
            bodyEnd = index + 1
        }

        let multi = body.filter { $0.phrases.count >= 2 }
        guard multi.count >= minimumBodyRows else { return .failed(.tooFewRows) }

        // Columns: where the rows with the most common cell count print something.
        let counts = multi.map { $0.phrases.count }
        let histogram = counts.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        guard let modal = histogram.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else {
            return fail(.varyingColumnCount)
        }
        let modalRows = multi.filter { $0.phrases.count == modal }
        guard modalRows.count >= 2, Double(modalRows.count) >= 0.5 * Double(multi.count) else {
            return fail(.varyingColumnCount)
        }
        let segments = unionSegments(modalRows.flatMap { $0.phrases.map { ($0.minX, $0.maxX) } })
        guard segments.count == modal else { return fail(.varyingColumnCount) }

        // Every body row onto the grid.
        var misfits = 0
        var merged = 0
        var placed: [(line: Line, cells: [Phrase?])] = []
        for line in body {
            let phrases = line.phrases
            var cells = [Phrase?](repeating: nil, count: segments.count)
            var fits = true
            var spans = false
            for phrase in phrases {
                let covered = segments.indices.filter { overlap(phrase, segments[$0]) > 0 }
                let column: Int
                if covered.count > 1 {
                    spans = true
                    fits = false
                    column = covered[0]
                } else if let only = covered.first {
                    column = only
                } else {
                    column = nearest(phrase.center, segments)
                }
                if cells[column] != nil { fits = false; cells[column]?.text += " " + phrase.text }
                else { cells[column] = phrase }
            }
            if phrases.count >= 2, !fits {
                misfits += 1
                if spans { merged += 1 }
            }
            placed.append((line, cells))
        }
        if Double(misfits) > misfitTolerance * Double(multi.count) {
            return fail(merged * 2 >= misfits ? .mergedCells : .varyingColumnCount)
        }

        // Row-header columns: the first, and any after it that never hold a number.
        func isNumeric(_ phrase: Phrase?) -> Bool {
            guard let phrase else { return false }
            return parseCell(phrase.text, markers: phrase.markers, columnUnit: nil).value != nil
        }
        var stubs = 1
        while stubs < segments.count - 1 {
            let column = placed.compactMap { $0.cells[stubs] }
            guard !column.isEmpty, !placed.contains(where: { isNumeric($0.cells[stubs]) }) else { break }
            stubs += 1
        }

        // Column paths from the header lines.
        let paths = columnPaths(header: header, segments: segments)
        let columns = (stubs..<segments.count).map { index -> ManualTable.Column in
            ManualTable.Column(path: paths[index], unit: unit(in: paths[index]))
        }
        let rowHeaders = (0..<stubs).map { paths[$0].joined(separator: " ") }

        // Rows.
        var rows: [ManualTable.Row] = []
        var group: String?
        var previousStubs: [String] = []
        var previousLine: Line?
        for (line, cells) in placed {
            let filled = cells.compactMap { $0 }
            if filled.count == 1, let only = cells.firstIndex(where: { $0 != nil }), only < stubs {
                let text = cells[only]!.printed
                // A short line under a row, close to it and not bold, is that row's header
                // wrapping onto a second line; anything else alone at the left heads a group.
                if !line.isBold, let previous = previousLine, let last = rows.indices.last,
                   line.top - previous.bottom < 0.4 * line.size, !rows[last].path.isEmpty, !previousStubs.isEmpty {
                    rows[last].path[rows[last].path.count - 1] += " " + text
                    previousStubs[previousStubs.count - 1] += " " + text
                } else {
                    group = text
                    previousStubs = []
                }
                previousLine = line
                continue
            }
            var stubTexts = (0..<stubs).map { cells[$0]?.printed ?? "" }
            // A row header printed once for the rows under it: carry it down to the rows that
            // leave it blank.
            if let firstFilled = stubTexts.firstIndex(where: { !$0.isEmpty }) {
                for index in 0..<firstFilled where index < previousStubs.count { stubTexts[index] = previousStubs[index] }
            } else {
                stubTexts = previousStubs.count == stubs ? previousStubs : stubTexts
            }
            let values = (stubs..<segments.count).map { index -> ManualTable.Cell in
                guard let phrase = cells[index] else { return ManualTable.Cell(text: "") }
                return parseCell(phrase.text, markers: phrase.markers, columnUnit: columns[index - stubs].unit)
            }
            let path = (group.map { [$0] } ?? []) + stubTexts.filter { !$0.isEmpty }
            rows.append(ManualTable.Row(path: path, cells: values, page: page))
            previousStubs = stubTexts
            previousLine = line
        }

        // Notes: marked lines under the body, each with its wrapped lines.
        var notes: [ManualTable.Note] = []
        var lastNoteLine: Line?
        for line in region[bodyEnd...] {
            if isNoteLine(line) {
                notes.append(note(from: line))
                lastNoteLine = line
            } else if let previous = lastNoteLine, !notes.isEmpty, line.top - previous.bottom < 0.8 * line.size {
                notes[notes.count - 1].text += " " + line.text
                lastNoteLine = line
            } else {
                break
            }
        }
        notes.removeAll { $0.text.isEmpty }

        return .table(ManualTable(label: caption.label, title: title, page: page, rowHeaders: rowHeaders,
                                  columns: columns, rows: rows, notes: notes, continues: caption.continues))
    }

    // MARK: - Geometry

    /// Merge overlapping horizontal extents into the columns they make, left to right.
    static func unionSegments(_ intervals: [(Double, Double)]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for (low, high) in intervals.sorted(by: { $0.0 < $1.0 }) {
            if let last = out.last, low <= last.1 + 0.5 {
                out[out.count - 1].1 = max(last.1, high)
            } else {
                out.append((low, high))
            }
        }
        return out
    }

    private static func overlap(_ phrase: Phrase, _ segment: (Double, Double)) -> Double {
        min(phrase.maxX, segment.1) - max(phrase.minX, segment.0)
    }

    private static func nearest(_ x: Double, _ segments: [(Double, Double)]) -> Int {
        segments.indices.min { abs((segments[$0].0 + segments[$0].1) / 2 - x) < abs((segments[$1].0 + segments[$1].1) / 2 - x) } ?? 0
    }

    /// Each column's header path, outermost first. A header phrase reaches the columns whose
    /// centres fall in its region — its own extent, widened symmetrically about its centre to the
    /// midpoint with its neighbours — so a group heading centred over three columns heads all
    /// three. Stacked phrases over the same columns are one heading wrapped onto two lines and are
    /// joined; a phrase over more columns than the one below it is a level of the path.
    static func columnPaths(header: [Line], segments: [(Double, Double)]) -> [[String]] {
        let centers = segments.map { ($0.0 + $0.1) / 2 }
        let gaps = zip(segments, segments.dropFirst()).map { $1.0 - $0.1 }.sorted()
        let gap = gaps.isEmpty ? 0 : gaps[gaps.count / 2]
        var paths = [[(text: String, columns: Set<Int>)]](repeating: [], count: segments.count)
        for line in header {
            let phrases = line.phrases.filter { !$0.text.isEmpty }
            var coverage: [Set<Int>] = []
            for (index, phrase) in phrases.enumerated() {
                let leftMid = index > 0 ? (phrases[index - 1].maxX + phrase.minX) / 2 : nil
                let rightMid = index + 1 < phrases.count ? (phrase.maxX + phrases[index + 1].minX) / 2 : nil
                var low: Double
                var high: Double
                switch (leftMid, rightMid) {
                case let (l?, r?): low = l; high = r
                case let (nil, r?): high = r; low = min(phrase.minX, phrase.center - (r - phrase.center))
                case let (l?, nil): low = l; high = max(phrase.maxX, phrase.center + (phrase.center - l))
                case (nil, nil): low = phrase.minX - gap; high = phrase.maxX + gap
                }
                var covered = Set(centers.indices.filter { centers[$0] >= low && centers[$0] <= high })
                covered.formUnion(segments.indices.filter { min(phrase.maxX, segments[$0].1) - max(phrase.minX, segments[$0].0) > 0 })
                coverage.append(covered)
            }
            for column in segments.indices {
                let owners = phrases.indices.filter { coverage[$0].contains(column) }
                guard let owner = owners.min(by: { abs(phrases[$0].center - centers[column]) < abs(phrases[$1].center - centers[column]) })
                else { continue }
                let text = phrases[owner].printed
                if let last = paths[column].last, last.columns == coverage[owner] {
                    paths[column][paths[column].count - 1].text += " " + text
                } else {
                    paths[column].append((text, coverage[owner]))
                }
            }
        }
        return paths.map { $0.map(\.text) }
    }

    // MARK: - Cells

    private static let superscriptDigits: [Character: Character] = [
        "\u{2070}": "0", "\u{00B9}": "1", "\u{00B2}": "2", "\u{00B3}": "3", "\u{2074}": "4",
        "\u{2075}": "5", "\u{2076}": "6", "\u{2077}": "7", "\u{2078}": "8", "\u{2079}": "9",
    ]

    /// A digit marker written back as the superscript it was printed as; anything else as is.
    static func superscripted(_ marker: String) -> String {
        guard marker.allSatisfy(\.isASCII), marker.allSatisfy(\.isNumber) else { return marker }
        let inverse = Dictionary(uniqueKeysWithValues: superscriptDigits.map { ($1, $0) })
        return String(marker.map { inverse[$0] ?? $0 })
    }

    /// A marker as notes and cells compare it: superscript digits as plain digits, "(a)" as "a",
    /// "1)" as "1".
    static func normalisedMarker(_ raw: String) -> String {
        let mapped = String(raw.map { superscriptDigits[$0] ?? $0 })
        return mapped.trimmingCharacters(in: CharacterSet(charactersIn: "()[]. :"))
    }

    private static let numberPattern =
        #"^([-+\x{2212}]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:[.,]\d+)?|[-+\x{2212}]?[.,]\d+)\s*([A-Za-z\x{00B5}\x{03A9}\x{00B0}%\x{00B2}\x{00B3}/]{1,8})?$"#

    /// The unit a header path names in brackets at its end, innermost heading first: "(A)",
    /// "[mm²]", "(°C)".
    static func unit(in path: [String]) -> String? {
        for heading in path.reversed() {
            guard let range = heading.range(of: #"[\(\[]\s*([^()\[\]]{1,10}?)\s*[\)\]]\s*$"#, options: .regularExpression)
            else { continue }
            let unit = heading[range].trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
            if unit.contains(where: { $0.isLetter || "%\u{00B0}\u{00B5}\u{03A9}".contains($0) }),
               !unit.contains(" ") {
                return unit
            }
        }
        return nil
    }

    /// A cell's number, unit and markers. Trailing markers — asterisks, daggers, superscript
    /// digits after a number, "(a)" — are taken off before the number is read; the text keeps
    /// them, as printed. A unit is the cell's own ("30 A") or, for a number, its column's.
    static func parseCell(_ raw: String, markers given: [String], columnUnit: String?) -> ManualTable.Cell {
        let printed = (raw + given.map(superscripted).joined()).trimmingCharacters(in: .whitespaces)
        var body = raw.trimmingCharacters(in: .whitespaces)
        var markers = given
        var trailing: [String] = []
        while true {
            if let range = body.range(of: #"(\*+|\x{2020}|\x{2021})$"#, options: .regularExpression) {
                trailing.insert(String(body[range]), at: 0)
                body.removeSubrange(range)
            } else if let range = body.range(of: #"(?<=[\d)])[\x{00B9}\x{00B2}\x{00B3}\x{2070}-\x{2079}]+$"#,
                                             options: .regularExpression) {
                trailing.insert(normalisedMarker(String(body[range])), at: 0)
                body.removeSubrange(range)
            } else if let range = body.range(of: #"\s*\([a-z]\)$"#, options: .regularExpression),
                      body[..<range.lowerBound].last?.isNumber == true {
                trailing.insert(normalisedMarker(String(body[range]).trimmingCharacters(in: .whitespaces)), at: 0)
                body.removeSubrange(range)
            } else {
                break
            }
            body = body.trimmingCharacters(in: .whitespaces)
        }
        markers = trailing + markers
        guard let regex = try? NSRegularExpression(pattern: numberPattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let numberRange = Range(match.range(at: 1), in: body) else {
            return ManualTable.Cell(text: printed, markers: markers)
        }
        var number = String(body[numberRange]).replacingOccurrences(of: "\u{2212}", with: "-")
        if number.range(of: #"\d,\d{3}(,|$|\.)"#, options: .regularExpression) != nil {
            number = number.replacingOccurrences(of: ",", with: "")
        } else {
            number = number.replacingOccurrences(of: ",", with: ".")
        }
        let own = Range(match.range(at: 2), in: body).map { String(body[$0]) }
        return ManualTable.Cell(text: printed, value: Double(number), unit: own ?? columnUnit, markers: markers)
    }

    private static func note(from line: Line) -> ManualTable.Note {
        let phrases = line.phrases
        guard let first = phrases.first else { return ManualTable.Note(marker: nil, text: line.text) }
        if first.leadingMarker {
            let rest = ([first.text] + phrases.dropFirst().map(\.printed)).filter { !$0.isEmpty }.joined(separator: " ")
            return ManualTable.Note(marker: first.markers.first, text: rest)
        }
        let text = phrases.map(\.printed).joined(separator: " ")
        guard let range = text.range(of: noteStart, options: [.regularExpression, .caseInsensitive]) else {
            return ManualTable.Note(marker: nil, text: text)
        }
        let token = String(text[range])
        var rest = String(String(text[range.upperBound...]).drop { " :.-\u{2014}\u{2013}".contains($0) })
        if token.lowercased().hasPrefix("note") {
            // "Note 2: …" keys the note by its number; "Notes:" alone is a heading over the notes.
            if let number = rest.range(of: #"^\d+[\).:]?\s*"#, options: .regularExpression) {
                let marker = normalisedMarker(String(rest[number]))
                rest.removeSubrange(number)
                return ManualTable.Note(marker: marker, text: rest)
            }
            return ManualTable.Note(marker: nil, text: rest)
        }
        return ManualTable.Note(marker: normalisedMarker(token), text: rest)
    }

    // MARK: - Continued tables

    /// Join each continued piece onto the table it continues: the previous page's table of the
    /// same label, keeping that table's headers and each row's own page. A continuation with no
    /// start before it stays its own table, marked as continuing.
    static func merge(_ tables: [ManualTable]) -> [ManualTable] {
        var out: [ManualTable] = []
        for piece in tables {
            if piece.continues, let index = out.lastIndex(where: { $0.label == piece.label }),
               let lastPage = out[index].pages.last, piece.page.physical == lastPage.physical + 1,
               out[index].columns.count == piece.columns.count {
                out[index].rows.append(contentsOf: piece.rows)
                for note in piece.notes where !out[index].notes.contains(note) { out[index].notes.append(note) }
                continue
            }
            out.append(piece)
        }
        return out
    }
}
