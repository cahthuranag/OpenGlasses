import SQLite3
import XCTest
@testable import OpenGlasses

/// Plan JY P0 — the evidence gate's lexical criterion in every interface language: a question and
/// the passage that answers it share enough terms under the passage's document's rule, and the
/// same question against an unrelated passage of that language does not. Every sentence is
/// invented.
///
/// The similarity criteria are pinned out of the way (every passage scores well above the
/// floor), because the simulator's embedder scores everything alike: what is tested is the words.
@MainActor
final class MultilingualEvidenceGateTests: XCTestCase {

    /// A question, the passage that answers it, and one about something else, per language.
    private static let cases: [(language: String, question: String, answer: String, unrelated: String)] = [
        ("en", "What is the maximum supply air temperature?",
         "Check the supply air temperature after five minutes; the maximum value is listed in table 3.",
         "The warranty covers parts for two years from the date of purchase."),
        ("de", "Wie hoch ist die maximale Vorlauftemperatur der Heizung?",
         "Die maximale Vorlauftemperatur der Heizung beträgt 75 Grad und wird am Regler eingestellt.",
         "Die Garantie gilt zwei Jahre ab dem Kaufdatum für alle Ersatzteile."),
        ("es", "¿Cuál es la presión máxima del refrigerante en el condensador?",
         "La presión máxima del refrigerante en el condensador no debe superar los 30 bar.",
         "El manual del usuario se encuentra en la caja junto con la garantía."),
        ("fr", "Quelle est la pression maximale du réfrigérant dans le condenseur ?",
         "La pression maximale du réfrigérant dans le condenseur ne doit pas dépasser 30 bar.",
         "Le manuel de l'utilisateur se trouve dans la boîte avec la garantie."),
        ("hu", "Mekkora a hűtőközeg legnagyobb nyomása a kondenzátorban?",
         "A hűtőközeg nyomása a kondenzátorban legfeljebb 30 bar lehet, ez a legnagyobb megengedett érték.",
         "A használati útmutató a dobozban található a garanciajeggyel együtt."),
        ("it", "Qual è la pressione massima del refrigerante nel condensatore?",
         "La pressione massima del refrigerante nel condensatore non deve superare i 30 bar.",
         "Il manuale d'uso si trova nella scatola insieme alla garanzia."),
        ("nl", "Wat is de maximale druk van het koudemiddel in de condensor?",
         "De maximale druk van het koudemiddel in de condensor mag niet hoger zijn dan 30 bar.",
         "De gebruikershandleiding zit in de doos samen met het garantiebewijs."),
        ("pl", "Jakie jest maksymalne ciśnienie czynnika chłodniczego w skraplaczu?",
         "Maksymalne ciśnienie czynnika chłodniczego w skraplaczu nie może przekraczać 30 barów.",
         "Instrukcja obsługi znajduje się w pudełku razem z kartą gwarancyjną."),
        ("pt", "Qual é a pressão máxima do refrigerante no condensador?",
         "A pressão máxima do refrigerante no condensador não deve ultrapassar 30 bar.",
         "O manual do usuário está na caixa junto com o certificado de garantia."),
        ("uk", "Яка максимальна температура подачі повітря?",
         "Температуру повітря на подачі слід перевіряти після п’яти хвилин роботи; максимальне значення вказано в таблиці 3.",
         "Гарантія діє протягом двох років з дня покупки."),
        ("ru", "Какова максимальная температура подачи воздуха?",
         "Температуру воздуха на подаче следует проверять через пять минут работы; максимальное значение указано в таблице 3.",
         "Гарантия действует в течение двух лет со дня покупки."),
        ("ar", "ما هي درجة حرارة الهواء القصوى عند المخرج؟",
         "يجب ألا تتجاوز درجة حرارة الهواء القصوى عند المخرج خمسين درجة مئوية.",
         "يغطي الضمان قطع الغيار لمدة سنتين من تاريخ الشراء."),
        ("ur", "ہوا کا زیادہ سے زیادہ درجہ حرارت کیا ہے؟",
         "ہوا کا زیادہ سے زیادہ درجہ حرارت پچاس ڈگری سے زیادہ نہیں ہونا چاہیے۔",
         "وارنٹی خریداری کی تاریخ سے دو سال تک کے لیے ہے۔"),
        ("zh-Hans", "这篇论文用了什么方法来测量温度？",
         "本研究采用红外热成像方法测量样品表面温度，并与热电偶读数进行对比。",
         "今天下午天气晴朗，适合去公园散步。"),
        ("zh-Hant", "這篇論文用了什麼方法來測量溫度？",
         "本研究採用紅外熱成像方法測量樣品表面溫度，並與熱電偶讀數進行對比。",
         "今天下午天氣晴朗，適合去公園散步。"),
        ("ja", "供給空気の最高温度は何度ですか？",
         "供給空気の温度は運転開始から五分後に確認し、最高温度は表3に記載されています。",
         "保証期間は購入日から二年間です。"),
        ("ko", "공급 공기의 최고 온도는 얼마입니까?",
         "공급 공기 온도는 운전 시작 5분 후에 확인하며 최고 온도는 표 3에 나와 있습니다.",
         "보증 기간은 구입일로부터 2년입니다."),
    ]

