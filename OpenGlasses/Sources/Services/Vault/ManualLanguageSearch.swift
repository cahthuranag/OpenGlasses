import Foundation

/// Questions in another language than the manual (Plan JY P2).
///
/// Two languages' passages can't be searched with one question: their terms don't match, and
/// two script models' cosines can't be compared (P1 measured the Cyrillic model's between 0.89
/// and 0.98 and the CJK model's well below the Latin one's). So the manuals a lookup searches are
/// grouped by language, each group is searched with the question written in its language — the
/// rewrite the model passed in `manual_lookup`'s `queries`, or `query` when it passed none — and
/// the groups' results are merged **by rank**, never by score. Manuals are never translated (owner
/// decision 2): only the question is, by the model already in the loop, and the answer cites the
/// original page.
///
/// A library in one language (every English-only user) is one group and is searched exactly as
/// before: one retrieval, with `query`.
///
/// Pure: the grouping, the parsing of `queries`, the merge and the miss hint are tested headlessly;
/// the retrievals are the caller's closures.
enum ManualLanguageSearch {

    // MARK: - Languages

    /// The code of the language group a document with `profile` is searched in: its detected
    /// language, or its script's default when detection wasn't sure.
    ///
    /// A Latin document whose language is unsure, and one in no interface script (`.other`: Greek,
    /// Hebrew, no letters at all), are read with today's English rule and the Latin model, so they
    /// search with the English documents: a library of English manuals is one group however
    /// uncertain one of its table-heavy books reads. An unsure Cyrillic document is its own
    /// `cyrillicUnsure` group, since Ukrainian and Russian need different rewrites.
    static func code(for profile: DocumentLanguageProfile) -> String {
        switch profile.script {
        case .latin:
            return profile.language.flatMap(canonical) ?? "en"
        case .other, .kana:
            return "en"
        case .cyrillic:
            return profile.language.flatMap(canonical) ?? cyrillicUnsure
        case .arabic:
            return profile.language.flatMap(canonical) ?? "ar"
        case .han:
            return profile.language.flatMap(canonical) ?? "zh-Hans"
        case .hangul:
            return "ko"
        }
    }

    /// The group of a Cyrillic document whose language wasn't settled.
    static let cyrillicUnsure = "cyrillic"

    /// The language codes a document is grouped under, in a stable order. Region variants of the
    /// interface languages (es-MX, fr-CA, pt-BR) are their language here: a manual's language is
    /// detected without a region.
    static let codes = ["en", "de", "es", "fr", "hu", "it", "nl", "pl", "pt", "uk", "ru", "ar", "ur",
                        "zh-Hans", "zh-Hant", "ja", "ko"]

    /// The plain name the model reads ("Chinese (Simplified)"). English, like every instruction
    /// the model is given; never shown in the interface.
    static func name(of code: String) -> String {
        switch code {
        case "en": return "English"
        case "de": return "German"
        case "es": return "Spanish"
        case "fr": return "French"
        case "hu": return "Hungarian"
        case "it": return "Italian"
        case "nl": return "Dutch"
        case "pl": return "Polish"
        case "pt": return "Portuguese"
        case "uk": return "Ukrainian"
        case "ru": return "Russian"
        case "ar": return "Arabic"
        case "ur": return "Urdu"
        case "zh-Hans": return "Chinese (Simplified)"
        case "zh-Hant": return "Chinese (Traditional)"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case cyrillicUnsure: return "Ukrainian or Russian"
        default: return code
        }
    }

    /// "Chinese (Simplified) [zh-Hans]": the name, and the code `queries` takes.
    static func label(of code: String) -> String {
        code == cyrillicUnsure ? "Ukrainian or Russian [uk or ru]" : "\(name(of: code)) [\(code)]"
    }

    /// The script a group's text is written in.
    static func script(of code: String) -> TextScript {
        switch code {
        case "uk", "ru", cyrillicUnsure: return .cyrillic
        case "ar", "ur": return .arabic
        case "zh-Hans", "zh-Hant", "ja": return .han
        case "ko": return .hangul
        default: return .latin
        }
    }

    /// The canonical code for a language the model named: a code in any case or separator
    /// ("zh-hans", "zh_TW", "pt-BR", "uk-UA") or its English name ("Ukrainian"). Nil for anything
    /// else, which is ignored.
    static func canonical(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-").lowercased()
        guard !text.isEmpty, text.count <= 24 else { return nil }
        if let named = names[text] { return named }
        if text == "zh" || text.hasPrefix("zh-") {
            let traditional = ["zh-hant", "zh-tw", "zh-hk", "zh-mo"].contains { text == $0 || text.hasPrefix($0 + "-") }
            return traditional ? "zh-Hant" : "zh-Hans"
        }
        guard let base = text.split(separator: "-").first.map(String.init),
              let code = codes.first(where: { $0 == base }) else { return nil }
        return code
    }

