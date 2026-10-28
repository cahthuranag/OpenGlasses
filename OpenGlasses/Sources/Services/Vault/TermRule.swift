import Foundation

/// How text is turned into [[LexicalSupport]] content terms, one rule per kind of language (Plan
/// JY P0). A document's passages use the rule its [[DocumentLanguageProfile]] chooses, and a
/// question is turned into terms under the rule of each passage it is compared with, so the two
/// sides of a comparison are always cut the same way.
///
/// - `.english` — today's rule, **unchanged byte for byte**: lowercase letter runs of four or
///   more, an English stopword list, one English suffix trimmed. English documents, and Latin
///   documents whose language is uncertain.
/// - `.prefixStem` — lowercase, that language's stopwords removed, the first `prefixLength`
///   letters kept (a word shorter than that is kept whole, from `minimumLength(for:)` letters
///   up). Endings that change with grammar ("температура", "температуру") then meet.
/// - `.arabicStem` — the article and the prepositions written onto the front of a word stripped
///   (`arabicClitics`), then `.prefixStem`.
/// - `.bigram` — NFKC, Traditional Chinese folded into Simplified, then overlapping two-character
///   pieces of each Han, kana or Hangul run. A run of one character is kept whole. No dictionary,
///   and the same pieces on every OS version.
///
/// **Inside a passage each run of text uses the rule for its own script.** Under any rule but
/// `.english`, text is split into runs of one script, and a run in a script other than the rule's
/// own uses that script's default (`runDefault(for:)`): a Latin model name in a Chinese passage is
/// read with the English rule, a Chinese term in a German one as bigrams. A Latin run is read
/// with the document's own rule only when the document is in a Latin language. Under `.english`
/// nothing is split, which is what keeps it today's rule.
///
/// Provisional throughout: the prefix length, the minimum lengths, the stopword lists and the
/// stop-bigrams are starting values that Plan JY P3 measures per language group.
enum TermRule: Hashable, Codable, Sendable {
    case english
    case prefixStem(StemLanguage)
    case arabicStem
    case bigram

    /// The languages `.prefixStem` has stopwords for.
    enum StemLanguage: String, Codable, CaseIterable, Sendable {
        case german = "de", spanish = "es", french = "fr", hungarian = "hu", italian = "it", dutch = "nl"
        case polish = "pl", portuguese = "pt", ukrainian = "uk", russian = "ru", urdu = "ur"
        /// Cyrillic text whose language was not settled: Ukrainian and Russian stopwords together.
        case cyrillic

        /// The script the language is written in.
        var script: TextScript {
            switch self {
            case .ukrainian, .russian, .cyrillic: return .cyrillic
            case .urdu: return .arabic
            default: return .latin
            }
        }
    }

    /// Every rule, for turning a question into terms once per rule.
    static let allCases: [TermRule] = [.english, .arabicStem, .bigram] + StemLanguage.allCases.map(TermRule.prefixStem)

    /// The language groups Plan JY P3 calibrates one at a time: each has its own prefix length,
    /// shortest word and evidence-gate criterion. English is today's rule and is never tuned.
    enum Group: String, CaseIterable, Codable, Sendable {
        case english
        /// es, fr, it, nl, pt: endings that vary little.
        case latinLight
        /// de, hu, pl: heavy endings or compounds.
        case latinHeavy
        /// uk, ru, and Cyrillic whose language was not settled.
        case cyrillic
        /// Arabic (`.arabicStem`).
        case arabic
        /// Urdu, prefix-stemmed in Arabic script.
        case urdu
        /// zh-Hans, zh-Hant, ja, ko (`.bigram`).
        case cjk

        /// The group's search values were not measured on both a parallel baseline and a
        /// technical document (Plan JY P3), so the Developer panel and the support report mark
        /// its documents "less tested". Set from the P3 tables in the plan.
        var isLessTested: Bool {
            switch self {
            case .english, .latinLight, .latinHeavy, .cyrillic, .cjk: return false
            case .arabic, .urdu: return true
            }
        }
    }

