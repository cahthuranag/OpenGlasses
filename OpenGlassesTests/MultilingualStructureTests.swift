import XCTest
@testable import OpenGlasses

/// Plan JY P4: structure in books in the other interface languages — printed folios, fake bold,
/// caption words, headings in scripts without case, CJK splitting and chunk sizes by language.
/// Every fixture is an invented line.
final class MultilingualStructureTests: XCTestCase {

    // MARK: - Printed folios

    func testAFooterFolioDoesNotRenumberTheExtractorsNextPage() {
        let chunker = DocumentChunker(targetChars: 40, maxChars: 80, overlapChars: 0)
        let text = """
        Page 31

        The valve opens at the set point.

        - 25 -

        Page 32

        The relief line drains to the sump.

        - 26 -
        """
        let chunks = chunker.chunk(text)
        XCTAssertTrue(chunks.contains { $0.page == 31 && $0.text.contains("set point") }, "\(chunks)")
        XCTAssertTrue(chunks.contains { $0.page == 32 && $0.text.contains("sump") }, "\(chunks)")
        XCTAssertNil(chunks.first { $0.page == 25 || $0.page == 26 }, "\(chunks)")
        XCTAssertNil(chunks.first { $0.text.contains("- 25 -") || $0.text.contains("- 26 -") })
    }

    func testAFooterFolioDoesNotRenumberAFormFeedPage() {
        let chunker = DocumentChunker(targetChars: 40, maxChars: 80, overlapChars: 0)
        let text = "The valve opens at the set point.\n- 25 -\u{0C}The relief line drains to the sump.\n- 26 -"
        let chunks = chunker.chunk(text)
        XCTAssertEqual(chunks.first { $0.text.contains("set point") }?.page, 1, "\(chunks)")
        XCTAssertEqual(chunks.first { $0.text.contains("sump") }?.page, 2, "\(chunks)")
    }

    func testAFolioStillTurnsThePageOfAPlainTextDocument() {
        // Only folios paginate it, so they are its page breaks, as before.
        let chunker = DocumentChunker(targetChars: 40, maxChars: 80, overlapChars: 0)
        let chunks = chunker.chunk("- 1 -\nThe valve opens at the set point.\n- 2 -\nThe relief line drains to the sump.")
        XCTAssertEqual(chunks.first { $0.text.contains("set point") }?.page, 1, "\(chunks)")
        XCTAssertEqual(chunks.first { $0.text.contains("sump") }?.page, 2, "\(chunks)")
    }

    func testFolioAndPaginationShapes() {
        XCTAssertTrue(DocumentChunker.isPrintedFolio("- 397 -"))
        XCTAssertTrue(DocumentChunker.isPrintedFolio("-12-"))
        XCTAssertFalse(DocumentChunker.isPrintedFolio("Page 12"))
        XCTAssertFalse(DocumentChunker.isPrintedFolio("- 12 - continued"))
        XCTAssertTrue(DocumentChunker.isExtractorPaginated("Page 1\n\nText"))
        XCTAssertTrue(DocumentChunker.isExtractorPaginated("Text\u{0C}More"))
        XCTAssertFalse(DocumentChunker.isExtractorPaginated("- 1 -\nText\n- 2 -\nMore"))
        XCTAssertFalse(DocumentChunker.isExtractorPaginated("See page 12 for the wiring."))
    }

    // MARK: - Fake bold

    func testOverprintedCJKRunCollapses() {
        // An invented heading, every character printed twice, after an unprinted section number.
        XCTAssertEqual(OverprintedText.collapsed("3.2 安安装装说说明明").text, "3.2 安装说明")
        XCTAssertEqual(OverprintedText.collapsed("3.2 安安装装说说明明").overprinted, 4)
        // Two pairs with a doubled full-width colon: no text doubles a colon on purpose.
        XCTAssertEqual(OverprintedText.collapsed("注注：：先断开电源").text, "注：先断开电源")
        XCTAssertEqual(OverprintedText.collapsed("設設定定値値の確認").text, "設定値の確認")
        XCTAssertEqual(OverprintedText.collapsed("점점검검방방법법").text, "점검방법")
    }

    func testLegitimateRepetitionIsKept() {
        for line in ["常常检查阀门", "看看压力表", "高高兴兴地完成", "常常看看", "人人都要戴手套",
                     "committee bookkeeper", "Llama wool", "XXIII", "касса класса",
                     "............", "__________", "𝑃𝑃𝐺𝐺𝑆𝑆", "2019 年"] {
            XCTAssertEqual(OverprintedText.collapsed(line).text, line, line)
            XCTAssertEqual(OverprintedText.collapsed(line).overprinted, 0, line)
        }
    }

