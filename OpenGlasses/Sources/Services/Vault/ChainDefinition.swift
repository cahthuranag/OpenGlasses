import Foundation

/// A rule chain an organisation wrote in its vault's `chains.md` (Plan JJ P2, decision 3): the
/// values to ask the technician for, the table cells to look up, the arithmetic, the comparison and
/// what to say, in order, against the table and rule numbers of *its* code and edition. The app
/// ships the schema, the runner and an invented example, and no rule.
///
/// One chain is a `##` heading — its name — with an `Answers:` line saying what it answers and its
/// steps, one per line, in a fenced block or as a list. The vocabulary is fixed and small so an
/// electrician can write one in a text editor:
///
/// ```text
/// ask <name> (<unit>) range <a>..<b>: <what to ask>      a value from the technician
/// ask <name> (text): <what to ask>                        words, e.g. a size as printed
/// lookup <name> = <table> row <row> column <column> rule <exact|at_least|at_most>
/// lookup <name> = <table> column <column> cell <number> rule <exact|at_least|at_most>
/// calc <name> (<unit>) = <expression over names>
/// convert <name> = <name or number unit> to <unit>
/// check <expression> <op> <expression> ? "<if true>" : "<if false>"
/// cite <the rule the step above follows, as printed>
/// say "<the result, with {name} for a value>"
/// ```
///
/// Pure value types; `ChainParser` reads and writes them.
struct ChainDefinition: Equatable {

    /// What the chain is called, from its heading.
    var name: String
    /// What it answers, from its `Answers:` line (or its first line of prose).
    var answers: String
    var steps: [Step]
    /// The heading's line in the file.
    var line: Int

    struct Step: Equatable {
        var kind: Kind
        /// The rules `cite` lines attached to this step, as printed.
        var citations: [String]
        /// The step's line in the file.
        var line: Int

        init(kind: Kind, citations: [String] = [], line: Int = 0) {
            self.kind = kind
            self.citations = citations
            self.line = line
        }

        /// Equal when they say the same thing, wherever they are written.
        static func == (lhs: Step, rhs: Step) -> Bool { lhs.kind == rhs.kind && lhs.citations == rhs.citations }
    }

    enum Kind: Equatable {
        case ask(Ask)
        case lookup(Lookup)
        case calc(name: String, unit: String?, expression: String)
        /// `source` is a name, or a number with its unit ("100 ft").
        case convert(name: String, source: String, toUnit: String)
        case check(Check)
        case say(String)
    }

    struct Ask: Equatable {
        var name: String
        /// Nil for a number with no unit.
        var unit: String?
        /// The technician's words rather than a number.
        var isText: Bool
        var range: ClosedRange<Double>?
        var question: String
    }

    struct Lookup: Equatable {
        var name: String
        /// The table's label as printed ("Table 99").
        var table: String
        /// The row to read, by its heading or a number (the `row` form).
        var row: String?
        /// The number to find in the column (the `cell` form): the row is the one whose cell meets it.
        var cell: String?
        var column: String?
        var rule: TableLookup.RowRule
    }

    struct Check: Equatable {
        var left: String
        var comparison: Comparison
        var right: String
        var ifTrue: String
        var ifFalse: String
    }

    enum Comparison: String, CaseIterable, Equatable {
        case lessOrEqual = "<="
        case greaterOrEqual = ">="
        case notEqual = "!="
        case equal = "=="
        case less = "<"
        case greater = ">"

        func holds(_ left: Double, _ right: Double) -> Bool {
            switch self {
            case .lessOrEqual: return left <= right
            case .greaterOrEqual: return left >= right
            case .notEqual: return left != right
            case .equal: return left == right
            case .less: return left < right
            case .greater: return left > right
            }
        }
    }

    static func == (lhs: ChainDefinition, rhs: ChainDefinition) -> Bool {
        lhs.name == rhs.name && lhs.answers == rhs.answers && lhs.steps == rhs.steps
    }

    /// The labels of the tables the chain's lookups read, as the vault's tables are labelled
    /// ("Table 99"), in order, once each.
    var tableLabels: [String] {
        var out: [String] = []
        for step in steps {
            guard case .lookup(let lookup) = step.kind else { continue }
            let label = Self.label(lookup.table)
            if !out.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) { out.append(label) }
        }
        return out
    }

    /// A table as a chain names it, as a stored table is labelled.
    static func label(_ table: String) -> String {
        TableReference.labels(in: table).first ?? table.trimmingCharacters(in: .whitespaces)
    }

    /// The tables the chain names that `available` does not hold (labels compared without case).
    func missingTables(available: [String]) -> [String] {
        tableLabels.filter { label in !available.contains { $0.caseInsensitiveCompare(label) == .orderedSame } }
    }

    /// The step that sets `name`, if any.
    func step(setting name: String) -> Step? {
        steps.first { $0.kind.setsName == name }
    }

    /// The number of steps that ask the technician.
    var askCount: Int { steps.filter { if case .ask = $0.kind { return true } else { return false } }.count }
}

