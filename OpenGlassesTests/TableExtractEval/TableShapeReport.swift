import Foundation
#if canImport(OpenGlasses)
@testable import OpenGlasses
#endif

/// The shape of every captioned table the extractor could not read (Plan JJ P5), in counts only:
/// how many lines sit under the caption, how many words and cells those lines have, how many
/// column positions they line up on, how many of their cells are a single character or not a
/// number, and whether the next page carries the grid on with no caption of its own, prints the
/// headings again, or the page sets two groups of columns side by side. Captions are reported by
/// index — never a label, a title, a heading or a cell — so a run over a licensed book can be
/// read to decide what to fix without anyone reading the book.
///
/// Shared by two runners: `TableCoverageTests` in the simulator, on invented fixtures, and
/// `Scripts/table-extract-eval` on a Mac, which compiles this file beside the app's own
/// `TableExtractor` and `PDFTableReader`.
enum TableShapeReport {

    /// How a caption's label is printed.
    enum LabelShape: String, CaseIterable, Equatable {
        case digits
        case letterAfter = "letter_after"
        case lettersBefore = "letters_before"
    }

    struct Shape: Equatable {
        /// The caption's place among the failed captions, from 1.
        var index: Int
        var failure: TableExtractor.Failure
        var label: LabelShape
        /// Lines under the caption (and its title) before the next caption or the foot of the page.
        var linesBelow: Int
        /// Lines by how many words they hold, bucketed as `buckets` names them.
        var wordsPerLine: [String: Int]
        /// Lines by how many cells (phrases) they hold.
        var cellsPerLine: [String: Int]
        /// Positions at least three cells start at.
        var clusters: Int
        /// Of the cells on lines of two or more: a single character, and not a number.
        var singleCharacter: Double
        var nonNumeric: Double
        /// Words set smaller than the line they sit on (a raised marker, or a symbol font).
        var smallWords: Int
        /// Header and body lines as the extractor read them.
        var headerLines: Int
        var bodyRows: Int
        /// The next page begins with lines on the same positions and no caption before them.
        var nextPageSameClusters: Bool
        /// The next page sets a caption before its first line of cells.
        var nextPageCaptionFirst: Bool
        /// One of the next page's first lines is one of this table's first lines again.
        var nextPageRepeatsHeading: Bool
        /// The next page's first ten lines, above any caption, hold three or more lines of cells.
        var nextPageGridAtTop: Bool
        /// Another caption follows within two lines: a list of tables, not a table.
        var listed: Bool
        /// Below the caption the page's text stops for a stretch of at least `blankLines` lines'
        /// height: the table is printed there with no text to read.
        var blankBelow = false
        /// The positions fall into two groups with a gap between them wider than any inside a group.
        var twoGroups: Bool
        /// A heading line's cells repeat: its first half reads as its second.
        var headingsRepeat: Bool
    }

    struct Report: Equatable {
        var shapes: [Shape] = []
        /// Read tables whose next page carries the grid on with no caption of its own, and how
        /// many of those the extractor's continuation read.
        var extracted = 0
        /// Read tables by how their label is printed.
        var extractedByLabel: [String: Int] = [:]
        var extractedNextPageSameClusters = 0
        var continuationsRead = 0
        /// Of those, the ones whose table runs to the foot of its page.
        var extractedRunningToFoot = 0
        /// Every line that reads as a table caption, by how its label is printed — including the
        /// shapes the extractor does not read as a label ("4.1", "4-1").
        var captionLabelCensus: [String: Int] = [:]
    }

    static let buckets = ["1", "2", "3", "4", "5-8", "9+"]

    static func bucket(_ count: Int) -> String {
        switch count {
        case ...1: return "1"
        case 2, 3, 4: return String(count)
        case 5...8: return "5-8"
        default: return "9+"
        }
    }

    // MARK: - Reading