    func testAMostlyOverprintedLineIsBoldAndAPartlyOverprintedOneIsNot() {
        let heading = "3.2 安安装装说说明明"
        XCTAssertTrue(OverprintedText.isMostlyOverprinted(heading, collapsed: OverprintedText.collapsed(heading)))
        let note = "注注：：先断开电源再拆下盖板"
        XCTAssertFalse(OverprintedText.isMostlyOverprinted(note, collapsed: OverprintedText.collapsed(note)))
    }

    func testCollapsedLinesLeavesTextWithoutCJKAlone() {
        let latin = "Committee bookkeeping\n\nTABLE 3 Torque"
        XCTAssertEqual(OverprintedText.collapsedLines(latin), latin)
        XCTAssertEqual(OverprintedText.collapsedLines("正文\n安安装装说说明明"), "正文\n安装说明")
    }

    func testAnOverprintedTypedLineIsReadAsABoldHeading() {
        let attributed = NSMutableAttributedString(string: "2.1 温温度度范范围围\n正文说明温度范围。\n",
                                                   attributes: [.font: UIFont.systemFont(ofSize: 10)])
        let page = ManualStructure.typedPage(from: attributed)
        XCTAssertEqual(page.lines.first?.text, "2.1 温度范围")
        XCTAssertEqual(page.lines.first?.bold, true)
        XCTAssertEqual(page.lines.dropFirst().first?.bold, false)
    }

    // MARK: - Caption words

    func testTableCaptionWordsInEveryInterfaceLanguage() {
        let cases: [(String, String, String)] = [
            ("Tabelle 4 Anzugsmomente", "Table 4", "Anzugsmomente"),
            ("Tableau 2 — Valeurs de serrage", "Table 2", "Valeurs de serrage"),
            ("Tabla 3 Presiones", "Table 3", "Presiones"),
            ("Tabella 5 Coppie", "Table 5", "Coppie"),
            ("Tabel 6 Waarden", "Table 6", "Waarden"),
            ("Tabela 7 Valores", "Table 7", "Valores"),
            ("Tabela 8 Wartości", "Table 8", "Wartości"),
            ("9. táblázat Értékek", "Table 9", "Értékek"),
            ("Таблица 10 Значения", "Table 10", "Значения"),
            ("Таблиця 11 Значення", "Table 11", "Значення"),
            ("جدول ١٢ القيم", "Table 12", "القيم"),
            ("الجدول 13 القيم", "Table 13", "القيم"),
            ("表 14 参数", "Table 14", "参数"),
            ("表14：参数", "Table 14", "参数"),
            ("表 15 參數", "Table 15", "參數"),
            ("表 16 仕様", "Table 16", "仕様"),
            ("표 17 사양", "Table 17", "사양"),
            ("Tabelle 95A Werte", "Table 95A", "Werte")
        ]
        for (line, label, title) in cases {
            let match = CaptionWords.match(line)
            XCTAssertEqual(match?.kind, .table, line)
            XCTAssertEqual(match?.label, label, line)
            XCTAssertEqual(match?.title, title, line)
            XCTAssertEqual(match?.continues, false, line)
        }
    }

    func testFigureCaptionWords() {
        for (line, label) in [("Abbildung 2 Schaltplan", "Figure 2"), ("Figura 3 Esquema", "Figure 3"),
                              ("Rysunek 4 Schemat", "Figure 4"), ("Рисунок 5 Схема", "Figure 5"),
                              ("شكل 6 مخطط", "Figure 6"), ("图 7 接线", "Figure 7"), ("図 8 配線", "Figure 8"),
                              ("그림 9 배선", "Figure 9"), ("10. ábra Rajz", "Figure 10")] {
            XCTAssertEqual(CaptionWords.match(line)?.kind, .figure, line)
            XCTAssertEqual(CaptionWords.match(line)?.label, label, line)
        }
    }

    func testContinuationMarkers() {
        for line in ["Tabelle 4 Anzugsmomente (Fortsetzung)", "Fortsetzung Tabelle 4", "Tableau 2 (suite)",
                     "Tabla 3 Presiones (continuación)", "Tabela 7 (continuação)", "Tabela 8 (ciąg dalszy)",
                     "9. táblázat (folytatás)", "Таблица 10 (продолжение)", "Продолжение таблицы 10",
                     "Таблиця 11 (продовження)", "Продовження таблиці 11", "تابع الجدول 12", "جدول 12 (تابع)",
                     "续表 14", "續表 15", "表 16（続き）", "표 17 (계속)", "Tabla 3 Presiones continuación", "Таблица 10 (продолж.)"] {
            XCTAssertEqual(CaptionWords.match(line)?.continues, true, line)
            XCTAssertEqual(CaptionWords.match(line)?.kind, .table, line)
        }
        XCTAssertEqual(CaptionWords.match("续表 14")?.label, "Table 14")
        XCTAssertEqual(CaptionWords.match("Tabelle 4 Anzugsmomente (Fortsetzung)")?.title, "Anzugsmomente")
        // A title that merely ends on a common word is not a continuation.
        XCTAssertEqual(CaptionWords.match("Tableau 2 Coefficients de fin")?.continues, false)
    }

