import XCTest
@testable import OpenGlasses

/// Plan JY P0 — the four term rules, and the rule-aware forms of [[LexicalSupport]]. Every
/// sentence is invented.
final class TermRuleTests: XCTestCase {

    // MARK: - English: today's rule, unchanged

    /// Text in every script, read under `.english`, gives exactly what the rule-less forms give.
    func testTheEnglishRuleIsTodaysRule() {
        let texts = [
            "How to test the flame sensor readings or signal",
            "Gases and matches: the pressures were measured while clocking the meter.",
            "Температуру повітря на подачі слід перевіряти",
            "本研究采用红外热成像方法测量样品表面温度",
            "يجب ألا تتجاوز درجة حرارة الهواء القصوى",
            "Die maximale Vorlauftemperatur der Heizung",
            "",
        ]
        for text in texts {
            XCTAssertEqual(LexicalSupport.contentTerms(text, rule: .english), LexicalSupport.contentTerms(text), text)
            XCTAssertEqual(LexicalSupport.termCounts(text, rule: .english).counts, LexicalSupport.termCounts(text).counts, text)
            XCTAssertEqual(LexicalSupport.termCounts(text, rule: .english).length, LexicalSupport.termCounts(text).length, text)
            XCTAssertEqual(TermRule.english.termSequence(text), LexicalSupport.englishTermSequence(text), text)
        }
        XCTAssertEqual(LexicalSupport.contentTerms("pressures matches clocking"), ["pressure", "match", "clock"])
    }

    func testTheEnglishStatisticsAreTodays() {
        var plain = LexicalSupport.TermStatistics(), ruled = LexicalSupport.TermStatistics()
        for (text, heading) in [("The flame sensor signal reads in microamps.", "Flame sensor"),
                                ("Check the gas valve wiring.", nil)] {
            plain.add(text: text, heading: heading)
            ruled.add(text: text, heading: heading, rule: .english)
        }
        XCTAssertEqual(plain, ruled)
        let terms = LexicalSupport.contentTerms("flame sensor signal")
        XCTAssertEqual(plain.score(queryTerms: terms, text: "flame sensor signal", heading: "Flame sensor"),
                       ruled.score(queryTerms: terms, text: "flame sensor signal", heading: "Flame sensor", rule: .english))
    }

    // MARK: - Prefix stems

    func testPrefixStemsMeetAcrossEndings() {
        let rule = TermRule.prefixStem(.ukrainian)
        // Plan JY P3: the ending goes, then seven letters are kept.
        XCTAssertEqual(LexicalSupport.contentTerms("температура", rule: rule), ["темпера"])
        XCTAssertEqual(LexicalSupport.contentTerms("Температуру", rule: rule), ["темпера"])
        XCTAssertEqual(LexicalSupport.contentTerms("максимальна максимальне", rule: rule), ["максима"])
        XCTAssertEqual(TermRule.prefixLength(for: .cyrillic), 7)
    }

    func testShortWordsAreKeptWholeAndShorterOnesDropped() {
        let rule = TermRule.prefixStem(.polish)
        XCTAssertEqual(rule.termSequence("pompa"), ["pomp"], "under the prefix length: kept whole but for its ending (P3)")
        XCTAssertEqual(rule.termSequence("gaz"), ["gaz"], "at the minimum length: kept")
        XCTAssertEqual(rule.termSequence("w o"), [], "under the minimum length: dropped")
        XCTAssertEqual(TermRule.minimumLength(for: .latinHeavy), 3)
    }

    func testEachLanguageDropsItsOwnStopwords() {
        XCTAssertEqual(TermRule.prefixStem(.ukrainian).termSequence("Яка температура"), ["темпера"])
        XCTAssertEqual(TermRule.prefixStem(.russian).termSequence("Какова температура"), ["темпера"])
        XCTAssertEqual(TermRule.prefixStem(.german).termSequence("Wie hoch ist die Temperatur"), ["hoch", "temper"])
        XCTAssertEqual(TermRule.prefixStem(.french).termSequence("Quelle est la pression"), ["pressio"])
        XCTAssertEqual(TermRule.prefixStem(.urdu).termSequence("درجہ حرارت کیا ہے"), ["درج", "حرار"])
        // Another language's stopword is a word like any other.
        XCTAssertEqual(TermRule.prefixStem(.german).termSequence("quelle"), ["quell"])
        XCTAssertTrue(TermRuleStopwords.cyrillic.isSuperset(of: TermRuleStopwords.ukrainian))
        XCTAssertTrue(TermRuleStopwords.cyrillic.isSuperset(of: TermRuleStopwords.russian))
    }

