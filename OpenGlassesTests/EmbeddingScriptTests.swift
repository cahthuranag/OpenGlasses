import XCTest
@testable import OpenGlasses

/// Which model reads a document, the scripts fetched ahead for the phone's languages, the gate
/// for a passage whose model is pending, and the diagnostics (Plan JY P1). Pure: no store and no
/// Apple asset.
final class EmbeddingScriptTests: XCTestCase {

    private func profile(_ script: TextScript, _ language: String?) -> DocumentLanguageProfile {
        DocumentLanguageProfile(script: script, language: language, confidence: language == nil ? 0 : 0.95, scriptShare: 0.9)
    }

    // MARK: - Model by script

    func testEachScriptPicksItsOwnModel() {
        XCTAssertEqual(EmbeddingScript(profile: profile(.latin, "en")), .latin)
        XCTAssertEqual(EmbeddingScript(profile: profile(.latin, "de")), .latin)
        XCTAssertEqual(EmbeddingScript(profile: profile(.latin, nil)), .latin)
        XCTAssertEqual(EmbeddingScript(profile: profile(.cyrillic, "uk")), .cyrillic)
        XCTAssertEqual(EmbeddingScript(profile: profile(.cyrillic, nil)), .cyrillic)
        XCTAssertEqual(EmbeddingScript(profile: profile(.arabic, "ar")), .arabic)
        XCTAssertEqual(EmbeddingScript(profile: profile(.arabic, "ur")), .urdu, "Urdu is read by the model Apple maps ur to")
        XCTAssertEqual(EmbeddingScript(profile: profile(.arabic, nil)), .arabic, "an unsettled Arabic-script text reads as Arabic")
        XCTAssertEqual(EmbeddingScript(profile: profile(.han, "zh-Hans")), .cjk)
        XCTAssertEqual(EmbeddingScript(profile: profile(.han, "ja")), .cjk)
        XCTAssertEqual(EmbeddingScript(profile: profile(.hangul, "ko")), .cjk)
        XCTAssertEqual(EmbeddingScript(profile: .unknown), .latin, "no letters: today's model")
        XCTAssertEqual(EmbeddingScript(profile: profile(.other, nil)), .latin, "a script outside the interface: today's model")
    }

    func testDetectedTextChoosesItsScript() {
        XCTAssertEqual(EmbeddingScript(profile: .detect("Replace the air filter every three months under normal use.")), .latin)
        XCTAssertEqual(EmbeddingScript(profile: .detect("Повітряний фільтр слід замінювати кожні три місяці під час звичайної роботи.")), .cyrillic)
        XCTAssertEqual(EmbeddingScript(profile: .detect("压缩机的排气温度不得超过一百二十度，每三个月检查一次过滤器。")), .cjk)
        XCTAssertEqual(EmbeddingScript(profile: .detect("フィルターは三か月ごとに交換してください。通常の使用で十分です。")), .cjk)
    }

    func testEachScriptsModelIsAskedForInItsOwnLanguage() {
        XCTAssertEqual(EmbeddingScript.cyrillic.contextualLanguage, .russian)
        XCTAssertEqual(EmbeddingScript.arabic.contextualLanguage, .arabic)
        XCTAssertEqual(EmbeddingScript.urdu.contextualLanguage, .urdu)
        XCTAssertEqual(EmbeddingScript.cjk.contextualLanguage, .simplifiedChinese)
        XCTAssertNil(Embedder.contextual(for: .latin), "Latin's model is the caller's choice, never a script model")
    }

    // MARK: - The phone's languages

    func testThePhonesLanguagesNameTheScriptsFetchedAhead() {
        XCTAssertEqual(EmbeddingScript.of(preferredLanguage: "uk-UA"), .cyrillic)
        XCTAssertEqual(EmbeddingScript.of(preferredLanguage: "zh-Hans-CN"), .cjk)
        XCTAssertEqual(EmbeddingScript.of(preferredLanguage: "ur-PK"), .urdu)
        XCTAssertEqual(EmbeddingScript.of(preferredLanguage: "en-NZ"), .latin)
        XCTAssertNil(EmbeddingScript.of(preferredLanguage: "he-IL"), "Hebrew has no Apple model")
        XCTAssertEqual(EmbeddingScript.aheadOfTime(preferredLanguages: ["en-NZ", "uk-UA", "ru", "ja-JP", "he", "zh-Hant-TW"]),
                       [.cyrillic, .cjk], "in order, without repeats, Latin and unknown left out")
        XCTAssertEqual(EmbeddingScript.aheadOfTime(preferredLanguages: ["en-US"]), [])
    }