    func testNotCaptions() {
        // A sentence mentioning a table, a word with no number, and English (its own rule).
        for line in ["表5中的参数需要检查", "表は次のとおり", "Tableau de bord", "Tabelle der Werte",
                     "TABLE 3 Torque", "Table 3", "Figure 2", "Tabletop 4", "표시 5"] {
            XCTAssertNil(CaptionWords.match(line), line)
        }
    }

    func testTheExtractorsAndTheStructuresCaptionsAgree() {
        let words = [PositionedWord("Tabelle", x: 10, y: 10, bold: true), PositionedWord("4", x: 60, y: 10, bold: true),
                     PositionedWord("Werte", x: 80, y: 10, bold: true)]
        XCTAssertEqual(TableExtractor.captions(in: words).first?.label, "Table 4")
        XCTAssertEqual(TableExtractor.captions(in: words).first?.title, "Werte")
        let typed = ManualStructure.TypedLine(raw: "Tabelle 4 Werte", size: 10, bold: true)
        XCTAssertEqual(ManualStructure.caption(typed)?.label, "Table 4")
        XCTAssertEqual(ManualStructure.caption(typed)?.inlineTitle, "Werte")
        // English is read by its own rule, as before.
        XCTAssertEqual(ManualStructure.caption(.init(raw: "TABLE 16 Inputs", size: 10, bold: true))?.label, "Table 16")
    }

    // MARK: - Headings without case

    func testTypedHeadingsInAScriptWithoutCase() {
        func line(_ text: String, _ size: Double, _ bold: Bool) -> ManualStructure.TypedLine {
            .init(raw: text, size: size, bold: bold)
        }
        XCTAssertTrue(ManualStructure.isHeading(line("2.1 温度范围", 10, true), bodySize: 10))
        XCTAssertTrue(ManualStructure.isHeading(line("温度范围", 10, true), bodySize: 10))
        XCTAssertTrue(ManualStructure.isHeading(line("第3章 安装", 13, false), bodySize: 10))
        XCTAssertTrue(ManualStructure.isHeading(line("الفصل الأول", 13, false), bodySize: 10))
        XCTAssertFalse(ManualStructure.isHeading(line("第3章 安装", 10, false), bodySize: 10))
        XCTAssertFalse(ManualStructure.isHeading(line("先断开电源再拆下盖板。", 10, true), bodySize: 10))
        XCTAssertFalse(ManualStructure.isHeading(line("先断开电源，", 10, true), bodySize: 10))
        // Latin keeps its rules: larger without bold is not a heading, lower case never opens one.
        XCTAssertFalse(ManualStructure.isHeading(line("Installation", 13, false), bodySize: 10))
        XCTAssertFalse(ManualStructure.isHeading(line("installation steps", 10, true), bodySize: 10))
        XCTAssertTrue(ManualStructure.isHeading(line("Installation", 10, true), bodySize: 10))
    }

    func testClauseNumbersFollowedByACaselessLetterAreClauseHeadings() {
        let lines = (1...12).map { "2.\($0).1 检查阀门的压力" } + (1...3).map { "3.\($0)安装要求" }
        XCTAssertEqual(DocumentChunker.clauseHeadingLines(in: lines.joined(separator: "\n")).count, 15)
        XCTAssertTrue(DocumentChunker.isClauseNumbered(lines.joined(separator: "\n")))
        XCTAssertEqual(DocumentChunker.clauseHeadingLines(in: "3.4 الفصل الأول\n5.6 제2장 설치").count, 2)
        // Latin keeps its rule: a capitalised word after the number, nothing else.
        XCTAssertEqual(DocumentChunker.clauseHeadingLines(in: "2.6 or greater\n3.4 Gas Piping\n1.5 m").count, 1)
    }

    // MARK: - Splitting and sizes