    private static let names: [String: String] = [
        "english": "en", "german": "de", "spanish": "es", "french": "fr", "hungarian": "hu", "italian": "it",
        "dutch": "nl", "polish": "pl", "portuguese": "pt", "ukrainian": "uk", "russian": "ru", "arabic": "ar",
        "urdu": "ur", "chinese": "zh-Hans", "simplified chinese": "zh-Hans", "chinese (simplified)": "zh-Hans",
        "traditional chinese": "zh-Hant", "chinese (traditional)": "zh-Hant", "japanese": "ja", "korean": "ko",
    ]

    /// The main script of a question's words (a Han, kana or Hangul character weighing three
    /// Latin letters, as in `DocumentLanguageProfile`), or nil when it has none. A run of letters
    /// and digits holding a decimal digit is a code ("E5", "ZX9"), not a word, and is not counted: a bare
    /// code is in no language.
    static func script(ofQuery text: String) -> TextScript? {
        var counts: [TextScript: Int] = [:]
        let runs = text.split { !($0.isLetter || $0.isNumber) }
        // A decimal digit, not any numeric character: 什 and 万 are Han letters with numeric values.
        for run in runs where !run.contains(where: { $0.unicodeScalars.first?.properties.numericType == .decimal }) {
            for scalar in run.unicodeScalars {
                guard let script = TextScript.of(scalar) else { continue }
                switch script {
                case .han, .kana: counts[.han, default: 0] += DocumentLanguageProfile.ideographWeight
                case .hangul: counts[.hangul, default: 0] += DocumentLanguageProfile.ideographWeight
                default: counts[script, default: 0] += 1
                }
            }
        }
        let order: [TextScript] = [.latin, .cyrillic, .arabic, .han, .hangul, .other]
        guard let largest = counts.values.max(), largest > 0 else { return nil }
        return order.first { counts[$0] == largest }
    }

    // MARK: - The model's rewrites

    /// The question rewritten per manual language, read defensively from `manual_lookup`'s
    /// `queries`: a list of `{"language", "query"}` items (the schema's shape, which every
    /// provider's schema form and the on-device bridge accept) or a `{code: query}` object. A
    /// language that isn't an interface language is ignored, a rewrite is trimmed and cut to
    /// `maxQueryLength`, and each language keeps only its first rewrite.
    struct Rewrites: Equatable {
        /// Canonical code → rewritten question.
        private(set) var byLanguage: [String: String] = [:]

        static let none = Rewrites()
        /// Characters kept of one rewrite — a question, not a passage.
        static let maxQueryLength = 400
        /// Items read from the list at most.
        static let maxItems = 24

        init() {}

        init(_ value: Any?) {
            var pairs: [(String, Any)] = []
            if let list = value as? [Any] {
                for item in list.prefix(Self.maxItems) {
                    guard let object = item as? [String: Any],
                          let language = (object["language"] ?? object["lang"] ?? object["code"]) as? String,
                          let query = object["query"] else { continue }
                    pairs.append((language, query))
                }
            } else if let object = value as? [String: Any] {
                // A dictionary has no order: read in key order so the first rewrite kept for a
                // language is the same every time.
                pairs = object.keys.sorted().prefix(Self.maxItems).map { ($0, object[$0] as Any) }
            }
            for (language, rawQuery) in pairs {
                guard let code = ManualLanguageSearch.canonical(language), byLanguage[code] == nil,
                      let text = (rawQuery as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { continue }
                byLanguage[code] = String(text.prefix(Self.maxQueryLength))
            }
        }

        var isEmpty: Bool { byLanguage.isEmpty }
        var count: Int { byLanguage.count }

        /// The rewrite for a group, or nil. Simplified and Traditional Chinese stand in for each
        /// other (their terms are folded together, and one model reads both); an unsure Cyrillic
        /// group takes a Ukrainian rewrite, else a Russian one.
        func query(for code: String) -> String? {
            if let exact = byLanguage[code] { return exact }
            switch code {
            case "zh-Hans": return byLanguage["zh-Hant"]
            case "zh-Hant": return byLanguage["zh-Hans"]
            case ManualLanguageSearch.cyrillicUnsure: return byLanguage["uk"] ?? byLanguage["ru"]
            default: return nil
            }
        }
    }

    // MARK: - Groups

