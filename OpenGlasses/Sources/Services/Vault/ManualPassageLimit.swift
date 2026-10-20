import Foundation

/// How many manual passages a retrieval hands the model (Plan IV P6): more where a passage is one
/// clause, four everywhere else.
///
/// A clause-numbered document (a code book, a standard) is chunked at each clause (Plan IV P3), so
/// one passage is one rule, and the question's answer is often the fifth or sixth rule the
/// retriever ranked. Measured on a code book, six passages answered 0.53 → 0.57 of the questions on
/// the contextual model (0.59 → 0.68 of the single-rule ones), and 0.44 → 0.50 on the sentence
/// model, at about 1,200 more characters per retrieval. A prose manual's passages are longer
/// stretches of a procedure and the four it had already answer the Lennox pair at 0.94, so prose
/// stays at four.
///
/// **A mixed vault is decided by the best passage.** The retriever is asked for the larger number
/// whenever a manual it may search is clause-numbered; the outcome keeps it when the first manual
/// passage comes from a clause-numbered document, and is cut to the prose number otherwise. A vault
/// with no clause-numbered manual is asked for four, exactly as before.
///
/// **A table row counts as a clause** (Plan JJ P1). A row passage is one row of one table, as
/// short and as self-contained as a rule, and a table question's answer is often the row beside the
/// one ranked first; the retriever is asked for six whenever a searched manual has table rows, and
/// an outcome whose best manual passage is a row keeps six.
///
/// Pure: whether a document is clause-numbered is the caller's to say (the store reads it from the
/// document's stored text, `DocumentStore.isClauseNumbered(documentId:)`).
struct ManualPassageLimit: Equatable {
    /// Passages for a prose manual, and for any vault without a clause-numbered one.
    var prose = 4
    /// Passages when the best passage is from a clause-numbered document.
    var clauseNumbered = 6

    /// What to ask the retriever for: the larger number when a searched manual is clause-numbered
    /// or has table rows.
    func requestLimit(searchesClauseNumbered: Bool, searchesTableRows: Bool = false) -> Int {
        searchesClauseNumbered || searchesTableRows ? max(prose, clauseNumbered) : prose
    }

    /// The outcome as sent: kept whole when its first manual passage is from a clause-numbered
    /// document or is a table row, cut to `prose` passages otherwise. A cut `.sufficient` outcome still carries a
    /// manual passage, as the gate promises: if team learnings filled the first slots, the last
    /// kept slot goes to the best manual passage.
    func shaped(_ outcome: RetrievalOutcome, isClauseNumbered: (String) -> Bool) -> RetrievalOutcome {
        let passages = outcome.passages
        guard passages.count > prose else { return outcome }
        if let best = passages.first(where: { $0.source.isReference }),
           best.kind == .tableRow || isClauseNumbered(best.documentId) { return outcome }
        var kept = Array(passages.prefix(max(prose, 1)))
        switch outcome {
        case .sufficient:
            if !kept.contains(where: { $0.source.isReference }),
               let best = passages.first(where: { $0.source.isReference }) {
                kept[kept.count - 1] = best
            }
            return .sufficient(kept)
        case .teamLearningOnly:
            return .teamLearningOnly(kept)
        case .insufficient:
            return outcome
        }
    }

    /// Retrieve and shape in one step.
    func retrieve(_ request: VaultRetriever.Request, with retriever: VaultRetriever, searchesClauseNumbered: Bool,
                  searchesTableRows: Bool = false, isClauseNumbered: (String) -> Bool) -> RetrievalOutcome {
        var request = request
        request.limit = requestLimit(searchesClauseNumbered: searchesClauseNumbered, searchesTableRows: searchesTableRows)
        return shaped(retriever.retrieve(request), isClauseNumbered: isClauseNumbered)
    }
}