    /// The shipped gates: the nl-word / nl-sentence rule (0.75) and the contextual model's (0.6).
    private static let policies = [
        RetrievalEvidencePolicy.default(for: "nl-word.en"),
        RetrievalEvidencePolicy.default(for: "nl-contextual.Latn"),
    ]

    private func passage(_ text: String, rule: TermRule, id: String = "doc") -> VaultRetriever.Passage {
        VaultRetriever.Passage(documentId: id, documentName: "Manual \(id)", chunkIndex: 0, text: text,
                               page: 1, section: nil, similarity: 0.9, score: 0.9, matchedTokens: [],
                               termRule: rule)
    }

    func testEveryLanguagesAnswerPassesAndAnUnrelatedPassageFails() {
        for sample in Self.cases {
            let profile = DocumentLanguageProfile.detect(sample.answer)
            XCTAssertEqual(profile.language, sample.language, sample.answer)
            let rule = profile.termRule
            let question = LexicalSupport.QueryTerms(sample.question)
            for policy in Self.policies {
                XCTAssertTrue(policy.decide([passage(sample.answer, rule: rule)], limit: 4, question: question).isSufficient,
                              "\(sample.language): the answer must clear the gate (\(policy.sharedFraction))")
                XCTAssertFalse(policy.decide([passage(sample.unrelated, rule: rule)], limit: 4, question: question).isSufficient,
                               "\(sample.language): an unrelated passage must not (\(policy.sharedFraction))")
            }
        }
    }

    /// The finding that started the plan: a Ukrainian question sharing two of its four terms with
    /// its answer under today's rule is refused; under prefix stems it shares all four.
    func testTheUkrainianQuestionIsNoLongerRefused() {
        let sample = Self.cases.first { $0.language == "uk" }!
        let question = LexicalSupport.QueryTerms(sample.question)
        XCTAssertEqual(question.english.count, 4)
        XCTAssertEqual(LexicalSupport.sharedTermCount(text: sample.answer, queryTerms: question.english), 2)
        let rule = TermRule.prefixStem(.ukrainian)
        XCTAssertEqual(question.terms(for: rule).count, 4)
        XCTAssertEqual(LexicalSupport.sharedTermCount(text: sample.answer, question: question, rule: rule), 4)
        for policy in Self.policies {
            XCTAssertFalse(policy.decide([passage(sample.answer, rule: .english)], limit: 4, queryTerms: question.english).isSufficient,
                           "today's rule refuses it")
            XCTAssertTrue(policy.decide([passage(sample.answer, rule: rule)], limit: 4, question: question).isSufficient)
        }
    }

