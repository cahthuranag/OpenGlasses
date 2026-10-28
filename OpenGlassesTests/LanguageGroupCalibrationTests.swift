import XCTest
@testable import OpenGlasses

/// Plan JY P3 — the values each language group was calibrated to, and the "less tested" mark.
/// The measurements behind them are in the plan's P3 tables; these tests pin the values and
/// what they do to invented words. English is pinned unchanged.
final class LanguageGroupCalibrationTests: XCTestCase {

    // MARK: - Groups

    func testEachRuleBelongsToItsGroup() {
        XCTAssertEqual(TermRule.english.group, .english)
        XCTAssertEqual(TermRule.bigram.group, .cjk)
        XCTAssertEqual(TermRule.arabicStem.group, .arabic)
        XCTAssertEqual(TermRule.prefixStem(.urdu).group, .urdu)
        for language: TermRule.StemLanguage in [.spanish, .french, .italian, .dutch, .portuguese] {
            XCTAssertEqual(TermRule.prefixStem(language).group, .latinLight, language.rawValue)
        }
        for language: TermRule.StemLanguage in [.german, .hungarian, .polish] {
            XCTAssertEqual(TermRule.prefixStem(language).group, .latinHeavy, language.rawValue)
        }
        for language: TermRule.StemLanguage in [.ukrainian, .russian, .cyrillic] {
            XCTAssertEqual(TermRule.prefixStem(language).group, .cyrillic, language.rawValue)
        }
    }

    func testTheMeasuredPrefixLengths() {
        XCTAssertEqual(TermRule.prefixLength(for: .latinLight), 7)
        XCTAssertEqual(TermRule.prefixLength(for: .cyrillic), 7)
        XCTAssertEqual(TermRule.prefixLength(for: .arabic), 4)
        XCTAssertEqual(TermRule.prefixLength(for: .urdu), 4)
        XCTAssertEqual(TermRule.prefixLength(for: .latinHeavy), 6)
        XCTAssertEqual(TermRule.prefixLength(for: .cjk), 6, "unused: bigrams have no prefix")
    }

    // MARK: - English unchanged

    func testTheEnglishRuleIsTodaysRule() {
        let sentence = "Checking the flame sensors before measuring gases and matches"
        XCTAssertEqual(TermRule.english.termSequence(sentence), LexicalSupport.englishTermSequence(sentence))
        XCTAssertFalse(TermRule.stripsEndings(.english))
        XCTAssertNil(RetrievalEvidencePolicy.default(for: "nl-contextual.x").groupCriteria[.english])
    }

    // MARK: - Endings

    func testCyrillicFormsShorterThanThePrefixMeet() {
        let rule = TermRule.prefixStem(.ukrainian)
        XCTAssertEqual(rule.termSequence("жінка"), rule.termSequence("жінкою"))
        XCTAssertEqual(rule.termSequence("температура"), rule.termSequence("температуру"))
        XCTAssertEqual(TermRule.prefixStem(.russian).termSequence("насоса"), TermRule.prefixStem(.russian).termSequence("насосом"))
        XCTAssertNotEqual(rule.termSequence("насос"), rule.termSequence("насіння"), "different words stay apart")
    }

    func testLightLatinPluralsMeet() {
        let spanish = TermRule.prefixStem(.spanish)
        XCTAssertEqual(spanish.termSequence("válvula"), spanish.termSequence("válvulas"))
        let italian = TermRule.prefixStem(.italian)
        XCTAssertEqual(italian.termSequence("filtro"), italian.termSequence("filtri"))
    }

    func testHeavyLatinFormsMeet() {
        let german = TermRule.prefixStem(.german)
        XCTAssertEqual(german.termSequence("Pumpe"), german.termSequence("Pumpen"))
        let polish = TermRule.prefixStem(.polish)
        XCTAssertEqual(polish.termSequence("pompa"), polish.termSequence("pompy"))
    }

    func testAnEndingIsStrippedOnlyWhenAStemIsLeft() {
        XCTAssertEqual(TermRule.prefixStem(.ukrainian).termSequence("дах"), ["дах"], "three letters: nothing stripped")
    }

    func testArabicLosesItsConjunctionAndPronoun() {
        // "and its valve" and "the valve": و + صمام + ه, ال + صمام.
        XCTAssertEqual(TermRule.arabicStem.termSequence("وصمامه"), TermRule.arabicStem.termSequence("الصمام"))
        XCTAssertEqual(TermRule.arabicStem.termSequence("الصمام"), ["صمام"])
    }

