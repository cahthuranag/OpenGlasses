import PDFKit
import SQLite3
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JJ P1 — a cell from the book, with its page. Every table, designation and value here is
/// invented (`TableFixtureLayouts`, and the tables built below); nothing is a fact from any book.
final class TableLookupTests: XCTestCase {

    // MARK: - Fixtures

    private func extracted(_ page: TableFixtureLayouts.Page, physical: Int, printed: String? = nil) throws -> ManualTable {
        let found = TableExtractor.extractAll(words: TableFixtureLayouts.words(page),
                                              page: ManualTable.Page(physical: physical, printed: printed))
        return try XCTUnwrap(found.first?.outcome.table)
    }

    /// Table 97, keyed by a number: one value column.
    private let runLengths = ManualTable(
        label: "Table 97", title: "Run lengths by size", page: .init(physical: 5, printed: "20"),
        rowHeaders: ["Size (mm²)"], columns: [.init(path: ["Length (m)"], unit: "m")],
        rows: [("1.5", 12), ("2.5", 18), ("4", 26), ("6", 33), ("10", 47)].map { size, length in
            ManualTable.Row(path: [size], cells: [.init(text: "\(length)", value: Double(length), unit: "m")],
                            page: .init(physical: 5, printed: "20"))
        })

    private func sources() throws -> [TableLookup.Source] {
        [
            .init(documentId: "a", documentName: "Invented Book A",
                  table: try extracted(TableFixtureLayouts.simpleGrid(), physical: 2, printed: "12")),
            .init(documentId: "a", documentName: "Invented Book A",
                  table: try extracted(TableFixtureLayouts.twoLevelHeader(), physical: 3)),
            .init(documentId: "a", documentName: "Invented Book A",
                  table: try extracted(TableFixtureLayouts.footnotes(), physical: 4)),
            .init(documentId: "a", documentName: "Invented Book A", table: runLengths),
            .init(documentId: "a", documentName: "Invented Book A",
                  table: .unextracted(.init(label: "Table 96", title: "Spacing", continues: false),
                                      page: .init(physical: 7, printed: "40"), failure: .tooFewRows)),
        ]
    }

    private func found(_ outcome: TableLookup.Outcome, file: StaticString = #filePath, line: UInt = #line) throws -> TableLookup.Found {
        guard case .found(let found) = outcome else {
            XCTFail("expected a cell, got \(outcome)", file: file, line: line)
            throw XCTSkip("no cell")
        }
        return found
    }

    private func cells(_ found: TableLookup.Found) -> [String] {
        found.rows.flatMap { row in found.columns.map { row.cells[$0].text } }
    }

    // MARK: - The table

    func testByLabelRowAndColumnTheCellComesBackWithItsHeadersAndPage() throws {
        let outcome = TableLookup.resolve(.init(table: "Table 99", row: "QXRT three conductors", column: "Rating group 2"),
                                          in: try sources())
        let hit = try found(outcome)
        XCTAssertEqual(hit.rows.map(\.path), [["QXRT", "three conductors"]])
        XCTAssertEqual(hit.columns, [1])
        XCTAssertEqual(cells(hit), ["35"])
        XCTAssertNil(hit.between)

        let text = TableLookup.render(outcome)
        XCTAssertTrue(text.contains("Table 99 (Conductor ratings), Invented Book A"), text)
        XCTAssertTrue(text.contains("row QXRT › three conductors (page 12)"), text)
        XCTAssertTrue(text.contains("column Rating group 2: \"35\" (the number 35)"), text)
        XCTAssertTrue(text.contains("Do not interpolate"), text)
        XCTAssertTrue(text.hasSuffix("Source: Invented Book A, page 2 (printed 12), Table 99"), text)

        // The Source line is a door: the chip opens that table's page in that book.
        let line = try XCTUnwrap(text.split(separator: "\n").last.map(String.init))
        XCTAssertEqual(CitationLineParser.citations(inLine: line),
                       [Citation(kind: .manual, title: "Invented Book A", page: 2, figure: "Table 99")])
    }

    func testATableSpokenOrAbbreviatedResolvesTheSame() throws {
        for spelling in ["table ninety-nine", "tbl 99", "99", "Table No. 99"] {
            let hit = try found(TableLookup.resolve(.init(table: spelling, row: "QMX90 two conductors",
                                                          column: "Rating group 3"), in: try sources()))
            XCTAssertEqual(cells(hit), ["50"], spelling)
        }
    }

    func testByTitleWords() throws {
        let hit = try found(TableLookup.resolve(.init(table: "the correction factors table", row: "10-12",
                                                      column: "Rating group 2 › Band B"), in: try sources()))
        XCTAssertEqual(hit.source.table.label, "Table 98")
        XCTAssertEqual(cells(hit), ["0.97"])
    }

