import Foundation

/// A value a running chain holds: what it is, and where it came from — the step that made it and,
/// for a lookup, the cell, its headings and its citation (Plan JJ P2), so the read-back can cite
/// every step.
struct ChainValue: Equatable {
    enum Source: Equatable {
        /// What the technician said, as said ("57 °F" when it was converted to the asked unit).
        case asked(said: String)
        case lookup(ChainLookup)
        /// The expression and the numbers it ran on ("32 / 0.86").
        case calc(expression: String, worked: String)
        /// The value converted, with its unit ("100 ft").
        case convert(from: String)
    }

    let name: String
    /// The number, when the value is one.
    let number: Double?
    /// As said, as printed in the cell, or the number as the chain says it.
    let text: String
    let unit: String?
    /// The step that made it, by its index in the chain, and its line in the file.
    let stepIndex: Int
    let line: Int
    let source: Source

    /// Whether a `{name.row}` and the like can be read from it.
    var lookup: ChainLookup? {
        if case .lookup(let lookup) = source { return lookup }
        return nil
    }
}

/// One cell a chain's lookup read, with everything a citation needs.
struct ChainLookup: Equatable {
    let found: TableLookup.Found
    let rule: TableLookup.RowRule
    /// The row or the number the step asked for, values filled in.
    let asked: String
    /// The row was chosen by its cell in the column (the `cell` form), not by its heading.
    let byCell: Bool

    var documentName: String { found.source.documentName }
    var table: ManualTable { found.source.table }
    var row: ManualTable.Row { found.rows[0] }
    var columnIndex: Int { found.columns[0] }
    var rowName: String { TableLookup.rowName(row) }
    var columnName: String {
        columnIndex < table.columns.count ? TableLookup.columnName(table.columns[columnIndex]) : "column \(columnIndex + 1)"
    }
    var cell: ManualTable.Cell {
        columnIndex < row.cells.count ? row.cells[columnIndex] : ManualTable.Cell(text: "")
    }
    var page: ManualTable.Page { row.page }
    var notes: [ManualTable.Note] { TableLookup.notes(for: found) }

    /// The cell came from a table read from a picture (Plan JN P2). It still feeds the chain
    /// (owner decision 1), and every read-back of it says so.
    var fromPicture: Bool { table.source.isRecognised }

    /// "from a picture of Table Q7 (Invented spacings), page 31: check it against the page" — the
    /// read-back's mark on a step that used a value read from a picture, nil for any other.
    var pictureMark: String? {
        guard fromPicture else { return nil }
        let place = "from a picture of \(table.displayName), \(TableLookup.spokenPage(page))"
        // A cell someone checked against the page is not handed back to be checked (Plan JN P3).
        if let mark = cell.check?.agreedMark { return place + ", " + TableChecks.checkedNote(mark) }
        return place + ": check it against the page"
    }

    /// "QMX90 › three conductors (55)", the row printed after this one with its cell in the same
    /// column; nil on the last row, and on a row whose key was read unclearly from a picture, whose
    /// unclear cell is left out (Plan JN P1).
    var next: String? {
        guard let next = TableLookup.nextRow(after: row, in: table), !next.keyUncertain else { return nil }
        let cell = columnIndex < next.cells.count && !next.cells[columnIndex].uncertain ? next.cells[columnIndex].text : ""
        return TableLookup.rowName(next) + (cell.isEmpty ? "" : " (\(cell))")
    }

    /// The `Source:` line for the cell's page, which `CitationLineParser` turns into a chip.
    var sourceLine: String {
        TableLookup.sourceLine(documentName: documentName, label: table.label, pages: [page])
    }

    var citations: [Citation] {
        TableLookup.citations(documentName: documentName, label: table.label, pages: [page])
    }
}

/// Why a chain stopped, and the page to show when there is one.
struct ChainStop: Equatable, Error {
    let reason: String
    /// The step it stopped at (index) and its line in the file.
    let stepIndex: Int
    let line: Int
    /// The table page the step could not use, to show.
    let sourceLine: String?
    let citations: [Citation]
    /// Where that table was read from a picture, for "show me the table" to outline (Plan JN P2).
    var pictureAreas: [ManualTable.PictureArea] = []
}

