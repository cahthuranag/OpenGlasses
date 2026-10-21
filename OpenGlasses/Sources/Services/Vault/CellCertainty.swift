import CoreGraphics
import Foundation

/// How clearly each cell of a table read from a picture was read (Plan JN P0). Pure: a
/// [[RecognisedReading]] in, the table with its unclear cells marked `uncertain` out — or, when too
/// few cells are clear, `unclear_in_picture`, kept as an unread table rather than a sparse one.
///
/// A wrong cable size is worse than a page reference, so a cell is uncertain on any doubt, and an
/// uncertain cell keeps its text (for the page to be checked against) and is never given as a
/// value. Nothing here ever changes what a cell reads: a glyph that could be a digit is flagged,
/// never "corrected".
enum CellCertainty {

    /// Why a cell is uncertain. Counted, never logged with the cell.
    enum Reason: String, CaseIterable, Equatable {
        /// Its least confident word is under the floor.
        case lowConfidence = "low_confidence"
        /// Its column is one of numbers and it holds a letter a digit is mistaken for, or a stray
        /// separator between digits.
        case confusableGlyph = "confusable_glyph"
        /// A second pass over the region read it differently, or not at all.
        case passesDisagree = "passes_disagree"
        /// Its text could not be tied to the words it was read from.
        case noEvidence = "no_evidence"
        /// It reads empty: in a picture a blank and a cell the recogniser missed look alike.
        case blank
    }

    /// Below this share of clear cells among the cells that read anything, the table is
    /// `unclear_in_picture`: mostly uncertain cells are not a table to give values from.
    static let minimumCertainShare = 0.5

    /// Letters a recogniser reads for a digit: O, D and Q for 0, l and I (and a bar) for 1, Z for
    /// 2, S for 5, G and b for 6, T for 7, B for 8, g and q for 9.
    static let confusableLetters: Set<Character> = ["O", "o", "D", "Q", "l", "I", "|", "Z", "z", "S", "s",
                                                    "G", "b", "T", "B", "g", "q"]

    struct Assessment: Equatable {
        var outcome: TableExtractor.Outcome
        /// Cells marked uncertain, and how many for each reason (a cell may have several).
        var uncertain: Int
        var byReason: [Reason: Int]
        /// Rows whose key, and columns whose heading, were marked uncertain (Plan JN P1).
        var uncertainKeys = 0
        var uncertainColumns = 0
    }

    /// `reading`'s table with its unclear cells marked. `floor` is the least word confidence a
    /// clear cell may have (settled by measurement, Plan JN P1); `secondPass` is the same region
    /// recognised again at another render scale, matched cell by cell by place. A reading that read
    /// no table is returned as it is.
    static func assess(_ reading: RecognisedReading, floor: Float, secondPass: RecognisedPage? = nil,
                       minimumCertainShare: Double = minimumCertainShare) -> Assessment {
        guard case .table(var table) = reading.outcome else {
            return Assessment(outcome: reading.outcome, uncertain: 0, byReason: [:])
        }
        var uncertain = 0
        var byReason: [Reason: Int] = [:]
        for row in table.rows.indices {
            for column in table.rows[row].cells.indices {
                let evidence = row < reading.cells.count && column < reading.cells[row].count
                    ? reading.cells[row][column] : .missing
                let others = table.rows.indices.filter { $0 != row }.compactMap { other -> ManualTable.Cell? in
                    column < table.rows[other].cells.count ? table.rows[other].cells[column] : nil
                }
                let reasons = self.reasons(table.rows[row].cells[column], evidence: evidence, column: others,
                                           floor: floor, secondPass: secondPass)
                guard !reasons.isEmpty else { continue }
                table.rows[row].cells[column].uncertain = true
                uncertain += 1
                for reason in reasons { byReason[reason, default: 0] += 1 }
            }
        }
        let headings = assessHeadings(&table, reading: reading, floor: floor, secondPass: secondPass)
        let read = table.rows.flatMap(\.cells).filter { !$0.isEmpty }
        let clear = read.filter { !$0.uncertain }.count
        if read.isEmpty || Double(clear) < minimumCertainShare * Double(read.count) {
            return Assessment(outcome: .failed(.unclearInPicture), uncertain: uncertain, byReason: byReason,
                              uncertainKeys: headings.keys, uncertainColumns: headings.columns)
        }
        return Assessment(outcome: .table(table), uncertain: uncertain, byReason: byReason,
                          uncertainKeys: headings.keys, uncertainColumns: headings.columns)
    }

    // MARK: - Row keys and column headings (Plan JN P1)