    /// The report over a document of `pageCount` pages. `mentionsTable` says whether a page's text
    /// mentions a table at all (only those, and the page after each, are read); `words` gives a
    /// page's positioned words, 0-based.
    static func report(pageCount: Int, mentionsTable: (Int) -> Bool, words: (Int) -> [PositionedWord]) -> Report {
        var report = Report()
        // A page's words are read once, and kept only while the page after it is read.
        var cache: [Int: [PositionedWord]] = [:]
        func page(_ index: Int) -> [PositionedWord] {
            if let cached = cache[index] { return cached }
            let read = words(index)
            cache[index] = read
            return read
        }
        var failedIndex = 0
        for index in 0..<pageCount where mentionsTable(index) {
            cache = cache.filter { $0.key >= index }
            let current = page(index)
            let lines = TableExtractor.lines(of: current)
            guard !lines.isEmpty else { continue }
            let bold = TableExtractor.hasBold(current)
            census(lines, into: &report.captionLabelCensus)
            let captions = TableExtractor.captionLines(in: lines, pageHasBold: bold)
            guard !captions.isEmpty else { continue }
            let next = index + 1 < pageCount ? page(index + 1) : []
            let nextLines = TableExtractor.lines(of: next)
            let nextCaption = TableExtractor.captionLines(in: nextLines, pageHasBold: TableExtractor.hasBold(next)).first?.index
            for found in captions {
                let read = TableExtractor.read(lines: lines, at: found.index, titleLines: found.titleLines,
                                               caption: found.caption, page: .init(physical: index + 1),
                                               hasRotatedWords: current.contains(where: \.isRotated), pageHasBold: bold)
                let layout = TableExtractor.layout(lines: lines, at: found.index, titleLines: found.titleLines,
                                                   caption: found.caption, pageHasBold: bold)
                let positions = clusterPositions(layout.region)
                let carriesOn = sameClusters(positions, nextLines: nextLines, before: nextCaption)
                switch read.outcome {
                case .table:
                    report.extracted += 1
                    report.extractedByLabel[labelShape(found.caption.label).rawValue, default: 0] += 1
                    if carriesOn {
                        report.extractedNextPageSameClusters += 1
                        if let grid = read.grid, grid.runsToFoot {
                            report.extractedRunningToFoot += 1
                            if TableExtractor.continuation(words: next, page: .init(physical: index + 2), grid: grid) != nil {
                                report.continuationsRead += 1
                            }
                        }
                    }
                case .failed(let failure):
                    failedIndex += 1
                    let endsAtCaption = found.index + 1 + found.titleLines + layout.region.count < lines.count
                    report.shapes.append(shape(index: failedIndex, failure: failure, caption: found.caption,
                                               layout: layout, positions: positions, carriesOn: carriesOn,
                                               nextLines: nextLines, nextCaption: nextCaption,
                                               listed: endsAtCaption && layout.region.count <= 2))
                }
            }
        }
        return report
    }

    /// The shape of the caption labelled `label` on a page, as `report` reads it, or nil when the
    /// page carries no such caption or its table was read.
    static func shape(of label: String, words: [PositionedWord], next: [PositionedWord], index: Int) -> Shape? {
        let lines = TableExtractor.lines(of: words)
        let bold = TableExtractor.hasBold(words)
        guard let found = TableExtractor.captionLines(in: lines, pageHasBold: bold)
            .first(where: { $0.caption.label.caseInsensitiveCompare(label) == .orderedSame }) else { return nil }
        let read = TableExtractor.read(lines: lines, at: found.index, titleLines: found.titleLines, caption: found.caption,
                                       page: .init(physical: 1), hasRotatedWords: words.contains(where: \.isRotated),
                                       pageHasBold: bold)
        guard let failure = read.outcome.failure else { return nil }
        let layout = TableExtractor.layout(lines: lines, at: found.index, titleLines: found.titleLines,
                                           caption: found.caption, pageHasBold: bold)
        let nextLines = TableExtractor.lines(of: next)
        let nextCaption = TableExtractor.captionLines(in: nextLines, pageHasBold: TableExtractor.hasBold(next)).first?.index
        let positions = clusterPositions(layout.region)
        let endsAtCaption = found.index + 1 + found.titleLines + layout.region.count < lines.count
        return shape(index: index, failure: failure, caption: found.caption, layout: layout, positions: positions,
                     carriesOn: sameClusters(positions, nextLines: nextLines, before: nextCaption),
                     nextLines: nextLines, nextCaption: nextCaption, listed: endsAtCaption && layout.region.count <= 2)
    }

