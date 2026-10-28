import XCTest
@testable import OpenGlasses

/// Plan JY P0 — a document's main script by a count of its letters, then its language within the
/// script by a constrained recogniser, and the term rule that follows. Every sentence is invented.
final class DocumentLanguageProfileTests: XCTestCase {

    /// One invented sentence per interface language (the regional variants detect as their base
    /// language), the script and the rule it must give.
    private static let sentences: [(text: String, script: TextScript, language: String, rule: TermRule)] = [
        ("Check the supply air temperature after five minutes; the maximum value is listed in table 3.",
         .latin, "en", .english),
        ("Die maximale Vorlauftemperatur der Heizung beträgt 75 Grad und wird am Regler eingestellt.",
         .latin, "de", .prefixStem(.german)),
        ("La presión máxima del refrigerante en el condensador no debe superar los 30 bar.",
         .latin, "es", .prefixStem(.spanish)),
        ("La pression maximale du réfrigérant dans le condenseur ne doit pas dépasser 30 bar.",
         .latin, "fr", .prefixStem(.french)),
        ("A hűtőközeg nyomása a kondenzátorban legfeljebb 30 bar lehet, ez a legnagyobb megengedett érték.",
         .latin, "hu", .prefixStem(.hungarian)),
        ("La pressione massima del refrigerante nel condensatore non deve superare i 30 bar.",
         .latin, "it", .prefixStem(.italian)),
        ("De maximale druk van het koudemiddel in de condensor mag niet hoger zijn dan 30 bar.",
         .latin, "nl", .prefixStem(.dutch)),
        ("Maksymalne ciśnienie czynnika chłodniczego w skraplaczu nie może przekraczać 30 barów.",
         .latin, "pl", .prefixStem(.polish)),
        ("A pressão máxima do refrigerante no condensador não deve ultrapassar 30 bar.",
         .latin, "pt", .prefixStem(.portuguese)),
        ("Температуру повітря на подачі слід перевіряти після п’яти хвилин роботи; максимальне значення вказано в таблиці 3.",
         .cyrillic, "uk", .prefixStem(.ukrainian)),
        ("Температуру воздуха на подаче следует проверять через пять минут работы; максимальное значение указано в таблице 3.",
         .cyrillic, "ru", .prefixStem(.russian)),
        ("يجب ألا تتجاوز درجة حرارة الهواء القصوى عند المخرج خمسين درجة مئوية.",
         .arabic, "ar", .arabicStem),
        ("ہوا کا زیادہ سے زیادہ درجہ حرارت پچاس ڈگری سے زیادہ نہیں ہونا چاہیے۔",
         .arabic, "ur", .prefixStem(.urdu)),
        ("本研究采用红外热成像方法测量样品表面温度，并与热电偶读数进行对比。",
         .han, "zh-Hans", .bigram),
        ("本研究採用紅外熱成像方法測量樣品表面溫度，並與熱電偶讀數進行對比。",
         .han, "zh-Hant", .bigram),
        ("供給空気の温度は運転開始から五分後に確認し、最高温度は表3に記載されています。",
         .han, "ja", .bigram),
        ("공급 공기 온도는 운전 시작 5분 후에 확인하며 최고 온도는 표 3에 나와 있습니다.",
         .hangul, "ko", .bigram),
    ]

    func testEveryInterfaceLanguageIsDetected() {
        for sample in Self.sentences {
            let profile = DocumentLanguageProfile.detect(sample.text)
            XCTAssertEqual(profile.script, sample.script, sample.text)
            XCTAssertEqual(profile.language, sample.language, sample.text)
            XCTAssertEqual(profile.termRule, sample.rule, sample.text)
            XCTAssertGreaterThanOrEqual(profile.confidence, DocumentLanguageProfile.minimumConfidence, sample.text)
        }
    }

    // MARK: - Mixed scripts

    /// The recogniser alone calls this Catalan; the letter count reads it as Chinese first.
    func testLatinTermsInsideChineseAreStillChinese() {
        let profile = DocumentLanguageProfile.detect("我们使用ResNet-50模型在ImageNet数据集上训练。")
        XCTAssertEqual(profile.script, .han)
        XCTAssertEqual(profile.language, "zh-Hans")
        XCTAssertEqual(profile.termRule, .bigram)
        XCTAssertLessThan(profile.scriptShare, 1)
    }

    func testLatinTermsInsideCyrillicAreStillUkrainian() {
        let profile = DocumentLanguageProfile.detect(
            "Модуль ESP32-C3 підключається до шини I2C через роз'єм J4, а прошивку оновлюють утилітою esptool після перезавантаження.")
        XCTAssertEqual(profile.script, .cyrillic)
        XCTAssertEqual(profile.language, "uk")
        XCTAssertEqual(profile.termRule, .prefixStem(.ukrainian))
    }

