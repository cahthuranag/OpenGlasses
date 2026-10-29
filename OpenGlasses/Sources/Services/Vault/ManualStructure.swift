import Foundation
import PDFKit
import UIKit

/// Reads a manual's structure off its **type** rather than out of its words, and writes it back as
/// the small Markdown-flavoured grammar [[DocumentChunker]] reads.
///
/// The lexical rules (Plan EJ) went as far as letters can go and stopped at a wall: on a real OEM
/// furnace manual the section headings are bold at body size and mixed case — `Turning Off Gas to
/// Unit`, `Pressure Switches (Two)` — which no rule over the text of a line can tell from the
/// sentence next to it, while an ALL-CAPS wiring-diagram fragment (`1- DATA LOW CONNECTION`) is
/// shaped exactly like a real ALL-CAPS heading. Type carries the difference: a heading is bold and
/// at least body size, a caption is bold and starts `FIGURE 58`, and a drawing is a page of labels
/// set below body size with no sentences in it.
///
/// Everything here is pure over `TypedLine`/`TypedPage`, so the rules are tested without a PDF, and
/// `Scripts/extract-manual-text.swift` carries a faithful copy (self-checked over the same cases)
/// so a manual extracted on a Mac and one imported on the phone reach the chunker looking alike.
enum ManualStructure {

    /// One line of a page with the type it was set in. `size` is 0 when the line carried no font
    /// information at all, which never reads as a heading.
    struct TypedLine: Equatable {
        /// The line exactly as it came off the page; what is written back when it is not grammar.
        let raw: String
        /// `raw`, trimmed — what the rules read.
        let text: String
        /// Dominant point size, by printable characters.
        let size: Double
        /// Whether the dominant run is bold.
        let bold: Bool

        init(raw: String, text: String? = nil, size: Double, bold: Bool) {
            self.raw = raw
            self.text = text ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
            self.size = size
            self.bold = bold
        }
    }

    /// A page's lines plus the character histogram the body-size and diagram rules need.
    struct TypedPage: Equatable {
        let lines: [TypedLine]
        /// Printable characters by rounded point size.
        let sizes: [Int: Int]

        init(lines: [TypedLine], sizes: [Int: Int]? = nil) {
            self.lines = lines
            self.sizes = sizes ?? lines.reduce(into: [Int: Int]()) { histogram, line in
                histogram[Int(line.size.rounded()), default: 0] += line.text.filter { !$0.isWhitespace }.count
            }
        }
    }

    /// What a structured page came out as.
    struct RenderedPage: Equatable {
        let text: String
        let headings: Int
        let isDiagram: Bool
    }

    /// The comment the chunker reads as "this page is a drawing".
    static let diagramMarker = "<!-- page: diagram -->"

    /// Words an OEM manual prints in bold that are labels rather than places. Same set as
    /// [[DocumentChunker]]'s lexical screen, so the two halves agree on what is furniture.
    ///
    /// `NOTICE` earns its place from the field: it is the one safety banner these manuals set on a
    /// line of its own, so it clears every shape rule and stands alone, and without it a page's
    /// prose is filed under a section called "NOTICE".
    private static let labelWords = "FIGURE|TABLE|NOTE|NOTES|NOTICE|WARNING|CAUTION|DANGER|IMPORTANT"

    /// A numbered line that is a list step or a spec-table row rather than a heading; the separator
    /// after the number is what tells them apart. Same set as [[DocumentChunker]]'s.
    private static let numberedNonHeading = [
        #"^\d+(\.\d+)*\s+[-\u{2013}\u{2014}]\s"#,   // 4 - Go to setup / system devices
        #"^\d+(\.\d+)*\s*\)"#,                     // 1) Remove the burner box cover
        #"^\d+(\.\d+)*\.?\s+\p{Ll}"#                // 2.6 or greater
    ]

    // MARK: - The rules

    /// The document-wide body size: the character-weighted modal point size, rounded to whole
    /// points. Document-wide and not per page on purpose — a diagram page's own mode is its labels,
    /// so a page cannot decide for itself what "small" means.
    static func bodySize(of pages: [TypedPage]) -> Int {
        var merged: [Int: Int] = [:]
        for page in pages { for (size, count) in page.sizes { merged[size, default: 0] += count } }
        guard let best = merged.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else { return 0 }
        return best
    }

