import Foundation
#if canImport(OpenGlasses)
@testable import OpenGlasses
#endif

/// The local retrieval eval: an answer key run through the shipped retriever, scored as hit@1 and
/// hit@4, with every miss put in the class that explains it.
///
/// Shared by two runners so both measure the same thing:
/// - `LocalManualEvalTests` in the simulator, through the session's own retriever factory, on the
///   simulator's embedder (`nl-word`);
/// - `Scripts/retrieval-eval` on a Mac, which compiles this file with the app's real
///   `DocumentStore` and `VaultRetriever`, on the device's embedding model (`nl-sentence`, or the
///   contextual model when asked).
///
/// **Nothing here prints a question, a passage or a document title.** The answer key and the
/// manuals behind it are often licensed to one person — a code book, a training workbook — so a
/// run's output is aggregate counts only, safe to paste into a plan or a PR. The answer key format
/// and how to write one from your own material are in `Scripts/retrieval-eval/README.md`.
enum RetrievalEval {

    // MARK: - The answer key

    /// One line of an answer key (JSON lines). A question is scored against what it expects:
    /// clause or rule numbers and table labels a passage must print (`rules`, `tables`), or pages
    /// of a named document a passage must come from (`pages`). `outOfScope` marks a question the
    /// manuals do not answer, which the gate should refuse.
    struct Question: Decodable, Equatable {
        let q: String
        var rules: [String]?
        var tables: [String]?
        /// Document title → the pages that answer it.
        var pages: [String: [Int]]?
        var outOfScope: Bool?
        /// Needs several rules or a calculation: one-passage hit@k is the wrong test for it.
        var multi: Bool?
        /// The expected answer itself is in doubt (a hard-to-read key, a corrected answer).
        var doubt: Bool?
        var note: String?

        var expectsLabels: [String] { (rules ?? []) + (tables ?? []) }
        var isScorable: Bool { !expectsLabels.isEmpty || !(pages ?? [:]).isEmpty }
    }

