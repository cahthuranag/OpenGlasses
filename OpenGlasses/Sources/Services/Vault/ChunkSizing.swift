import Foundation

/// Chunk sizes by a document's language (Plan JY P4). Kept beside [[DocumentLanguageProfile]]
/// rather than in `DocumentChunker.swift`, which stays free of the profile so the office's
/// portable contract package can compile it on its own.
extension DocumentChunker {

    /// How much a document's character targets are scaled for its language, so a chunk holds
    /// about as much as an English one. 1 — today's sizes, exactly — for every language not
    /// measured to need otherwise. The measured values and their basis are in Plan JY P4.
    static func sizeScale(for profile: DocumentLanguageProfile) -> Double {
        #if RETRIEVAL_EVAL
        if let measured = RetrievalEvalTuning.chunkScale(script: profile.script, language: profile.language) {
            return measured
        }
        #endif
        return profile.script.isCJK ? cjkSizeScale : 1
    }

    /// A Chinese, Japanese or Korean document's targets: 0.6 of today's, 420 characters a chunk
    /// (Plan JY P4). Measured on the P3 sets (S = hit@4 + 2 × out-of-scope refused − in-scope
    /// refused over the nine CJK sets, 340 at 1): 0.4 → 364, 0.5 → 368, 0.6 → 369, 0.75 → 359, and
    /// per language (Chinese 0.3, Japanese and Korean 0.5, their content per character against
    /// English) → 369, so one value serves the group. A CJK character carries 1.4–3.5 times an
    /// English one's content on these sets. Every other script stays at 1: Cyrillic at 1.2 lost
    /// (168 → 161 over its five sets).
    static let cjkSizeScale = 0.6

    /// This chunker with its character targets scaled for a document's language; itself, unchanged,
    /// at a scale of 1. A clause-numbered document keeps today's targets: it is chunked at each
    /// clause already, and scaling it as well cost the CJK transport regulation 27 → 23 hit@4.
    func sized(for profile: DocumentLanguageProfile, text: String) -> DocumentChunker {
        if chunksAtClauseHeadings, Self.isClauseNumbered(text) { return self }
        let scale = Self.sizeScale(for: profile)
        guard scale != 1, scale > 0 else { return self }
        func scaled(_ value: Int) -> Int { max(1, Int((Double(value) * scale).rounded())) }
        let target = scaled(targetChars)
        return DocumentChunker(targetChars: target, maxChars: max(target, scaled(maxChars)),
                               overlapChars: min(scaled(overlapChars), target - 1),
                               keepsLineBreaks: keepsLineBreaks, chunksAtClauseHeadings: chunksAtClauseHeadings)
    }
}