    func testTwoBooksWithTheSameTableAskWhichAndTheDocumentDecides() throws {
        let b = TableLookup.Source(documentId: "b", documentName: "Invented Book B",
                                   table: try extracted(TableFixtureLayouts.simpleGrid(printed: "30", offset: 100), physical: 1, printed: "30"))
        let all = try sources() + [b]
        guard case .ambiguous(.table, _, let candidates) = TableLookup.resolve(
            .init(table: "Table 99", row: "QXRT three conductors", column: "Rating group 2"), in: all) else {
            return XCTFail("two books print Table 99")
        }
        XCTAssertEqual(candidates, ["Table 99 (Conductor ratings) in Invented Book A",
                                    "Table 99 (Conductor ratings) in Invented Book B"])
        XCTAssertTrue(TableLookup.render(.ambiguous(.table, asked: "Table 99", candidates: candidates))
            .contains("pass 'document'"))

        let outcome = TableLookup.resolve(.init(table: "Table 99", row: "QXRT three conductors", column: "Rating group 2",
                                                document: "book b"), in: all)
        XCTAssertEqual(cells(try found(outcome)), ["135"])
        XCTAssertTrue(TableLookup.render(outcome).hasSuffix("Source: Invented Book B, page 1 (printed 30), Table 99"))
    }

    func testATableThatExtractedNothingSaysSoWithItsPage() throws {
        let outcome = TableLookup.resolve(.init(table: "Table 96", row: "QA1"), in: try sources())
        guard case .notExtracted(let source) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(source.table.label, "Table 96")
        let text = TableLookup.render(outcome)
        XCTAssertTrue(text.contains("printed on page 40 of Invented Book A"), text)
        XCTAssertTrue(text.contains("could not be read"), text)
        XCTAssertTrue(text.contains("Do not answer from memory"), text)
        XCTAssertTrue(text.hasSuffix("Source: Invented Book A, page 7 (printed 40), Table 96"), text)
    }

    func testAnUnknownTableNamesTheTablesThatWereRead() throws {
        let outcome = TableLookup.resolve(.init(table: "Table 12", row: "QXRT"), in: try sources())
        guard case .notFound(.table, _, let available) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(available.contains("Table 99 (Conductor ratings)"))
        XCTAssertFalse(TableLookup.render(outcome).contains("Source:"), "nothing found, nothing cited")
        XCTAssertEqual(TableLookup.resolve(.init(table: "Table 99", row: "QXRT"), in: []), .noTables)
    }

    // MARK: - The row

    func testByRowNumberAndByARangeThatHoldsIt() throws {
        XCTAssertEqual(cells(try found(TableLookup.resolve(.init(table: "Table 97", row: "4"), in: try sources()))), ["26"],
                       "one value column: no column needed")
        XCTAssertEqual(cells(try found(TableLookup.resolve(.init(table: "Table 97", row: "2.5 mm²"), in: try sources()))), ["18"])
        let inRange = try found(TableLookup.resolve(.init(table: "Table 98", row: "8", column: "Rating group 1 › Band A"),
                                                    in: try sources()))
        XCTAssertEqual(inRange.rows.map(\.path), [["7-9"]], "8 is inside the printed range 7-9")
        XCTAssertNil(inRange.between)
    }

    func testANumberBetweenTwoRowsReturnsBothAndNeverInterpolates() throws {
        let outcome = TableLookup.resolve(.init(table: "Table 97", row: "5"), in: try sources())
        let hit = try found(outcome)
        XCTAssertEqual(hit.rows.map(\.path), [["4"], ["6"]])
        XCTAssertEqual(hit.between, 5)
        XCTAssertEqual(cells(hit), ["26", "33"])
        let text = TableLookup.render(outcome)
        XCTAssertTrue(text.contains("5 is not a row of this table; it falls between two rows"), text)
        XCTAssertTrue(text.contains("row 4 (page 20)"), text)
        XCTAssertTrue(text.contains("row 6 (page 20)"), text)
        XCTAssertTrue(text.contains("Do not interpolate, round, or pick one"), text)
        for invented in ["29.5", "29", "30"] {
            XCTAssertFalse(text.contains("\"\(invented)\""), "no value the table does not print")
        }

        let ranged = try found(TableLookup.resolve(.init(table: "Table 98", row: "9.5", column: "Rating group 1 › Band A"),
                                                   in: try sources()))
        XCTAssertEqual(ranged.rows.map(\.path), [["7-9"], ["10-12"]])

        guard case .notFound(.row, _, let range) = TableLookup.resolve(.init(table: "Table 97", row: "12"), in: try sources())
        else { return XCTFail("12 is past the last row") }
        XCTAssertEqual(range, ["the rows run from 1.5 to 10"])
    }