    /// Reads JSON lines. Blank lines and lines starting with `//` are skipped, as is any object
    /// without a question.
    static func loadAnswerKey(_ text: String) -> [Question] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { return nil }
            return try? JSONDecoder().decode(Question.self, from: Data(trimmed.utf8))
        }
    }

    // MARK: - The retriever under test

    /// The shipped retrieval routes over one store, with the given gate — the routes
    /// `FieldSessionService.makeRetriever` builds, without the session's namespaces, availability
    /// check or model scope. For a runner that has no session (the Mac script, the calibration
    /// test). `LocalManualEvalTests` checks it ranks exactly as the session's factory does.
    @MainActor
    static func retriever(over store: DocumentStore, policy: RetrievalEvidencePolicy) -> VaultRetriever {
        VaultRetriever(query: { query, limit in store.query(query, limit: limit) },
                       tokenSearch: { token, limit in store.passages(containingToken: token, limit: limit) },
                       clauseSearch: { clause, limit in store.passages(clause: clause, limit: limit) },
                       termSearch: { query, limit in store.passages(sharingTermsWith: query, limit: limit) },
                       policy: policy)
    }

    /// The same routes, searching only what the newest-edition default (or the question's own
    /// reach past it) allows — the filter `makeRetriever` applies (Plan IV P2), for a runner with
    /// no session.
    @MainActor
    static func retriever(over store: DocumentStore, policy: RetrievalEvidencePolicy,
                          editions: DocumentEditions, turn: String) -> VaultRetriever {
        guard let titles = editions.searchableTitles(for: EditionRequest.parse(turn, editions: editions),
                                                     among: store.documents.map(\.name)) else {
            return retriever(over: store, policy: policy)
        }
        let ids = store.documents.filter { titles.contains($0.name) }.map(\.id)
        return VaultRetriever(query: { query, limit in store.query(query, limit: limit, documentIds: ids) },
                              tokenSearch: { token, limit in store.passages(containingToken: token, documentIds: ids, limit: limit) },
                              clauseSearch: { clause, limit in store.passages(clause: clause, documentIds: ids, limit: limit) },
                              termSearch: { query, limit in store.passages(sharingTermsWith: query, limit: limit, documentIds: ids) },
                              policy: policy)
    }

    // MARK: - Scoring

    /// Why a question missed hit@4, first class that fits, in this order.
    enum MissClass: String, CaseIterable {
        /// The expected rule or table is never printed as its own heading in the documents
        /// searched — another edition's number, or a doubtful key.
        case notInDocuments = "expected label not printed in these documents"
        /// The rule's continuation (the chunk after its heading) is in the top 4 without its number.
        case chunkBoundary = "chunk boundary"
        /// Near-identical passages from different documents take slots; removing them would hit.
        case duplicates = "duplicates across documents"
        /// The expected passage is in the top 30 candidates, outranked.
        case ranking = "ranking (in the top 30)"
        /// The expected passage is not in the top 30 candidates at all.
        case recall = "recall (not in the top 30)"
    }

    struct Report: Equatable {
        var scored = 0
        var hit1 = 0
        var hit4 = 0
        var outOfScope = 0
        var refused = 0
        /// Scored (in-scope) questions the gate turned away with "the manuals do not cover this".
        var inScopeRefused = 0
        var misses: [MissClass: Int] = [:]
        var multiQuestions = 0, multiMisses = 0
        var doubtQuestions = 0, doubtMisses = 0

        var missCount: Int { scored - hit4 }

        /// Aggregate lines only — never a question or a passage.
        func lines(label: String, embedder: String) -> [String] {
            func rate(_ n: Int, _ d: Int) -> String { d == 0 ? "-" : String(format: "%.2f", Double(n) / Double(d)) }
            var out = ["[EVAL] \(label) embedder=\(embedder) scored=\(scored) hit@1 \(hit1) (\(rate(hit1, scored))) "
                       + "hit@4 \(hit4) (\(rate(hit4, scored)))"
                       + " | in-scope refused \(inScopeRefused)"
                       + (outOfScope > 0 ? " | out-of-scope refused \(refused) of \(outOfScope)" : "")]
            if missCount > 0 {
                let parts = MissClass.allCases.compactMap { c -> String? in
                    guard let n = misses[c], n > 0 else { return nil }
                    return "\(c.rawValue) \(n) (\(Int((100 * Double(n) / Double(missCount)).rounded()))%)"
                }
                out.append("[EVAL]   misses \(missCount): " + parts.joined(separator: " · "))
            }
            if multiQuestions + doubtQuestions > 0 {
                out.append("[EVAL]   overlays: multi-rule or calculation \(multiQuestions) (\(multiMisses) missed) · "
                           + "answer in doubt \(doubtQuestions) (\(doubtMisses) missed)")
            }
            return out
        }
    }

    /// What a passage is to a question: it holds the answer (prints an expected label, or sits on
    /// an expected page), or not.
    static func holds(_ p: VaultRetriever.Passage, _ q: Question) -> Bool {
        if let pages = q.pages, let page = p.page, pages[p.documentName]?.contains(page) == true { return true }
        return q.expectsLabels.contains { label in
            ClauseReference.match(label, in: p.text, section: p.section) != nil
                || (p.figure ?? "").caseInsensitiveCompare(label) == .orderedSame
                || CodeTokenizer.contains(p.text, token: label) && !looksLikeClause(label)
        }
    }

    /// A clause or rule number ("99-200", "3.9.4.2"); a table label ("Table 99") is not one.
    private static func looksLikeClause(_ label: String) -> Bool {
        label.range(of: #"^\d+([.\-]\d+)+$"#, options: .regularExpression) != nil
    }

    /// Run every question. `gated` is the retriever as shipped (its gate decides); `open` is the
    /// same routes with no gate, read to 30 deep to tell a ranking miss from a recall miss.
    /// `classifyMisses: false` counts hits and refusals only, for a sweep over many gates.
    @MainActor
    static func run(_ questions: [Question], gated: VaultRetriever, open: VaultRetriever,
                    store: DocumentStore, classifyMisses: Bool = true) -> Report {
        run(questions, gatedFor: { _ in gated }, openFor: { _ in open }, store: store, classifyMisses: classifyMisses)
    }

    /// The same, with a retriever per question: the session's factory reads the question to
    /// choose an edition (Plan IV P2), so the runner hands it each one.
    @MainActor
    static func run(_ questions: [Question], gatedFor: (String) -> VaultRetriever, openFor: (String) -> VaultRetriever,
                    store: DocumentStore, classifyMisses: Bool = true) -> Report {
        var report = Report()
        for q in questions {
            let gated = gatedFor(q.q), open = openFor(q.q)
            if q.outOfScope == true {
                report.outOfScope += 1
                if !gated.retrieve(.init(turn: q.q, limit: 4)).isSufficient { report.refused += 1 }
                continue
            }
            guard q.isScorable else { continue }
            report.scored += 1
            if q.multi == true { report.multiQuestions += 1 }
            if q.doubt == true { report.doubtQuestions += 1 }

            let outcome = gated.retrieve(.init(turn: q.q, limit: 4))
            if !outcome.isSufficient { report.inScopeRefused += 1 }
            let top4 = Array(outcome.passages.prefix(4))
            if top4.first.map({ holds($0, q) }) == true { report.hit1 += 1 }
            if top4.contains(where: { holds($0, q) }) { report.hit4 += 1; continue }

            if q.multi == true { report.multiMisses += 1 }
            if q.doubt == true { report.doubtMisses += 1 }
            guard classifyMisses else { continue }
            report.misses[classify(q, top4: top4, gated: gated, open: open, store: store), default: 0] += 1
        }
        return report
    }

    @MainActor
    private static func classify(_ q: Question, top4: [VaultRetriever.Passage], gated: VaultRetriever,
                                 open: VaultRetriever, store: DocumentStore) -> MissClass {
        let own = ownPassages(q, store: store)
        if own.isEmpty, !q.expectsLabels.isEmpty, (q.pages ?? [:]).isEmpty { return .notInDocuments }
        // A page expectation has no "rest of the rule": the chunk after a page's last one is
        // simply the next page. Only a label's heading has a continuation.
        let labelled = q.expectsLabels.isEmpty ? [] : ownPassages(Question(q: q.q, rules: q.rules, tables: q.tables), store: store)
        let continuation = Set(labelled.map { Key(documentId: $0.documentId, chunkIndex: $0.chunkIndex + 1) })
            .subtracting(own)
        if top4.contains(where: { continuation.contains(Key($0)) }) { return .chunkBoundary }

        var deduped: [VaultRetriever.Passage] = []
        for p in gated.retrieve(.init(turn: q.q, limit: 12)).passages
        where !deduped.contains(where: { nearDuplicate($0, p) }) {
            deduped.append(p)
        }
        if deduped.prefix(4).contains(where: { holds($0, q) }) { return .duplicates }

        let ranked = open.retrieve(.init(turn: q.q, limit: 30)).passages
        if ranked.contains(where: { own.contains(Key($0)) || holds($0, q) }) { return .ranking }
        return .recall
    }

    struct Key: Hashable {
        let documentId: String
        let chunkIndex: Int
        init(documentId: String, chunkIndex: Int) { self.documentId = documentId; self.chunkIndex = chunkIndex }
        init(_ p: VaultRetriever.Passage) { self.init(documentId: p.documentId, chunkIndex: p.chunkIndex) }
        init(_ p: DocumentStore.Passage) { self.init(documentId: p.documentId, chunkIndex: p.chunkIndex) }
    }

    /// Where the expected answer's own text is: a chunk on an expected page, or a chunk that prints
    /// an expected label as a heading — the number then a capitalised title — rather than citing it
    /// ("Rule 99-200 2)", "see Table 99").
    @MainActor
    static func ownPassages(_ q: Question, store: DocumentStore) -> Set<Key> {
        var own = Set<Key>()
        for (title, pages) in q.pages ?? [:] {
            guard let doc = store.document(named: title) else { continue }
            for page in pages {
                store.passages(onPage: page, documentIds: [doc.id], limit: 1_000).forEach { own.insert(Key($0)) }
            }
        }
        for label in q.expectsLabels {
            for p in store.passages(containingToken: label, limit: Int.max)
            where printsAsHeading(label, in: p.text, section: p.section) {
                own.insert(Key(p))
            }
        }
        return own
    }

    private static let notHeadingBefore: Set<String> = [
        "rule", "rules", "and", "to", "or", "with", "see", "of", "in", "under", "per", "table", "tables",
        "clause", "clauses", "section", "sections",
    ]

    static func printsAsHeading(_ label: String, in text: String, section: String?) -> Bool {
        if (ClauseReference.match(label, in: text, section: section) ?? .cites) >= .continues { return true }
        let pattern = #"(\S+)?\s*(?<![\p{L}\p{N}.\-])"# + NSRegularExpression.escapedPattern(for: label)
            + #"\s+\p{Lu}\p{Ll}"#
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = text as NSString
        for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let before = m.range(at: 1).location == NSNotFound ? ""
                : ns.substring(with: m.range(at: 1)).lowercased().trimmingCharacters(in: .punctuationCharacters)
            if !notHeadingBefore.contains(before) { return true }
        }
        return false
    }

    /// Two passages from different documents sharing most of their words — the same table printed
    /// in two manuals, the same rule in two editions.
    static func nearDuplicate(_ a: VaultRetriever.Passage, _ b: VaultRetriever.Passage) -> Bool {
        guard a.documentId != b.documentId else { return false }
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let x = words(a.text), y = words(b.text)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return Double(x.intersection(y).count) / Double(x.union(y).count) >= 0.6
    }
}