/// What the technician is asked next.
struct ChainAsk: Equatable {
    let name: String
    let question: String
    let unit: String?
    let isText: Bool
    let range: ClosedRange<Double>?
    /// Why the last answer was not taken, when this is the same question again.
    let again: String?
    let stepIndex: Int
}

/// A running chain: its position, its values and what has been read back so far.
struct ChainState: Equatable {
    /// The index of the next step to run.
    var position = 0
    var values: [String: ChainValue] = [:]
    /// One per completed step, in order: what the read-back says.
    var entries: [Entry] = []
    /// What the chain said: its `say` sentences and its checks' verdicts, in order.
    var said: [String] = []
    /// The checks' verdicts, in order.
    var verdicts: [Bool] = []
    var finished = false
    var stop: ChainStop?

    struct Entry: Equatable {
        let stepIndex: Int
        let line: Int
        let text: String
        /// The rules the step follows, as the chain cites them.
        let rules: [String]
        /// The table page a lookup read, as a `Source:` line.
        let sourceLine: String?
        let citations: [Citation]
        /// The step's lookup used a value read from a picture of a table (Plan JN P2): the mark it
        /// is read back with, which the reading filed on the job keeps as well.
        var pictureMark: String? = nil
    }

    init() {}
}

/// What `advance` hands back: the question to ask, the result, or where it stopped.
enum ChainStep: Equatable {
    case ask(ChainAsk)
    case finished(said: [String])
    case stopped(ChainStop)
}

/// Runs a `ChainDefinition` one step at a time over a `ChainState` (Plan JJ P2).
///
/// It runs lookups, arithmetic, conversions and checks as it reaches them and comes back at every
/// `ask`, so the model asks the technician in its own words while the runner keeps the values. It
/// never continues past a step it could not complete — a table that is not there or could not be
/// read, a row or column that does not resolve, a number between two rows under `exact`, a cell
/// with nothing printed, arithmetic that fails — and says why, with the page to show when there is
/// one. An answer out of the asked range is asked again, never taken.
///
/// Pure: the chain, the state, the answer and the vault's tables in; the state advanced and the
/// next step out.
enum ChainRunner {