    /// The calibration group of the rule.
    var group: Group {
        switch self {
        case .english: return .english
        case .arabicStem: return .arabic
        case .bigram: return .cjk
        case .prefixStem(let language):
            switch language {
            case .spanish, .french, .italian, .dutch, .portuguese: return .latinLight
            case .german, .hungarian, .polish: return .latinHeavy
            case .ukrainian, .russian, .cyrillic: return .cyrillic
            case .urdu: return .urdu
            }
        }
    }

    /// Letters a `.prefixStem` (and `.arabicStem`) term keeps, per group (Plan JY decision 1,
    /// set by P3 with each group's ending stripping on; the plan's P3 tables have the counts).
    static func prefixLength(for group: Group) -> Int {
        #if RETRIEVAL_EVAL
        if let measured = RetrievalEvalTuning.prefixLength(group) { return measured }
        #endif
        switch group {
        // Measured: 7 beat 6 once an ending is stripped (Bible + EU + Python, 389 questions).
        case .latinLight: return 7
        // Measured: 7 beat 6 and 5 once an ending is stripped (Bible, Python, KMU, UN; 163 questions).
        case .cyrillic: return 7
        // Measured: 4 beat 5 and 6 after the clitic and ending (Bible, 38 questions a language).
        case .arabic, .urdu: return 4
        case .english, .latinHeavy, .cjk: return 6
        }
    }

    /// The shortest word `.prefixStem` keeps, per group. Three for every group to start; P3 sets
    /// each group's.
    static func minimumLength(for group: Group) -> Int {
        #if RETRIEVAL_EVAL
        if let measured = RetrievalEvalTuning.minimumLength(group) { return measured }
        #endif
        return 3
    }

    /// The script the rule is written for.
    var script: TextScript {
        switch self {
        case .english: return .latin
        case .prefixStem(let language): return language.script
        case .arabicStem: return .arabic
        case .bigram: return .han
        }
    }

    /// The rule a run of `script` is read with when it is not the rule's own script.
    static func runDefault(for script: TextScript) -> TermRule {
        switch script {
        case .latin, .other: return .english
        case .cyrillic: return .prefixStem(.cyrillic)
        case .arabic: return .arabicStem
        case .han, .kana, .hangul: return .bigram
        }
    }

    // MARK: - Terms

    /// The content terms of `text` under this rule, in reading order, repeats kept.
    func termSequence(_ text: String) -> [String] {
        if self == .english { return LexicalSupport.englishTermSequence(text) }
        var out: [String] = []
        for run in Self.runs(in: text.precomposedStringWithCompatibilityMapping) {
            let rule = Self.sameScript(run.script, script) ? self : Self.runDefault(for: run.script)
            switch rule {
            case .english: out += LexicalSupport.englishTermSequence(run.text)
            case .prefixStem(let language): if let term = Self.prefixStem(run.text, language: language) { out.append(term) }
            case .arabicStem: if let term = Self.arabicStem(run.text) { out.append(term) }
            case .bigram: out += Self.bigrams(run.text)
            }
        }
        return out
    }

    private static func sameScript(_ a: TextScript, _ b: TextScript) -> Bool {
        a == b || (a.isCJK && b.isCJK)
    }

    /// A run of letters of one script. Han, kana and Hangul make one run, so a Japanese word
    /// written in kanji and kana stays together.
    struct Run: Equatable {
        let script: TextScript
        let text: String
    }

