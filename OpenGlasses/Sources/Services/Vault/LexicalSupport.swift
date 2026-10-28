import Foundation

/// Content-word overlap between a question and a passage — the deterministic evidence signal that
/// works when embedding similarity does not.
///
/// The word-average embedding backend scores every passage of a real OEM manual within a couple of
/// hundredths of every other (0.87–0.91 measured across the Lennox SLP99 pair), so no similarity
/// floor and no relative margin can tell an in-scope question from an out-of-scope one. Shared
/// content terms can: a question about a torque spec the manual never gives shares almost nothing
/// with the prose the embedder returned, while a question about manifold pressure shares the words
/// the table is printed with.
///
/// Sibling of [[CodeTokenizer]], and deliberately as dumb: lowercase, letters only, four or more
/// characters, a short stopword list, one pass of suffix trimming. No stemmer, no language model —
/// the point is that the same query gives the same answer on every device and in every test.
///
/// Those are English rules. A document in another language is read under its own [[TermRule]]
/// (Plan JY P0), chosen by its [[DocumentLanguageProfile]]: the `rule:` forms below. The forms
/// without a rule are the English rule, unchanged, and what `TermRule.english` is.
enum LexicalSupport {

    /// Function words long enough to survive the four-letter cut. Everything shorter ("the", "for",
    /// "how", "is") is already excluded by length.
    static let stopwords: Set<String> = [
        "about", "after", "again", "also", "back", "been", "before", "being", "both", "cannot",
        "could", "does", "doing", "done", "down", "each", "else", "even", "ever", "every", "from",
        "give", "goes", "have", "here", "into", "just", "know", "like", "look", "make", "many",
        "more", "most", "much", "must", "need", "next", "only", "onto", "other", "over", "same",
        "should", "some", "such", "take", "tell", "than", "that", "their", "them", "then", "there",
        "these", "they", "this", "those", "through", "used", "using", "very", "want", "what",
        "when", "where", "which", "while", "will", "with", "would", "your",
    ]

    /// Minimum length of a term, before and after suffix trimming.
    private static let minimumLength = 4

    /// The content terms of a piece of text: lowercased alphabetic runs of at least four
    /// characters, stopwords removed, each trimmed of one plural/`-ing`/`-ed` suffix so that
    /// "pressures" and "pressure" are the same term.
    ///
    /// Digits are deliberately dropped: a code-like token is [[CodeTokenizer]]'s job and already
    /// counts as evidence on its own, so counting it twice here would let a bare model number carry
    /// a question the manual does not answer.
    static func contentTerms(_ text: String) -> Set<String> {
        Set(englishTermSequence(text))
    }

    /// Each content term's count in `text`, and how many there were in all — `contentTerms`
    /// counted rather than collected, for [[TermStatistics]].
    static func termCounts(_ text: String) -> (counts: [String: Int], length: Int) {
        let sequence = englishTermSequence(text)
        return (sequence.reduce(into: [:]) { $0[$1, default: 0] += 1 }, sequence.count)
    }

    /// The content terms of `text` in reading order, repeats kept, under the English rule — today's
    /// rule, which [[TermRule]] `.english` is.
    static func englishTermSequence(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.letters.inverted).compactMap { run in
            guard run.count >= minimumLength, !stopwords.contains(run) else { return nil }
            let stem = trimSuffix(run)
            return stem.count >= minimumLength ? stem : nil
        }
    }

    /// How many of `queryTerms` appear in `text`. The passage side is stemmed the same way, so the
    /// comparison is symmetric.
    static func sharedTermCount(text: String, queryTerms: Set<String>) -> Int {
        guard !queryTerms.isEmpty else { return 0 }
        return queryTerms.intersection(contentTerms(text)).count
    }

    // MARK: - By rule (Plan JY P0)

    /// `contentTerms` under `rule`. `.english` is exactly `contentTerms(_:)`.
    static func contentTerms(_ text: String, rule: TermRule) -> Set<String> {
        Set(rule.termSequence(text))
    }

    /// `termCounts` under `rule`. `.english` is exactly `termCounts(_:)`.
    static func termCounts(_ text: String, rule: TermRule) -> (counts: [String: Int], length: Int) {
        let sequence = rule.termSequence(text)
        return (sequence.reduce(into: [:]) { $0[$1, default: 0] += 1 }, sequence.count)
    }

    /// How many of `queryTerms` — the question's terms under the same `rule` — appear in `text`
    /// read under `rule`.
    static func sharedTermCount(text: String, queryTerms: Set<String>, rule: TermRule) -> Int {
        guard !queryTerms.isEmpty else { return 0 }
        return queryTerms.intersection(contentTerms(text, rule: rule)).count
    }

    /// How many of the question's terms under `rule` appear in `text` read under `rule` — the
    /// comparison a passage of a document read with `rule` gets.
    static func sharedTermCount(text: String, question: QueryTerms, rule: TermRule) -> Int {
        sharedTermCount(text: text, queryTerms: question.terms(for: rule), rule: rule)
    }

    /// A question's content terms under every [[TermRule]], made once (Plan JY P0), so each
    /// passage is compared with the question cut the way the passage's own document is. A question
    /// is a few words, so making all of them costs nothing next to reading one passage.
    struct QueryTerms: Equatable, Sendable {
        let text: String
        private let byRule: [TermRule: Set<String>]

        init(_ text: String) {
            self.text = text
            byRule = Dictionary(uniqueKeysWithValues: TermRule.allCases.map { ($0, LexicalSupport.contentTerms(text, rule: $0)) })
        }

        /// The question's terms under `rule`.
        func terms(for rule: TermRule) -> Set<String> { byRule[rule] ?? LexicalSupport.contentTerms(text, rule: rule) }

        /// The question's terms under today's English rule — `contentTerms(text)`.
        var english: Set<String> { terms(for: .english) }

        /// The question has no content term under any rule.
        var isEmpty: Bool { byRule.values.allSatisfy(\.isEmpty) }
    }

    /// One pass of suffix trimming. Approximate by design: "clocking" → "clock" and "pressures" →
    /// "pressure" are what matter; "measuring" → "measur" not matching "measure" is a miss we
    /// accept in exchange for a rule that fits in a paragraph.
    private static func trimSuffix(_ word: String) -> String {
        if word.hasSuffix("ing"), word.count >= minimumLength + 3 { return String(word.dropLast(3)) }
        if word.hasSuffix("ed"), word.count >= minimumLength + 2 { return String(word.dropLast(2)) }
        // "gases" → "gas", "matches" → "match": an -es plural after a sibilant loses both letters.
        for sibilant in ["ses", "xes", "zes", "ches", "shes"] where word.hasSuffix(sibilant) {
            if word.count >= minimumLength + 2 { return String(word.dropLast(2)) }
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"),
           word.count >= minimumLength + 1 { return String(word.dropLast()) }
        return word
    }
}