extension ChainDefinition.Kind {
    /// The name the step sets, for those that set one.
    var setsName: String? {
        switch self {
        case .ask(let ask): return ask.name
        case .lookup(let lookup): return lookup.name
        case .calc(let name, _, _), .convert(let name, _, _): return name
        case .check, .say: return nil
        }
    }
}

// MARK: - Parsing and writing

/// Reads `chains.md` into chains, and writes chains back so a file round-trips. Every problem it
/// finds names its line, so an author can fix a chain in a text editor (Plan JJ P2). A chain with
/// a problem is not offered; the rest of the file still is.
enum ChainParser {

    struct Problem: Equatable, CustomStringConvertible {
        let line: Int
        /// The chain the problem is in, when it is inside one.
        let chain: String?
        let message: String

        var description: String { "line \(line): " + (chain.map { "\($0): " } ?? "") + message }
    }

    struct Parsed: Equatable {
        /// The chains with no problem.
        var chains: [ChainDefinition]
        var problems: [Problem]
    }

    /// The attributes a `{name.attribute}` may read: a looked-up value's row, column, table, page
    /// and the row after it; any value's unit.
    static let lookupAttributes: Set<String> = ["row", "column", "table", "page", "next"]
    static let anyAttributes: Set<String> = ["unit"]

    static let keywords = ["ask", "lookup", "calc", "convert", "check", "cite", "say"]

    // MARK: Reading

