import Foundation
import NaturalLanguage

/// Which of Apple's contextual embedding models reads a document's text (Plan JY P1).
///
/// `NLContextualEmbedding` is one model per script, measured on the Mac: Latin (`Latn`, 20
/// languages), Cyrillic, Arabic, CJK (Hans, Hant, Jpan, Kore), and an Indic model that Apple maps
/// `ur` to. A model given text in another script returns a vector, but it is noise — the Latin
/// model scored a Chinese question 0.968 against its answer and 0.965 against an unrelated
/// sentence — so a document's passages are only ever embedded, and compared, with its own
/// script's model.
///
/// - `.latin` is today's choice, unchanged: Field Assist's model for a vault, the store's own
///   embedder for everything else. A document whose script is `.other` (Greek, Hebrew, no letters)
///   stays here too; no interface language is written in it.
/// - `.urdu` is Urdu in Arabic script, read by the model Apple maps `ur` to. Its scripts list no
///   Arabic, but measured on invented Urdu sentences it separates an answer from an unrelated
///   sentence (margins 0.19–0.20) as well as it does Devanagari Hindi (0.21), while the Arabic
///   model reads the same Urdu as noise (0.01–0.03). See the plan's P1 table.
///
/// An Arabic-script document whose language was not settled is read as Arabic, the way its term
/// rule defaults to `.arabicStem`.
enum EmbeddingScript: String, CaseIterable, Codable, Hashable, Sendable {
    case latin, cyrillic, arabic, cjk, urdu

    /// The language whose `NLContextualEmbedding` is this script's model. Ukrainian and Russian
    /// share the Cyrillic model; Chinese, Japanese and Korean share the CJK one.
    var contextualLanguage: NLLanguage {
        switch self {
        case .latin: return .english
        case .cyrillic: return .russian
        case .arabic: return .arabic
        case .cjk: return .simplifiedChinese
        case .urdu: return .urdu
        }
    }

    /// The model that embeds a document with `profile`.
    init(profile: DocumentLanguageProfile) {
        switch profile.script {
        case .latin, .other, .kana:
            self = .latin
        case .cyrillic:
            self = .cyrillic
        case .arabic:
            self = profile.language == "ur" ? .urdu : .arabic
        case .han, .hangul:
            self = .cjk
        }
    }

    /// The script a phone language (`Locale.preferredLanguages`: "uk-UA", "zh-Hans-CN", "ur") is
    /// written in, or nil for a language outside the interface's scripts.
    static func of(preferredLanguage identifier: String) -> EmbeddingScript? {
        let code = Locale(identifier: identifier).language.languageCode?.identifier
            ?? String(identifier.prefix { $0 != "-" && $0 != "_" })
        switch code.lowercased() {
        case "en", "de", "es", "fr", "hu", "it", "nl", "pl", "pt": return .latin
        case "uk", "ru": return .cyrillic
        case "ar": return .arabic
        case "ur": return .urdu
        case "zh", "ja", "ko": return .cjk
        default: return nil
        }
    }

    /// The scripts other than Latin that the phone's languages are written in, in the phone's
    /// order and without repeats — the models fetched ahead of time for manual search. Latin is
    /// left out: its asset is Field Assist's own (`Embedder.prepareFieldAssistAssets`).
    static func aheadOfTime(preferredLanguages: [String]) -> [EmbeddingScript] {
        var out: [EmbeddingScript] = []
        for identifier in preferredLanguages {
            guard let script = of(preferredLanguage: identifier), script != .latin, !out.contains(script) else { continue }
            out.append(script)
        }
        return out
    }

    /// A short name for the Developer panel and the support report. Not localised: it is a
    /// diagnostic label, read alongside the model family.
    var diagnosticLabel: String {
        switch self {
        case .latin: return "Latin"
        case .cyrillic: return "Cyrillic"
        case .arabic: return "Arabic"
        case .cjk: return "CJK"
        case .urdu: return "Urdu"
        }
    }
}
