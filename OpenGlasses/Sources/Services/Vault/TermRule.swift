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

    /// Letters a `.prefixStem` term keeps. 6 to start (Plan JY decision 1); P3 sets one per group.
    static let prefixLength = 6

    /// The shortest word `.prefixStem` keeps, per language. Three for every language to start;
    /// P3 sets each group's.
    static func minimumLength(for language: StemLanguage) -> Int { 3 }

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
            if let script = TextScript.of(character) {
                let group: TextScript = script.isCJK ? .han : script
                if group == currentScript {
                    current.append(character)
                    pendingApostrophe = false
                } else {
                    flush()
                    currentScript = group
                    current.append(character)
                }
            } else if apostrophes.contains(character), currentScript == .cyrillic, !pendingApostrophe {
                pendingApostrophe = true
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
        let lower = word.lowercased()
        guard lower.count >= minimumLength(for: language),
              !TermRuleStopwords.words(for: language).contains(lower) else { return nil }
        return lower.count > prefixLength ? String(lower.prefix(prefixLength)) : lower
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
        guard stem.count >= 3, !stopwords.contains(stem) else { return nil }
        return stem.count > prefixLength ? String(stem.prefix(prefixLength)) : stem
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
        let characters = Array(foldedToSimplified(run))
        guard characters.count > 1 else {
            return characters.map(String.init).filter { !TermRuleStopwords.singleCharacters.contains($0) }
        }
        return (0..<(characters.count - 1)).compactMap { index in
            let piece = String(characters[index...index + 1])
            return TermRuleStopwords.bigrams.contains(piece) ? nil : piece
        }
    }
}
