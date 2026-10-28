import Foundation
import NaturalLanguage

/// The writing system a letter belongs to, as far as manual search needs to know (Plan JY P0).
///
/// Only the scripts of the interface languages are told apart; every other letter (Greek, Hebrew,
/// Devanagari, Thai…) is `.other`. Classified by code-point block, so the answer is the same on
/// every OS version.
enum TextScript: String, Codable, Equatable, Hashable, Sendable {
    case latin, cyrillic, arabic, han, kana, hangul, other

    /// The script of `scalar`, or nil when it is not a letter.
    static func of(_ scalar: Unicode.Scalar) -> TextScript? {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: break
        default: return nil
        }
        return block(of: scalar.value)
    }

    /// The script of the first scalar of a character that is a letter (`Character.isLetter`), or
    /// nil when it is not one.
    static func of(_ character: Character) -> TextScript? {
        guard character.isLetter, let first = character.unicodeScalars.first else { return nil }
        return block(of: first.value)
    }

    private static func block(of value: UInt32) -> TextScript {
        switch value {
        case 0x41...0x5A, 0x61...0x7A, 0xAA, 0xBA, 0xC0...0x24F, 0x250...0x2AF, 0x1D00...0x1DBF,
             0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F, 0xFB00...0xFB06,
             0xFF21...0xFF3A, 0xFF41...0xFF5A:
            return .latin
        case 0x400...0x52F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
            return .cyrillic
        case 0x600...0x6FF, 0x750...0x77F, 0x870...0x8FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return .arabic
        case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F:
            return .kana
        case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7AF, 0xD7B0...0xD7FF, 0xFFA0...0xFFDC:
            return .hangul
        case 0x2E80...0x2FDF, 0x3005, 0x3007, 0x3021...0x3029, 0x3038...0x303B, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3FFFF:
            return .han
        default:
            return .other
        }
    }

    /// Han, kana or Hangul: a script whose terms are two-character pieces ([[TermRule]] `.bigram`).
    var isCJK: Bool { self == .han || self == .kana || self == .hangul }
}

/// A document's main script and, within it, its language (Plan JY P0) — what decides which
/// [[TermRule]] its passages are compared under.
///
/// **The script comes first, from a count of letters.** `NLLanguageRecognizer` alone labels a
/// Chinese sentence carrying "ResNet-50" and "ImageNet" as Catalan, and technical text mixes Latin
/// terms into every script. So the letters are counted per script — a Han, kana or Hangul
/// character weighing `ideographWeight` Latin letters, since one carries about a word's share of
/// a Latin one — and only then is the recogniser asked, constrained to that script's interface
/// languages, which language the main script's own text is. Within Han text, kana means Japanese;
/// Hangul text is Korean.
///
/// **When it is unsure it says so**, and the document gets its script's default rule: a Latin
/// document whose language is uncertain is read with today's English rule. Uncertain means too
/// few letters, a main script that is under half the weighted letters, or a recogniser
/// probability under `minimumConfidence`.
///
/// Pure and deterministic over its text. Stored with the document (`DocumentStore`), recomputed
/// when the document is re-indexed or when `currentVersion` moves; shown in no interface in P0.
struct DocumentLanguageProfile: Codable, Equatable, Sendable {
    /// Bumped when detection changes, so a stored profile is recomputed from the document's text.
    static let currentVersion = 1

    var version: Int
    /// The script most of the document's letters are in. Han for Chinese and Japanese (kana counts
    /// with Han), Hangul for Korean, `.other` for a document with no letters of a known script.
    var script: TextScript
    /// The interface language within `script` ("en", "uk", "zh-Hans", "ja"…), or nil when the
    /// detection was not sure enough to name one.
    var language: String?
    /// The recogniser's probability for `language` (1 for a decision read off the letters alone:
    /// kana, Hangul), or 0 when no language was decided.
    var confidence: Double
    /// The main script's share of the weighted letters, 0–1.
    var scriptShare: Double

    init(script: TextScript, language: String?, confidence: Double, scriptShare: Double,
         version: Int = DocumentLanguageProfile.currentVersion) {
        self.version = version
        self.script = script
        self.language = language
        self.confidence = confidence
        self.scriptShare = scriptShare
    }

    /// What a document with nothing to read is: today's rule.
    static let unknown = DocumentLanguageProfile(script: .other, language: nil, confidence: 0, scriptShare: 0)

    /// The rule the document's passages are compared under.
    var termRule: TermRule {
        switch script {
        case .latin:
            return language.flatMap(TermRule.StemLanguage.init(rawValue:)).map(TermRule.prefixStem) ?? .english
        case .cyrillic:
            return .prefixStem(language.flatMap(TermRule.StemLanguage.init(rawValue:)) ?? .cyrillic)
        case .arabic:
            return language == TermRule.StemLanguage.urdu.rawValue ? .prefixStem(.urdu) : .arabicStem
        case .han, .kana, .hangul:
            return .bigram
        case .other:
            return .english
        }
    }

    // MARK: - Detection