    func testByRowWords() throws {
        let hit = try found(TableLookup.resolve(.init(table: "Table 99", row: "the QXRT cord with three conductor",
                                                      column: "Rating group 1"), in: try sources()))
        XCTAssertEqual(hit.rows.map(\.path), [["QXRT", "three conductors"]])
        XCTAssertEqual(cells(hit), ["30"])
    }

    func testAnAmbiguousRowOrColumnListsTheCandidatesAndAsks() throws {
        guard case .ambiguous(.row, _, let rows) = TableLookup.resolve(.init(table: "Table 99", row: "QXRT",
                                                                              column: "Rating group 1"), in: try sources())
        else { return XCTFail("QXRT has two rows") }
        XCTAssertEqual(rows, ["QXRT › two conductors", "QXRT › three conductors"])

        guard case .ambiguous(.column, _, let columns) = TableLookup.resolve(.init(table: "Table 98", row: "7-9",
                                                                                   column: "Band B"), in: try sources())
        else { return XCTFail("Band B is under both groups") }
        XCTAssertEqual(columns, ["Rating group 1 › Band B", "Rating group 2 › Band B"])
        let text = TableLookup.render(.ambiguous(.column, asked: "Band B", candidates: columns))
        XCTAssertTrue(text.contains("Ask the technician which column"), text)
        XCTAssertTrue(text.contains("No value was given"), text)

        let narrowed = try found(TableLookup.resolve(.init(table: "Table 98", row: "7-9", column: "group 1 band c"),
                                                     in: try sources()))
        XCTAssertEqual(cells(narrowed), ["1.07"])

        guard case .notFound(.row, _, _) = TableLookup.resolve(.init(table: "Table 99", row: "QZZ9"), in: try sources())
        else { return XCTFail("no such row") }
    }

    func testWithoutAColumnTheWholeRowIsRead() throws {
        let outcome = TableLookup.resolve(.init(table: "Table 99", row: "QMX90 three conductors"), in: try sources())
        XCTAssertEqual(cells(try found(outcome)), ["45", "50", "55"])
        XCTAssertTrue(TableLookup.render(outcome).contains("column Rating group 3: \"55\""))
    }

    func testTheNotesACellPointsToComeWithIt() throws {
        let outcome = TableLookup.resolve(.init(table: "Table 95", row: "QXRT"), in: try sources())
        let hit = try found(outcome)
        XCTAssertEqual(TableLookup.notes(for: hit).map(\.marker), ["*"], "only the note its marker keys")
        XCTAssertTrue(TableLookup.render(outcome).contains("Notes: [*] Value for a dry location."))
        let other = try found(TableLookup.resolve(.init(table: "Table 95", row: "QMX90"), in: try sources()))
        XCTAssertEqual(TableLookup.notes(for: other).map(\.marker), ["1"])
    }

    // MARK: - Recognising a table in a question

    func testATableReferenceIsRecognisedPrintedAbbreviatedAndSpoken() {
        XCTAssertEqual(TableReference.labels(in: "what does table 99 say"), ["Table 99"])
        XCTAssertEqual(TableReference.labels(in: "Table 99, row QXRT"), ["Table 99"])
        XCTAssertEqual(TableReference.labels(in: "tbl 98 band A"), ["Table 98"])
        XCTAssertEqual(TableReference.labels(in: "see tbl. 97"), ["Table 97"])
        XCTAssertEqual(TableReference.labels(in: "table no. 96"), ["Table 96"])
        XCTAssertEqual(TableReference.labels(in: "look at table ninety-nine"), ["Table 99"])
        XCTAssertEqual(TableReference.labels(in: "look at table ninety nine for QXRT"), ["Table 99"])
        XCTAssertEqual(TableReference.labels(in: "table one hundred and two"), ["Table 102"])
        XCTAssertEqual(TableReference.labels(in: "table twelve and table 99"), ["Table 12", "Table 99"])
        XCTAssertEqual(TableReference.removingReferences(from: "in table 99, QXRT 40").contains("99"), false)
    }

    func testThingsThatAreNotATableReference() {
        for text in ["can I use the table saw here", "the timetable 9 says", "what is a TBL99X controller",
                     "the QX99 table", "table and chairs", "a 99 table top"] {
            XCTAssertEqual(TableReference.labels(in: text), [], text)
        }
        // Plan JJ P5: a letter against the number is the label's, so "table 99X" names a Table 99X
        // (which a vault may not print) and never Table 99.
        XCTAssertEqual(TableReference.labels(in: "table 99X is the model"), ["Table 99X"])
    }