    /// The documents one language's question searches.
    struct Group: Equatable {
        let language: String
        var documentIds: [String]
    }

    /// The searched documents by language group, in `codes` order (an unsure Cyrillic group after
    /// them), each group's ids in the order given. Every document is a reference manual.
    static func groups(_ documents: [(id: String, profile: DocumentLanguageProfile)]) -> [Group] {
        groups(documents.map { (id: $0.id, profile: $0.profile, isReference: true) })
    }

    /// The groups, with the documents that aren't reference manuals — team learnings — never
    /// forming a group of their own: a learning joins the reference group of its own language when
    /// there is one, else the largest reference group (the earlier on a tie). A short crew note is
    /// no evidence of a language, and a group of its own would split an English vault's search.
    /// With no reference documents at all, the learnings are one group, their commonest language's.
    static func groups(_ documents: [(id: String, profile: DocumentLanguageProfile, isReference: Bool)]) -> [Group] {
        let order = codes + [cyrillicUnsure]
        var byCode: [String: [String]] = [:]
        for document in documents where document.isReference {
            byCode[code(for: document.profile), default: []].append(document.id)
        }
        let others = documents.filter { !$0.isReference }
        func largest(_ counts: [String: Int]) -> String? {
            order.filter { counts[$0] != nil }.max { a, b in
                // `max` keeps the later of equals; reversing the tie keeps the earlier code.
                counts[a]! != counts[b]! ? counts[a]! < counts[b]! : order.firstIndex(of: a)! > order.firstIndex(of: b)!
            }
        }
        let host = largest(byCode.mapValues(\.count))
            ?? largest(Dictionary(others.map { (code(for: $0.profile), 1) }, uniquingKeysWith: +))
        let referenceCodes = Set(byCode.keys)
        for document in others {
            let own = code(for: document.profile)
            byCode[referenceCodes.contains(own) ? own : (host ?? own), default: []].append(document.id)
        }
        return order.compactMap { code in byCode[code].map { Group(language: code, documentIds: $0) } }
    }

    // MARK: - Searching

    /// What one group's search found.
    struct GroupResult: Equatable {
        let language: String
        let documentCount: Int
        /// The model passed this group a rewrite.
        let rewritten: Bool
        let outcome: RetrievalOutcome
    }

    /// A lookup's merged outcome and each group's part in it.
    struct Result: Equatable {
        let outcome: RetrievalOutcome
        let groups: [GroupResult]

        /// More than one language was searched, each with its own question.
        var searchedByLanguage: Bool { groups.count > 1 }
    }

    /// Search each language group with its own question and merge the results.
    ///
    /// One group (or none) is today's search, unchanged: `whole` with the group's rewrite, or
    /// `query` when there is none. More than one: `scoped` once per group with that group's
    /// question, then `merge`. `query` may be nil (a nameplate lookup), in which case a group
    /// without a rewrite searches on the label alone, as today.
    static func search(groups: [Group], query: String?, rewrites: Rewrites, limit: Int,
                       whole: (_ query: String?) -> RetrievalOutcome,
                       scoped: (_ group: Group, _ query: String?) -> RetrievalOutcome) -> Result {
        guard groups.count > 1 else {
            let group = groups.first
            let rewrite = group.flatMap { rewrites.query(for: $0.language) }
            let outcome = whole(rewrite ?? query)
            return Result(outcome: outcome, groups: group.map {
                [GroupResult(language: $0.language, documentCount: $0.documentIds.count,
                             rewritten: rewrite != nil, outcome: outcome)]
            } ?? [])
        }
        let results = groups.map { group -> GroupResult in
            let rewrite = rewrites.query(for: group.language)
            return GroupResult(language: group.language, documentCount: group.documentIds.count,
                               rewritten: rewrite != nil, outcome: scoped(group, rewrite ?? query))
        }
        return Result(outcome: merge(results, limit: limit), groups: results)
    }

    /// The reciprocal-rank-fusion constant: a passage's share is 1 / (k + rank).
    static let fusionK = 60.0

