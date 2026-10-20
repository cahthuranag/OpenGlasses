import Foundation

/// Where a chain the session runs came from (Plan JJ P3). An authored chain is the organisation's
/// own, from its vault's `chains.md`; a proposed one the model wrote on this job from the passages
/// it retrieved; a kept one is a proposed chain the technician kept on this phone. Neither of the
/// last two has been reviewed by anybody, and everything that says or files them says so.
enum ChainOrigin: String, Codable, Equatable {
    case authored
    case proposed
    case kept

    /// How the chain is marked wherever it is listed, said or filed. Nil for an authored chain.
    var marking: String? {
        switch self {
        case .authored: return nil
        case .proposed: return "proposed, unreviewed"
        case .kept: return "unreviewed — kept on this phone"
        }
    }
}

/// A chain the model proposes for a question no authored chain answers (Plan JJ P3, decision 4),
/// checked before the technician hears it.
///
/// The model retrieves the clauses first (`manual_lookup`, its clause and table routes) and writes
/// the steps it reads there in the P2 syntax, with the passage each lookup came from. A proposal is
/// accepted only when:
///
/// - it reads as exactly one chain under `ChainParser` (the same parser `chains.md` goes through);
/// - every `lookup` and every `check` carries a `cite` line, and the proposal cites something;
/// - every lookup names the passage it came from, and that passage is one retrieved on this job;
/// - every rule it cites is printed in a passage retrieved on this job — a rule the passages do not
///   contain is one the model brought from memory, and the proposal is refused for it.
///
/// A lookup naming a table the vault has not extracted is accepted and marked "needs Table N", as
/// the validator marks an authored one: the chain stops at that step with the reason.
///
/// Pure: the text, the sources, the passages and the vault's table labels in; the proposal or the
/// refusal out.
struct ChainProposal: Equatable {

    /// A passage retrieved on this job, as a proposal is checked against it.
    struct Passage: Equatable {
        let documentName: String
        let page: Int?
        let section: String?
        let text: String

        init(documentName: String, page: Int?, section: String?, text: String) {
            self.documentName = documentName
            self.page = page
            self.section = section
            self.text = text
        }

        init(_ retrieved: AnswerSourceMemory.Retrieved) {
            self.init(documentName: retrieved.documentName, page: retrieved.page, section: retrieved.section,
                      text: retrieved.text)
        }

        /// "Invented Book A, page 4, §QR-14" — the form a `Source:` line names it by.
        var citation: String {
            var parts = [documentName]
            if let page { parts.append("page \(page)") }
            if let section, !section.isEmpty { parts.append("§\(section)") }
            return parts.joined(separator: ", ")
        }
    }

    /// What a proposal is checked against: the passages retrieved on this job, the labels of the
    /// tables the vault's manuals print (read or not), and the names of the chains already offered.
    struct Context: Equatable {
        var passages: [Passage]
        var tableLabels: [String]
        var takenNames: [String]

        init(passages: [Passage], tableLabels: [String], takenNames: [String] = []) {
            self.passages = passages
            self.tableLabels = tableLabels
            self.takenNames = takenNames
        }
    }

    enum Refusal: Error, Equatable {
        case noName
        case doesNotRead([String])
        case notOneChain(Int)
        case nameTaken(String)
        case noPassages
        case citesNothing
        case uncited([String])
        case missingSource([String])
        case sourceNotRetrieved(lookup: String, source: String)
        case ruleNotInPassages([String])
        case noSuchStep(Int, count: Int)