    static func advance(_ chain: ChainDefinition, state: inout ChainState, answer: String?,
                        tables: [TableLookup.Source]) -> ChainStep {
        if let stop = state.stop { return .stopped(stop) }
        if state.finished { return .finished(said: state.said) }
        var answer = answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        while state.position < chain.steps.count {
            let index = state.position
            let step = chain.steps[index]
            switch step.kind {
            case .ask(let ask):
                guard let said = answer, !said.isEmpty else { return .ask(question(ask, index: index, again: nil)) }
                answer = nil
                switch accept(said, for: ask, index: index, line: step.line) {
                case .failure(let why):
                    return .ask(question(ask, index: index, again: why.message))
                case .success(let value):
                    state.values[ask.name] = value
                    let shown = value.unit.map { "\(value.text) \($0)" } ?? value.text
                    var text = "\(ask.name): \(shown)"
                    if case .asked(let original) = value.source, original != value.text, !ask.isText {
                        text += " (said as \(original))"
                    }
                    text += ", as the technician said"
                    state.entries.append(.init(stepIndex: index, line: step.line, text: text, rules: step.citations,
                                               sourceLine: nil, citations: []))
                }
            case .lookup(let lookup):
                switch runLookup(lookup, state: state, tables: tables, index: index, line: step.line) {
                case .failure(let stop):
                    state.stop = stop
                    return .stopped(stop)
                case .success(let value):
                    state.values[lookup.name] = value
                    state.entries.append(.init(stepIndex: index, line: step.line, text: lookupEntry(value),
                                               rules: step.citations, sourceLine: value.lookup?.sourceLine,
                                               citations: value.lookup?.citations ?? [],
                                               pictureMark: value.lookup?.pictureMark))
                }
            case .calc(let name, let unit, let expression):
                switch evaluate(expression, state: state) {
                case .failure(let why):
                    let stop = ChainStop(reason: "The calculation for \(name) (\(expression)) could not be done: \(why). "
                                         + "The chain stops here.", stepIndex: index, line: step.line,
                                         sourceLine: nil, citations: [])
                    state.stop = stop
                    return .stopped(stop)
                case .success(let result):
                    let value = ChainValue(name: name, number: result.value, text: display(result.value), unit: unit,
                                           stepIndex: index, line: step.line,
                                           source: .calc(expression: expression, worked: result.worked))
                    state.values[name] = value
                    let text = "\(name) = \(expression) = \(result.worked) = \(display(result.value))"
                        + (unit.map { " \($0)" } ?? "")
                    state.entries.append(.init(stepIndex: index, line: step.line, text: text, rules: step.citations,
                                               sourceLine: nil, citations: []))
                }
            case .convert(let name, let source, let toUnit):
                switch convert(source, to: toUnit, state: state) {
                case .failure(let why):
                    let stop = ChainStop(reason: "\(name) could not be converted to \(toUnit): \(why). The chain stops here.",
                                         stepIndex: index, line: step.line, sourceLine: nil, citations: [])
                    state.stop = stop
                    return .stopped(stop)
                case .success(let converted):
                    state.values[name] = ChainValue(name: name, number: converted.value, text: display(converted.value),
                                                    unit: toUnit, stepIndex: index, line: step.line,
                                                    source: .convert(from: converted.from))
                    state.entries.append(.init(stepIndex: index, line: step.line,
                                               text: "\(name) = \(converted.from) in \(toUnit) = \(display(converted.value)) \(toUnit)",
                                               rules: step.citations, sourceLine: nil, citations: []))
                }
            case .check(let check):
                let left = evaluate(check.left, state: state), right = evaluate(check.right, state: state)
                guard case .success(let l) = left, case .success(let r) = right else {
                    var why = ""
                    if case .failure(let reason) = left { why = reason.message }
                    if case .failure(let reason) = right { why = reason.message }
                    let stop = ChainStop(reason: "The check \(check.left) \(check.comparison.rawValue) \(check.right) "
                                         + "could not be worked: \(why). The chain stops here.",
                                         stepIndex: index, line: step.line, sourceLine: nil, citations: [])
                    state.stop = stop
                    return .stopped(stop)
                }
                let holds = check.comparison.holds(l.value, r.value)
                let sentence = render(holds ? check.ifTrue : check.ifFalse, state: state)
                state.verdicts.append(holds)
                state.said.append(sentence)
                let text = "check \(check.left) \(check.comparison.rawValue) \(check.right): "
                    + "\(display(l.value)) \(check.comparison.rawValue) \(display(r.value)) is \(holds ? "true" : "false") — \(sentence)"
                state.entries.append(.init(stepIndex: index, line: step.line, text: text, rules: step.citations,
                                           sourceLine: nil, citations: []))
            case .say(let template):
                let sentence = render(template, state: state)
                state.said.append(sentence)
                state.entries.append(.init(stepIndex: index, line: step.line, text: "said: \(sentence)",
                                           rules: step.citations, sourceLine: nil, citations: []))
            }
            state.position += 1
        }
        state.finished = true
        return .finished(said: state.said)
    }

    private static func question(_ ask: ChainDefinition.Ask, index: Int, again: String?) -> ChainAsk {
        ChainAsk(name: ask.name, question: ask.question, unit: ask.unit, isText: ask.isText, range: ask.range,
                 again: again, stepIndex: index)
    }

    // MARK: - Answers

