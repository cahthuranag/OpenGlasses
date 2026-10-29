import PDFKit
import SQLite3
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JY P5a: the defects P3 and P4 found, each with the test that proves its fix. Invented
/// sentences only; every PDF is drawn here.
@MainActor
final class MultilingualDefectsTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultilingualDefectsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - 1. A page whose text layer is only its furniture

    private final class CountingReader: ScannedPageReader, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var calls: Int { lock.withLock { count } }
        func recognise(_ image: CGImage) async -> ScannedPageText {
            lock.withLock { count += 1 }
            return ScannedPageText(text: "Recognised invented body: the relief valve opens at the set pressure.", confidence: 0.9)
        }
    }

    /// Four pages under one running header and a folio: a page of body text, a page whose body is a
    /// drawing of type (no text layer under it), a blank page, and a figure page with its caption.
    private func furniturePDF() throws -> URL {
        let header: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for page in 1...4 {
                context.beginPage()
                ("Invented Valve Handbook Rev A" as NSString).draw(at: CGPoint(x: 40, y: 20), withAttributes: header)
                ("- \(page) -" as NSString).draw(at: CGPoint(x: 290, y: 765), withAttributes: header)
                switch page {
                case 1:
                    ("The invented relief valve is checked every spring. Open the cover, read the gauge and write the value in the log."
                        as NSString).draw(in: CGRect(x: 40, y: 120, width: 520, height: 200), withAttributes: body)
                case 2:
                    // Type drawn as shapes, as an edition printed in outlined glyphs is.
                    UIColor.black.setFill()
                    for row in 0..<30 { UIRectFill(CGRect(x: 60, y: 140 + row * 18, width: 480, height: 7)) }
                case 4:
                    ("Figure 3 Wiring of the invented control board" as NSString)
                        .draw(at: CGPoint(x: 40, y: 600), withAttributes: body)
                    UIColor.black.setStroke()
                    UIBezierPath(rect: CGRect(x: 100, y: 150, width: 400, height: 400)).stroke()
                default:
                    break
                }
            }
        }
        let url = tempRoot.appendingPathComponent("furniture.pdf")
        try data.write(to: url)
        return url
    }

    func testFurnitureIsAFolioALetterlessLineOrALineRepeatedOnThreePages() {
        let pages = ["Invented Handbook Rev A\nThe valve opens at the set pressure and closes below it.\n- 1 -",
                     "Invented Handbook Rev A\n- 2 -", "Invented Handbook Rev A\n- iii -",
                     "Invented Handbook Rev A\nFigure 3 Wiring of the invented board\n- 4 -", ""]
        XCTAssertEqual(VaultDocumentExtractor.furnitureOnlyPages(pages), [1, 2],
                       "a caption is not furniture, and an empty page is the empty-page rule's")
    }

    func testAPageCarryingOnlyItsFurnitureIsSentToTheReaderWhenItsBodyIsDrawn() async throws {
        let url = try furniturePDF()
        let reader = CountingReader()
        let extracted = try await VaultDocumentExtractor.extract(from: url, reader: reader)
        XCTAssertEqual(reader.calls, 1, "only the drawn page: the blank page and the figure page keep their text layer")
        XCTAssertEqual(extracted.ocrPages, 1)
        let pages = extracted.text.components(separatedBy: VaultDocumentExtractor.pageSeparator)
        XCTAssertEqual(pages.count, 4)
        XCTAssertTrue(pages[1].contains("Recognised invented body"))
        XCTAssertTrue(pages[3].contains("Figure 3"), "the figure page is its text layer")

        let document = try XCTUnwrap(PDFDocument(url: url))
        let ink = (0..<4).map { VaultDocumentExtractor.bodyInk(of: document.page(at: $0)!) }
        XCTAssertGreaterThanOrEqual(ink[1], VaultDocumentExtractor.minimumBodyInk)
        XCTAssertLessThan(ink[2], VaultDocumentExtractor.minimumBodyInk, "a blank page carrying its header and folio")

        // Without a reader nothing changes: the text layer as before.
        let plain = try VaultDocumentExtractor.extract(from: url)
        XCTAssertEqual(plain.ocrPages, 0)
    }

    // MARK: - 2. Navigation outweighs the body

    func testAPageThreeQuartersLatinNavigationNamesItsCyrillicBody() {
        let navigation = (1...130).map { ["Home", "Next topic", "Previous", "Index", "Modules", "Report a bug", "Show source",
                                         "Theme", "Auto", "Light", "Dark", "Contents"][$0 % 12] }.joined(separator: "\n")
        let body = """
        Перевірте запобіжний клапан щовесни перед запуском котла та запишіть тиск у журнал.
        Відкрийте кришку, зачекайте, доки стрілка манометра зупиниться, і порівняйте її з позначкою.
        Якщо тиск вищий за позначку, закрийте подачу води та викличте майстра з обслуговування.
        """
        let latin = navigation.filter(\.isLetter).count, cyrillic = body.filter(\.isLetter).count
        XCTAssertGreaterThan(latin, 2 * cyrillic, "the navigation outweighs the body letter for letter")
        let profile = DocumentLanguageProfile.detect(navigation + "\n" + body)
        XCTAssertEqual(profile.script, .cyrillic)
        XCTAssertTrue(profile.language == nil || profile.language == "uk", "the body's language or none, never English")
        // A document of long lines is read as before.
        XCTAssertEqual(DocumentLanguageProfile.detect(body).script, .cyrillic)
        XCTAssertEqual(DocumentLanguageProfile.currentVersion, 3)
    }

    // MARK: - 4. A merged multi-language result keeps its best passage's budget

    private func passage(_ doc: String, _ index: Int, tokens: [String] = []) -> VaultRetriever.Passage {
        VaultRetriever.Passage(documentId: doc, documentName: doc, chunkIndex: index, text: "invented passage \(index)",
                               page: index + 1, section: nil, similarity: 0.8, score: 0.8, matchedTokens: tokens,
                               source: .manual)
    }

    func testAChineseAndAnEnglishManualSendSixWhenTheChinesePassageRanksFirst() {
        let limit = ManualPassageLimit()
        let groups: [ManualLanguageSearch.Group] = [.init(language: "en", documentIds: ["en"]),
                                                    .init(language: "zh-Hans", documentIds: ["zh"])]
        func search(chineseFirst: Bool) -> RetrievalOutcome {
            ManualLanguageSearch.search(
                groups: groups, query: "relief valve", rewrites: .none,
                limit: max(limit.prose, limit.clauseNumbered),
                shape: { limit.shaped($0, isClauseNumbered: { $0 == "zh" }) },
                whole: { _ in .insufficient(reason: "x") },
                scoped: { group, _ in
                    group.language == "en" ? .sufficient((0..<4).map { self.passage("en", $0) })
                        : .sufficient((0..<6).map { self.passage("zh", $0, tokens: chineseFirst && $0 == 0 ? ["ZX9"] : []) })
                }).outcome
        }
        let led = search(chineseFirst: true)
        XCTAssertEqual(led.passages.first?.documentId, "zh")
        XCTAssertEqual(led.passages.count, 6, "the Chinese manual's best passage takes six, as it does alone")
        let english = search(chineseFirst: false)
        XCTAssertEqual(english.passages.first?.documentId, "en")
        XCTAssertEqual(english.passages.count, 4, "a merge led by a prose passage is cut to four as before")
    }

    // MARK: - 5. Dotted caption labels

    private func extractorLabel(_ text: String, bold: Bool = true) -> String? {
        let words = TableFixtureLayouts.words([TableFixtureLayouts.Item(text: text, x: 50, y: 60, size: 10, bold: bold)])
        return TableExtractor.lines(of: words).first.flatMap { TableExtractor.caption(of: $0) }?.label
    }

    func testCaptionsDifferingPastTheFirstDotKeepSeparateLabels() {
        XCTAssertEqual(extractorLabel("Table 2.7.2.2.1 Invented limits for one class"), "Table 2.7.2.2.1")
        XCTAssertEqual(extractorLabel("Table 2.7.2.2.2 Invented limits for another class"), "Table 2.7.2.2.2")
        XCTAssertEqual(ManualStructure.caption(ManualStructure.TypedLine(raw: "Figure 2.4.1: Invented flow chart", size: 10, bold: true))?.label,
                       "Figure 2.4.1")
        XCTAssertEqual(CaptionWords.match("Таблица 1.4.1 Вигаданий перелік")?.label, "Table 1.4.1")
        XCTAssertEqual(TableReference.labels(in: "what does table 2.7.2.2.1 allow"), ["Table 2.7.2.2.1"])
    }

    func testACodeBooksLabelsDoNotMove() {
        // Shaped like a code book's: a number, a number with a letter, a full stop before the title.
        XCTAssertEqual(extractorLabel("Table 2 Invented minimum clearances"), "Table 2")
        XCTAssertEqual(extractorLabel("TABLE 4B Invented conductor ratings"), "Table 4B")
        XCTAssertEqual(extractorLabel("Table 12. Invented ampacities"), "Table 12")
        XCTAssertEqual(extractorLabel("TABLE 4B (Continued)"), "Table 4B")
        XCTAssertEqual(TableReference.labels(in: "check table 4B and table 2"), ["Table 4B", "Table 2"])
        XCTAssertEqual(TableReference.labels(in: "is 0.35 in table 12."), ["Table 12"])
        XCTAssertEqual(TableReference.labels(in: "table 0.35"), [])
    }

    // MARK: - 6. Full-width letters and digits

    func testAFullWidthModelNumberMeetsTheASCIIOne() {
        let passage = "型号ＡＢＣ１２３的安全阀每年检查一次。"
        XCTAssertTrue(CodeTokenizer.codeTokens(from: passage).contains("ABC123"))
        XCTAssertTrue(CodeTokenizer.contains(passage, token: "abc123"))
        XCTAssertTrue(CodeTokenizer.contains("model ABC123 valve", token: "ＡＢＣ１２３"))
        XCTAssertTrue(CodeTokenizer.contains("الطراز ٧٠٩ للصمام", token: "709"), "Arabic-Indic digits read as ASCII")
        XCTAssertEqual(CodeTokenizer.foldedForms("plain text 123"), "plain text 123")
        XCTAssertTrue(LexicalSupport.contentTerms("ＦＬＡＭＥ sensor").contains("flame"))
    }

    // MARK: - 7. Two-pair fake bold, read off the glyphs

    func testAnOverprintedTwoCharacterHeadingCollapsesAndAReduplicatedWordDoesNot() {
        XCTAssertEqual(OverprintedText.collapsed("温温度度", advance: { _ in 0.5 }).text, "温度")
        XCTAssertEqual(OverprintedText.collapsed("高高兴兴", advance: { _ in 1.0 }).text, "高高兴兴")
        XCTAssertEqual(OverprintedText.collapsed("高高兴兴").text, "高高兴兴", "no geometry: the text rule")
        XCTAssertEqual(OverprintedText.collapsed("温温度度").text, "温温度度")
        XCTAssertEqual(OverprintedText.collapsed("Allee 11", advance: { _ in 0.1 }).text, "Allee 11", "Latin is never touched")
        XCTAssertEqual(OverprintedText.collapsed("注注 1：说明", advance: { $0 == 0 ? 0.5 : nil }).text, "注 1：说明",
                       "a lone overprinted lead-in")
    }

    func testTheTypeReaderPassesTheGlyphsToTheCollapse() {
        let font = UIFont.systemFont(ofSize: 10)
        let attributed = NSAttributedString(string: "温温度度\n高高兴兴", attributes: [.font: font])
        let typed = ManualStructure.typedPage(from: attributed, glyphs: { range in
            // The first line's copies half an em apart; the second line's characters a full em.
            range.location < 4 ? CGRect(x: CGFloat(range.location) * 5, y: 100, width: 5, height: 10)
                : CGRect(x: CGFloat(range.location - 5) * 10, y: 80, width: 10, height: 10)
        })
        XCTAssertEqual(typed.lines.map(\.text), ["温度", "高高兴兴"])
        XCTAssertTrue(typed.lines[0].bold, "a line set in fake bold is bold")
        XCTAssertFalse(typed.lines[1].bold)
    }

    func testABoldAndARegularRunOfOneSizeAndCountReadAsBoldEveryTime() {
        let bold = UIFont.boldSystemFont(ofSize: 11), regular = UIFont.systemFont(ofSize: 11)
        let line = NSMutableAttributedString(string: "1.1.1", attributes: [.font: bold])
        line.append(NSAttributedString(string: " 范围和适用", attributes: [.font: regular]))
        for _ in 0..<5 { XCTAssertTrue(ManualStructure.typedPage(from: line).lines[0].bold) }
    }

    // MARK: - 9. A chunk cites the page that holds most of it

    func testAChunkCrossingAPageBreakIsCitedAtThePageHoldingMostOfIt() {
        let first = (1...3).map { "Invented step \($0) on the first sheet checks the valve seat before closing." }
        let second = (1...6).map { "Invented step \($0) on the second sheet reads the gauge and logs the pressure." }
        let text = "Page 1\n" + first.joined(separator: " ") + "\nPage 2\n" + second.joined(separator: " ")
        let english = DocumentLanguageProfile(script: .latin, language: "en", confidence: 1, scriptShare: 1)
        let credited = DocumentChunker().sized(for: english, text: text).chunk(text)
        let firstSentence = DocumentChunker().chunk(text)
        XCTAssertGreaterThan(credited.count, 0)
        XCTAssertEqual(credited.map(\.text), firstSentence.map(\.text), "only the citation moves")
        XCTAssertTrue(credited[0].text.contains("first sheet") && credited[0].text.contains("second sheet"))
        XCTAssertEqual(firstSentence[0].page, 1, "the first sentence's page, as before")
        XCTAssertEqual(credited[0].page, 2, "most of the chunk is on the second page")

        let ukrainian = DocumentLanguageProfile(script: .cyrillic, language: "uk", confidence: 1, scriptShare: 1)
        XCTAssertFalse(DocumentChunker.creditsMajorityPage(for: ukrainian), "measured to cost Cyrillic: the first sentence's page")
        XCTAssertTrue(DocumentChunker.creditsMajorityPage(for: english))
    }

    func testAChunkRunningIntoTheNextSectionOnTheNextPageKeepsItsFirstPage() {
        let first = (1...3).map { "Invented step \($0) on the first sheet checks the valve seat before closing." }
        let second = (1...6).map { "Invented step \($0) on the second sheet reads the gauge and logs the pressure." }
        let text = "Page 1\n## 4.1 Invented valve seats\n" + first.joined(separator: " ")
            + "\nPage 2\n## 4.2 Invented gauges\n" + second.joined(separator: " ")
        let english = DocumentLanguageProfile(script: .latin, language: "en", confidence: 1, scriptShare: 1)
        let credited = DocumentChunker().sized(for: english, text: text).chunk(text)
        XCTAssertTrue(credited[0].text.contains("first sheet") && credited[0].text.contains("second sheet"),
                      "the chunk crosses both the page and the section")
        XCTAssertEqual(credited[0].section, "4.1 Invented valve seats")
        XCTAssertEqual(credited[0].page, 1, "cited where its section is printed, not at the next section's page")
    }

    // MARK: - 8. Recognised and library documents get the location-version-8 re-read

    private func rows(_ directory: URL) -> [(text: String, page: Int?, embedding: Data?, version: Int?)] {
        var db: OpaquePointer?
        sqlite3_open(directory.appendingPathComponent("documents.sqlite").path, &db)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT text, page, embedding, location_version FROM doc_chunks ORDER BY document_id, chunk_index", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        var out: [(String, Int?, Data?, Int?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let page = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 1))
            let blob = sqlite3_column_blob(stmt, 2).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(stmt, 2))) }
            let version = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 3))
            out.append((String(cString: sqlite3_column_text(stmt, 0)), page, blob, version))
        }
        return out
    }

    private func exec(_ sql: String, in directory: URL) {
        var db: OpaquePointer?
        sqlite3_open(directory.appendingPathComponent("documents.sqlite").path, &db)
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)
    }

    func testARecognisedManualIsRepaginatedFromItsRecordWithoutRecognisingAgain() async throws {
        // Page 1 has a text layer; page 2 is a scan, recognised at import, with its folio on a line.
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ((1...10).map { "Invented step \($0) on the first sheet checks the relief valve." }.joined(separator: " ") as NSString)
                .draw(in: CGRect(x: 40, y: 60, width: 520, height: 600), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            context.beginPage()
        }
        let pdf = tempRoot.appendingPathComponent("scan.pdf")
        try data.write(to: pdf)
        let recognised = (1...10).map { "Invented step \($0) on the scanned sheet tests the gauge." }.joined(separator: " ") + "\n- 41 -"
        let record = OCRCheckpoint(contentHash: "h", pages: [1: .init(index: 1, text: recognised, confidence: 0.9)])
        let overlay = tempRoot.appendingPathComponent("overlay", isDirectory: true)
        try record.save(to: overlay)
        let indexed = try await VaultDocumentExtractor.extract(from: pdf, reader: CountingReader(),
                                                               checkpoint: (load: { record }, save: { _ in }))
        XCTAssertEqual(indexed.ocrPages, 1)

        let dir = tempRoot.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: dir)
        let ingested = await store.ingest(name: "Invented Scan", text: indexed.text,
                                          sourceType: VaultImporter.recognisedSourceType, namespace: "vault:r")
        let ref = try XCTUnwrap(ingested)
        let fresh = rows(dir)
        XCTAssertEqual(Set(fresh.compactMap(\.page)), [1, 2])
        // What a build before P4 stored: the scanned page under its printed folio, at version 7.
        exec("UPDATE doc_chunks SET page = 42 WHERE page = 2", in: dir)
        exec("UPDATE doc_chunks SET location_version = 7", in: dir)
        let before = rows(dir)
        let entry = VaultDocumentLedger.Entry(file: "scan.pdf", title: ref.name, documentId: ref.id, contentHash: "h",
                                              chunkCount: ref.chunkCount, ocrPages: 1)
        XCTAssertTrue(entry.usedRecognition)

        let noRecord = await PassageLocationMigration.migrate(entry: entry, fileURL: pdf, store: store, pictureReader: nil,
                                                              checkpointDirectory: tempRoot.appendingPathComponent("none"))
        XCTAssertEqual(noRecord, .recognisedSkipped, "imported before its pages were kept: left as it is")

        let outcome = await PassageLocationMigration.migrate(entry: entry, fileURL: pdf, store: store, pictureReader: nil,
                                                             checkpointDirectory: overlay)
        XCTAssertEqual(outcome, .located, "the text chunks as stored")
        let after = rows(dir)
        XCTAssertEqual(after.map(\.text), before.map(\.text))
        XCTAssertEqual(after.map(\.embedding), before.map(\.embedding), "no chunk was re-embedded")
        XCTAssertEqual(after.map(\.page), fresh.map(\.page), "the scanned page is the PDF's own again")
        XCTAssertFalse(store.needsLocation(documentId: ref.id))
    }

    func testTheLibrarysCJKDocumentIsReadAgainFromItsChunksAndItsLatinOneOnlyStamped() async throws {
        let dir = tempRoot.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: dir)
        let chinese = (1...40).map { "第\($0)步：打开虚构的安全阀盖，读取压力表并记录数值。" }.joined(separator: "\n")
        let english = (1...30).map { "Invented step \($0) opens the cover and reads the gauge before the valve is reset." }
            .joined(separator: " ")
        let zhRef = await store.ingest(name: "虚构手册", text: chinese, namespace: "global")
        let enRef = await store.ingest(name: "Invented notes", text: english, namespace: "global")
        let zh = try XCTUnwrap(zhRef), en = try XCTUnwrap(enRef)
        XCTAssertGreaterThan(zh.chunkCount, 1, "the overlap has something to drop")
        exec("UPDATE doc_chunks SET location_version = 7", in: dir)
        let before = rows(dir)

        let rebuilt = try XCTUnwrap(store.reconstructedText(documentId: zh.id))
        XCTAssertEqual(rebuilt.components(separatedBy: "\n").count, 40, "every line once, the overlap dropped")

        let report = await PassageLocationMigration.migrateLibrary(store: store)
        XCTAssertEqual(report.located + report.rechunked, 1, "only the Chinese document is read again")
        let after = rows(dir)
        XCTAssertEqual(after.map(\.text), before.map(\.text), "its text chunks as stored, so its rows are kept")
        XCTAssertEqual(after.map(\.embedding), before.map(\.embedding))
        XCTAssertTrue(after.allSatisfy { $0.version == DocumentStore.locationVersion })
        XCTAssertFalse(store.needsLocation(documentId: zh.id))
        XCTAssertFalse(store.needsLocation(documentId: en.id))
    }
}