    // MARK: - The gate while a passage's model is pending

    private func passage(_ text: String, similarity: Float, pending: Bool) -> VaultRetriever.Passage {
        VaultRetriever.Passage(documentId: "d", documentName: "Invented Manual", chunkIndex: 0, text: text,
                               page: 1, section: nil, similarity: similarity, score: similarity, matchedTokens: [],
                               vectorPending: pending)
    }

    func testAPendingPassageIsJudgedByItsWordsUnderTheStricterCount() {
        let contextual = RetrievalEvidencePolicy.default(for: "nl-contextual.Latn")
        let question = LexicalSupport.QueryTerms("compressor discharge temperature")
        XCTAssertEqual(question.english.count, 3)
        XCTAssertEqual(contextual.requiredSharedTerms(queryTermCount: 3, rule: .english), 2)
        XCTAssertEqual(contextual.requiredSharedTermsWithoutVector(queryTermCount: 3, rule: .english), 3,
                       "0.6 + 0.15 of three terms is three")
        let allThree = "The compressor discharge temperature must stay below the limit."
        let twoOfThree = "The compressor discharge line runs behind the panel."
        // No similarity to clear the floor with: the words decide.
        XCTAssertTrue(contextual.isEvidence(passage(allThree, similarity: 0, pending: true), question: question))
        XCTAssertFalse(contextual.isEvidence(passage(twoOfThree, similarity: 0, pending: true), question: question),
                       "two of three would pass with a vector; without one it is not enough")
        XCTAssertTrue(contextual.isEvidence(passage(allThree, similarity: 0, pending: true), queryTerms: question.english))
        XCTAssertFalse(contextual.isEvidence(passage(twoOfThree, similarity: 0, pending: true), queryTerms: question.english))
    }

    func testAPassageWithAVectorIsJudgedExactlyAsBefore() {
        let policy = RetrievalEvidencePolicy.default(for: "nl-contextual.Latn")
        let question = LexicalSupport.QueryTerms("compressor discharge temperature")
        let twoOfThree = "The compressor discharge line runs behind the panel."
        XCTAssertTrue(policy.isEvidence(passage(twoOfThree, similarity: 0.5, pending: false), question: question))
        XCTAssertFalse(policy.isEvidence(passage(twoOfThree, similarity: 0, pending: false), question: question),
                       "a passage with a vector still needs the floor")
    }

    func testTheStricterCountIsCappedAndNeverAsksMoreThanTheFlatCount() {
        let strict = RetrievalEvidencePolicy(similarityFloor: 0.3, minSharedTerms: 3, sharedFraction: 0.9)
        XCTAssertEqual(strict.requiredSharedTermsWithoutVector(queryTermCount: 2, rule: .bigram), 2, "capped at the whole question")
        XCTAssertEqual(strict.requiredSharedTermsWithoutVector(queryTermCount: 12, rule: .bigram), 3, "never past minSharedTerms")
        let flat = RetrievalEvidencePolicy(similarityFloor: 0.3, minSharedTerms: 3)
        XCTAssertEqual(flat.requiredSharedTermsWithoutVector(queryTermCount: 2, rule: .english), 3, "no fraction: the flat count")
        let standard = RetrievalEvidencePolicy.default(for: "nl-sentence.en")
        for count in 1...8 {
            XCTAssertGreaterThanOrEqual(standard.requiredSharedTermsWithoutVector(queryTermCount: count, rule: .english),
                                        standard.requiredSharedTerms(queryTermCount: count), "never looser (\(count) terms)")
        }
    }