    /// The technician's answer as a value, or why it is asked again: not a number, a unit that
    /// measures something else, or outside the range the chain gives.
    static func accept(_ said: String, for ask: ChainDefinition.Ask, index: Int, line: Int)
        -> Result<ChainValue, ChainParser.StepError> {
        if ask.isText {
            return .success(ChainValue(name: ask.name, number: nil, text: said, unit: nil, stepIndex: index, line: line,
                                       source: .asked(said: said)))
        }
        guard let parsed = leadingNumber(in: said) else {
            return .failure(.init("\"\(said)\" is not a number. Ask again for \(ask.name)"
                                  + (ask.unit.map { " in \($0)" } ?? "") + "."))
        }
        let (number, rest) = parsed
        var value = number
        var original = display(number)
        if let asked = ask.unit, UnitConversionTool.knowsUnit(asked), let saidUnit = unitWord(in: rest),
           saidUnit.lowercased() != asked.lowercased() {
            guard let converted = UnitConversionTool.convert(number, from: saidUnit, to: asked) else {
                return .failure(.init("\(display(number)) \(saidUnit) is not something that converts to \(asked). "
                                      + "Ask again for \(ask.name) in \(asked)."))
            }
            original = "\(display(number)) \(saidUnit)"
            value = converted
        }
        if let range = ask.range, !range.contains(value) {
            let unit = ask.unit.map { " \($0)" } ?? ""
            return .failure(.init("\(display(value))\(unit) is outside what this chain takes for \(ask.name) "
                                  + "(\(display(range.lowerBound)) to \(display(range.upperBound))\(unit)). "
                                  + "Ask again; never take it as said."))
        }
        return .success(ChainValue(name: ask.name, number: value, text: display(value), unit: ask.unit,
                                   stepIndex: index, line: line, source: .asked(said: original)))
    }