        /// What the model is told. Nothing was proposed to the technician when it hears this.
        var message: String {
            switch self {
            case .noName:
                return "Give the proposed chain a name ('name'), or start its text with a ## heading."
            case .doesNotRead(let problems):
                return "The proposed chain does not read: " + problems.prefix(4).joined(separator: "; ")
                    + ". Write it in the chain syntax and propose it again."
            case .notOneChain(let count):
                return "Propose one chain at a time; the text holds \(count)."
            case .nameTaken(let name):
                return "A chain called '\(name)' is already offered: start it with rule_chain, or give this one another name."
            case .noPassages:
                return "Nothing has been retrieved on this job to build a chain from. Retrieve the clauses first "
                    + "with manual_lookup (and the table with table_lookup), then propose the chain from what they say."
            case .citesNothing:
                return "The proposed chain cites nothing. Every lookup and every check needs a 'cite' line naming the "
                    + "rule it follows, as the retrieved passage prints it."
            case .uncited(let steps):
                return "These steps cite no rule: " + steps.joined(separator: "; ")
                    + ". Add a 'cite' line under each, naming the rule as the retrieved passage prints it."
            case .missingSource(let lookups):
                return "Name the retrieved passage each lookup came from ('sources', one per lookup, in order, as its "
                    + "Source line reads): none given for " + lookups.joined(separator: ", ") + "."
            case .sourceNotRetrieved(let lookup, let source):
                return "The source given for '\(lookup)' (\(source)) is not a passage retrieved on this job. Name a "
                    + "passage manual_lookup returned, by its Source line, or retrieve the clause first."
            case .ruleNotInPassages(let rules):
                return "The retrieved passages do not contain " + rules.joined(separator: ", ")
                    + ". Propose only steps the passages say; never a rule from memory. Retrieve that rule first, or leave it out."
            case .noSuchStep(let number, let count):
                return "The proposed chain has no step \(number); it has \(count)."
            }
        }
    }

    let chain: ChainDefinition
    /// The passage each lookup came from, by the lookup's value name, as the model gave it.
    let sources: [String: String]
    /// The tables a lookup names that no manual in the vault prints as a table the app found.
    let missingTables: [String]

    // MARK: - Making one