    func testUrduPluralsMeet() {
        let rule = TermRule.prefixStem(.urdu)
        XCTAssertEqual(rule.termSequence("مشینیں"), rule.termSequence("مشین"))
    }

    // MARK: - CJK

    func testJapaneseHiraganaPairsAreLeftOut() {
        let terms = TermRule.bigram.termSequence("温度を確認しました")
        XCTAssertTrue(terms.contains("温度"))
        XCTAssertTrue(terms.contains("確認"))
        XCTAssertFalse(terms.contains("しま"), "grammar, written in hiragana, is not a term")
        XCTAssertFalse(terms.contains("した"))
    }

    func testAKoreanWordLosesItsParticle() {
        XCTAssertEqual(TermRule.bigram.termSequence("온도를"), ["온도"])
        XCTAssertEqual(TermRule.bigram.termSequence("온도는"), ["온도"])
    }

    func testChineseBigramsAreUnchanged() {
        XCTAssertEqual(TermRule.bigram.termSequence("测量温度"), ["测量", "量温", "温度"])
    }

    // MARK: - Gate

    func testArabicAsksHalfTheQuestionsTerms() {
        let policy = RetrievalEvidencePolicy.default(for: "nl-contextual.x")
        XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: 4, rule: .arabicStem), 2)
        XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: 4, rule: .english), 3, "English keeps 0.6")
        XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: 4, rule: .bigram), 3)
        XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: 10, rule: .arabicStem), 3, "never more than three")
    }

    func testHeavyLatinAsksThreeQuartersOfTheQuestionsTerms() {
        let policy = RetrievalEvidencePolicy.default(for: "nl-contextual.x")
        XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: 3, rule: .prefixStem(.german)), 3)
        XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: 3, rule: .english), 2)
        XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: 3, rule: .prefixStem(.french)), 2, "light Latin keeps 0.6")
    }

    func testTheGroupCriteriaHoldForEveryBackendWithALexicalCriterion() {
        for model in ["nl-word.en", "nl-sentence.en", "nl-contextual.x"] {
            XCTAssertEqual(RetrievalEvidencePolicy.default(for: model).groupCriteria,
                           RetrievalEvidencePolicy.measuredGroupCriteria, model)
        }
        XCTAssertTrue(RetrievalEvidencePolicy.default(for: "none.en").groupCriteria.isEmpty)
        XCTAssertEqual(RetrievalEvidencePolicy().requiredSharedTerms(queryTermCount: 4, rule: .arabicStem), 0,
                       "no lexical criterion, no group criterion")
    }

    func testAPendingPassageAsksMoreOfItsGroup() {
        let policy = RetrievalEvidencePolicy.default(for: "nl-contextual.x")
        // Arabic: 0.5 + 0.15 of four terms is three.
        XCTAssertEqual(policy.requiredSharedTermsWithoutVector(queryTermCount: 4, rule: .arabicStem), 3)
        XCTAssertEqual(policy.requiredSharedTermsWithoutVector(queryTermCount: 3, rule: .english), 3)
    }

    // MARK: - Less tested

    func testOnlyArabicAndUrduAreLessTested() {
        XCTAssertEqual(TermRule.Group.allCases.filter(\.isLessTested), [.arabic, .urdu])
    }

    func testTheReportMarksLessTestedDocuments() {
        func diagnostic(_ script: EmbeddingScript, _ textScript: TextScript, _ language: String) -> DocumentStore.LanguageDiagnostic {
            DocumentStore.LanguageDiagnostic(
                documentId: UUID().uuidString, isManual: true,
                profile: DocumentLanguageProfile(script: textScript, language: language, confidence: 0.95, scriptShare: 0.9),
                script: script, modelClass: "contextual", chunksWithVectors: 3, chunks: 3)
        }
        let urdu = diagnostic(.urdu, .arabic, "ur")
        XCTAssertTrue(urdu.line.hasSuffix(" · less tested"))
        let chinese = diagnostic(.cjk, .han, "zh-Hans")
        XCTAssertFalse(chinese.line.contains("less tested"))
        let lines = ManualLanguageReport.lines([urdu, chinese, diagnostic(.arabic, .arabic, "ar")], models: [])
        XCTAssertEqual(lines[1], "Less tested: arabic 1, urdu 1")
        XCTAssertFalse(ManualLanguageReport.lines([chinese], models: []).contains { $0.hasPrefix("Less tested") })
    }
}