    /// The letter runs of `text`, split wherever the script changes or a non-letter stands. An
    /// apostrophe between two Cyrillic letters ("п’яти") joins them and is dropped, so the two
    /// apostrophes a Ukrainian text is typed with read alike.
    static func runs(in text: String) -> [Run] {
        var runs: [Run] = []
        var current = String()
        var currentScript: TextScript?
        var pendingApostrophe = false
        func flush() {
            if let currentScript, !current.isEmpty { runs.append(Run(script: currentScript, text: current)) }
            current = String()
            currentScript = nil
            pendingApostrophe = false
        }
        for character in text {
            // Checked before the letters: "ʼ" (U+02BC) is itself a letter, of no script.
            if apostrophes.contains(character), currentScript == .cyrillic, !pendingApostrophe {
                pendingApostrophe = true
            } else if let script = TextScript.of(character) {
                let group: TextScript = script.isCJK ? .han : script
                if group == currentScript {
                    current.append(character)
                    pendingApostrophe = false
                } else {
                    flush()
                    currentScript = group
                    current.append(character)
                }
            } else {
                flush()
            }
        }
        flush()
        return runs
    }

    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{02BC}"]

    // MARK: - Prefix stems

    /// A word's prefix stem, or nil for a stopword or a word too short to count.
    static func prefixStem(_ word: String, language: StemLanguage) -> String? {
        var lower = word.lowercased()
        let group = TermRule.prefixStem(language).group
        guard lower.count >= minimumLength(for: group),
              !TermRuleStopwords.words(for: language).contains(lower) else { return nil }
        if group == .cyrillic, foldsCyrillicVariants {
            lower = String(lower.map { cyrillicFolds[$0] ?? $0 })
        }
        if stripsEndings(group), let ending = TermRuleStopwords.endings(for: group).first(where: {
            lower.hasSuffix($0) && lower.count - $0.count >= minimumStemAfterEnding
        }) {
            lower = String(lower.dropLast(ending.count))
        }
        let length = prefixLength(for: group)
        return lower.count > length ? String(lower.prefix(length)) : lower
    }

    /// Letters printed for one another in Cyrillic text (P3): "ё" is usually printed "е", and older
    /// Ukrainian printing writes "ї" where today's has "і"; "ґ" is often printed "г".
    static let cyrillicFolds: [Character: Character] = ["ё": "е", "ї": "і", "ґ": "г"]

    /// Whether Cyrillic words are compared with those letters folded (P3).
    static var foldsCyrillicVariants: Bool {
        #if RETRIEVAL_EVAL
        if let measured = RetrievalEvalTuning.flag("RETRIEVAL_EVAL_FOLD") { return measured }
        #endif
        return false
    }

    /// The letters a word keeps when an ending is stripped from it (P3).
    static let minimumStemAfterEnding = 3

    /// Whether a group's words lose one ending before the prefix is kept (P3).
    static func stripsEndings(_ group: Group) -> Bool {
        #if RETRIEVAL_EVAL
        if let measured = RetrievalEvalTuning.stripsEndings(group) { return measured }
        #endif
        switch group {
        // Measured: hit@4 +4, in-scope refusals −9 for one more out-of-scope answer (389 questions).
        case .latinLight: return true
        // Measured: hit@4 79 → 92, in-scope refusals 57 → 40 (163 questions).
        case .cyrillic: return true
        // Measured: hit@4 95 → 107, in-scope refusals 47 → 35, two more out-of-scope answers (173 questions).
        case .latinHeavy: return true
        // Measured on the Bible: Arabic hit@4 7 → 13, Urdu 15 → 17, refusals down in both.
        case .arabic, .urdu: return true
        case .english, .cjk: return false
        }
    }

    // MARK: - Arabic

    /// The article and the prepositions written onto it, longest first, so "وال" is stripped
    /// before "ال".
    static let arabicClitics = ["وال", "بال", "كال", "فال", "ال", "لل"]