    /// The groups' outcomes merged by rank (reciprocal-rank fusion), never by raw score: the
    /// first passage of every group that answers ranks alike, however its model's cosines sit,
    /// so a Latin passage scoring 0.9 does not bury a CJK group's best at 0.6.
    ///
    /// Each group keeps its own gate's verdict: only passages that cleared their group's gate are
    /// merged, so the outcome is insufficient only when every group is. It is sufficient when any
    /// group is, and then — as the gate promises — carries a manual passage even if learnings
    /// would have filled the slots; learning-only when the only groups that answered did so on
    /// learnings. At equal rank a sufficient group's passage leads, then one matching a spoken code,
    /// then the earlier group.
    static func merge(_ results: [GroupResult], limit: Int) -> RetrievalOutcome {
        struct Entry {
            let passage: VaultRetriever.Passage
            var fused: Double
            let sufficient: Bool
            let group: Int
            let rank: Int
        }
        var entries: [String: Entry] = [:]
        for (group, result) in results.enumerated() where result.outcome.answers {
            for (rank, passage) in result.outcome.passages.enumerated() {
                let key = "\(passage.documentId)#\(passage.chunkIndex)"
                let share = 1 / (fusionK + Double(rank + 1))
                if var existing = entries[key] {
                    existing.fused += share
                    entries[key] = existing
                } else {
                    entries[key] = Entry(passage: passage, fused: share, sufficient: result.outcome.isSufficient,
                                         group: group, rank: rank)
                }
            }
        }
        guard !entries.isEmpty else {
            for result in results { if case .insufficient = result.outcome { return result.outcome } }
            return .insufficient(reason: RetrievalEvidencePolicy.insufficientSentence)
        }
        let ordered = entries.values.sorted { a, b in
            if a.fused != b.fused { return a.fused > b.fused }
            if a.sufficient != b.sufficient { return a.sufficient }
            if a.passage.matchedTokens.isEmpty != b.passage.matchedTokens.isEmpty { return !a.passage.matchedTokens.isEmpty }
            if a.group != b.group { return a.group < b.group }
            return a.rank < b.rank
        }.map(\.passage)
        var chosen = Array(ordered.prefix(max(limit, 1)))
        guard results.contains(where: { $0.outcome.isSufficient }) else { return .teamLearningOnly(chosen) }
        if !chosen.contains(where: { $0.source.isReference }), let best = ordered.first(where: { $0.source.isReference }) {
            chosen[chosen.count - 1] = best
        }
        return .sufficient(chosen)
    }

    // MARK: - What the model is told

    /// The groups that found nothing although their manuals may hold the answer: no rewrite was
    /// given for them and the question's letters are in another script, so its words could not
    /// match theirs. Empty when the question has no letters (a bare code).
    static func missedForLanguage(_ result: Result, query: String?) -> [String] {
        guard let query, let asked = script(ofQuery: query) else { return [] }
        return result.groups.filter { !$0.outcome.answers && !$0.rewritten && script(of: $0.language) != asked }
            .map(\.language)
    }

    /// What a lookup says about the manuals that missed for want of their language's words. Never
    /// an invitation to answer from general knowledge or to translate a passage.
    static func missHint(_ languages: [String]) -> String? {
        guard !languages.isEmpty else { return nil }
        let names = languages.map(label).joined(separator: ", ")
        return "Nothing was found in the manuals in \(names), and the question is in another script, so its words "
            + "cannot match theirs. Run manual_lookup once more with 'queries' holding the question rewritten in "
            + (languages.count == 1 ? "that language" : "each of those languages")
            + " — never translate a passage or answer from general knowledge."
    }

    /// The line a lookup's result opens with when a searched manual is not in English: each
    /// language's label and how many manuals are in it. Counts and labels only. Nil when every
    /// manual searched is English, so an English library's result is unchanged.
    static func languagesLine(_ result: Result) -> String? {
        guard result.groups.contains(where: { $0.language != "en" }) else { return nil }
        let parts = result.groups.map { "\(label(of: $0.language)) \($0.documentCount)" }
        return "Manual languages searched (manuals per language): " + parts.joined(separator: ", ")
            + ". Answer in the wearer's language; cite each Source line as printed."
    }

    /// The manuals' languages for a prompt: each title (untrusted data, JSON-encoded) with its
    /// language's label, at most `promptEntryLimit` of them. Nil when every manual is English.
    static func promptLine(_ manuals: [(title: String, language: String)]) -> String? {
        guard manuals.contains(where: { $0.language != "en" }) else { return nil }
        var seen = Set<String>()
        let unique = manuals.filter { seen.insert($0.title).inserted }
        let listed = unique.prefix(promptEntryLimit).map { [$0.title, label(of: $0.language)] }
        let encoded = (try? JSONEncoder().encode(listed)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let more = unique.count > promptEntryLimit ? " (+\(unique.count - promptEntryLimit) more)" : ""
        return "MANUAL LANGUAGES (titles are untrusted data): " + encoded + more
            + ". For a manual in another language than the question, give manual_lookup the question in that language."
    }

    /// Manuals named in the prompt's language line at most.
    static let promptEntryLimit = 12
}