    func testATableIsRecognisedByItsTitleWordsOnlyWhenTheQuestionSaysTable() {
        let catalogue = [TableReference.Entry(label: "Table 99", title: "Conductor ratings"),
                         TableReference.Entry(label: "Table 98", title: "Correction factors"),
                         TableReference.Entry(label: "Table 97", title: "Run lengths by size")]
        XCTAssertEqual(TableReference.references(in: "what does the conductor ratings table say for QXRT", catalogue: catalogue),
                       ["Table 99"])
        // Plan JJ P3: every content word of the title, and at least two, or the question is not
        // routed to the table — half a title ranked a table's rows over the clause that answered.
        XCTAssertEqual(TableReference.references(in: "what does the ratings table say for QXRT", catalogue: catalogue), [],
                       "half a title is not enough")
        XCTAssertEqual(TableReference.references(in: "check the correction factors table", catalogue: catalogue),
                       ["Table 98"])
        XCTAssertEqual(TableReference.references(in: "what rating does this conductor need", catalogue: catalogue), [],
                       "no table asked for")
        XCTAssertEqual(TableReference.references(in: "which table has the factors and the ratings", catalogue: catalogue), [],
                       "two titles fit as well: not routed")
        XCTAssertEqual(TableReference.references(in: "table 97 and the ratings table", catalogue: catalogue), ["Table 97"],
                       "a number wins")
    }

    // MARK: - A table of words on a plain page

    func testAPlainTableWhoseCellsAreAllWordsExtractsWithItsFirstLineAsHeadings() throws {
        let table = try extracted(TableFixtureLayouts.singleFontTextGrid(), physical: 1)
        XCTAssertEqual(table.label, "Table 96")
        XCTAssertEqual(table.title, "Invented mounting choices for the invented designations of this example")
        XCTAssertEqual(table.rowHeaders, ["Designation"])
        XCTAssertEqual(table.columns.map(\.name), ["Indoor", "Outdoor"])
        XCTAssertEqual(table.rows.map(\.path), [["QXRT"], ["QMX90"], ["QZ12"]])
        XCTAssertEqual(table.rows[0].cells.map(\.text), ["permitted", "not permitted"])
        let words = TableFixtureLayouts.words(TableFixtureLayouts.singleFontTextGrid())
        XCTAssertTrue(TableExtractor.diagnoseTooFewRows(words: words, page: .init(physical: 1)).isEmpty,
                      "it no longer fails for too few rows")
        // A caption over prose still extracts nothing, and the reading says where it stopped.
        let prose = TableFixtureLayouts.words(TableFixtureLayouts.captionOverProse())
        XCTAssertEqual(TableExtractor.diagnoseTooFewRows(words: prose, page: .init(physical: 1)),
                       [TableExtractor.TooFewRows(bodyRows: 0, gridStart: nil)])
    }

    // MARK: - Keys the tokenizer keeps whole

    func testARangeRowKeyIsKeptWhole() {
        XCTAssertEqual(CodeTokenizer.rangeKeys(from: "the factor for 7-9 in band B"), ["7-9", "7\u{2013}9"])
        XCTAssertEqual(CodeTokenizer.rangeKeys(from: "ambient 10 – 12"), ["10-12", "10\u{2013}12"])
        XCTAssertEqual(CodeTokenizer.rangeKeys(from: "QMX90 at 35"), [])
        XCTAssertEqual(CodeTokenizer.rangeKeys(from: "9-7 backwards"), [], "not a range")
        XCTAssertTrue(CodeTokenizer.contains("Table 98 (Correction factors), row 7-9: 1.13", token: "7-9"))
        XCTAssertFalse(CodeTokenizer.contains("row 17-9", token: "7-9"))
        XCTAssertEqual(CodeTokenizer.capitalisedDesignations(from: "the QXRT cord"), ["QXRT"], "a designation is one word already")
    }

    // MARK: - Marking the row on the page