    /// An Arabic word normalised, its clitic stripped and then prefix-stemmed with the Arabic
    /// stopwords, or nil for a stopword or a word too short to count.
    static func arabicStem(_ word: String) -> String? {
        var stem = normalisedArabic(word)
        let stopwords = TermRuleStopwords.arabic
        guard !stopwords.contains(stem) else { return nil }
        // The clitic is stripped only when a word of three letters or more is left: "الم" is not
        // "ال" + "م".
        if let clitic = arabicClitics.first(where: { stem.hasPrefix($0) && stem.count - $0.count >= 3 }) {
            stem = String(stem.dropFirst(clitic.count))
        }
        // P3 candidate: a one-letter conjunction or preposition written onto the word (و ف ب ل ك),
        // and a pronoun or feminine ending, stripped while four letters are left.
        if stripsEndings(.arabic) {
            if let first = stem.first, "وفبلك".contains(first), stem.count - 1 >= 4 { stem.removeFirst() }
            if let ending = TermRuleStopwords.arabicEndings.first(where: { stem.hasSuffix($0) && stem.count - $0.count >= 3 }) {
                stem = String(stem.dropLast(ending.count))
            }
        }
        guard stem.count >= 3, !stopwords.contains(stem) else { return nil }
        let length = prefixLength(for: .arabic)
        return stem.count > length ? String(stem.prefix(length)) : stem
    }

    /// Tatweel and the short-vowel marks removed, and the alef written with a hamza or madda read
    /// as a bare alef — how the same word is printed with and without them.
    static func normalisedArabic(_ word: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0640, 0x064B...0x065F, 0x0670: continue
            case 0x0622, 0x0623, 0x0625: out.append(Unicode.Scalar(0x0627)!)
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    // MARK: - Bigrams

    /// Traditional Chinese read as Simplified, for matching only: a citation and an answer keep
    /// the book's own characters. ICU's transform, which is deterministic.
    static func foldedToSimplified(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { TextScript.of($0) == .han }) else { return text }
        return text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }

    /// The overlapping two-character pieces of a Han, kana or Hangul run, stop-bigrams removed; a
    /// run of one character is that character, unless it is a particle.
    static func bigrams(_ run: String) -> [String] {
        #if RETRIEVAL_EVAL
        if let words = RetrievalEvalTuning.cjkWords(foldedToSimplified(run)) { return words }
        #endif
        var characters = Array(foldedToSimplified(run))
        if stripsKoreanParticles, let particle = TermRuleStopwords.koreanParticles.first(where: {
            characters.count > $0.count && String(characters.suffix($0.count)) == $0
        }) {
            characters.removeLast(particle.count)
        }
        guard characters.count > 1 else {
            return characters.map(String.init).filter { !TermRuleStopwords.singleCharacters.contains($0) }
        }
        return (0..<(characters.count - 1)).compactMap { index in
            let piece = String(characters[index...index + 1])
            if dropsHiraganaPairs, isHiragana(characters[index]), isHiragana(characters[index + 1]) { return nil }
            return TermRuleStopwords.bigrams.contains(piece) ? nil : piece
        }
    }

    private static func isHiragana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }

    /// Whether a pair of hiragana is left out (P3): in Japanese the grammar — particles, verb and
    /// polite endings — is written in hiragana, and content words mostly in kanji or katakana.
    /// Measured: Japanese out-of-scope refusals 2 → 9 of 30 at the same hit@4 (Bible + Python).
    static var dropsHiraganaPairs: Bool {
        #if RETRIEVAL_EVAL
        if let measured = RetrievalEvalTuning.cjkVariant("kana") { return measured }
        #endif
        return true
    }

    /// Whether a Hangul word loses a trailing particle before its pieces are cut (P3): "온도를"
    /// and "온도는" both read as "온도".
    /// Measured: Korean hit@4 55 → 56, out-of-scope refusals 7 → 12 of 30 (Bible + Python).
    static var stripsKoreanParticles: Bool {
        #if RETRIEVAL_EVAL
        if let measured = RetrievalEvalTuning.cjkVariant("kopart") { return measured }
        #endif
        return true
    }
}