    static func parse(_ markdown: String) -> Parsed {
        var chains: [ChainDefinition] = []
        var problems: [Problem] = []

        struct Draft {
            var name: String
            var line: Int
            var answers: String?
            var prose: String?
            var stepLines: [(text: String, line: Int)] = []
        }
        var draft: Draft?
        var inFence = false
        var fenceLine = 0

        func finish() {
            guard let done = draft else { return }
            draft = nil
            let (chain, found) = build(name: done.name, line: done.line, answers: done.answers ?? done.prose ?? "",
                                       stepLines: done.stepLines)
            problems += found
            guard let chain, found.isEmpty else { return }
            if chains.contains(where: { $0.name.caseInsensitiveCompare(chain.name) == .orderedSame }) {
                problems.append(Problem(line: chain.line, chain: chain.name, message: "another chain already has this name"))
            } else {
                chains.append(chain)
            }
        }

        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, raw) in lines.enumerated() {
            let number = offset + 1
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                fenceLine = number
                if inFence, draft == nil {
                    problems.append(Problem(line: number, chain: nil, message: "steps outside a chain: put them under a ## heading"))
                }
                continue
            }
            if inFence {
                guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }
                draft?.stepLines.append((trimmed, number))
                continue
            }
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if level == 2 {
                    finish()
                    if title.isEmpty {
                        problems.append(Problem(line: number, chain: nil, message: "a chain heading needs a name"))
                    } else {
                        draft = Draft(name: title, line: number)
                    }
                }
                continue
            }
            guard draft != nil, !trimmed.isEmpty else { continue }
            if let item = listItem(trimmed) {
                draft?.stepLines.append((item, number))
            } else if line.hasPrefix("    ") || line.hasPrefix("\t") {
                draft?.stepLines.append((trimmed, number))
            } else if trimmed.lowercased().hasPrefix("answers:") {
                draft?.answers = trimmed.dropFirst("answers:".count).trimmingCharacters(in: .whitespaces)
            } else if draft?.prose == nil {
                draft?.prose = trimmed
            }
        }
        if inFence {
            problems.append(Problem(line: fenceLine, chain: draft?.name, message: "a ``` block is not closed"))
        }
        finish()
        return Parsed(chains: chains, problems: problems.sorted { $0.line < $1.line })
    }

    /// "- ask …", "* ask …", "1. ask …" → "ask …".
    private static func listItem(_ trimmed: String) -> String? {
        if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
            return trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        }
        if let match = trimmed.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) {
            return String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// One chain from its heading and its step lines, with every problem found.
    private static func build(name: String, line: Int, answers: String,
                              stepLines: [(text: String, line: Int)]) -> (ChainDefinition?, [Problem]) {
        var problems: [Problem] = []
        func problem(_ line: Int, _ message: String) { problems.append(Problem(line: line, chain: name, message: message)) }

        var steps: [ChainDefinition.Step] = []
        for (text, number) in stepLines {
            switch parseStep(text) {
            case .failure(let message):
                problem(number, message.message)
            case .success(.cite(let rule)):
                if steps.isEmpty {
                    problem(number, "'cite' attaches a rule to the step above it, and there is none")
                } else {
                    steps[steps.count - 1].citations.append(rule)
                }
            case .success(.step(let kind)):
                steps.append(ChainDefinition.Step(kind: kind, line: number))
            }
        }
        guard !stepLines.isEmpty else {
            problem(line, "the chain has no steps")
            return (nil, problems)
        }

        // Every name read is set by an earlier step, once; every attribute is one the value has.
        var lookups = Set<String>()
        var defined = Set<String>()
        func checkReads(_ reads: [(name: String, attribute: String?)], at number: Int) {
            for read in reads {
                guard defined.contains(read.name) else {
                    problem(number, "'\(read.name)' is used before any step sets it")
                    continue
                }
                if let attribute = read.attribute {
                    if lookupAttributes.contains(attribute) {
                        if !lookups.contains(read.name) {
                            problem(number, "'\(read.name).\(attribute)' needs a value a lookup set")
                        }
                    } else if !anyAttributes.contains(attribute) {
                        problem(number, "'\(read.name).\(attribute)' is not something a value has: use row, column, table, page, next or unit")
                    }
                }
            }
        }
        var says = false
        for step in steps {
            let number = step.line
            switch step.kind {
            case .ask:
                break
            case .lookup(let lookup):
                if lookup.table.contains("{") {
                    problem(number, "the table must be named as printed, not from a value, so the import can check it")
                }
                for part in [lookup.row, lookup.cell, lookup.column].compactMap({ $0 }) {
                    switch templateReads(part) {
                    case .success(let reads): checkReads(reads, at: number)
                    case .failure(let message): problem(number, message.message)
                    }
                }
            case .calc(_, _, let expression):
                if let node = try? ArithmeticExpression.parse(expression) {
                    checkReads(ArithmeticExpression.names(in: node).map { ($0, nil) }, at: number)
                }
            case .convert(_, let source, _):
                if isName(source) { checkReads([(source, nil)], at: number) }
            case .check(let check):
                says = true
                for side in [check.left, check.right] {
                    if let node = try? ArithmeticExpression.parse(side) {
                        checkReads(ArithmeticExpression.names(in: node).map { ($0, nil) }, at: number)
                    }
                }
                for text in [check.ifTrue, check.ifFalse] {
                    switch templateReads(text) {
                    case .success(let reads): checkReads(reads, at: number)
                    case .failure(let message): problem(number, message.message)
                    }
                }
            case .say(let text):
                says = true
                switch templateReads(text) {
                case .success(let reads): checkReads(reads, at: number)
                case .failure(let message): problem(number, message.message)
                }
            }
            if let set = step.kind.setsName {
                if defined.contains(set) {
                    let first = steps.first { $0.kind.setsName == set }?.line ?? 0
                    problem(number, "'\(set)' is already set by line \(first)")
                }
                defined.insert(set)
                if case .lookup = step.kind { lookups.insert(set) }
            }
        }
        if !says, !steps.isEmpty {
            problem(steps.last?.line ?? line, "the chain says nothing: end it with a 'say' or a 'check'")
        }
        let chain = ChainDefinition(name: name, answers: answers, steps: steps, line: line)
        return (problems.isEmpty ? chain : nil, problems)
    }

    /// One `lookup` step line read on its own ("lookup band = Table 90 row {n} column Band rule
    /// exact"), as `parse` reads it, or nil when it is not a lookup that reads. For a checker that
    /// looks at every lookup in a file, those in a chain with a problem elsewhere included
    /// (`Scripts/chains-validate`).
    static func lookupStep(_ text: String) -> ChainDefinition.Lookup? {
        guard case .success(.step(.lookup(let lookup))) = parseStep(text.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return lookup
    }

    private enum Parsed1 {
        case step(ChainDefinition.Kind)
        case cite(String)
    }

    private static let identifier = #"[A-Za-z_][A-Za-z0-9_]*"#

    static func isName(_ text: String) -> Bool {
        text.range(of: "^" + identifier + "$", options: .regularExpression) != nil
    }

    /// One step line, or what is wrong with it.
    private static func parseStep(_ text: String) -> Result<Parsed1, StepError> {
        let keyword = text.prefix { !$0.isWhitespace }.lowercased()
        let rest = text.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
        switch keyword {
        case "ask": return parseAsk(rest).map { .step(.ask($0)) }
        case "lookup": return parseLookup(rest).map { .step(.lookup($0)) }
        case "calc": return parseCalc(rest).map { .step($0) }
        case "convert": return parseConvert(rest).map { .step($0) }
        case "check": return parseCheck(rest).map { .step(.check($0)) }
        case "cite":
            return rest.isEmpty ? .failure("'cite' needs the rule as printed, e.g. cite Rule 1-2") : .success(.cite(rest))
        case "say":
            guard let said = quoted(rest), said.rest.isEmpty else {
                return .failure("'say' needs its sentence in double quotes: say \"Use {size}.\"")
            }
            return .success(.step(.say(said.text)))
        default:
            return .failure(StepError("unknown step '\(keyword)': a step begins with " + keywords.joined(separator: ", ")))
        }
    }

    /// A problem's text, as an error so it can travel in a `Result`.
    struct StepError: Error, Equatable, ExpressibleByStringInterpolation, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        init(stringLiteral value: String) { self.message = value }
        var description: String { message }
    }

    private static func match(_ text: String, _ pattern: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<found.numberOfRanges).map { index in
            Range(found.range(at: index), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
        }
    }

    private static func parseAsk(_ rest: String) -> Result<ChainDefinition.Ask, StepError> {
        let number = #"[-+]?\d+(?:\.\d+)?"#
        guard let parts = match(rest, "^(" + identifier + #")\s*(?:\(([^)]*)\))?\s*(?:range\s+("# + number
                                + #")\s*\.\.\s*("# + number + #"))?\s*:\s*(.*)$"#) else {
            return .failure(StepError("an ask is: ask <name> (<unit>) range <low>..<high>: <what to ask>"))
        }
        let name = parts[0] ?? ""
        let unit = parts[1].flatMap { $0.isEmpty ? nil : $0 }
        let isText = unit?.lowercased() == "text"
        let question = parts[4] ?? ""
        guard !question.isEmpty else { return .failure(StepError("the ask for '\(name)' says nothing to ask after the colon")) }
        var range: ClosedRange<Double>?
        if let low = parts[2].flatMap(Double.init), let high = parts[3].flatMap(Double.init) {
            guard low <= high else { return .failure(StepError("the range \(parts[2] ?? "")..\(parts[3] ?? "") runs backwards")) }
            guard !isText else { return .failure(StepError("an ask for words has no range")) }
            range = low...high
        }
        return .success(.init(name: name, unit: isText ? nil : unit, isText: isText, range: range, question: question))
    }

    private static func parseLookup(_ rest: String) -> Result<ChainDefinition.Lookup, StepError> {
        let rules = TableLookup.RowRule.allCases.map(\.rawValue).joined(separator: "|")
        let head = "^(" + identifier + #")\s*=\s*(.+?)\s+"#
        if let parts = match(rest, head + #"column\s+(.+?)\s+cell\s+(.+?)\s+rule\s+(\S+)$"#) {
            guard let rule = TableLookup.RowRule(rawValue: (parts[4] ?? "").lowercased()) else {
                return .failure(StepError("the rule '\(parts[4] ?? "")' is not one of \(rules.replacingOccurrences(of: "|", with: ", "))"))
            }
            return .success(.init(name: parts[0] ?? "", table: parts[1] ?? "", row: nil, cell: parts[3],
                                  column: parts[2], rule: rule))
        }
        if let parts = match(rest, head + #"row\s+(.+?)(?:\s+column\s+(.+?))?\s+rule\s+(\S+)$"#) {
            guard let rule = TableLookup.RowRule(rawValue: (parts[4] ?? "").lowercased()) else {
                return .failure(StepError("the rule '\(parts[4] ?? "")' is not one of \(rules.replacingOccurrences(of: "|", with: ", "))"))
            }
            return .success(.init(name: parts[0] ?? "", table: parts[1] ?? "", row: parts[2], cell: nil,
                                  column: parts[3].flatMap { $0.isEmpty ? nil : $0 }, rule: rule))
        }
        return .failure(StepError("a lookup is: lookup <name> = <table> row <row> column <column> rule <exact|at_least|at_most>, "
                                  + "or lookup <name> = <table> column <column> cell <number> rule <…>"))
    }

    private static func parseCalc(_ rest: String) -> Result<ChainDefinition.Kind, StepError> {
        guard let parts = match(rest, "^(" + identifier + #")\s*(?:\(([^)]*)\))?\s*=\s*(.+)$"#) else {
            return .failure(StepError("a calc is: calc <name> (<unit>) = <expression>"))
        }
        let expression = parts[2] ?? ""
        do {
            _ = try ArithmeticExpression.parse(expression)
        } catch let error as ArithmeticExpression.ParseError {
            return .failure(StepError("the expression does not read: \(error.description)"))
        } catch {
            return .failure(StepError("the expression does not read"))
        }
        return .success(.calc(name: parts[0] ?? "", unit: parts[1].flatMap { $0.isEmpty ? nil : $0 }, expression: expression))
    }

    private static func parseConvert(_ rest: String) -> Result<ChainDefinition.Kind, StepError> {
        guard let parts = match(rest, "^(" + identifier + #")\s*=\s*(.+?)\s+to\s+(.+)$"#) else {
            return .failure(StepError("a convert is: convert <name> = <name> to <unit>"))
        }
        let source = parts[1] ?? "", toUnit = parts[2] ?? ""
        guard UnitConversionTool.knowsUnit(toUnit) else { return .failure(StepError("'\(toUnit)' is not a unit the converter knows")) }
        if !isName(source) {
            guard let literal = match(source, #"^[-+]?\d+(?:\.\d+)?\s*(.+)$"#), let unit = literal[0],
                  UnitConversionTool.knowsUnit(unit) else {
                return .failure(StepError("convert a named value, or a number with a unit the converter knows"))
            }
        }
        return .success(.convert(name: parts[0] ?? "", source: source, toUnit: toUnit))
    }

    private static func parseCheck(_ rest: String) -> Result<ChainDefinition.Check, StepError> {
        let shape = StepError("a check is: check <expression> <op> <expression> ? \"<if true>\" : \"<if false>\"")
        guard let question = rest.firstIndex(of: "?") else { return .failure(shape) }
        let condition = rest[..<question].trimmingCharacters(in: .whitespaces)
        guard let ifTrue = quoted(String(rest[rest.index(after: question)...])),
              ifTrue.rest.hasPrefix(":"),
              let ifFalse = quoted(String(ifTrue.rest.dropFirst())), ifFalse.rest.isEmpty else { return .failure(shape) }
        // The comparison: the longest operator first, so "<=" is not read as "<".
        let operators: [(String, ChainDefinition.Comparison)] = [("<=", .lessOrEqual), (">=", .greaterOrEqual),
                                                                 ("!=", .notEqual), ("==", .equal),
                                                                 ("<", .less), (">", .greater), ("=", .equal)]
        for (symbol, comparison) in operators {
            guard let range = condition.range(of: symbol) else { continue }
            let left = condition[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let right = condition[range.upperBound...].trimmingCharacters(in: .whitespaces)
            for side in [left, right] {
                do { _ = try ArithmeticExpression.parse(side) } catch let error as ArithmeticExpression.ParseError {
                    return .failure(StepError("the comparison does not read: \(error.description)"))
                } catch { return .failure(shape) }
            }
            return .success(.init(left: left, comparison: comparison, right: right,
                                  ifTrue: ifTrue.text, ifFalse: ifFalse.text))
        }
        return .failure(StepError("a check compares two values with <, <=, >, >=, == or !="))
    }

    /// `"text" rest` → (text, rest), or nil when the text does not open and close a quote.
    private static func quoted(_ text: String) -> (text: String, rest: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\"") else { return nil }
        let body = trimmed.dropFirst()
        guard let close = body.firstIndex(of: "\"") else { return nil }
        return (String(body[..<close]), body[body.index(after: close)...].trimmingCharacters(in: .whitespaces))
    }

    /// The `{name}` and `{name.attribute}` references in a template.
    static func templateReads(_ text: String) -> Result<[(name: String, attribute: String?)], StepError> {
        guard let regex = try? NSRegularExpression(pattern: #"\{(\#(identifier))(?:\.([A-Za-z]+))?\}"#) else {
            return .success([])
        }
        let ns = text as NSString
        var reads: [(String, String?)] = []
        var leftover = text
        for found in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: found.range(at: 1))
            let attribute = found.range(at: 2).location == NSNotFound ? nil : ns.substring(with: found.range(at: 2)).lowercased()
            reads.append((name, attribute))
            leftover = leftover.replacingOccurrences(of: ns.substring(with: found.range), with: "")
        }
        if leftover.contains("{") || leftover.contains("}") {
            return .failure(StepError("a value in braces is written {name} or {name.row}"))
        }
        return .success(reads)
    }

    // MARK: Writing

    /// The chains as a `chains.md` reads them back: each a heading, its `Answers:` line and a
    /// fenced block of steps.
    static func render(_ chains: [ChainDefinition], title: String = "Rule chains") -> String {
        var lines = ["# \(title)", ""]
        for chain in chains {
            lines.append("## \(chain.name)")
            if !chain.answers.isEmpty { lines.append("Answers: \(chain.answers)") }
            lines.append("")
            lines.append("```chain")
            for step in chain.steps {
                lines.append(text(of: step.kind))
                lines += step.citations.map { "cite \($0)" }
            }
            lines.append("```")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// One step as it is written.
    static func text(of kind: ChainDefinition.Kind) -> String {
        switch kind {
        case .ask(let ask):
            var text = "ask \(ask.name)"
            if ask.isText { text += " (text)" } else if let unit = ask.unit { text += " (\(unit))" }
            if let range = ask.range { text += " range \(number(range.lowerBound))..\(number(range.upperBound))" }
            return text + ": \(ask.question)"
        case .lookup(let lookup):
            var text = "lookup \(lookup.name) = \(lookup.table)"
            if let cell = lookup.cell {
                text += " column \(lookup.column ?? "") cell \(cell)"
            } else {
                text += " row \(lookup.row ?? "")"
                if let column = lookup.column { text += " column \(column)" }
            }
            return text + " rule \(lookup.rule.rawValue)"
        case .calc(let name, let unit, let expression):
            return "calc \(name)" + (unit.map { " (\($0))" } ?? "") + " = \(expression)"
        case .convert(let name, let source, let toUnit):
            return "convert \(name) = \(source) to \(toUnit)"
        case .check(let check):
            return "check \(check.left) \(check.comparison.rawValue) \(check.right) ? \"\(check.ifTrue)\" : \"\(check.ifFalse)\""
        case .say(let text):
            return "say \"\(text)\""
        }
    }

    /// A number as a chain writes it: "1", "0.5".
    static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }
}