    func testARowIsMarkedOnItsOwnLineOnlyWhereItIsPrintedOnce() {
        let page = "Designation Conductors Rating group 1\nQXRT two conductors 25 30 35\nthree conductors 30 35 40\n"
            + "QMX90 two conductors 40 45 50\nthree conductors 45 50 55\n"
        let row = ManualTable.Row(path: ["QXRT", "three conductors"],
                                  cells: ["30", "35", "40"].map { ManualTable.Cell(text: $0) }, page: .init(physical: 1))
        let runs = TableRowPassage.printedRuns(of: row)
        XCTAssertEqual(runs, ["QXRT three conductors 30 35 40", "three conductors 30 35 40"])
        let location = PassageLocator.locate(printedRuns: runs, onPageText: page)
        let range = (page as NSString).range(of: "three conductors 30 35 40")
        XCTAssertEqual(location.ranges, [range], "the row's own line, the carried-down designation left out")

        let twice = page + "three conductors 30 35 40\n"
        XCTAssertEqual(PassageLocator.locate(printedRuns: runs, onPageText: twice), .notLocatable(.notFound),
                       "printed twice: never chosen between")
        XCTAssertEqual(PassageLocator.locate(printedRuns: ["QX4 12.5"], onPageText: "QX41 2.5 and more"),
                       .notLocatable(.notFound), "the same letters in other words are not the row")
        XCTAssertEqual(PassageLocator.locate(printedRuns: runs, onPageText: nil), .notLocatable(.noTextLayer))
        let anchor = PassageAnchor(documentId: "d", chunkIndex: 9, text: "Table 99 (Conductor ratings), row …",
                                   page: 1, printedRuns: runs)
        XCTAssertEqual(PassageLocator.locate(anchor, onPageText: page).ranges, [range])
    }

    // MARK: - Limits and tool sets

    func testATableRowBestPassageKeepsSixLikeAClause() {
        let limit = ManualPassageLimit()
        XCTAssertEqual(limit.requestLimit(searchesClauseNumbered: false, searchesTableRows: true), 6)
        XCTAssertEqual(limit.requestLimit(searchesClauseNumbered: false, searchesTableRows: false), 4)
        let passages = (0..<6).map { index -> VaultRetriever.Passage in
            var p = VaultRetriever.Passage(documentId: "manual", documentName: "Invented Book A", chunkIndex: index,
                                           text: "x", page: 2, section: nil, similarity: 0.5, score: 0.5, matchedTokens: [])
            if index == 0 { p.kind = .tableRow; p.figure = "Table 99" }
            return p
        }
        XCTAssertEqual(limit.shaped(.sufficient(passages), isClauseNumbered: { _ in false }).passages.count, 6)
        let prose = Array(passages.dropFirst()) + [passages[0]]
        XCTAssertEqual(limit.shaped(.sufficient(prose), isClauseNumbered: { _ in false }).passages.count, 4,
                       "a prose passage first still cuts to four")
    }

    func testTheOnDeviceSetAndTheFieldProfileOfferTableLookup() {
        let registered = ["field_session", "reading", "table_lookup", "rule_chain", "manual_lookup", "get_datetime"]
        let names = AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: true, offlineHandoff: false)
        XCTAssertTrue(names.contains("table_lookup"))
        XCTAssertFalse(names.contains("rule_chain"), "chains are not for the on-device model")
        XCTAssertFalse(names.contains("manual_lookup"), "unchanged: a lookup's passages do not fit this window")
        XCTAssertFalse(AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: false,
                                                          offlineHandoff: false).contains("table_lookup"))
        XCTAssertTrue(FieldToolProfile.names.contains("table_lookup"))
        XCTAssertTrue(AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: true, offlineHandoff: true)
            .contains("table_lookup"), "it reads the phone's own tables, with or without signal")
    }

    @MainActor
    func testTableLookupFitsTheOnDeviceBudgetBesideTheSessionTool() {
        func tokens(_ tool: NativeTool) -> Int {
            AppleToolSchema.estimatedTokens(name: tool.name, description: AppleToolSchema.toolDescription(tool.description),
                                            root: AppleToolSchema.root(toolName: tool.name, parameters: tool.parametersSchema))
        }
        let lookup = tokens(TableLookupTool(documentStore: nil))
        XCTAssertLessThan(tokens(FieldSessionTool()) + lookup, AppleOnDeviceToolSet.definitionBudgetTokens,
                          "the job's first tool and the table lookup are offered together")
    }
}

// MARK: - In a session, with two invented books loaded

/// The tool, retrieval and "show me the table" end to end over two invented books that both print
/// a Table 99, with different values.
@MainActor
final class TableLookupSessionTests: XCTestCase {