    func testCyrillicApostrophesJoinTheWord() {
        let rule = TermRule.prefixStem(.ukrainian)
        XCTAssertEqual(rule.termSequence("п’яти"), ["пят"])
        XCTAssertEqual(rule.termSequence("п'яти"), ["пят"])
        XCTAssertEqual(rule.termSequence("пʼяти"), ["пят"])
    }

    // MARK: - Arabic

    func testArabicCliticsAreStripped() {
        XCTAssertEqual(TermRule.arabicStem.termSequence("الهواء والهواء بالهواء للهواء"), ["هواء", "هواء", "هواء", "هواء"])
        XCTAssertEqual(TermRule.arabicStem.termSequence("بالماء"), ["ماء"])
        XCTAssertEqual(TermRule.arabicStem.termSequence("الم"), ["الم"], "a clitic is stripped only when a word is left")
        XCTAssertEqual(TermRule.arabicClitics.first, "وال", "the longest clitics first")
    }

    func testArabicMarksAndAlefFormsAreNormalised() {
        XCTAssertEqual(TermRule.arabicStem.termSequence("الْهَوَاء"), ["هواء"])
        XCTAssertEqual(TermRule.arabicStem.termSequence("أحمد"), TermRule.arabicStem.termSequence("احمد"))
        XCTAssertEqual(TermRule.arabicStem.termSequence("هل ألا على"), [], "stopwords, after normalising")
    }

    // MARK: - Bigrams

    func testHanRunsAreOverlappingPairs() {
        XCTAssertEqual(TermRule.bigram.termSequence("测量温度"), ["测量", "量温", "温度"])
        XCTAssertEqual(TermRule.bigram.termSequence("温"), ["温"], "a single character is kept whole")
        XCTAssertEqual(TermRule.bigram.termSequence("的"), [], "unless it is a particle")
    }

    func testTraditionalIsFoldedIntoSimplified() {
        XCTAssertEqual(TermRule.bigram.termSequence("溫度測量"), TermRule.bigram.termSequence("温度测量"))
        XCTAssertEqual(TermRule.foldedToSimplified("臺灣電腦"), "台湾电脑")
        XCTAssertEqual(TermRule.foldedToSimplified("温度"), "温度")
        XCTAssertEqual(TermRule.foldedToSimplified("no Han here"), "no Han here")
        // Deterministic.
        XCTAssertEqual(TermRule.foldedToSimplified("熱電偶讀數"), TermRule.foldedToSimplified("熱電偶讀數"))
    }

    func testFullWidthLettersAndDigitsAreNormalised() {
        XCTAssertEqual(TermRule.bigram.termSequence("ＳＥＮＳＯＲ温度"), ["sensor", "温度"])
    }

    func testQuestionWordPiecesAreDropped() {
        XCTAssertFalse(TermRule.bigram.termSequence("什么方法").contains("什么"))
        XCTAssertFalse(TermRule.bigram.termSequence("這篇論文").contains("这篇"))
        XCTAssertFalse(TermRule.bigram.termSequence("어떤 온도").contains("어떤"))
        XCTAssertFalse(TermRule.bigram.termSequence("温度ですか").contains("です"))
        XCTAssertTrue(TermRule.bigram.termSequence("어떤 온도").contains("온도"))
    }

    func testKoreanParticlesStillShareTheWord() {
        let a = LexicalSupport.contentTerms("온도를", rule: .bigram), b = LexicalSupport.contentTerms("온도는", rule: .bigram)
        XCTAssertTrue(a.intersection(b).contains("온도"))
    }

    // MARK: - Runs of another script