    /// The first number in the words and what follows it.
    private static func leadingNumber(in text: String) -> (Double, String)? {
        let normalised = text.replacingOccurrences(of: "\u{2212}", with: "-")
        guard let range = normalised.range(of: #"[-+]?\d+(?:[.,]\d+)?"#, options: .regularExpression),
              let number = Double(normalised[range].replacingOccurrences(of: ",", with: ".")) else { return nil }
        return (number, String(normalised[range.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    /// The unit said after a number, when the converter knows it ("°F", "feet", "degrees f").
    private static func unitWord(in rest: String) -> String? {
        let words = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = words.first else { return nil }
        if words.count >= 2, UnitConversionTool.knowsUnit("\(first) \(words[1])") { return "\(first) \(words[1])" }
        if first.lowercased() == "degrees", words.count >= 2, UnitConversionTool.knowsUnit(words[1]) { return words[1] }
        return UnitConversionTool.knowsUnit(first) ? first : nil
    }

    // MARK: - Lookups

    private static func runLookup(_ lookup: ChainDefinition.Lookup, state: ChainState, tables: [TableLookup.Source],
                                  index: Int, line: Int) -> Result<ChainValue, ChainStop> {
        func stop(_ reason: String, page source: TableLookup.Source? = nil,
                  pages: [ManualTable.Page]? = nil) -> Result<ChainValue, ChainStop> {
            let page = source.map { pages ?? [$0.table.page] }
            return .failure(ChainStop(
                reason: reason + " The chain stops here; it never goes on from a guessed cell.",
                stepIndex: index, line: line,
                sourceLine: source.flatMap { s in page.map { TableLookup.sourceLine(documentName: s.documentName, label: s.table.label, pages: $0) } },
                citations: source.flatMap { s in page.map { TableLookup.citations(documentName: s.documentName, label: s.table.label, pages: $0) } } ?? [],
                pictureAreas: source?.table.pictureAreas ?? []))
        }
        let label = ChainDefinition.label(lookup.table)
        let column = lookup.column.map { render($0, state: state, precise: true) }
        let request: TableLookup.Request
        let asked: String
        let outcome: TableLookup.Outcome
        if let cellTemplate = lookup.cell {
            asked = render(cellTemplate, state: state, precise: true)
            let value = singleReference(cellTemplate).flatMap { state.values[$0]?.number } ?? leadingNumber(in: asked)?.0
            guard let value else { return stop("The number to find in \(label) (\(asked)) is not a number.") }
            request = .init(table: label, row: "", column: column)
            switch TableLookup.search(request, value: value, rule: lookup.rule, in: tables) {
            case .found(let found):
                outcome = .found(found)
            case .refused(let refused):
                outcome = refused
            case .none(let source, let columnIndex, let range):
                let name = TableLookup.columnName(source.table.columns[columnIndex])
                let spread = range.map { " (the column runs from \(display($0.lowerBound)) to \(display($0.upperBound)))" } ?? ""
                return stop("No row of \(source.table.displayName) has a value in \(name) \(ruleWords(lookup.rule)) \(display(value))\(spread).",
                            page: source)
            case .several(let source, _, let rows):
                return stop("More than one row of \(source.table.displayName) holds \(display(value)): "
                            + rows.map(TableLookup.rowName).joined(separator: "; ") + ".", page: source)
            }
        } else {
            asked = render(lookup.row ?? "", state: state, precise: true)
            request = .init(table: label, row: asked, column: column)
            outcome = TableLookup.resolve(request, rule: lookup.rule, in: tables)
        }
        let table = { () -> TableLookup.Source? in
            if case .success(let resolved) = TableLookup.resolveTable(request, in: tables) { return resolved.source }
            return nil
        }
        switch outcome {
        case .noTables:
            return stop("No table could be read from the loaded manuals, so \(label) cannot be looked up.")
        case .unclear(let source, let pages, let part):
            // A cell read from a picture never stops a chain; one that could not be read clearly
            // does, naming the page (Plan JN P2).
            return stop("\(source.table.displayName) is printed on " + pages.map(TableLookup.spokenPage).joined(separator: ", ")
                        + " of \(source.documentName) as a picture, and \(TableLookup.unclearReason(part)), so the "
                        + "chain cannot read this step's cell. Show the page and work this step from the book.",
                        page: source, pages: pages)
        case .notExtracted(let source):
            return stop("\(source.table.displayName) is printed on \(TableLookup.spokenPage(source.table.page)) of "
                        + "\(source.documentName), but its grid could not be read, so the chain cannot read its cell. "
                        + "Show the page and work this step from the book.", page: source)
        case .notFound(.table, _, let available):
            return stop("\(label) is not among the tables read from the loaded manuals"
                        + (available.isEmpty ? "." : " (tables read: \(available.joined(separator: "; "))).")
                        + " Load the book that prints it.")
        case .notFound(.document, let asked, _):
            return stop("No loaded manual matches \"\(asked)\".")
        case .notFound(.column, let asked, let available):
            return stop("\(label) has no column \"\(asked)\" (its columns: \(available.joined(separator: "; "))).", page: table())
        case .notFound(.row, let asked, let available):
            let range = available.isEmpty ? "" : " (\(available.joined(separator: "; ")))"
            return stop("No row of \(label) is \(ruleWords(lookup.rule)) \"\(asked)\"\(range).", page: table())
        case .ambiguous(let part, let asked, let candidates):
            return stop("More than one \(part.rawValue) of \(label) fits \"\(asked)\": \(candidates.joined(separator: "; ")). "
                        + "The chain names its \(part.rawValue) too loosely.", page: table())
        case .found(let found):
            if let between = found.between, found.rows.count == 2 {
                return stop("\(display(between)) falls between the rows \(TableLookup.rowName(found.rows[0])) and "
                            + "\(TableLookup.rowName(found.rows[1])) of \(found.source.table.displayName), and this step "
                            + "takes an exact row.", page: found.source)
            }
            guard found.rows.count == 1 else {
                return stop("\(label) gave more than one row for \"\(asked)\".", page: found.source)
            }
            guard found.columns.count == 1 else {
                let names = found.columns.map { TableLookup.columnName(found.source.table.columns[$0]) }
                return stop("\(found.source.table.displayName) has several columns (\(names.joined(separator: "; "))) "
                            + "and the step names none.", page: found.source)
            }
            let record = ChainLookup(found: found, rule: lookup.rule, asked: asked, byCell: lookup.cell != nil)
            guard !record.cell.isEmpty else {
                return stop("Nothing is printed in \(found.source.table.displayName) at row \(record.rowName), "
                            + "column \(record.columnName).", page: found.source)
            }
            let columnUnit = record.columnIndex < record.table.columns.count ? record.table.columns[record.columnIndex].unit : nil
            return .success(ChainValue(name: lookup.name, number: record.cell.value, text: record.cell.text,
                                       unit: record.cell.unit ?? columnUnit, stepIndex: index, line: line,
                                       source: .lookup(record)))
        }
    }

    private static func ruleWords(_ rule: TableLookup.RowRule) -> String {
        switch rule {
        case .exact: return "exactly"
        case .atLeast: return "at least"
        case .atMost: return "at most"
        }
    }

    /// "Table 98 (Correction factors), row 13-15, column Rating group 2 › Band B: 0.86 — page 3 of
    /// Invented Book A (asked for 14, rule at_least)".
    private static func lookupEntry(_ value: ChainValue) -> String {
        guard let lookup = value.lookup else { return "\(value.name): \(value.text)" }
        var text = "\(value.name): \(lookup.table.displayName), row \(lookup.rowName), column \(lookup.columnName): "
            + "\(lookup.cell.text)" + (value.unit.map { " \($0)" } ?? "")
            + " — \(TableLookup.spokenPage(lookup.page)) of \(lookup.documentName)"
        if lookup.byCell {
            text += " (the row whose cell is \(ruleWords(lookup.rule)) \(lookup.asked); rule \(lookup.rule.rawValue))"
        } else {
            text += " (row asked for: \(lookup.asked); rule \(lookup.rule.rawValue))"
        }
        let notes = lookup.notes
        if !notes.isEmpty {
            text += ". Notes: " + notes.map { note in
                (note.marker.map { "[\(TableExtractor.superscripted($0))] " } ?? "") + note.text
            }.joined(separator: " | ")
        }
        if let mark = lookup.pictureMark { text += " — " + mark }
        return text
    }

    // MARK: - Arithmetic

    private static func evaluate(_ expression: String, state: ChainState) -> Result<(value: Double, worked: String), ChainParser.StepError> {
        guard let node = try? ArithmeticExpression.parse(expression) else { return .failure("the expression does not read") }
        for name in ArithmeticExpression.names(in: node) {
            guard let value = state.values[name] else { return .failure("no step has set \(name)") }
            guard value.number != nil else { return .failure("\(name) is \"\(value.text)\", which is not a number") }
        }
        switch ArithmeticExpression.evaluate(node, value: { state.values[$0]?.number }) {
        case .success(let result):
            let worked = (try? ArithmeticExpression.tokens(expression))?.map { token -> String in
                if case .name(let name) = token.kind, let number = state.values[name]?.number { return display(number) }
                return token.text
            }.joined(separator: " ") ?? expression
            return .success((result, worked))
        case .failure(.divisionByZero): return .failure("it divides by zero")
        case .failure(.unknownName(let name)): return .failure("no step has set \(name)")
        case .failure(.notFinite): return .failure("the result is not a number")
        }
    }

    private static func convert(_ source: String, to unit: String, state: ChainState) -> Result<(value: Double, from: String), ChainParser.StepError> {
        let number: Double, fromUnit: String
        if ChainParser.isName(source) {
            guard let value = state.values[source] else { return .failure("no step has set \(source)") }
            guard let n = value.number else { return .failure("\(source) is \"\(value.text)\", which is not a number") }
            guard let u = value.unit, !u.isEmpty else { return .failure("\(source) has no unit to convert from") }
            number = n
            fromUnit = u
        } else {
            guard let parsed = leadingNumber(in: source), !parsed.1.isEmpty else { return .failure("\(source) has no unit") }
            number = parsed.0
            fromUnit = parsed.1
        }
        guard let converted = UnitConversionTool.convert(number, from: fromUnit, to: unit) else {
            return .failure("\(fromUnit) does not convert to \(unit)")
        }
        return .success((converted, "\(display(number)) \(fromUnit)"))
    }

    // MARK: - Templates

    /// A template with its `{name}` and `{name.attribute}` filled in. `precise` writes numbers to
    /// six places, for a value handed to a lookup; otherwise they are said to two.
    static func render(_ template: String, state: ChainState, precise: Bool = false) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z]+))?\}"#) else {
            return template
        }
        let ns = template as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = ns.substring(with: match.range(at: 1))
            let attribute = match.range(at: 2).location == NSNotFound ? nil : ns.substring(with: match.range(at: 2)).lowercased()
            out += text(of: state.values[name], attribute: attribute, precise: precise) ?? ns.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    private static func text(of value: ChainValue?, attribute: String?, precise: Bool) -> String? {
        guard let value else { return nil }
        switch attribute {
        case nil:
            if case .lookup = value.source { return value.text }
            if case .asked = value.source, value.number == nil { return value.text }
            return value.number.map { precise ? preciseText($0) : display($0) } ?? value.text
        case "unit": return value.unit ?? ""
        case "row": return value.lookup?.rowName
        case "column": return value.lookup?.columnName
        case "table": return value.lookup?.table.displayName
        case "page": return value.lookup.map { TableLookup.spokenPage($0.page) }
        case "next": return value.lookup.map { $0.next ?? "none (it is the last row)" }
        default: return nil
        }
    }