    func testLatinTermsInsideArabicAreStillArabic() {
        let profile = DocumentLanguageProfile.detect(
            "يتصل المعالج STM32F4 بوحدة WiFi عبر منفذ UART ويجب تحديث البرنامج الثابت بعد إعادة التشغيل.")
        XCTAssertEqual(profile.script, .arabic)
        XCTAssertEqual(profile.language, "ar")
        XCTAssertEqual(profile.termRule, .arabicStem)
    }

    func testKanaMakesHanTextJapanese() {
        let profile = DocumentLanguageProfile.detect("ホームページのURLはexample.comです。設定画面でWi-Fiを選択してください。")
        XCTAssertEqual(profile.script, .han)
        XCTAssertEqual(profile.language, "ja")
        XCTAssertEqual(profile.termRule, .bigram)
    }

    func testABilingualManualTakesItsLargerScript() {
        let profile = DocumentLanguageProfile.detect(
            "The installer must check the gas pressure before lighting the burner. 安装人员必须检查燃气压力。")
        XCTAssertEqual(profile.script, .latin)
        XCTAssertEqual(profile.termRule, .english)
    }

    /// No script has half the letters: the script's default rule, and no language named.
    func testAMixedDocumentGetsItsScriptsDefaultRule() {
        let profile = DocumentLanguageProfile.detect("Перевірте датчик температури. Check the sensor. افحص المستشعر الآن")
        XCTAssertEqual(profile.script, .cyrillic)
        XCTAssertLessThan(profile.scriptShare, DocumentLanguageProfile.minimumScriptShare)
        XCTAssertNil(profile.language)
        XCTAssertEqual(profile.termRule, .prefixStem(.cyrillic))
    }

    // MARK: - Uncertain

    func testTooFewLettersNameNoLanguage() {
        let latin = DocumentLanguageProfile.detect("Code E223 flame rollout")
        XCTAssertNil(latin.language)
        XCTAssertEqual(latin.termRule, .english, "a Latin document whose language is uncertain keeps today's rule")
        let cyrillic = DocumentLanguageProfile.detect("Привіт")
        XCTAssertNil(cyrillic.language)
        XCTAssertEqual(cyrillic.termRule, .prefixStem(.cyrillic))
    }

    func testTextWithoutLettersIsUnknown() {
        XCTAssertEqual(DocumentLanguageProfile.detect(""), .unknown)
        XCTAssertEqual(DocumentLanguageProfile.detect("12345 67.8 — 90%"), .unknown)
        XCTAssertEqual(DocumentLanguageProfile.unknown.termRule, .english)
    }

    func testDetectionIsDeterministic() {
        for sample in Self.sentences {
            XCTAssertEqual(DocumentLanguageProfile.detect(sample.text), DocumentLanguageProfile.detect(sample.text))
        }
    }

    /// A long document is sampled in evenly spaced windows, so a front page in another language
    /// does not decide it.
    func testALongDocumentIsSampledAcrossItsLength() {
        let cover = String(repeating: "Installation and service instructions for the outdoor unit. ", count: 40)
        let body = String(repeating: "Температуру повітря на подачі слід перевіряти після п’яти хвилин роботи. ", count: 400)
        let profile = DocumentLanguageProfile.detect(cover + body)
        XCTAssertEqual(profile.script, .cyrillic)
        XCTAssertEqual(profile.language, "uk")
        let sample = DocumentLanguageProfile.sample(of: cover + body, script: .cyrillic)
        XCTAssertLessThanOrEqual(sample.count,
                                 DocumentLanguageProfile.sampleWindows * DocumentLanguageProfile.sampleWindowLength + DocumentLanguageProfile.sampleWindows)
    }

    func testTheProfileRoundTripsThroughJSON() throws {
        let profile = DocumentLanguageProfile.detect(Self.sentences[9].text)
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(DocumentLanguageProfile.self, from: data), profile)
        XCTAssertEqual(profile.version, DocumentLanguageProfile.currentVersion)
    }

    // MARK: - Scripts

    func testLettersAreClassifiedByScript() {
        XCTAssertEqual(TextScript.of(Character("a")), .latin)
        XCTAssertEqual(TextScript.of(Character("ő")), .latin)
        XCTAssertEqual(TextScript.of(Character("Ж")), .cyrillic)
        XCTAssertEqual(TextScript.of(Character("ب")), .arabic)
        XCTAssertEqual(TextScript.of(Character("ڈ")), .arabic)
        XCTAssertEqual(TextScript.of(Character("温")), .han)
        XCTAssertEqual(TextScript.of(Character("の")), .kana)
        XCTAssertEqual(TextScript.of(Character("カ")), .kana)
        XCTAssertEqual(TextScript.of(Character("한")), .hangul)
        XCTAssertEqual(TextScript.of(Character("Ω")), .other)
        XCTAssertNil(TextScript.of(Character("3")))
        XCTAssertNil(TextScript.of(Character("，")))
    }
}
