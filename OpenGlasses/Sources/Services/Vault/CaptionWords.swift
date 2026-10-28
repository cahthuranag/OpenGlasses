import Foundation

/// The words a table or figure caption starts with in the interface languages other than English,
/// and the words that say a table carries on from an earlier page (Plan JY P4).
///
/// English keeps its own rules, read first and unchanged (`TableExtractor.caption`,
/// `ManualStructure.caption`): a line that is an English caption never reaches these. A caption
/// found here gets the same canonical label an English one gets ("Table 7", "Figure 3"), because
/// the label is how a table is named everywhere else — a row passage's `figure`, a question's
/// table reference, the table directory — while its title stays as printed.
///
/// Recognised, case-insensitively, then a label (`TableExtractor.labelPattern`, its digits read as
/// ASCII):
/// - **Tables:** Tabelle, Tableau, Tabla, Tabella, Tabel, Tabela, Quadro, Таблица, Таблиця, جدول
///   (and الجدول, optionally "رقم"), 表, 표; Hungarian puts the number first ("3. táblázat").
/// - **Figures:** Abbildung, Abb., Figura, Figuur, Afbeelding, Rysunek, Rys., Рисунок, Рис., شكل
///   (الشكل), شکل, 图, 圖, 図, 그림; Hungarian "3. ábra".
/// - **Carrying on:** a caption opened by 续表 or 續表, "Fortsetzung (von) Tabelle", "Продолжение
///   таблицы", "Продовження таблиці" or "تابع الجدول"; or a title holding, in brackets or at its
///   end, Fortsetzung, suite, continuación, continuação, continua, segue, vervolg, ciąg dalszy,
///   folytatás, продолжение, продовження, تابع, جاری, 続き, 계속 (and Forts., продолж., продовж.) —
///   or a last-page word (Schluss, fin, conclusión, окончание, оконч., закінчення).
///
/// A CJK caption needs no space before its number, so it must not run straight on into a word
/// ("表1中…" is a sentence that mentions a table, not a caption). Pure and deterministic.
enum CaptionWords {

    enum Kind: Equatable { case table, figure }

    struct Match: Equatable {
        let kind: Kind
        /// "Table 7", "Figure 3A": the canonical label.
        let label: String
        /// What follows the label on the line, continuation words removed, trimmed.
        let title: String
        /// Whether the caption carries on a table begun on an earlier page.
        let continues: Bool
    }

    private static let label = TableExtractor.labelPattern
    /// After a CJK caption's label: not a Han, kana or Hangul letter.
    private static let notIntoCJK = #"(?![\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}])"#

    private static let tableWords = #"Tabelle|Tableau|Tabla|Tabella|Tabel|Tabela|Quadro|Таблица|Таблиця|(?:ال)?جدول(?:\s+رقم)?"#
    private static let figureWords = #"Abbildung|Abb\.|Figura|Figuur|Afbeelding|Rysunek|Rys\.|Рисунок|Рис\.|(?:ال)?شكل|شکل"#
    private static let carriedTableWords = #"Fortsetzung\s+(?:der\s+|von\s+)?Tabelle|Продолжение\s+таблицы|Окончание\s+таблицы|Продовження\s+таблиці|Закінчення\s+таблиці|تابع\s+(?:ال)?جدول"#

    /// Each form: its regex (the label in group 1), its kind, and whether the form itself says the
    /// table carries on.
    private static let forms: [(pattern: String, kind: Kind, carried: Bool)] = [
        (#"^(?:续表|續表)\s*("# + label + ")" + notIntoCJK, .table, true),
        (#"^(?:表|표)\s*("# + label + ")" + notIntoCJK, .table, false),
        (#"^(?:图|圖|図|그림)\s*("# + label + ")" + notIntoCJK, .figure, false),
        (#"^(?i:"# + carriedTableWords + #")\s+("# + label + ")", .table, true),
        (#"^(?i:"# + tableWords + #")\s+\(?("# + label + ")", .table, false),
        (#"^(?i:"# + figureWords + #")\s*("# + label + ")", .figure, false),
        (#"^("# + label + #")\.?\s+(?i:táblázat)"#, .table, false),
        (#"^("# + label + #")\.?\s+(?i:ábra)"#, .figure, false)
    ]

    private static let carryingWords = #"Fortsetzung|suite|continuación|continuação|continua|segue|vervolg|ciąg dalszy|folytatás|продолжение|продовження|تابع|جاری|続き|계속|Schluss|fin|conclusión|окончание|закінчення|Forts|продолж|продовж|оконч"#
    /// The words distinctive enough to say it unbracketed, at the end of the title.
    private static let bareCarryingWords = #"Fortsetzung|continuación|continuação|ciąg dalszy|folytatás|продолжение|продовження|окончание|закінчення"#
    /// A carrying-on word in brackets anywhere in the title, or ending it.
    private static let carryingPatterns = [
        #"[\(\[（]\s*(?i:"# + carryingWords + #")\.?\s*[\)\]）]"#,
        #"(?:^|[\s,\u{2013}\u{2014}-])(?i:"# + bareCarryingWords + #")\.?\s*$"#
    ]
    private static let compiled: [(regex: NSRegularExpression, kind: Kind, carried: Bool)] = forms.compactMap { form in
        (try? NSRegularExpression(pattern: form.pattern)).map { ($0, form.kind, form.carried) }
    }

    /// The caption a line starts with in a language other than English, else nil.
    static func match(_ text: String) -> Match? {
        #if RETRIEVAL_EVAL
        if RetrievalEvalTuning.p4Off.contains("captions") { return nil }
        #endif
        for form in compiled {
            guard let found = form.regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let whole = Range(found.range, in: text), let number = Range(found.range(at: 1), in: text) else { continue }
            var title = String(text[whole.upperBound...])
            var continues = form.carried
            for pattern in carryingPatterns {
                if let range = title.range(of: pattern, options: .regularExpression) {
                    continues = true
                    title.removeSubrange(range)
                }
            }
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: " \t.:\u{2014}\u{2013}-\u{FF1A}\u{3001})）"))
            let word = form.kind == .table ? "Table" : "Figure"
            return Match(kind: form.kind, label: "\(word) \(asciiDigits(String(text[number])))", title: title, continues: continues)
        }
        return nil
    }

    /// Any decimal digit (Arabic-Indic, Extended Arabic-Indic, full-width) read as its ASCII digit.
    static func asciiDigits(_ text: String) -> String {
        String(text.map { character -> Character in
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
                  scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue,
                  !(0x30...0x39).contains(scalar.value) else { return character }
            return Character(String(Int(value)))
        })
    }
}