    func testAnOversizedCJKSentenceBreaksAfterItsOwnPunctuation() {
        let clause = "先检查阀门的压力，"            // 9 characters
        let sentence = String(repeating: clause, count: 10)
        let pieces = DocumentChunker.hardSplit(sentence, maxChars: 40)
        XCTAssertEqual(pieces.joined(), sentence)
        XCTAssertTrue(pieces.allSatisfy { $0.count <= 40 }, "\(pieces.map(\.count))")
        XCTAssertTrue(pieces.dropLast().allSatisfy { $0.hasSuffix("，") }, "\(pieces)")
        // A sentence end is preferred over a comma when both fit.
        let mixed = String(repeating: "检查阀门，", count: 3) + "然后关闭。" + String(repeating: "检查阀门，", count: 6)
        XCTAssertTrue(DocumentChunker.hardSplit(mixed, maxChars: 28).first?.hasSuffix("。") == true)
    }

    func testARunWithoutCJKPunctuationIsSlicedAsBefore() {
        let word = String(repeating: "x", count: 100)
        XCTAssertEqual(DocumentChunker.hardSplit(word, maxChars: 30).map(\.count), [30, 30, 30, 10])
        let han = String(repeating: "阀", count: 100)
        XCTAssertEqual(DocumentChunker.hardSplit(han, maxChars: 30).map(\.count), [30, 30, 30, 10])
        XCTAssertEqual(DocumentChunker.hardSplit("short words here", maxChars: 30), ["short words here"])
    }

    func testChunkSizesFollowTheMeasuredScales() {
        let base = DocumentChunker()
        let english = DocumentLanguageProfile(script: .latin, language: "en", confidence: 1, scriptShare: 1)
        XCTAssertEqual(base.sized(for: english, text: "").targetChars, 700)
        XCTAssertEqual(base.sized(for: english, text: "").maxChars, 900)
        XCTAssertEqual(base.sized(for: english, text: "").overlapChars, 100)
        XCTAssertEqual(base.sized(for: .unknown, text: "").targetChars, 700)
        for language in ["de", "fr", "ru", "uk", "ar", "ur", "zh-Hans", "zh-Hant", "ja", "ko"] {
            let script: TextScript = ["zh-Hans", "zh-Hant", "ja"].contains(language) ? .han
                : language == "ko" ? .hangul : ["ru", "uk"].contains(language) ? .cyrillic
                : ["ar", "ur"].contains(language) ? .arabic : .latin
            let profile = DocumentLanguageProfile(script: script, language: language, confidence: 1, scriptShare: 1)
            let scale = script.isCJK ? 0.6 : 1
            let sized = base.sized(for: profile, text: "")
            XCTAssertEqual(sized.targetChars, Int((700 * scale).rounded()), language)
            XCTAssertGreaterThanOrEqual(sized.maxChars, sized.targetChars, language)
            XCTAssertLessThan(sized.overlapChars, sized.targetChars, language)
        }
    }

    func testACJKDocumentGetsSmallerChunks() {
        let chinese = DocumentLanguageProfile(script: .han, language: "zh-Hans", confidence: 1, scriptShare: 1)
        let sized = DocumentChunker().sized(for: chinese, text: "")
        XCTAssertEqual([sized.targetChars, sized.maxChars, sized.overlapChars], [420, 540, 60])
        let unsure = DocumentLanguageProfile(script: .hangul, language: nil, confidence: 0, scriptShare: 0.6)
        XCTAssertEqual(DocumentChunker().sized(for: unsure, text: "").targetChars, 420, "the script decides, named or not")
        let text = String(repeating: "先检查阀门的压力再打开盖板。", count: 60)
        let chunks = DocumentChunker().sized(for: chinese, text: text).chunk(text)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 540 }, "\(chunks.map(\.text.count))")
        XCTAssertGreaterThan(chunks.count, DocumentChunker().chunk(text).count)
    }

    func testAClauseNumberedCJKDocumentKeepsTodaysTargets() {
        let chinese = DocumentLanguageProfile(script: .han, language: "zh-Hans", confidence: 1, scriptShare: 1)
        let code = (1...12).map { "2.\($0).1 检查阀门的压力\n先断开电源再拆下盖板。" }.joined(separator: "\n")
        XCTAssertEqual(DocumentChunker().sized(for: chinese, text: code).targetChars, 700)
    }

    func testLatinChunkingIsUnchangedBySizing() {
        let text = (1...40).map { "Sentence number \($0) explains the next step of the service." }.joined(separator: " ")
        let english = DocumentLanguageProfile(script: .latin, language: "en", confidence: 1, scriptShare: 1)
        XCTAssertEqual(DocumentChunker().sized(for: english, text: text).chunk(text), DocumentChunker().chunk(text))
    }
}