    /// Whether a line has the *shape* of a section heading: bold, at least body size, short enough
    /// to say aloud in a citation, and none of the things a manual sets in bold that are not places
    /// — a caption or safety label, a sentence, a bare callout number, the publisher's page header,
    /// or the middle of a paragraph that happens to be bold.
    ///
    /// Shape only. Whether it *stands alone* is `standsAlone(at:in:bodySize:)`, which needs its
    /// neighbours.
    static func isHeading(_ line: TypedLine, bodySize: Int) -> Bool {
        let text = line.text
        // A script without case (Plan JY P4) has no capital to open a heading with, and its
        // headings are often set larger rather than bolder: such a line may be one by its size.
        let caseless = isCaseless(text)
        guard line.bold || (caseless && line.size >= Double(bodySize) * largerHeadingRatio),
              bodySize > 0, line.size >= Double(bodySize) - 0.5 else { return false }
        guard text.count >= 2, text.count <= 80 else { return false }
        guard text.contains(where: { $0.isLetter }) else { return false }       // "1", "2", "3 4"
        guard !text.hasPrefix("(") else { return false }    // a qualifier belongs to the line above
        // A heading opens; it does not continue. A line that starts lower case or ends on a broken
        // word or an unfinished clause is the middle of a paragraph that happens to be set in bold.
        guard let first = text.first, first.isUppercase || first.isNumber || caseless else { return false }
        guard let tail = text.last, !",;:-\u{2013}\u{2014}/&+".contains(tail) else { return false }
        if caseless {
            // The same screens in CJK punctuation, and a sentence's end anywhere on the line.
            guard !"，、；：".contains(tail), !text.contains(where: { "。！？".contains($0) }) else { return false }
        }
        guard text.range(of: "^(\(labelWords))\\b", options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }
        // A numbered procedure step is a step whatever weight it is set in, and this class of
        // manual sets them in bold: "4 - Go to setup / system devices / thermostat". Same screen as
        // [[DocumentChunker]]'s lexical rules, keyed on the separator after the number.
        for pattern in numberedNonHeading where text.range(of: pattern, options: .regularExpression) != nil {
            return false
        }
        guard let last = text.last, !".!?".contains(last) else { return false }
        guard DocumentChunker.pageNumber(in: text) == nil else { return false }
        return true
    }

    /// How much larger than body a line in a script without case must be set to be a heading
    /// without bold (Plan JY P4).
    static let largerHeadingRatio = 1.2

    /// Whether a line opens in a script without case: its first letter (after any section number
    /// and punctuation) is neither upper nor lower case — Han, kana, Hangul, Arabic. A Latin or
    /// Cyrillic line never is, so their rules are untouched.
    static func isCaseless(_ text: String) -> Bool {
        guard let letter = text.first(where: \.isLetter) else { return false }
        return !letter.isUppercase && !letter.isLowercase
    }

    /// A parenthetical qualifier set on its own line under a heading or a caption ("(shown in
    /// upflow position)"). Never a heading on its own — it belongs to the line above it.
    static func isParentheticalQualifier(_ line: TypedLine, bodySize: Int) -> Bool {
        line.bold && bodySize > 0 && line.size >= Double(bodySize) - 0.5
            && line.text.hasPrefix("(") && line.text.count <= 80
    }