    private static func shape(index: Int, failure: TableExtractor.Failure, caption: TableExtractor.Caption,
                              layout: TableExtractor.Layout, positions: [Double], carriesOn: Bool,
                              nextLines: [TableExtractor.Line], nextCaption: Int?, listed: Bool) -> Shape {
        let region = layout.region
        var words: [String: Int] = [:]
        var cells: [String: Int] = [:]
        var small = 0
        for line in region {
            words[bucket(line.words.count), default: 0] += 1
            cells[bucket(line.phrases.count), default: 0] += 1
            small += line.words.filter { $0.size < 0.8 * line.size }.count
        }
        let gridCells = region.filter { $0.phrases.count >= 2 }.flatMap(\.phrases).filter { !$0.text.isEmpty }
        let single = gridCells.filter { $0.text.count == 1 }.count
        let text = gridCells.filter { TableExtractor.parseCell($0.text, markers: $0.markers, columnUnit: nil).value == nil }.count
        let firstLines = Set(region.prefix(6).map { TableExtractor.headingKey($0.text) }.filter { $0.split(separator: " ").count >= 2 })
        let nextFirst = nextLines.prefix(8).map { TableExtractor.headingKey($0.text) }
        return Shape(index: index, failure: failure, label: labelShape(caption.label), linesBelow: region.count,
                     wordsPerLine: words, cellsPerLine: cells, clusters: positions.count,
                     singleCharacter: gridCells.isEmpty ? 0 : Double(single) / Double(gridCells.count),
                     nonNumeric: gridCells.isEmpty ? 0 : Double(text) / Double(gridCells.count),
                     smallWords: small, headerLines: layout.header.count, bodyRows: layout.body.count,
                     nextPageSameClusters: carriesOn,
                     nextPageCaptionFirst: nextCaption.map { at in
                         !nextLines.prefix(at).contains { $0.phrases.count >= 2 }
                     } ?? false,
                     nextPageRepeatsHeading: nextFirst.contains { firstLines.contains($0) },
                     nextPageGridAtTop: nextLines.prefix(nextCaption ?? nextLines.count).prefix(10)
                         .filter { $0.phrases.count >= 2 }.count >= 3,
                     listed: listed,
                     blankBelow: TableExtractor.textStopsBelowCaption(region: region),
                     twoGroups: twoGroups(positions),
                     headingsRepeat: region.prefix(6).contains(where: headingsRepeat))
    }

    static func labelShape(_ label: String) -> LabelShape {
        let token = label.split(separator: " ").last.map(String.init) ?? ""
        if token.first?.isLetter == true { return .lettersBefore }
        if token.last?.isLetter == true { return .letterAfter }
        return .digits
    }

    /// Where cells start, as positions at least three cells of lines of two or more start at
    /// (within three points of one another), left to right.
    static func clusterPositions(_ lines: [TableExtractor.Line]) -> [Double] {
        let starts = lines.filter { $0.phrases.count >= 2 }.flatMap { $0.phrases.map(\.minX) }.sorted()
        var groups: [[Double]] = []
        for x in starts {
            if let last = groups.last?.last, x - last <= 3 { groups[groups.count - 1].append(x) } else { groups.append([x]) }
        }
        return groups.filter { $0.count >= 3 }.map { $0.reduce(0, +) / Double($0.count) }
    }

    /// The next page's first lines of cells, above any caption, start where this table's cells do.
    static func sameClusters(_ positions: [Double], nextLines: [TableExtractor.Line], before caption: Int?) -> Bool {
        guard positions.count >= 2 else { return false }
        let top = Array(nextLines.prefix(caption ?? nextLines.count).prefix(15)).filter { $0.phrases.count >= 2 }
        guard top.count >= 3 else { return false }
        let starts = top.flatMap { $0.phrases.map(\.minX) }
        let near = starts.filter { x in positions.contains { abs($0 - x) <= 3 } }.count
        return Double(near) >= 0.7 * Double(starts.count)
    }

    /// Positions that fall into two groups of two or more with a gap between them at least twice
    /// as wide as any gap inside either group.
    static func twoGroups(_ positions: [Double]) -> Bool {
        guard positions.count >= 4 else { return false }
        let gaps = zip(positions, positions.dropFirst()).map { $1 - $0 }
        guard let widest = gaps.indices.max(by: { gaps[$0] < gaps[$1] }) else { return false }
        let left = widest + 1, right = positions.count - left
        guard left >= 2, right >= 2 else { return false }
        let others = gaps.enumerated().filter { $0.offset != widest }.map(\.element)
        return gaps[widest] >= 2 * (others.max() ?? 0)
    }

    /// A line of four or more cells whose first half reads as its second.
    static func headingsRepeat(_ line: TableExtractor.Line) -> Bool {
        let cells = line.phrases.map { TableExtractor.headingKey($0.text) }
        guard cells.count >= 4, cells.count % 2 == 0 else { return false }
        let half = cells.count / 2
        return Array(cells[..<half]) == Array(cells[half...]) && cells.contains { !$0.isEmpty }
    }