    /// Marks each row whose key, and each column whose heading, was read unclearly. A misread key
    /// or heading points a lookup at another row's or column's values, so they are judged as a
    /// value cell is: a word under the floor, a second pass that reads them differently, words the
    /// reader could not tie to them, or a confusable glyph where the other rows' keys (the other
    /// columns' headings) are numbers. Only the last level of a key or a heading is checked for a
    /// glyph, since that is where a number heading is printed. A reading that kept no evidence for
    /// headings (`rowKeys` / `columnHeadings` empty) is not judged here.
    static func assessHeadings(_ table: inout ManualTable, reading: RecognisedReading, floor: Float,
                               secondPass: RecognisedPage?) -> (keys: Int, columns: Int) {
        func doubtful(_ evidence: [RecognisedReading.Evidence]) -> Bool {
            evidence.contains { proof in
                if proof.words.isEmpty { return true }
                if let least = proof.words.map(\.confidence).min(), least < floor { return true }
                if let secondPass, !passesAgree(proof, secondPass: secondPass) { return true }
                return false
            }
        }
        func asCell(_ text: String?) -> ManualTable.Cell? {
            guard let text, !text.isEmpty else { return nil }
            return TableExtractor.parseCell(text, markers: [], columnUnit: nil)
        }
        var keys = 0
        if reading.rowKeys.count == table.rows.count {
            let lasts = table.rows.map { asCell($0.path.last) }
            for row in table.rows.indices where !table.rows[row].path.isEmpty {
                let others = lasts.indices.filter { $0 != row }.compactMap { lasts[$0] }
                let glyph = lasts[row].map { holdsConfusableGlyph($0, column: others) } ?? false
                guard glyph || doubtful(reading.rowKeys[row]) else { continue }
                table.rows[row].keyUncertain = true
                keys += 1
            }
        }
        var columns = 0
        if reading.columnHeadings.count == table.columns.count {
            let lasts = table.columns.map { asCell($0.path.last) }
            for column in table.columns.indices where !table.columns[column].path.isEmpty {
                let others = lasts.indices.filter { $0 != column }.compactMap { lasts[$0] }
                let glyph = lasts[column].map { holdsConfusableGlyph($0, column: others) } ?? false
                guard glyph || doubtful(reading.columnHeadings[column]) else { continue }
                table.columns[column].uncertain = true
                columns += 1
            }
        }
        return (keys, columns)
    }

    /// Why one cell is uncertain; empty when it is clear. `column` is the other cells of its column.
    static func reasons(_ cell: ManualTable.Cell, evidence: RecognisedReading.Evidence, column: [ManualTable.Cell],
                        floor: Float, secondPass: RecognisedPage?) -> Set<Reason> {
        guard !cell.isEmpty else { return [.blank] }
        var reasons: Set<Reason> = []
        if evidence.words.isEmpty {
            reasons.insert(.noEvidence)
        } else if let least = evidence.words.map(\.confidence).min(), least < floor {
            reasons.insert(.lowConfidence)
        }
        if holdsConfusableGlyph(cell, column: column) { reasons.insert(.confusableGlyph) }
        if let secondPass, !passesAgree(evidence, secondPass: secondPass) { reasons.insert(.passesDisagree) }
        return reasons
    }

    // MARK: - Confusable glyphs

    /// The cell's column is one of numbers (at least half of its other filled cells read as one)
    /// and the cell holds a letter a digit is read as — run into a number, or standing alone — or a
    /// "," or "." between digits that the column's numbers mostly do not print. A unit the
    /// column's numbers share ("5s" among "10s") is not a glyph to doubt.
    static func holdsConfusableGlyph(_ cell: ManualTable.Cell, column others: [ManualTable.Cell]) -> Bool {
        let filled = others.filter { !$0.isEmpty }
        let numbers = filled.filter { $0.value != nil }
        guard !filled.isEmpty, numbers.count * 2 >= filled.count, !numbers.isEmpty else { return false }
        var core = cell.text
        if let unit = cell.unit, core.hasSuffix(unit),
           numbers.filter({ $0.unit == unit && $0.text.hasSuffix(unit) }).count * 2 >= numbers.count {
            core.removeLast(unit.count)
        }
        for token in core.split(whereSeparator: \.isWhitespace) {
            guard token.contains(where: confusableLetters.contains) else { continue }
            if token.contains(where: \.isNumber) { return true }
            if token.allSatisfy({ confusableLetters.contains($0) || $0.isPunctuation }) { return true }
        }
        for separator in [",", "."] where separatesDigits(core, separator) {
            let printing = numbers.filter { separatesDigits($0.text, separator) }.count
            if printing * 2 < numbers.count { return true }
        }
        return false
    }

    private static func separatesDigits(_ text: String, _ separator: String) -> Bool {
        text.range(of: #"\d"# + NSRegularExpression.escapedPattern(for: separator) + #"\d"#, options: .regularExpression) != nil
    }

    // MARK: - Two passes

    /// The second pass read the same cell, at the same place, the same way. A cell the second pass
    /// has no reading for does not agree.
    static func passesAgree(_ evidence: RecognisedReading.Evidence, secondPass: RecognisedPage) -> Bool {
        let first = RecognisedCellText(evidence.words).key
        switch evidence.place {
        case nil:
            return false
        case .grid(let table, let rows, let columns)?:
            guard table < secondPass.tables.count,
                  let cell = secondPass.tables[table].cells.first(where: { $0.rowRange == rows && $0.columnRange == columns })
            else { return false }
            return RecognisedCellText(cell.words).key == first
        case .box(let box)?:
            let words = RecognisedWords.words(in: box, of: secondPass.words)
            guard !words.isEmpty else { return false }
            return RecognisedCellText(words).key == first
        }
    }
}