    /// A Han, kana or Hangul character counts as this many Latin letters.
    static let ideographWeight = 3
    /// Fewer weighted letters of the main script than this and no language is named.
    static let minimumLetters = 20
    /// Below this share of the weighted letters the document is mixed and no language is named.
    static let minimumScriptShare = 0.5
    /// Below this recogniser probability no language is named (provisional until Plan JY P3).
    static let minimumConfidence = 0.8
    /// How much of the main script's text the recogniser reads: evenly spaced windows, so a
    /// bilingual cover page does not decide a whole manual.
    static let sampleWindows = 8
    static let sampleWindowLength = 2_500

    /// The interface languages written in each script, as the recogniser's constraints.
    static let latinLanguages: [NLLanguage] = [.english, .german, .spanish, .french, .hungarian, .italian,
                                               .dutch, .polish, .portuguese]
    static let cyrillicLanguages: [NLLanguage] = [.ukrainian, .russian]
    static let arabicLanguages: [NLLanguage] = [.arabic, .urdu]
    static let chineseLanguages: [NLLanguage] = [.simplifiedChinese, .traditionalChinese]

    /// The profile of `text`.
    static func detect(_ text: String) -> DocumentLanguageProfile {
        var counts: [TextScript: Int] = [:]
        for scalar in text.unicodeScalars {
            if let script = TextScript.of(scalar) { counts[script, default: 0] += 1 }
        }
        let han = counts[.han, default: 0], kana = counts[.kana, default: 0], hangul = counts[.hangul, default: 0]
        // Han and kana are one script here: Japanese is written in both.
        let weighted: [(TextScript, Int)] = [
            (.latin, counts[.latin, default: 0]),
            (.cyrillic, counts[.cyrillic, default: 0]),
            (.arabic, counts[.arabic, default: 0]),
            (.han, (han + kana) * ideographWeight),
            (.hangul, hangul * ideographWeight),
            (.other, counts[.other, default: 0]),
        ]
        let total = weighted.reduce(0) { $0 + $1.1 }
        // The first of the largest, in the order above: a tie goes to Latin.
        let largest = weighted.map(\.1).max() ?? 0
        guard total > 0, let main = weighted.first(where: { $0.1 == largest }) else { return .unknown }
        let share = Double(main.1) / Double(total)
        let settled = main.1 >= minimumLetters && share >= minimumScriptShare

        switch main.0 {
        case .hangul:
            return DocumentLanguageProfile(script: .hangul, language: settled ? "ko" : nil,
                                           confidence: settled ? 1 : 0, scriptShare: share)
        case .han:
            // Kana is a twentieth of the Han-and-kana letters or more: Japanese. A Chinese text
            // quoting a Japanese name or two stays Chinese.
            if kana * 20 >= han + kana, kana > 0 {
                return DocumentLanguageProfile(script: .han, language: settled ? "ja" : nil,
                                               confidence: settled ? 1 : 0, scriptShare: share)
            }
            return recognised(text, script: .han, among: chineseLanguages, share: share, settled: settled)
        case .latin:
            return recognised(text, script: .latin, among: latinLanguages, share: share, settled: settled)
        case .cyrillic:
            return recognised(text, script: .cyrillic, among: cyrillicLanguages, share: share, settled: settled)
        case .arabic:
            return recognised(text, script: .arabic, among: arabicLanguages, share: share, settled: settled)
        case .kana, .other:
            return DocumentLanguageProfile(script: .other, language: nil, confidence: 0, scriptShare: share)
        }
    }

    /// The recogniser's language for the main script's own letters, when it is sure enough.
    private static func recognised(_ text: String, script: TextScript, among languages: [NLLanguage],
                                   share: Double, settled: Bool) -> DocumentLanguageProfile {
        guard settled else {
            return DocumentLanguageProfile(script: script, language: nil, confidence: 0, scriptShare: share)
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = languages
        recognizer.processString(sample(of: text, script: script))
        let hypotheses = recognizer.languageHypotheses(withMaximum: languages.count + 2)
        guard let best = languages.map({ ($0, hypotheses[$0] ?? 0) }).max(by: { $0.1 < $1.1 }),
              best.1 >= minimumConfidence else {
            return DocumentLanguageProfile(script: script, language: nil, confidence: 0, scriptShare: share)
        }
        return DocumentLanguageProfile(script: script, language: best.0.rawValue, confidence: best.1, scriptShare: share)
    }

    /// The text with every letter not of `script` (kana counting as Han) turned into a space, cut
    /// to `sampleWindows` evenly spaced windows when it is long.
    static func sample(of text: String, script: TextScript) -> String {
        var kept = String()
        kept.reserveCapacity(min(text.utf8.count, sampleWindows * sampleWindowLength * 4))
        for character in text {
            if let letter = TextScript.of(character) {
                let same = letter == script || (script == .han && letter == .kana)
                kept.append(same ? character : " ")
            } else {
                kept.append(character)
            }
        }
        let characters = Array(kept)
        let budget = sampleWindows * sampleWindowLength
        guard characters.count > budget else { return kept }
        let stride = characters.count / sampleWindows
        return (0..<sampleWindows).map { window in
            let start = window * stride
            return String(characters[start..<min(start + sampleWindowLength, characters.count)])
        }.joined(separator: "\n")
    }
}