    /// Lines that read as a caption — "Table" first, a label, at most twelve words — by how the
    /// label is printed.
    private static func census(_ lines: [TableExtractor.Line], into counts: inout [String: Int]) {
        for line in lines where line.words.count <= TableExtractor.plainCaptionMaximumWords {
            let words = line.words.map(\.text)
            guard words.count >= 2, words[0].lowercased() == "table" else { continue }
            let token = words[1].trimmingCharacters(in: CharacterSet(charactersIn: ".:,;\u{2014}\u{2013}"))
            let kind: String
            if token.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil { kind = "digits" }
            else if token.range(of: #"^\d{1,4}[A-Za-z]$"#, options: .regularExpression) != nil { kind = "letter_after" }
            else if token.range(of: #"^[A-Z]{1,2}\d{1,4}[A-Za-z]?$"#, options: .regularExpression) != nil { kind = "letters_before" }
            else if token.range(of: #"^\d+\.\d+"#, options: .regularExpression) != nil { kind = "dotted" }
            else if token.range(of: #"^\d+[-\x{2010}\x{2011}]\d+"#, options: .regularExpression) != nil { kind = "hyphenated" }
            else if token.range(of: #"^[IVXLC]+$"#, options: .regularExpression) != nil { kind = "roman" }
            else { kind = "other" }
            counts[kind, default: 0] += 1
        }
    }

    // MARK: - Output

    /// The report as lines: counts, shares and booleans, and captions by index only.
    static func render(_ report: Report) -> [String] {
        let shapes = report.shapes
        func count(_ test: (Shape) -> Bool) -> Int { shapes.filter(test).count }
        func histogram(_ values: [String: Int]) -> String {
            buckets.compactMap { key in values[key].map { "\(key):\($0)" } }.joined(separator: " ")
        }
        func flag(_ value: Bool) -> String { value ? "yes" : "no" }
        let below = shapes.map(\.linesBelow).sorted()
        var lines: [String] = []
        let labels = TableShapeReport.LabelShape.allCases.map { shape in "\(shape.rawValue)=\(count { $0.label == shape })" }
        lines.append("[SHAPE] failed=\(shapes.count) · labels " + labels.joined(separator: " "))
        let census = report.captionLabelCensus.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        lines.append("[SHAPE] caption lines by label: " + (census.isEmpty ? "none" : census))
        lines.append("[SHAPE] lines_below median=\(below.isEmpty ? 0 : below[below.count / 2]) "
                     + "under_5=\(count { $0.linesBelow < 5 }) · next page: same_clusters=\(count(\.nextPageSameClusters)) "
                     + "caption_first=\(count(\.nextPageCaptionFirst)) repeats_heading=\(count(\.nextPageRepeatsHeading)) "
                     + "· two_groups=\(count(\.twoGroups)) headings_repeat=\(count(\.headingsRepeat)) "
                     + "· single_char>0.3=\(count { $0.singleCharacter > 0.3 }) non_numeric>0.5=\(count { $0.nonNumeric > 0.5 }) "
                     + "small_words>0=\(count { $0.smallWords > 0 }) · listed=\(count(\.listed)) "
                     + "under_5_next_page_grid_at_top=\(count { $0.linesBelow < 5 && !$0.listed && $0.nextPageGridAtTop }) "
                     + "blank_below=\(count(\.blankBelow))")
        let byLabel = TableShapeReport.LabelShape.allCases.map { "\($0.rawValue)=\(report.extractedByLabel[$0.rawValue] ?? 0)" }
        lines.append("[SHAPE] extracted=\(report.extracted) (labels " + byLabel.joined(separator: " ") + ") "
                     + "next_page_same_clusters=\(report.extractedNextPageSameClusters) "
                     + "running_to_foot=\(report.extractedRunningToFoot) continuation_read=\(report.continuationsRead)")
        for shape in shapes {
            lines.append("[SHAPE]   #\(shape.index) \(shape.failure.rawValue) label=\(shape.label.rawValue) "
                         + "lines=\(shape.linesBelow) header=\(shape.headerLines) body=\(shape.bodyRows) "
                         + "clusters=\(shape.clusters) words/line \(histogram(shape.wordsPerLine)) "
                         + "cells/line \(histogram(shape.cellsPerLine)) "
                         + String(format: "single=%.2f text=%.2f ", shape.singleCharacter, shape.nonNumeric)
                         + "small=\(shape.smallWords) next: same=\(flag(shape.nextPageSameClusters)) "
                         + "caption_first=\(flag(shape.nextPageCaptionFirst)) heading_again=\(flag(shape.nextPageRepeatsHeading)) "
                         + "grid_at_top=\(flag(shape.nextPageGridAtTop)) listed=\(flag(shape.listed)) "
                         + "blank_below=\(flag(shape.blankBelow)) "
                         + "two_groups=\(flag(shape.twoGroups)) headings_repeat=\(flag(shape.headingsRepeat))")
        }
        return lines
    }
}