    /// A proposal from the model's text: one chain in the P2 syntax, under a `##` heading or with
    /// `name` (and `answers`) given beside it, and `sources`, the passage each lookup came from,
    /// one per lookup in the order the lookups are written.
    static func make(text: String, name: String? = nil, answers: String? = nil, sources: [String],
                     context: Context) -> Result<ChainProposal, Refusal> {
        let markdown: String
        switch wrapped(text: text, name: name, answers: answers) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let value): markdown = value
        }
        let chain: ChainDefinition
        switch parseOne(markdown) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let value): chain = value
        }
        let lookups = lookupNames(chain)
        let given = sources.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var keyed: [String: String] = [:]
        for (index, lookup) in lookups.enumerated() where index < given.count {
            keyed[lookup] = given[index]
        }
        return validate(chain, sources: keyed, context: context)
    }

    /// The proposal with one step changed — "ask me the ambient instead" — and checked again from
    /// the start. `number` is the step's place as the read-back numbers it (from 1); `text` is the
    /// step as written, with its `cite` lines under it; `source` is the passage a new lookup came
    /// from. A lookup the change removes takes its source with it.
    func changing(step number: Int, to text: String, source: String? = nil,
                  context: Context) -> Result<ChainProposal, Refusal> {
        guard number >= 1, number <= chain.steps.count else {
            return .failure(.noSuchStep(number, count: chain.steps.count))
        }
        var lines: [String] = []
        for (index, step) in chain.steps.enumerated() {
            if index == number - 1 {
                lines += text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } else {
                lines.append(ChainParser.text(of: step.kind))
                lines += step.citations.map { "cite \($0)" }
            }
        }
        let markdown = Self.markdown(name: chain.name, answers: chain.answers, stepLines: lines)
        let changed: ChainDefinition
        switch Self.parseOne(markdown) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let value): changed = value
        }
        let lookups = Self.lookupNames(changed)
        var keyed = sources.filter { lookups.contains($0.key) }
        let given = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !given.isEmpty {
            for lookup in lookups where keyed[lookup] == nil { keyed[lookup] = given }
        }
        // The chain keeps its own name when it is changed: the taken names are the others'.
        var others = context
        others.takenNames.removeAll { $0.caseInsensitiveCompare(chain.name) == .orderedSame }
        return Self.validate(changed, sources: keyed, context: others)
    }

    /// The checks every proposal passes, in the order the model is told about them.
    static func validate(_ chain: ChainDefinition, sources: [String: String],
                         context: Context) -> Result<ChainProposal, Refusal> {
        if context.takenNames.contains(where: { $0.caseInsensitiveCompare(chain.name) == .orderedSame }) {
            return .failure(.nameTaken(chain.name))
        }
        guard !context.passages.isEmpty else { return .failure(.noPassages) }
        guard chain.steps.contains(where: { !$0.citations.isEmpty }) else { return .failure(.citesNothing) }
        let uncited = chain.steps.enumerated().compactMap { index, step -> String? in
            switch step.kind {
            case .lookup, .check:
                return step.citations.isEmpty ? "step \(index + 1) (\(ChainParser.text(of: step.kind)))" : nil
            default:
                return nil
            }
        }
        guard uncited.isEmpty else { return .failure(.uncited(uncited)) }

        let lookups = lookupNames(chain)
        let unsourced = lookups.filter { (sources[$0] ?? "").isEmpty }
        guard unsourced.isEmpty else { return .failure(.missingSource(unsourced)) }
        for lookup in lookups {
            let source = sources[lookup] ?? ""
            guard passage(cited: source, in: context.passages) != nil else {
                return .failure(.sourceNotRetrieved(lookup: lookup, source: source))
            }
        }

        var absent: [String] = []
        for step in chain.steps {
            for rule in step.citations where !absent.contains(rule) && !printed(rule, in: context.passages) {
                absent.append(rule)
            }
        }
        guard absent.isEmpty else { return .failure(.ruleNotInPassages(absent)) }

        // Kept as the citation alone, without a "Source:" the model may have written before it.
        var cited: [String: String] = [:]
        for lookup in lookups {
            let source = sources[lookup] ?? ""
            cited[lookup] = CitationLineParser.sourceBody(of: source) ?? source.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return .success(ChainProposal(chain: chain, sources: cited,
                                      missingTables: chain.missingTables(available: context.tableLabels)))
    }

    // MARK: - Reading it back

    /// The proposal as the technician hears it before anything runs: every step, the rule it
    /// follows and the passage it came from, and the tables it needs that the vault lacks.
    var readBack: String {
        var lines = ["Proposed chain: \(chain.name) (\(ChainOrigin.proposed.marking ?? ""))"]
        if !chain.answers.isEmpty { lines.append("Answers: \(chain.answers)") }
        for (index, step) in chain.steps.enumerated() {
            var line = "\(index + 1). " + Self.describe(step.kind)
            if !step.citations.isEmpty { line += " — follows \(step.citations.joined(separator: ", "))" }
            if case .lookup(let lookup) = step.kind {
                if let source = sources[lookup.name] { line += " — from \(source)" }
                let label = ChainDefinition.label(lookup.table)
                if missingTables.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
                    line += " (needs \(label), which no loaded manual's tables include: the chain will stop here)"
                }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// One step in words: what it asks, reads, works out, checks or says.
    static func describe(_ kind: ChainDefinition.Kind) -> String {
        switch kind {
        case .ask(let ask):
            let needs: String
            if ask.isText {
                needs = "in the technician's words"
            } else {
                var text = "a number" + (ask.unit.map { " in \($0)" } ?? "")
                if let range = ask.range {
                    text += ", from \(ChainParser.number(range.lowerBound)) to \(ChainParser.number(range.upperBound))"
                }
                needs = text
            }
            return "Ask for \(ask.name): \(ask.question) (\(needs))"
        case .lookup(let lookup):
            var text = "Look up \(lookup.name) in \(lookup.table): "
            if let cell = lookup.cell {
                text += "the row whose cell in column \(lookup.column ?? "") is \(ruleWords(lookup.rule)) \(cell)"
            } else {
                text += "row \(lookup.row ?? "")" + (lookup.column.map { ", column \($0)" } ?? "")
                text += ", rule \(lookup.rule.rawValue)"
            }
            return text
        case .calc(let name, let unit, let expression):
            return "Work out \(name)" + (unit.map { " (\($0))" } ?? "") + " = \(expression)"
        case .convert(let name, let source, let toUnit):
            return "Convert \(source) to \(toUnit) as \(name)"
        case .check(let check):
            return "Check \(check.left) \(check.comparison.rawValue) \(check.right): \"\(check.ifTrue)\", else \"\(check.ifFalse)\""
        case .say(let text):
            return "Say: \"\(text)\""
        }
    }

    private static func ruleWords(_ rule: TableLookup.RowRule) -> String {
        switch rule {
        case .exact: return "exactly"
        case .atLeast: return "at least"
        case .atMost: return "at most"
        }
    }

    /// The passages the proposal's lookups came from, by citation, once each, in order.
    var passageCitations: [String] {
        var out: [String] = []
        for step in chain.steps {
            guard case .lookup(let lookup) = step.kind, let source = sources[lookup.name],
                  !out.contains(source) else { continue }
            out.append(source)
        }
        return out
    }

    // MARK: - Parts

    /// The model's text as a `chains.md` holding one chain: its heading added when it has none,
    /// and its steps fenced when they are bare lines.
    private static func wrapped(text: String, name: String?, answers: String?) -> Result<String, Refusal> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasHeading = trimmed.split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") }
        if hasHeading { return .success(trimmed) }
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return .failure(.noName) }
        let said = answers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.contains("```") {
            return .success("## \(title)\n" + (said.isEmpty ? "" : "Answers: \(said)\n") + "\n" + trimmed)
        }
        let lines = trimmed.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return .success(markdown(name: title, answers: said, stepLines: lines))
    }

    static func markdown(name: String, answers: String, stepLines: [String]) -> String {
        var lines = ["## \(name)"]
        if !answers.isEmpty { lines.append("Answers: \(answers)") }
        lines.append("")
        lines.append("```chain")
        lines += stepLines.filter { !$0.isEmpty }
        lines.append("```")
        return lines.joined(separator: "\n")
    }

    private static func parseOne(_ markdown: String) -> Result<ChainDefinition, Refusal> {
        let parsed = ChainParser.parse(markdown)
        guard parsed.problems.isEmpty else { return .failure(.doesNotRead(parsed.problems.map(\.description))) }
        guard parsed.chains.count == 1, let chain = parsed.chains.first else {
            return parsed.chains.isEmpty ? .failure(.doesNotRead(["no chain was found"])) : .failure(.notOneChain(parsed.chains.count))
        }
        return .success(chain)
    }

    static func lookupNames(_ chain: ChainDefinition) -> [String] {
        chain.steps.compactMap { step in
            if case .lookup(let lookup) = step.kind { return lookup.name }
            return nil
        }
    }

    /// The retrieved passage a source names, by its document and page: "Invented Book A, page 4,
    /// §QR-14", with or without a leading "Source:". Nil when it names none of them.
    static func passage(cited source: String, in passages: [Passage]) -> Passage? {
        let body = CitationLineParser.sourceBody(of: source) ?? source.trimmingCharacters(in: .whitespacesAndNewlines)
        for citation in CitationLineParser.citations(inBody: body) where citation.kind == .manual {
            guard let page = citation.page else { continue }
            let last = citation.throughPage ?? page
            if let found = passages.first(where: {
                $0.documentName.caseInsensitiveCompare(citation.title) == .orderedSame
                    && ($0.page.map { (page...last).contains($0) } ?? false)
            }) {
                return found
            }
        }
        return nil
    }

    /// Whether a rule, as a `cite` line names it, is printed in one of the passages: its first
    /// numbered token ("QR-14" in "Rule QR-14(2)", "26-700" in "Rule 26-700") as a whole token of a
    /// passage's text or section, or, for a rule with no number, the words themselves.
    static func printed(_ rule: String, in passages: [Passage]) -> Bool {
        let tokens = Self.tokens(rule)
        if let identifier = tokens.first(where: { $0.contains(where: \.isNumber) }) {
            return passages.contains { passage in
                Self.tokens(passage.text + " " + (passage.section ?? "")).contains(identifier)
            }
        }
        let wanted = normalised(rule)
        guard !wanted.isEmpty else { return false }
        return passages.contains { normalised($0.text + " " + ($0.section ?? "")).contains(wanted) }
    }

    /// Upper-cased tokens of letters, digits, dots and hyphens, with a trailing dot or hyphen cut,
    /// and a parenthesised part ("(2)") left off.
    private static func tokens(_ text: String) -> [String] {
        let pattern = #"[A-Za-z0-9](?:[A-Za-z0-9.\-]*[A-Za-z0-9])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).uppercased()
        }
    }

    private static func normalised(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