    func testEachRunUsesTheRuleForItsOwnScript() {
        // A Latin model name in a Chinese passage is read with the English rule.
        XCTAssertEqual(TermRule.bigram.termSequence("我们使用ResNet模型"), ["们使", "使用", "resnet", "模型"])
        // A Chinese term and a Cyrillic phrase in a German passage use bigrams and Cyrillic stems.
        XCTAssertEqual(TermRule.prefixStem(.german).termSequence("Der Fühler 温度传感器 und датчик температури"),
                       ["fühl", "温度", "度传", "传感", "感器", "датчик", "темпера"])
        // A Latin run in a Latin-language document uses that document's rule.
        XCTAssertEqual(TermRule.prefixStem(.german).termSequence("Vorlauftemperatur"), ["vorlau"])
        XCTAssertEqual(TermRule.runs(in: "温度ABC").map(\.script), [.han, .latin])
    }

    // MARK: - Questions

    func testQueryTermsHoldEveryRule() {
        let question = LexicalSupport.QueryTerms("Яка максимальна температура подачі повітря?")
        XCTAssertEqual(question.english, LexicalSupport.contentTerms(question.text))
        for rule in TermRule.allCases {
            XCTAssertEqual(question.terms(for: rule), LexicalSupport.contentTerms(question.text, rule: rule))
        }
        XCTAssertEqual(question.terms(for: .prefixStem(.ukrainian)), ["максима", "темпера", "подач", "повітр"])
        XCTAssertFalse(question.isEmpty)
        XCTAssertTrue(LexicalSupport.QueryTerms("is it on?").isEmpty)
    }

    func testTheSharedCountComparesBothSidesUnderOneRule() {
        let question = LexicalSupport.QueryTerms("这篇论文用了什么方法来测量温度？")
        let answer = "本研究采用红外热成像方法测量样品表面温度，并与热电偶读数进行对比。"
        XCTAssertEqual(LexicalSupport.sharedTermCount(text: answer, question: question, rule: .bigram), 3)
        XCTAssertEqual(LexicalSupport.sharedTermCount(text: answer, queryTerms: question.english), 0,
                       "under today's rule the two share nothing")
    }

    func testStatisticsCountEachDocumentUnderItsRule() {
        var statistics = LexicalSupport.TermStatistics()
        statistics.add(text: "本研究采用红外热成像方法测量样品表面温度。", heading: nil, rule: .bigram)
        statistics.add(text: "今天下午天气晴朗，适合去公园散步。", heading: nil, rule: .bigram)
        let question = LexicalSupport.QueryTerms("用什么方法测量温度")
        let terms = question.terms(for: .bigram)
        let answer = statistics.score(queryTerms: terms, text: "本研究采用红外热成像方法测量样品表面温度。", heading: nil, rule: .bigram)
        let other = statistics.score(queryTerms: terms, text: "今天下午天气晴朗，适合去公园散步。", heading: nil, rule: .bigram)
        XCTAssertGreaterThan(answer, other)
        XCTAssertEqual(other, 0)
    }

    // MARK: - Other callers

    func testBackOfBookIndexReadsUnderItsDocumentsRule() {
        let index = BackOfBookIndex(entries: [
            BackOfBookIndex.Entry(terms: LexicalSupport.contentTerms("Температура подачі", rule: .prefixStem(.ukrainian)),
                                  references: ["3.4.1"]),
        ], rule: .prefixStem(.ukrainian))
        XCTAssertEqual(index.references(for: "яка температура повітря"), ["3.4.1"])
        XCTAssertEqual(BackOfBookIndex(entries: []).rule, .english)
    }

    func testTableTitlesAreComparedUnderTheirDocumentsRule() {
        let entry = TableReference.Entry(label: "Table 3", title: "Максимальна температура повітря на подачі",
                                         termRule: .prefixStem(.ukrainian))
        let other = TableReference.Entry(label: "Table 4", title: "Розміри корпусу та маса",
                                         termRule: .prefixStem(.ukrainian))
        let ranked = TableDirectory.ranked("максимальне значення температури повітря", in: [entry, other])
        XCTAssertEqual(ranked.first?.entry.label, "Table 3")
        XCTAssertEqual(ranked.first?.shared, 3)
        XCTAssertTrue(TableDirectory.ranked("максимальне значення температури повітря",
                                            in: [TableReference.Entry(label: "Table 3", title: entry.title)])
            .allSatisfy { $0.shared < 3 }, "under today's rule the endings do not meet")
    }
}