    func testWithTheLexicalCriterionOffAPendingPassageMeetsTheFloorAsBefore() {
        let floorOnly = RetrievalEvidencePolicy(similarityFloor: 0.3)
        let question = LexicalSupport.QueryTerms("compressor discharge temperature")
        let text = "The compressor discharge temperature must stay below the limit."
        XCTAssertEqual(floorOnly.requiredSharedTermsWithoutVector(queryTermCount: 3, rule: .english), 0)
        XCTAssertFalse(floorOnly.isEvidence(passage(text, similarity: 0, pending: true), question: question))
        XCTAssertTrue(RetrievalEvidencePolicy(similarityFloor: 0).isEvidence(passage(text, similarity: 0, pending: true), question: question))
    }

    // MARK: - Diagnostics

    private func diagnostic(_ script: EmbeddingScript, _ profile: DocumentLanguageProfile, vectors: Int, chunks: Int,
                            manual: Bool = true, model: String = "contextual") -> DocumentStore.LanguageDiagnostic {
        DocumentStore.LanguageDiagnostic(documentId: UUID().uuidString, isManual: manual, profile: profile, script: script,
                                         modelClass: vectors > 0 ? model : "none", chunksWithVectors: vectors, chunks: chunks)
    }

    func testADocumentLineCarriesLabelsAndCountsOnly() {
        let chinese = diagnostic(.cjk, profile(.han, "zh-Hans"), vectors: 0, chunks: 42)
        XCTAssertTrue(chinese.searchesByWords)
        XCTAssertEqual(chinese.line, "manual · han zh-Hans 0.95 · CJK model none · vectors 0/42 · words only")
        let english = diagnostic(.latin, profile(.latin, "en"), vectors: 0, chunks: 10, manual: false)
        XCTAssertFalse(english.searchesByWords, "a Latin document is never 'words only'")
        XCTAssertEqual(english.line, "document · latin en 0.95 · Latin model none · vectors 0/10")
        let unsure = diagnostic(.cyrillic, profile(.cyrillic, nil), vectors: 5, chunks: 5)
        XCTAssertEqual(unsure.line, "manual · cyrillic language unsure · Cyrillic model contextual · vectors 5/5")
    }

    func testTheReportSummarisesThenListsDocumentsByNumber() {
        let diagnostics = [
            diagnostic(.latin, profile(.latin, "en"), vectors: 10, chunks: 10),
            diagnostic(.cjk, profile(.han, "zh-Hans"), vectors: 0, chunks: 4),
            diagnostic(.cyrillic, profile(.cyrillic, "uk"), vectors: 3, chunks: 3, manual: false),
        ]
        let models = [ManualLanguageReport.ModelState(script: .cyrillic, state: .onPhone),
                      ManualLanguageReport.ModelState(script: .cjk, state: .downloading)]
        let lines = ManualLanguageReport.lines(diagnostics, models: models, limit: 2)
        XCTAssertEqual(lines[0], "Document languages: 3 documents (2 manuals); by script Latin 1, Cyrillic 1, CJK 1; words only 1")
        XCTAssertEqual(lines[1], "Search models: Cyrillic on the phone, CJK downloading")
        XCTAssertTrue(lines[2].hasPrefix("Document 1: manual · latin en"))
        XCTAssertTrue(lines[3].hasPrefix("Document 2: manual · han zh-Hans"))
        XCTAssertEqual(lines.last, "Documents not listed: 1")
        XCTAssertEqual(ManualLanguageReport.lines([], models: []), ["Document languages: none"])
    }

    func testTheReportedScriptsAreTheDocumentsAndThePhonesLatinLeftOut() {
        let diagnostics = [diagnostic(.latin, profile(.latin, "en"), vectors: 1, chunks: 1),
                           diagnostic(.arabic, profile(.arabic, "ar"), vectors: 0, chunks: 1)]
        XCTAssertEqual(ManualLanguageReport.reportedScripts(diagnostics, preferredLanguages: ["ja-JP", "en"]), [.arabic, .cjk])
    }

    func testTheLanguageIsNamedInTheInterfacesLanguage() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(ManualLanguageLine.languageName("uk", locale: english), "Ukrainian")
        XCTAssertNotNil(ManualLanguageLine.languageName("zh-Hans", locale: english))
        XCTAssertNil(ManualLanguageLine.languageName(nil, locale: english))
    }
}