extension LexicalSupport {

    /// How often each content term occurs across a corpus's chunks, and how long their text and
    /// headings run — what BM25F needs to weigh a shared word by how rare it is (Plan IV P7).
    ///
    /// Derived from stored chunk text and held in memory (`DocumentStore.termStatistics`), so no
    /// re-index and no schema change. Totals rather than averages, so two corpora's statistics add.
    struct TermStatistics: Equatable, Sendable {
        private(set) var chunkCount = 0
        /// Chunks whose text or heading carries the term.
        private(set) var documentFrequency: [String: Int] = [:]
        private(set) var bodyLength = 0
        private(set) var headingLength = 0

        init() {}

        mutating func add(text: String, heading: String?) {
            add(text: text, heading: heading, rule: .english)
        }

        /// A chunk read under its document's rule (Plan JY P0). A corpus of documents in several
        /// languages keeps one table: each rule's terms are its own strings, so they count apart.
        mutating func add(text: String, heading: String?, rule: TermRule) {
            let body = LexicalSupport.termCounts(text, rule: rule)
            let head = LexicalSupport.termCounts(heading ?? "", rule: rule)
            for term in Set(body.counts.keys).union(head.counts.keys) { documentFrequency[term, default: 0] += 1 }
            chunkCount += 1
            bodyLength += body.length
            headingLength += head.length
        }

        static func + (lhs: Self, rhs: Self) -> Self {
            var sum = lhs
            sum.chunkCount += rhs.chunkCount
            sum.bodyLength += rhs.bodyLength
            sum.headingLength += rhs.headingLength
            sum.documentFrequency.merge(rhs.documentFrequency, uniquingKeysWith: +)
            return sum
        }

        /// The weight of a heading word against a body word. Measured on a code book and a field
        /// manual pair at the shipped candidate depth: 3 and 5 rank alike, 1 no better than none.
        static let headingWeight = 3.0

        /// BM25F (k1 1.2, b 0.75) of a chunk against the question's content terms: each field's
        /// term count normalised by its length against the corpus average, the heading's weighted
        /// by `headingWeight`, then the sum saturated and weighted by the term's rarity. A word the
        /// whole corpus prints counts for little; one printed in a section's heading counts most.
        func score(queryTerms: Set<String>, text: String, heading: String?,
                   headingWeight: Double = Self.headingWeight) -> Double {
            score(queryTerms: queryTerms, text: text, heading: heading, rule: .english, headingWeight: headingWeight)
        }

        /// `score` with the chunk read under its document's rule, against the question's terms
        /// under the same rule (Plan JY P0).
        func score(queryTerms: Set<String>, text: String, heading: String?, rule: TermRule,
                   headingWeight: Double = Self.headingWeight) -> Double {
            guard !queryTerms.isEmpty else { return 0 }
            let k1 = 1.2, b = 0.75
            let n = Double(max(chunkCount, 1))
            let averageBody = max(1, Double(bodyLength) / n), averageHeading = max(1, Double(headingLength) / n)
            let body = LexicalSupport.termCounts(text, rule: rule)
            let head = LexicalSupport.termCounts(heading ?? "", rule: rule)
            let bodyNorm = 1 - b + b * Double(body.length) / averageBody
            let headNorm = 1 - b + b * Double(head.length) / averageHeading
            var score = 0.0
            for term in queryTerms {
                let tf = Double(body.counts[term] ?? 0) / bodyNorm + headingWeight * Double(head.counts[term] ?? 0) / headNorm
                guard tf > 0 else { continue }
                let df = Double(documentFrequency[term] ?? 0)
                score += log(1 + (Double(chunkCount) - df + 0.5) / (df + 0.5)) * tf / (k1 + tf)
            }
            return score
        }
    }
}
