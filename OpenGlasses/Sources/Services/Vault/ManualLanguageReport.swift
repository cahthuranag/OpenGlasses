import Foundation

/// The lines the support report and the Developer panel carry about documents' languages and
/// the search models for them (Plan JY P1): each document's detected profile, the model family
/// and script its passages are searched with, how many of its chunks have vectors, and whether
/// each script's model is on the phone. Counts and labels only — never a document's name or text
/// (Plan DM). Pure over its inputs.
enum ManualLanguageReport {

    /// Where one script's search model stands on this phone.
    struct ModelState: Equatable {
        enum State: String { case onPhone = "on the phone", downloading, unavailable, notRequested = "not requested" }
        let script: EmbeddingScript
        let state: State
    }

    /// At most this many per-document lines; the rest are counted.
    static let documentLineLimit = 12

    static func lines(_ diagnostics: [DocumentStore.LanguageDiagnostic], models: [ModelState],
                      limit: Int = documentLineLimit) -> [String] {
        guard !diagnostics.isEmpty else {
            return ["Document languages: none"] + (modelLine(models).map { [$0] } ?? [])
        }
        let manuals = diagnostics.filter(\.isManual).count
        var byScript: [EmbeddingScript: Int] = [:]
        for diagnostic in diagnostics { byScript[diagnostic.script, default: 0] += 1 }
        let scripts = EmbeddingScript.allCases.compactMap { script in
            byScript[script].map { "\(script.diagnosticLabel) \($0)" }
        }.joined(separator: ", ")
        let byWords = diagnostics.filter(\.searchesByWords).count
        var out = ["Document languages: \(diagnostics.count) documents (\(manuals) manuals); by script \(scripts); words only \(byWords)"]
        // Plan JY P3: groups whose search values were not measured on both a parallel baseline
        // and a technical document.
        let lessTested = TermRule.Group.allCases.compactMap { group -> String? in
            let n = diagnostics.filter { $0.profile.termRule.group == group && group.isLessTested }.count
            return n > 0 ? "\(group.rawValue) \(n)" : nil
        }
        if !lessTested.isEmpty { out.append("Less tested: " + lessTested.joined(separator: ", ")) }
        if let models = modelLine(models) { out.append(models) }
        for (index, diagnostic) in diagnostics.prefix(max(limit, 0)).enumerated() {
            out.append("Document \(index + 1): \(diagnostic.line)")
        }
        if diagnostics.count > limit { out.append("Documents not listed: \(diagnostics.count - limit)") }
        return out
    }

    /// "Search models: CJK on the phone, Cyrillic downloading", or nil when no script but Latin
    /// is involved.
    static func modelLine(_ models: [ModelState]) -> String? {
        guard !models.isEmpty else { return nil }
        return "Search models: " + models.map { "\($0.script.diagnosticLabel) \($0.state.rawValue)" }.joined(separator: ", ")
    }

    /// The scripts worth reporting a model for: those of the stored documents and of the phone's
    /// languages, Latin left out (its model is reported with Field Assist's search setting).
    static func reportedScripts(_ diagnostics: [DocumentStore.LanguageDiagnostic],
                                preferredLanguages: [String]) -> [EmbeddingScript] {
        let wanted = Set(diagnostics.map(\.script)).union(EmbeddingScript.aheadOfTime(preferredLanguages: preferredLanguages))
        return EmbeddingScript.allCases.filter { $0 != .latin && wanted.contains($0) }
    }

    /// The lines for the app's store as it is now.
    @MainActor
    static func current(store: DocumentStore, assets: ScriptModelAssets = .shared,
                        preferredLanguages: [String] = Locale.preferredLanguages) -> [String] {
        let diagnostics = store.languageDiagnostics()
        let models = reportedScripts(diagnostics, preferredLanguages: preferredLanguages).map { script in
            // The asset's presence, not a loaded model: a report must not load a model it does
            // not search with.
            ModelState(script: script, state: assets.isReady(script) ? .onPhone
                       : assets.isDownloading(script) ? .downloading
                       : assets.lastFailed.contains(script) ? .unavailable : .notRequested)
        }
        return lines(diagnostics, models: models)
    }
}