// MARK: - A vault's chains

/// The chains a vault's `chains.md` offers (Plan JJ P2), read from the vault's core files. The
/// file is a core file the organisation writes by hand and lists in `files`; it is not loaded into
/// the prompt as reference text — the session offers its chains by name and the runner reads them.
struct VaultChains: Equatable {
    static let fileName = "chains.md"

    let chains: [ChainDefinition]
    let problems: [ChainParser.Problem]

    static func isChainsFile(_ filename: String) -> Bool {
        (filename as NSString).lastPathComponent.lowercased() == fileName
    }

    init(chains: [ChainDefinition] = [], problems: [ChainParser.Problem] = []) {
        self.chains = chains
        self.problems = problems
    }

    init(files: [(filename: String, contents: String)]) {
        var chains: [ChainDefinition] = []
        var problems: [ChainParser.Problem] = []
        for file in files where Self.isChainsFile(file.filename) {
            let parsed = ChainParser.parse(file.contents)
            chains += parsed.chains
            problems += parsed.problems
        }
        self.init(chains: chains, problems: problems)
    }

    init(store: VaultStore) {
        self.init(files: store.manifest.files.filter(Self.isChainsFile).compactMap { name in
            store.read(name).map { (name, $0) }
        })
    }

    /// The chain the words name: its name exactly, else the one whose name holds every asked word,
    /// else nil (or several, to ask which).
    func chains(named words: String) -> [ChainDefinition] {
        let asked = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return [] }
        if let exact = chains.first(where: { $0.name.caseInsensitiveCompare(asked) == .orderedSame }) { return [exact] }
        let wanted = TableLookup.significantWords(asked)
        guard !wanted.isEmpty else { return [] }
        let holding = chains.filter { wanted.isSubset(of: TableLookup.significantWords($0.name + " " + $0.answers)) }
        if !holding.isEmpty { return holding }
        let scored = chains.map { ($0, wanted.intersection(TableLookup.significantWords($0.name)).count) }
        guard let best = scored.map(\.1).max(), best > 0 else { return [] }
        return scored.filter { $0.1 == best }.map(\.0)
    }
}