    /// The caption a line carries ("Figure 58", "Table 16", "Table 95A") and whatever title follows it on the
    /// same line, else nil. Captions are bold; the number is what separates a caption from a
    /// cross-reference ("See FIGURE 58 on page 44").
    static func caption(_ line: TypedLine) -> (label: String, inlineTitle: String)? {
        guard line.bold else { return nil }
        // A revision mark in the margin on the caption's line, standing apart or glued to the word
        // (Plan JW P0), is dropped first — the table extractor's own rule, so a marked caption names
        // the passage and the table alike.
        let text = TableExtractor.droppingMarginMarks(line.text)
        // The label as printed, a letter beside the number included ("TABLE 95A", "FIGURE Q7"):
        // the rule the table extractor reads captions by (Plan JJ P5), so a passage's figure and
        // its table carry the same label.
        guard let match = text.range(of: #"^(?i:FIGURE|TABLE)\s+"# + TableExtractor.labelPattern,
                                     options: .regularExpression) else {
            // Another interface language's caption word (Plan JY P4), after the English rule.
            return CaptionWords.match(text).map { ($0.label, $0.title) }
        }
        let head = String(text[match])
        let word = head.range(of: "^FIGURE", options: [.regularExpression, .caseInsensitive]) != nil ? "Figure" : "Table"
        let number = head.range(of: TableExtractor.labelPattern + "$", options: .regularExpression).map { String(head[$0]) } ?? ""
        let rest = String(text[match.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t.:\u{2014}\u{2013}-"))
        return ("\(word) \(number)", rest)
    }

    /// Whether the bold line at `index` stands on its own rather than being one line of a paragraph
    /// that happens to be set in bold — which is how this class of manual sets its warnings, and
    /// which wraps over four or five lines that each read as a heading in isolation.
    ///
    /// A caption is not a continuation (it is its own structure) and neither is the parenthetical
    /// qualifier a heading absorbs; anything else bold at body size, immediately above or below,
    /// means this line is in the middle of something.
    static func standsAlone(at index: Int, in lines: [TypedLine], bodySize: Int) -> Bool {
        func isRun(_ i: Int) -> Bool {
            guard i >= 0, i < lines.count else { return false }
            let line = lines[i]
            guard !line.text.isEmpty, line.bold, line.size >= Double(bodySize) - 0.5 else { return false }
            // The publisher's own running header sits above the first heading on the page and is
            // set in the same bold; it is furniture, not the paragraph this line belongs to.
            guard DocumentChunker.pageNumber(in: line.text) == nil else { return false }
            return caption(line) == nil
        }
        func previousNonEmpty(from i: Int) -> Int? {
            var j = i - 1
            while j >= 0, lines[j].text.isEmpty { j -= 1 }
            return j >= 0 ? j : nil
        }
        func nextNonEmpty(from i: Int) -> Int? {
            var j = i + 1
            while j < lines.count, lines[j].text.isEmpty { j += 1 }
            return j < lines.count ? j : nil
        }
        if let previous = previousNonEmpty(from: index), isRun(previous) { return false }
        var after = nextNonEmpty(from: index)
        // The heading may absorb one parenthetical qualifier; what follows *that* is the test.
        if let candidate = after, isParentheticalQualifier(lines[candidate], bodySize: bodySize) {
            after = nextNonEmpty(from: candidate)
        }
        if let following = after, isRun(following) { return false }
        return true
    }

    /// Whether a page is a drawing rather than prose: most of its characters are set below body
    /// size and it has next to no sentences in it.
    ///
    /// A table page meets both tests, and that is accepted rather than worked around — a table is
    /// read as a figure too, its rows still reach exact-token search, and a citation that names the
    /// table is right. A page of prose at body size is never a diagram at any threshold.
    static func isDiagramPage(_ page: TypedPage, bodySize: Int) -> Bool {
        let total = page.sizes.values.reduce(0, +)
        guard total > 0, bodySize > 0 else { return false }
        let small = page.sizes.filter { $0.key < bodySize }.values.reduce(0, +)
        guard Double(small) >= 0.6 * Double(total) else { return false }
        let terminators = page.lines.reduce(0) { $0 + $1.text.filter { ".!?".contains($0) }.count }
        return terminators * 200 < total
    }

    // MARK: - Rendering

    /// A page rewritten in the grammar the chunker reads: `## Heading`, `### Figure 58 — Title`,
    /// and a `<!-- page: diagram -->` tag on a drawing. Every other line is passed through
    /// unchanged — the grammar annotates the text, it never replaces it.
    static func render(_ page: TypedPage, bodySize: Int) -> RenderedPage {
        var out: [String] = []
        var headings = 0
        let diagram = isDiagramPage(page, bodySize: bodySize)
        var hoisted: Int?

        if diagram {
            out.append(diagramMarker)
            // A drawing is one picture, and its caption names the page rather than a point inside
            // it: the labels around it come out of the PDF in no useful order, and the figure a
            // citation names has to be the one the reader sees when they turn to the page. So the
            // page's own caption — its FIGURE if it has one, otherwise its first TABLE — is written
            // at the top, where every chunk of the page inherits it.
            hoisted = page.lines.firstIndex { caption($0)?.label.hasPrefix("Figure") == true }
                ?? page.lines.firstIndex { caption($0) != nil }
            if let index = hoisted, let label = caption(page.lines[index]) {
                var title = label.inlineTitle
                if title.isEmpty, index + 1 < page.lines.count, isCaptionTitle(page.lines[index + 1]) {
                    title = page.lines[index + 1].text
                }
                out.append(title.isEmpty ? "### \(label.label)" : "### \(label.label) — \(title)")
            }
        }

        var index = 0
        while index < page.lines.count {
            let line = page.lines[index]
            if index == hoisted {
                // Already written at the top of the page; its title line goes with it.
                if let label = caption(line), label.inlineTitle.isEmpty,
                   index + 1 < page.lines.count, isCaptionTitle(page.lines[index + 1]) {
                    index += 1
                }
                index += 1
                continue
            }
            if let label = caption(line) {
                var title = label.inlineTitle
                if title.isEmpty, index + 1 < page.lines.count, isCaptionTitle(page.lines[index + 1]) {
                    title = page.lines[index + 1].text
                    index += 1
                }
                if !title.isEmpty, index + 1 < page.lines.count,
                   isParentheticalQualifier(page.lines[index + 1], bodySize: bodySize) {
                    title += " " + page.lines[index + 1].text
                    index += 1
                }
                out.append(title.isEmpty ? "### \(label.label)" : "### \(label.label) — \(title)")
                index += 1
                continue
            }
            if isHeading(line, bodySize: bodySize), standsAlone(at: index, in: page.lines, bodySize: bodySize) {
                var text = line.text
                // A parenthetical qualifier on its own line is the second half of the heading above
                // it ("PRESSURE SWITCH TUBING INSTALLATION" / "(shown in upflow position)").
                if index + 1 < page.lines.count, isParentheticalQualifier(page.lines[index + 1], bodySize: bodySize) {
                    text += " " + page.lines[index + 1].text
                    index += 1
                }
                out.append("## \(text)")
                headings += 1
                index += 1
                continue
            }
            out.append(line.raw)
            index += 1
        }
        return RenderedPage(text: out.joined(separator: "\n"), headings: headings, isDiagram: diagram)
    }

    /// Whether the line under a caption is that caption's title: bold, short, and not a caption
    /// itself.
    private static func isCaptionTitle(_ line: TypedLine) -> Bool {
        line.bold && !line.text.isEmpty && line.text.count <= 80 && caption(line) == nil
    }

    // MARK: - Reading type off a PDF page

    /// Whether a font is bold. The symbolic trait is the honest answer; a subset font embedded in a
    /// PDF often loses it and keeps only its name ("ABCDE+Arial-BoldMT"), so the name is the
    /// backstop.
    static func isBold(_ font: UIFont) -> Bool {
        if font.fontDescriptor.symbolicTraits.contains(.traitBold) { return true }
        let name = font.fontName.lowercased()
        return ["bold", "black", "heavy", "semibold", "-bd"].contains { name.contains($0) }
    }

    /// A page's lines with the type each was set in, from the attributed string PDFKit
    /// reconstructs. Nil when the page has no attributed string — a recognised scan, which keeps
    /// the lexical treatment.
    ///
    /// A line's size and weight are its *dominant* run by printable character count, so a heading
    /// with one italic word is still a heading and a body line with a bold lead-in is still body.
    ///
    /// `glyphs` (Plan JY P5a) reads where a character of the page's string is drawn, so a doubled
    /// CJK pair the text can't decide is decided by its type (`OverprintedText.collapsed`): the
    /// page's own selection bounds in the app (`typedPages(of:)`), nil in a test of text alone.
    static func typedPage(from attributed: NSAttributedString,
                          glyphs: ((NSRange) -> CGRect?)? = nil) -> TypedPage {
        let ns = attributed.string as NSString
        var runs: [(range: NSRange, size: Double, bold: Bool)] = []
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
            guard let font = value as? UIFont else { return }
            runs.append((range, Double(font.pointSize), isBold(font)))
        }

        var lines: [TypedLine] = []
        var sizes: [Int: Int] = [:]
        var runIndex = 0

        func emit(_ range: NSRange) {
            let raw = ns.substring(with: range)
            var weights: [String: (size: Double, bold: Bool, count: Int)] = [:]
            while runIndex < runs.count, NSMaxRange(runs[runIndex].range) <= range.location { runIndex += 1 }
            var scan = runIndex
            while scan < runs.count, runs[scan].range.location < NSMaxRange(range) {
                let run = runs[scan]
                let overlap = NSIntersectionRange(run.range, range)
                if overlap.length > 0 {
                    let printable = ns.substring(with: overlap).filter { !$0.isWhitespace }.count
                    if printable > 0 {
                        let rounded = Int(run.size.rounded())
                        sizes[rounded, default: 0] += printable
                        let key = "\(rounded)|\(run.bold)"
                        let existing = weights[key] ?? (run.size, run.bold, 0)
                        weights[key] = (existing.size, existing.bold, existing.count + printable)
                    }
                }
                scan += 1
            }
            // A tie between a bold and a regular run of one size and count is decided the same way every
            // time (Plan JY P5a): `weights` is a dictionary, whose order is seeded per process, so the
            // tie went either way from one run to the next and a line such as a clause number in bold
            // beside its title in a substituted regular font was a heading in one extraction and not in
            // the next.
            let dominant = weights.values.max { ($0.count, $0.size, $0.bold ? 1 : 0) < ($1.count, $1.size, $1.bold ? 1 : 0) }
            // Fake bold (Plan JY P4): a CJK line printed twice over reads each character twice and
            // carries no bold font. The doubling is collapsed, and a line mostly set that way is
            // bold, which is what the overprinting was for.
            let overprint = OverprintedText.collapsed(raw, advance: glyphs.map { glyphs in
                overprintAdvance(in: raw, at: range.location, attributed: attributed, glyphs: glyphs)
            })
            let bold = (dominant?.bold ?? false) || OverprintedText.isMostlyOverprinted(raw, collapsed: overprint)
            lines.append(TypedLine(raw: overprint.text, size: dominant?.size ?? 0, bold: bold))
        }

        var start = 0
        var index = 0
        while index < ns.length {
            let ch = ns.character(at: index)
            if ch == 10 || ch == 13 {
                emit(NSRange(location: start, length: index - start))
                if ch == 13, index + 1 < ns.length, ns.character(at: index + 1) == 10 { index += 1 }
                start = index + 1
            }
            index += 1
        }
        if start < ns.length { emit(NSRange(location: start, length: ns.length - start)) }

        return TypedPage(lines: lines, sizes: sizes)
    }

    /// For a line read from `attributed` at `location`, the advance from the character at an index
    /// of the line to the next one, in ems of its font: where the next character's box starts after
    /// this one's, over the point size, when both sit on one horizontal line (Plan JY P5a). Nil
    /// when the page gives no box or no size. Asked only for a doubled pair, so a page with none
    /// costs nothing.
    static func overprintAdvance(in line: String, at location: Int, attributed: NSAttributedString,
                                 glyphs: @escaping (NSRange) -> CGRect?) -> (Int) -> Double? {
        let offsets = line.indices.map { location + line.utf16.distance(from: line.startIndex, to: $0) }
        let lengths = line.map { $0.utf16.count }
        return { index in
            guard index + 1 < offsets.count else { return nil }
            let first = NSRange(location: offsets[index], length: lengths[index])
            let second = NSRange(location: offsets[index + 1], length: lengths[index + 1])
            guard NSMaxRange(second) <= attributed.length,
                  let font = attributed.attribute(.font, at: first.location, effectiveRange: nil) as? UIFont,
                  font.pointSize > 0, let a = glyphs(first), let b = glyphs(second),
                  a.width > 0, b.width > 0, abs(a.midY - b.midY) < font.pointSize / 2 else { return nil }
            return Double(b.minX - a.minX) / Double(font.pointSize)
        }
    }

    /// The typed pages of a document, indexed by page, for pages that carry an attributed string.
    static func typedPages(of document: PDFDocument) -> [Int: TypedPage] {
        var pages: [Int: TypedPage] = [:]
        for index in 0..<document.pageCount {
            pages[index] = autoreleasepool {
                guard let page = document.page(at: index),
                      let attributed = page.attributedString, attributed.length > 0 else { return nil }
                return typedPage(from: attributed, glyphs: { range in page.selection(for: range)?.bounds(for: page) })
            }
        }
        return pages
    }
}