    /// The Chinese finding: question and answer shared no term at all; as bigrams they share
    /// 方法, 测量 and 温度, which clears the gate, and nothing with a passage about the weather.
    func testTheChineseQuestionSharesItsWords() {
        let sample = Self.cases.first { $0.language == "zh-Hans" }!
        let question = LexicalSupport.QueryTerms(sample.question)
        let shared = question.terms(for: .bigram).intersection(LexicalSupport.contentTerms(sample.answer, rule: .bigram))
        XCTAssertEqual(shared, ["方法", "测量", "温度"])
        XCTAssertEqual(LexicalSupport.sharedTermCount(text: sample.answer, queryTerms: question.english), 0)
        for policy in Self.policies {
            XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: question.terms(for: .bigram).count, rule: .bigram), 3)
            XCTAssertTrue(policy.decide([passage(sample.answer, rule: .bigram)], limit: 4, question: question).isSufficient)
            XCTAssertFalse(policy.decide([passage(sample.unrelated, rule: .bigram)], limit: 4, question: question).isSufficient)
        }
    }

    /// A Traditional question finds a Simplified answer, and the other way round.
    func testTraditionalAndSimplifiedMeet() {
        let simplified = Self.cases.first { $0.language == "zh-Hans" }!
        let traditional = Self.cases.first { $0.language == "zh-Hant" }!
        let policy = Self.policies[0]
        XCTAssertTrue(policy.decide([passage(simplified.answer, rule: .bigram)], limit: 4,
                                    question: LexicalSupport.QueryTerms(traditional.question)).isSufficient)
        XCTAssertTrue(policy.decide([passage(traditional.answer, rule: .bigram)], limit: 4,
                                    question: LexicalSupport.QueryTerms(simplified.question)).isSufficient)
    }

    /// For an English passage the rule-aware gate is today's gate.
    func testTheEnglishGateIsUnchanged() {
        let questions = ["what is the pre-purge time", "how to test the flame sensor readings or signal",
                         "torque setting for the compressor mounting bolts"]
        let texts = ["The pre-purge time is 30 seconds before ignition.",
                     "To test the flame sensor, read the signal in Field Test Mode.",
                     "Replace the blower wheel if it is cracked."]
        for policy in Self.policies + [RetrievalEvidencePolicy(similarityFloor: 0.3, minSharedTerms: 1)] {
            for q in questions {
                let question = LexicalSupport.QueryTerms(q)
                for text in texts {
                    let p = passage(text, rule: .english)
                    XCTAssertEqual(policy.isEvidence(p, question: question), policy.isEvidence(p, queryTerms: question.english), "\(q) / \(text)")
                }
                XCTAssertEqual(policy.requiredSharedTerms(queryTermCount: question.english.count, rule: .english),
                               policy.requiredSharedTerms(queryTermCount: question.english.count))
            }
        }
    }

    /// A model number written against the text still carries a passage past the gate.
    func testACodeAgainstChineseTextIsAToken() {
        let text = "该机组型号ABC123的额定制冷量为三十五千瓦。"
        let found = CodeTokenizer.codeTokens(from: "型号ABC123的制冷量是多少？")
        XCTAssertEqual(found, ["ABC123"])
        XCTAssertTrue(CodeTokenizer.contains(text, token: "ABC123"))
    }

    // MARK: - Through the store

    private var directories: [URL] = []

    private func makeStore(at directory: URL? = nil) -> DocumentStore {
        let dir = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("MultilingualEvidenceGateTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        directories.append(dir)
        return DocumentStore(directory: dir)
    }

    override func tearDown() {
        for dir in directories { try? FileManager.default.removeItem(at: dir) }
        directories = []
        super.tearDown()
    }

    private func retriever(over store: DocumentStore, namespace: String) -> VaultRetriever {
        VaultRetriever(query: { q, limit in store.query(q, limit: limit, namespace: namespace) },
                       termSearch: { q, limit in store.passages(sharingTermsWith: q, limit: limit, namespace: namespace) },
                       termStatistics: { store.termStatistics(namespaces: [namespace]) },
                       policy: RetrievalEvidencePolicy(similarityFloor: 0, minSharedTerms: 3, sharedFraction: 0.75))
    }

    /// Each document is profiled at ingest, and a question finds its own language's passage under
    /// that document's rule, beside documents in other languages.
    func testAMixedLibraryAnswersEachLanguageFromItsOwnDocument() async throws {
        let store = makeStore()
        let namespace = "jy-test"
        let chineseRef = await store.ingest(name: "论文", text: Self.cases[13].answer, namespace: namespace)
        let ukrainianRef = await store.ingest(name: "Інструкція", text: Self.cases[9].answer, namespace: namespace)
        let englishRef = await store.ingest(name: "Manual", text: Self.cases[0].answer, namespace: namespace)
        let chinese = try XCTUnwrap(chineseRef)
        let ukrainian = try XCTUnwrap(ukrainianRef)
        let english = try XCTUnwrap(englishRef)
        XCTAssertEqual(store.termRule(documentId: chinese.id), .bigram)
        XCTAssertEqual(store.termRule(documentId: ukrainian.id), .prefixStem(.ukrainian))
        XCTAssertEqual(store.termRule(documentId: english.id), .english)
        XCTAssertEqual(store.languageProfile(documentId: ukrainian.id).language, "uk")

        let lexical = store.passages(sharingTermsWith: Self.cases[13].question, namespace: namespace)
        XCTAssertEqual(lexical.first?.documentId, chinese.id)
        XCTAssertEqual(lexical.first?.termRule, .bigram)

        let retriever = retriever(over: store, namespace: namespace)
        for (sample, document) in [(Self.cases[13], chinese), (Self.cases[9], ukrainian), (Self.cases[0], english)] {
            let outcome = retriever.retrieve(.init(turn: sample.question, limit: 4))
            XCTAssertTrue(outcome.isSufficient, sample.question)
            XCTAssertEqual(outcome.passages.first?.documentId, document.id, sample.question)
        }
        XCTAssertFalse(retriever.retrieve(.init(turn: "今天下午公园的天气怎么样？", limit: 4)).isSufficient)
    }

    /// A document indexed before profiles were recorded is profiled from its stored text the first
    /// time its rule is asked for, and the profile is written back.
    func testAnOlderDocumentIsBackfilledFromItsStoredText() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultilingualEvidenceGateTests-\(UUID().uuidString)", isDirectory: true)
        let first = makeStore(at: dir)
        let documentRef = await first.ingest(name: "Інструкція", text: Self.cases[9].answer, namespace: "global")
        let document = try XCTUnwrap(documentRef)
        XCTAssertNotNil(storedProfile(in: dir, documentId: document.id))

        try execute("UPDATE documents SET language_profile = NULL", in: dir)
        XCTAssertNil(storedProfile(in: dir, documentId: document.id))

        let reopened = makeStore(at: dir)
        XCTAssertEqual(reopened.termRule(documentId: document.id), .prefixStem(.ukrainian))
        let written = try XCTUnwrap(storedProfile(in: dir, documentId: document.id))
        let decoded = try JSONDecoder().decode(DocumentLanguageProfile.self, from: Data(written.utf8))
        XCTAssertEqual(decoded.language, "uk")
        _ = first
    }

    /// A stored profile from an older detection is recomputed, and an unreadable one too.
    func testAStaleProfileIsRecomputed() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultilingualEvidenceGateTests-\(UUID().uuidString)", isDirectory: true)
        let store = makeStore(at: dir)
        let documentRef = await store.ingest(name: "论文", text: Self.cases[13].answer, namespace: "global")
        let document = try XCTUnwrap(documentRef)
        try execute(#"UPDATE documents SET language_profile = '{"version":0,"script":"latin","confidence":1,"scriptShare":1}'"#, in: dir)
        XCTAssertEqual(makeStore(at: dir).termRule(documentId: document.id), .bigram)
        try execute("UPDATE documents SET language_profile = 'not json'", in: dir)
        XCTAssertEqual(makeStore(at: dir).termRule(documentId: document.id), .bigram)
    }

    // MARK: - SQLite helpers

    private func execute(_ sql: String, in directory: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(directory.appendingPathComponent("documents.sqlite").path, &db) == SQLITE_OK else {
            throw XCTSkip("could not open the store's database")
        }
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func storedProfile(in directory: URL, documentId: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open(directory.appendingPathComponent("documents.sqlite").path, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT language_profile FROM documents WHERE id = ?", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, documentId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: raw)
    }
}