    private var tempRoot: URL!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private static let vaultId = "table_lookup_test"
    private static let bookA = "Invented Book A"
    private static let bookB = "Invented Book B"

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TableLookupSessionTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousEntitlement = EntitlementTestScope.grant()
        VaultRegistry.shared.resetCache()
    }

    override func tearDown() {
        VaultImporter.uninstall(id: Self.vaultId)
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled")
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    private func startSession() async throws -> (FieldSessionService, DocumentStore) {
        let storeDir = tempRoot.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: storeDir)
        let dir = tempRoot.appendingPathComponent("vault", isDirectory: true)
        let docs = dir.appendingPathComponent("documents", isDirectory: true)
        _ = try TableFixtures.write(TableFixtures.pdf([TableFixtures.prosePage(), TableFixtureLayouts.simpleGrid(printed: "12"),
                                                       TableFixtureLayouts.twoLevelHeader(),
                                                       TableFixtureLayouts.captionOverProse()]),
                                    named: "a.pdf", in: docs)
        _ = try TableFixtures.write(TableFixtures.pdf([TableFixtureLayouts.simpleGrid(printed: "30", offset: 100)]),
                                    named: "b.pdf", in: docs)
        let manifest = VaultManifest(
            id: Self.vaultId, name: "Table Lookup Test", version: "1.0.0",
            files: ["safety.md"], proceduresDir: nil, documentsDir: "documents",
            documents: [VaultDocument(file: "a.pdf", title: Self.bookA), VaultDocument(file: "b.pdf", title: Self.bookB)],
            gating: .init(iap: "enterprise"), promptRules: ["Never fabricate.", "Cite the source."])
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try "# Safety\n\nIsolate before work.".write(to: dir.appendingPathComponent("safety.md"),
                                                     atomically: true, encoding: .utf8)
        let installed = try VaultImporter.install(from: dir)
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        _ = try await VaultImporter.syncDocuments(manifest: installed, into: store)

        let service = FieldSessionService(sessionsRoot: tempRoot.appendingPathComponent("sessions", isDirectory: true))
        service.documentStore = store
        service.retrievalPolicy = RetrievalEvidencePolicy(similarityFloor: 0)
        service.sourceCenter = ShowSourceCenter()
        service.sourceCenter.isAppActive = { true }
        service.sourceCenter.announce = { _ in }
        _ = try service.startSession(vaultId: installed.id, assetId: nil)
        return (service, store)
    }

    private func lookup(_ args: [String: Any], service: FieldSessionService, store: DocumentStore) async throws -> String {
        try await TableLookupTool(documentStore: store, sessionService: service, currentUtterance: { nil }).execute(args: args)
    }

    private func id(of title: String, in store: DocumentStore) throws -> String {
        try XCTUnwrap(store.documents.first { $0.name == title }?.id)
    }

    func testTheCitationOpensTheRightTableInTheRightBookAndMarksTheRow() async throws {
        let (service, store) = try await startSession()

        // Both books print Table 99: without a book named, it asks.
        let unnamed = try await lookup(["table": "Table 99", "row": "QXRT three conductors", "column": "Rating group 2"],
                                       service: service, store: store)
        XCTAssertTrue(unnamed.contains("More than one table"), unnamed)
        XCTAssertTrue(unnamed.contains(Self.bookA) && unnamed.contains(Self.bookB), unnamed)
        XCTAssertFalse(unnamed.contains("Source:"), unnamed)

        let reply = try await lookup(["table": "table 99", "row": "QXRT three conductors", "column": "rating group 2",
                                      "document": "book b"], service: service, store: store)
        XCTAssertTrue(reply.contains("\"135\""), reply)
        XCTAssertTrue(reply.contains("(page 30)"), "the printed page: \(reply)")
        let sourceLine = try XCTUnwrap(reply.split(separator: "\n").last.map(String.init))
        XCTAssertEqual(sourceLine, "Source: \(Self.bookB), page 1 (printed 30), Table 99")

        // The chip the answer's Source line becomes opens book B's page, not book A's.
        let citation = try XCTUnwrap(CitationLineParser.parse(sourceLine).first)
        guard case .figure(let staged) = service.resolveCitation(citation) else { return XCTFail("the citation resolves") }
        XCTAssertEqual(staged.documentId, try id(of: Self.bookB, in: store))
        XCTAssertEqual(staged.page, 1)
        XCTAssertEqual(staged.figure, "Table 99")

        // "Show me the table": that page, with the row marked.
        let shown = try await ShowSourceTool(documentStore: store, sessionService: service)
            .execute(args: ["which": "show me the table"])
        let pages = try XCTUnwrap(service.sourceCenter.presented?.pages)
        XCTAssertEqual(pages.map(\.documentTitle), [Self.bookB])
        XCTAssertEqual(pages.map(\.page), [1])
        XCTAssertEqual(pages.first?.citedPassages.count, 1, "the row the cell came from, and only it")
        XCTAssertTrue(shown.contains("highlighted"), shown)
        let url = try XCTUnwrap(service.sourcePDFURL(for: pages[0]))
        let pageText = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0)?.string)
        let marks = PassageMarks(passages: pages[0].citedPassages, page: 1, pageText: pageText)
        let marked = try XCTUnwrap(marks.located.first?.location.ranges.first)
        let words = (pageText as NSString).substring(with: marked)
        XCTAssertTrue(words.contains("three conductors") && words.contains("135") && words.contains("140"), words)
        XCTAssertFalse(words.contains("125"), "not the row above: \(words)")

        // The answer repeats the Source line (Direct mode); "Table 99" still opens the marked row.
        service.recordAssistantReply("QXRT with three conductors is 135 in rating group 2.\n\(sourceLine)", sourceID: "turn-1")
        _ = try await ShowSourceTool(documentStore: store, sessionService: service).execute(args: ["which": "Table 99"])
        XCTAssertEqual(service.sourceCenter.presented?.pages.first?.citedPassages.count, 1)
        let missing = try await ShowSourceTool(documentStore: store, sessionService: service).execute(args: ["which": "Table 98"])
        XCTAssertTrue(missing.contains("did not cite Table 98"), missing)
    }

    /// Plan JW P0 finding 5: a lookup on the same table page as the answer before, landing between
    /// two printed rows, marks both of its rows — a sheet of its own, not the page already open
    /// with the previous answer's row — and the reply names the rows it marked.
    func testShowMeAfterABetweenRowsLookupMarksBothRowsAsANewSheet() async throws {
        let (service, store) = try await startSession()
        let show = ShowSourceTool(documentStore: store, sessionService: service)

        let one = try await lookup(["table": "Table 98", "row": "14", "column": "rating group 1 band a"],
                                   service: service, store: store)
        XCTAssertTrue(one.contains("0.83"), one)
        let first = try await show.execute(args: ["which": "Table 98"])
        let firstPages = try XCTUnwrap(service.sourceCenter.presented?.pages)
        XCTAssertEqual(firstPages.first?.citedPassages.count, 1)
        XCTAssertTrue(first.contains("Marked on the page: row 13-15."), first)

        let between = try await lookup(["table": "Table 98", "row": "9.5", "column": "rating group 1 band a"],
                                       service: service, store: store)
        XCTAssertTrue(between.contains("7-9") && between.contains("10-12"), between)
        let second = try await show.execute(args: ["which": "the table"])
        let secondPages = try XCTUnwrap(service.sourceCenter.presented?.pages)
        XCTAssertEqual(secondPages.map(\.page), firstPages.map(\.page), "the same page")
        XCTAssertEqual(secondPages.first?.citedPassages.count, 2, "both rows either side of 9.5")
        XCTAssertTrue(second.contains("Marked on the page: row 7-9; row 10-12."), second)
        XCTAssertTrue(second.contains("Say only that these rows are highlighted."), second)
        XCTAssertFalse(second.contains("13-15"), second)

        // The sheet already open is identified by its marks too, so the new rows replace it.
        XCTAssertNotEqual(AppState.ManualFigureRequest.identity(of: firstPages),
                          AppState.ManualFigureRequest.identity(of: secondPages))
        // "Show me" again with nothing new is the sheet already open: no blink.
        _ = try await show.execute(args: ["which": "the table"])
        XCTAssertEqual(AppState.ManualFigureRequest.identity(of: try XCTUnwrap(service.sourceCenter.presented?.pages)),
                       AppState.ManualFigureRequest.identity(of: secondPages))
    }

    func testATableWhoseGridWasNotReadSaysSoAndItsPageOpensUnmarked() async throws {
        let (service, store) = try await startSession()
        let reply = try await lookup(["table": "Table 92", "row": "anything"], service: service, store: store)
        XCTAssertTrue(reply.contains("could not be read"), reply)
        XCTAssertTrue(reply.contains("PDF page 4"), "no printed number on that page: \(reply)")
        XCTAssertTrue(reply.hasSuffix("Source: \(Self.bookA), page 4, Table 92"), reply)

        let shown = try await ShowSourceTool(documentStore: store, sessionService: service).execute(args: ["which": "the table"])
        XCTAssertEqual(service.sourceCenter.presented?.pages.map(\.page), [4])
        XCTAssertEqual(service.sourceCenter.presented?.pages.first?.citedPassages, [])
        XCTAssertFalse(shown.contains("highlighted"), shown)
    }

    func testAQuestionNamingATableRanksThatTableFirst() async throws {
        let (service, store) = try await startSession()
        let vault = try XCTUnwrap(service.activeVault)
        let retriever = service.makeRetriever(store: vault, documentStore: store)

        // The prose page shares more of these words than any row does; the named table still leads.
        let named = service.retrieveManualPassages(.init(turn: "general care of the unit, per table 98, band A at 13-15"),
                                                   with: retriever, store: vault)
        XCTAssertEqual(named.passages.first?.figure, "Table 98", "\(named.passages.map(\.citation))")
        XCTAssertTrue(named.passages.first?.tableMatch == true)

        // By its title words, with the word "table".
        let titled = service.retrieveManualPassages(.init(turn: "what does the correction factors table give for 16-18"),
                                                    with: retriever, store: vault)
        XCTAssertEqual(titled.passages.first?.figure, "Table 98")
        XCTAssertEqual(titled.passages.first?.kind, .tableRow)
        XCTAssertTrue(titled.passages.first?.text.contains("row 16-18") == true, "\(titled.passages.first?.text ?? "")")

        // Spoken.
        let spoken = service.retrieveManualPassages(.init(turn: "read me table ninety-nine for QMX90 two conductors"),
                                                    with: retriever, store: vault)
        XCTAssertEqual(spoken.passages.first?.figure, "Table 99")
        XCTAssertTrue(spoken.passages.first?.text.contains("row QMX90, two conductors") == true)
        XCTAssertEqual(spoken.passages.count, 6, "a table row first: six passages, as for a clause")
    }

    /// Plan JW P1b: a value asked for in plain words, no table named, gets a line naming the table
    /// whose title fits, for `table_lookup` to read; a turn naming the table, or asking no value,
    /// gets none.
    func testAPlainWordsValueQuestionNamesTheTableInTheManualBlock() async throws {
        let (service, _) = try await startSession()
        let vault = try XCTUnwrap(service.activeVault)
        let plain = try XCTUnwrap(service.manualPassagesContext(turn: "which correction factor applies in band B for 10-12",
                                                                store: vault))
        XCTAssertTrue(plain.contains("Tables that may answer this: Table 98 — Correction factors (\(Self.bookA))"), plain)
        XCTAssertTrue(plain.contains("Read the value with table_lookup (table, row, column)"), plain)

        let named = try XCTUnwrap(service.manualPassagesContext(turn: "in table 98, band B at 10-12, what factor", store: vault))
        XCTAssertFalse(named.contains("Tables that may answer this"), named)
        let notValue = try XCTUnwrap(service.manualPassagesContext(turn: "how do I clean the unit", store: vault))
        XCTAssertFalse(notValue.contains("Tables that may answer this"), notValue)
    }

    func testAQuestionNamingARowHeaderReachesTheRowPassage() async throws {
        let (service, store) = try await startSession()
        let vault = try XCTUnwrap(service.activeVault)
        let retriever = service.makeRetriever(store: vault, documentStore: store)

        let byDesignation = service.retrieveManualPassages(.init(turn: "what is QXRT three conductors in rating group 2"),
                                                           with: retriever, store: vault).passages
        let firstRow = byDesignation.first { $0.kind == .tableRow }
        XCTAssertTrue(firstRow?.text.contains("row QXRT, three conductors") == true, "\(byDesignation.map(\.text))")
        XCTAssertTrue(firstRow?.matchedTokens.contains("QXRT") == true, "reached by the exact-token route")

        // A row keyed by a printed range, which the tokenizer used to split at the dash.
        let byRange = service.retrieveManualPassages(.init(turn: "what is the factor for 7-9 in rating group 2 band B"),
                                                     with: retriever, store: vault).passages
        let rows = byRange.filter { $0.kind == .tableRow && $0.figure == "Table 98" }
        XCTAssertTrue(rows.first?.text.contains("row 7-9") == true, "\(rows.map(\.text))")
        XCTAssertTrue(rows.first?.matchedTokens.contains("7-9") == true)
    }

    func testTheMigrationKeepsTheCaptionsThatCouldNotBeReadWithoutTouchingTheText() async throws {
        let (service, store) = try await startSession()
        _ = service
        let idA = try id(of: Self.bookA, in: store)
        // As a store P0 left it: version 3, the unreadable caption not kept.
        let read = store.tables(documentId: idA)
        XCTAssertEqual(read.filter { !$0.isExtracted }.map(\.label), ["Table 92"], "kept at import")
        _ = await store.replaceTables(read.filter(\.isExtracted), documentId: idA)
        let dbURL = tempRoot.appendingPathComponent("store/documents.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        sqlite3_exec(db, "UPDATE doc_chunks SET location_version = 3", nil, nil, nil)
        sqlite3_close(db)
        let texts = store.fullText(documentId: idA)
        XCTAssertTrue(store.needsLocation(documentId: idA))

        let ledger = VaultImporter.documentLedger(for: Self.vaultId)
        let entry = try XCTUnwrap(ledger.entries.first { $0.documentId == idA })
        let root = VaultImporter.baselineDirectory(for: Self.vaultId)
        let outcome = await PassageLocationMigration.migrate(entry: entry,
                                                             fileURL: root.appendingPathComponent("documents/a.pdf"),
                                                             store: store)
        XCTAssertEqual(outcome, .located)
        XCTAssertEqual(store.tables(documentId: idA).filter { !$0.isExtracted }.map(\.label), ["Table 92"])
        XCTAssertEqual(store.fullText(documentId: idA), texts, "the text is as it was")
        XCTAssertFalse(store.needsLocation(documentId: idA))
    }
}