    /// The name a template is when it is nothing but `{name}`.
    private static func singleReference(_ template: String) -> String? {
        let trimmed = template.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        let inner = String(trimmed.dropFirst().dropLast())
        return ChainParser.isName(inner) ? inner : nil
    }

    /// A number as the chain says it: whole numbers plain, else to two places ("37.21").
    static func display(_ value: Double) -> String {
        format(value, places: 2)
    }

    private static func preciseText(_ value: Double) -> String { format(value, places: 6) }

    private static func format(_ value: Double, places: Int) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        var text = String(format: "%.\(places)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: - Read-back

    /// The chain read back step by step, each lookup with its table, row, column and page and each
    /// step with the rule it cites — what lands on the job as a reading.
    static func readBack(_ chain: ChainDefinition, state: ChainState) -> String {
        var lines = ["Chain: \(chain.name)"]
        for (number, entry) in state.entries.enumerated() {
            var line = "\(number + 1). \(entry.text)"
            if !entry.rules.isEmpty { line += " — follows \(entry.rules.joined(separator: ", "))" }
            lines.append(line)
        }
        if let stop = state.stop {
            lines.append("Stopped at step \(stop.stepIndex + 1) of \(chain.steps.count): \(stop.reason)")
        } else if state.finished {
            lines.append("Result: " + state.said.joined(separator: " "))
        } else {
            lines.append("Not finished: at step \(state.position + 1) of \(chain.steps.count).")
        }
        return lines.joined(separator: "\n")
    }

    /// Every `Source:` line the chain's lookups cite, once each, in order.
    static func sourceLines(_ state: ChainState) -> [String] {
        var out: [String] = []
        for line in state.entries.compactMap(\.sourceLine) + [state.stop?.sourceLine].compactMap({ $0 })
        where !out.contains(line) {
            out.append(line)
        }
        return out
    }

    /// The marks of the steps whose lookups used a value read from a picture (Plan JN P2), once
    /// each, in order: what the reading filed on the job keeps beside the read-back.
    static func pictureMarks(_ state: ChainState) -> [String] {
        var out: [String] = []
        for mark in state.entries.compactMap(\.pictureMark) where !out.contains(mark) { out.append(mark) }
        return out
    }

    /// Every citation the chain's lookups make, once each.
    static func citations(_ state: ChainState) -> [Citation] {
        var out: [Citation] = []
        for citation in state.entries.flatMap(\.citations) + (state.stop?.citations ?? []) where !out.contains(citation) {
            out.append(citation)
        }
        return out
    }
}
