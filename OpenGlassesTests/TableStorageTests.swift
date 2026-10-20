import SQLite3
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JJ P0 — where an extracted table lives and where it never goes: stored beside the
/// document's passages at import, brought to stored documents by the location migration without
/// re-chunking their text, its rows searchable as passages that never open a page by themselves,
/// and nothing of it in a vault export.
@MainActor
final class TableStorageTests: XCTestCase {

    private static let vaultId = "table_storage_test"
    private var tempRoot: URL!
    private var previousEntitlement: FieldAssistEntitlementProvider!

    override func setUp() {
        super.setUp()
        previousEntitlement = EntitlementTestScope.grant()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TableStorageTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        VaultImporter.uninstall(id: Self.vaultId)
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        EntitlementTestScope.restore(previousEntitlement)
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func makeStore() -> (DocumentStore, URL) {
        let dir = tempRoot.appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (DocumentStore(directory: dir), dir)
    }

    /// A two-page manual: prose, then Table 99 with "12" printed in its footer.
    private func manualPDF(named name: String = "manual.pdf", in directory: URL? = nil) throws -> URL {
        try TableFixtures.write(TableFixtures.pdf([TableFixtures.prosePage(), TableFixtureLayouts.simpleGrid()]),
                                named: name, in: directory ?? tempRoot)
    }

    private func rows(_ directory: URL) -> [(index: Int, text: String, embedding: Data?, kind: String?)] {
        var db: OpaquePointer?
        sqlite3_open(directory.appendingPathComponent("documents.sqlite").path, &db)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT chunk_index, text, embedding, kind FROM doc_chunks ORDER BY chunk_index", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        var out: [(Int, String, Data?, String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let blob = sqlite3_column_blob(stmt, 2).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(stmt, 2))) }
            let kind = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 3))
            out.append((Int(sqlite3_column_int(stmt, 0)), String(cString: sqlite3_column_text(stmt, 1)), blob, kind))
        }
        return out
    }

    /// Mark every row as stored by the previous location version, as a store from before P0 reads.
    private func makeVersionTwo(_ directory: URL) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("documents.sqlite").path, &db), SQLITE_OK)
        sqlite3_exec(db, "UPDATE doc_chunks SET location_version = 2", nil, nil, nil)
        sqlite3_close(db)
    }

    // MARK: - Stored at import

    func testIngestStoresTheTablesAndTheirRowsAfterTheDocumentsOwnText() async throws {
        let (store, dir) = makeStore()
        let url = try manualPDF()
        let extracted = try VaultDocumentExtractor.extract(from: url)
        let tables = try XCTUnwrap(VaultDocumentExtractor.tables(from: url)).tables
        let plain = DocumentChunker().chunk(extracted.text.trimmingCharacters(in: .whitespacesAndNewlines))
        let ref = try await XCTUnwrapAsync(await store.ingest(name: "Invented Manual", text: extracted.text,
                                                              sourceType: "vault_document", namespace: "vault:x",
                                                              pageLabels: extracted.pageLabels, tables: tables))
        XCTAssertEqual(store.tables(documentId: ref.id), tables, "the table round-trips whole")

        let stored = rows(dir)
        XCTAssertEqual(stored.filter { $0.kind != "table_row" }.map(\.text), plain.map(\.text),
                       "the document's own chunks are exactly what they are without tables")
        let tableRows = stored.filter { $0.kind == "table_row" }
        XCTAssertEqual(tableRows.map(\.index), Array(plain.count..<(plain.count + 4)), "numbered after the text")
        XCTAssertEqual(tableRows[1].text, "Table 99 (Conductor ratings), row QXRT, three conductors: 30 in Rating group 1, "
                       + "35 in Rating group 2, 40 in Rating group 3 \u{2014} page 12")
        XCTAssertTrue(tableRows.allSatisfy { $0.embedding != nil }, "row passages are embedded like any chunk")
        XCTAssertEqual(ref.chunkCount, plain.count + 4)

        // The document's own text never includes them.
        XCTAssertFalse(store.fullText(documentId: ref.id)?.contains("in Rating group 1") ?? true)
        XCTAssertFalse(store.pageTexts(documentId: ref.id).contains { $0.text.contains("in Rating group 1") })
        XCTAssertTrue(store.writeLocations(documentId: ref.id, chunks: plain),
                      "re-locating compares the text chunks only")
    }

    func testRowPassagesAreFoundByTheirRowHeaderAndTheirTable() async throws {
        let (store, _) = makeStore()
        let url = try manualPDF()
        let extracted = try VaultDocumentExtractor.extract(from: url)
        let ref = try await XCTUnwrapAsync(await store.ingest(
            name: "Invented Manual", text: extracted.text, namespace: "vault:x",
            tables: try XCTUnwrap(VaultDocumentExtractor.tables(from: url)).tables))

        let byToken = store.passages(containingToken: "QMX90", namespace: "vault:x")
        XCTAssertTrue(byToken.contains { $0.kind == .tableRow && $0.figure == "Table 99" && $0.page == 2 }, "\(byToken)")
        let byLabel = store.passages(figure: "Table 99", namespace: "vault:x", limit: 10)
        XCTAssertEqual(byLabel.filter { $0.kind == .tableRow }.count, 4)
        let byTerms = store.passages(sharingTermsWith: "QXRT three conductors rating group", namespace: "vault:x")
        XCTAssertTrue(byTerms.contains { $0.kind == .tableRow }, "the lexical route reaches a row by its header words")
        XCTAssertTrue(store.query("QXRT three conductors rating group", limit: 20, namespace: "vault:x")
            .contains { $0.kind == .tableRow }, "and the semantic route searches them")
        XCTAssertFalse(store.query("QXRT three conductors", limit: 20, namespace: "vault:x", kinds: [.prose])
            .contains { $0.kind == .tableRow }, "the kinds filter still decides")
        XCTAssertFalse(store.isClauseNumbered(documentId: ref.id))
    }

    func testRowPassagesAreCappedPerTableAndTheTableIsKeptWhole() async throws {
        let (store, dir) = makeStore()
        let long = ManualTable(label: "Table 91", title: "Long list", page: .init(physical: 1),
                               columns: [.init(path: ["Value"])],
                               rows: (1...(TableRowPassage.rowCap + 3)).map {
                                   .init(path: ["QL\($0)"], cells: [.init(text: "\($0)", value: Double($0))],
                                         page: .init(physical: 1))
                               })
        let ref = try await XCTUnwrapAsync(await store.ingest(name: "Long", text: "An invented manual with one long table.",
                                                              namespace: "vault:x", tables: [long]))
        XCTAssertEqual(rows(dir).filter { $0.kind == "table_row" }.count, TableRowPassage.rowCap)
        XCTAssertEqual(store.lastTableRowsDropped, 3, "the cap is reported for the log")
        XCTAssertEqual(store.tables(documentId: ref.id).first?.rows.count, TableRowPassage.rowCap + 3)
    }

    func testForgettingOrClearingADocumentTakesItsTables() async throws {
        let (store, _) = makeStore()
        let table = ManualTable(label: "Table 99", title: "", page: .init(physical: 1), columns: [.init(path: ["A"])],
                                rows: [.init(path: ["QXRT"], cells: [.init(text: "1", value: 1)], page: .init(physical: 1))])
        let first = try await XCTUnwrapAsync(await store.ingest(name: "One", text: "Invented text one.",
                                                                namespace: "vault:x", tables: [table]))
        try store.forget(documentId: first.id, inNamespace: "vault:x")
        XCTAssertTrue(store.tables(documentId: first.id).isEmpty)

        let second = try await XCTUnwrapAsync(await store.ingest(name: "Two", text: "Invented text two.",
                                                                 namespace: "vault:y", tables: [table]))
        store.clear(namespace: "vault:y")
        XCTAssertTrue(store.tables(documentId: second.id).isEmpty)

        let third = try await XCTUnwrapAsync(await store.ingest(name: "Three", text: "Invented text three.",
                                                                namespace: "vault:z", tables: [table]))
        store.forget(documentId: third.id)
        XCTAssertTrue(store.tables(documentId: third.id).isEmpty)
    }

    // MARK: - Brought to stored documents by the location migration

    func testTheMigrationAddsTablesWithoutTouchingTheTextChunks() async throws {
        let (store, dir) = makeStore()
        let url = try manualPDF()
        let extracted = try VaultDocumentExtractor.extract(from: url)
        // Indexed by a build from before tables: text only, location version 2.
        let ref = try await XCTUnwrapAsync(await store.ingest(name: "Invented Manual", text: extracted.text,
                                                              sourceType: "vault_document", namespace: "vault:x"))
        makeVersionTwo(dir)
        XCTAssertTrue(store.needsLocation(documentId: ref.id))
        let before = rows(dir)

        let entry = VaultDocumentLedger.Entry(file: "manual.pdf", title: ref.name, documentId: ref.id,
                                              contentHash: "h", chunkCount: ref.chunkCount)
        let outcome = await PassageLocationMigration.migrate(entry: entry, fileURL: url, store: store)
        XCTAssertEqual(outcome, .located, "unchanged text is located, never re-chunked")

        let after = rows(dir)
        let text = after.filter { $0.kind != "table_row" }
        XCTAssertEqual(text.map(\.index), before.map(\.index))
        XCTAssertEqual(text.map(\.text), before.map(\.text))
        XCTAssertEqual(text.map(\.embedding), before.map(\.embedding), "no text chunk was re-embedded")
        XCTAssertEqual(after.filter { $0.kind == "table_row" }.count, 4)
        XCTAssertEqual(store.tables(documentId: ref.id).map(\.label), ["Table 99"])
        XCTAssertFalse(store.needsLocation(documentId: ref.id))
        XCTAssertEqual(store.documents.first { $0.id == ref.id }?.chunkCount, before.count + 4)

        let again = await PassageLocationMigration.migrate(entry: entry, fileURL: url, store: store)
        XCTAssertEqual(again, .current, "a second launch has nothing to do")
        XCTAssertEqual(rows(dir).count, after.count)
    }

    func testTheMigrationReadsTablesFromTheOriginalOfATextImport() async throws {
        let (store, dir) = makeStore()
        let pdf = try manualPDF()
        let text = try VaultDocumentExtractor.extract(from: pdf).text
        let markdown = tempRoot.appendingPathComponent("manual.md")
        try text.write(to: markdown, atomically: true, encoding: .utf8)
        let ref = try await XCTUnwrapAsync(await store.ingest(name: "Invented Manual", text: text,
                                                              sourceType: "vault_document", namespace: "vault:x"))
        makeVersionTwo(dir)
        let entry = VaultDocumentLedger.Entry(file: "manual.md", title: ref.name, documentId: ref.id,
                                              contentHash: "h", chunkCount: ref.chunkCount)

        let outcome = await PassageLocationMigration.migrate(entry: entry, fileURL: markdown, originalURL: pdf, store: store)
        XCTAssertEqual(outcome, .located)
        XCTAssertEqual(store.tables(documentId: ref.id).map(\.label), ["Table 99"], "read from the original PDF")
    }

    func testTheMigrationOfATextOnlyImportSkipsTablesQuietly() async throws {
        let (store, dir) = makeStore()
        let markdown = tempRoot.appendingPathComponent("notes.md")
        try "# Notes\n\nAn invented manual kept as text. TABLE 99 is mentioned but not drawn."
            .write(to: markdown, atomically: true, encoding: .utf8)
        let ref = try await XCTUnwrapAsync(await store.ingest(name: "Notes", text: try String(contentsOf: markdown, encoding: .utf8),
                                                              sourceType: "vault_document", namespace: "vault:x"))
        makeVersionTwo(dir)
        let entry = VaultDocumentLedger.Entry(file: "notes.md", title: ref.name, documentId: ref.id,
                                              contentHash: "h", chunkCount: ref.chunkCount)
        let outcome = await PassageLocationMigration.migrate(entry: entry, fileURL: markdown,
                                                             originalURL: tempRoot.appendingPathComponent("missing.pdf"),
                                                             store: store)
        XCTAssertEqual(outcome, .located)
        XCTAssertTrue(store.tables(documentId: ref.id).isEmpty)
        XCTAssertFalse(store.needsLocation(documentId: ref.id), "and it is not tried again")
    }

    // MARK: - Import, and never in an export

    private func writeVault() throws -> URL {
        let dir = tempRoot.appendingPathComponent("source", isDirectory: true)
        let documents = dir.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        _ = try manualPDF(named: "ratings.pdf", in: documents)
        let manifest = VaultManifest(id: Self.vaultId, name: "Table Storage Test", version: "1.0.0",
                                     files: ["info.md"], documentsDir: "documents",
                                     documents: [VaultDocument(file: "ratings.pdf", title: "Invented Ratings Manual")],
                                     promptRules: ["Never fabricate a value.", "Cite the source file."])
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try "# Info\n\nShipped content.".write(to: dir.appendingPathComponent("info.md"), atomically: true, encoding: .utf8)
        return dir
    }

    func testImportStoresTheTablesAndTheExportCarriesNoneOfThem() async throws {
        let (store, _) = makeStore()
        let manifest = try VaultImporter.install(from: writeVault())
        VaultRegistry.shared.reloadUserManifests()
        let ledger = try await VaultImporter.syncDocuments(manifest: manifest, into: store)
        let documentId = try XCTUnwrap(ledger.entries.first?.documentId)
        XCTAssertEqual(store.tables(documentId: documentId).map(\.label), ["Table 99"], "extracted at import")
        XCTAssertTrue(store.passages(containingToken: "QMX90", namespace: DocumentStore.vaultNamespace(manifest.id))
            .contains { $0.kind == .tableRow })

        let exported = try VaultExporter.export(id: manifest.id)
        let enumerator = FileManager.default.enumerator(at: exported, includingPropertiesForKeys: nil)
        let files = (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = String(data: try Data(contentsOf: file), encoding: .utf8) ?? ""
            // Value-only tokens: a cell's designation and a row's rendered words, never in the manifest.
            for token in ["QMX90", "QXRT", "Rating group", "three conductors"] {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) carries table content")
            }
        }
        await VaultImporter.uninstall(id: manifest.id, documentStore: store)
        XCTAssertTrue(store.tables(documentId: documentId).isEmpty, "uninstalling takes the tables with the manual")
    }

    func testTheExporterAndThePackPathsNeverReadTables() throws {
        // Tables live only in the document store; the paths a vault leaves the phone by never open it.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let vault = root.appendingPathComponent("OpenGlasses/Sources/Services/Vault")
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.path)
            .filter { $0.hasPrefix("VaultExporter") || $0.hasPrefix("VaultPack") || $0.hasPrefix("VaultLink")
                || $0.hasPrefix("VaultArchive") || $0.hasPrefix("VaultPublisher") }
        XCTAssertTrue(names.contains("VaultExporter.swift"), "sanity: the scan finds the exporter")
        for name in names {
            let source = try String(contentsOf: vault.appendingPathComponent(name), encoding: .utf8)
            for marker in ["doc_tables", "tables(documentId", "ManualTable", "TableRowPassage"] {
                XCTAssertFalse(source.contains(marker), "\(name) reaches extracted tables through \(marker)")
            }
        }
    }

    // MARK: - A row passage is never a drawing and never opens a page

    func testATableRowNeverOpensAPageUnasked() {
        XCTAssertEqual(FigureAutoOpenPolicy.PassageKind(.tableRow), .tableRow)
        XCTAssertEqual(FigureAutoOpenPolicy.PassageKind(.diagram), .diagram)
        XCTAssertEqual(FigureAutoOpenPolicy.PassageKind(.prose), .captioned)
        XCTAssertEqual(FigureAutoOpenPolicy.decide(turnKind: .question, passageKind: .tableRow, tokenHits: ["QXRT"]),
                       .attachToModelOnly(reason: .tableNotAskedFor))
        XCTAssertEqual(FigureAutoOpenPolicy.decide(turnKind: .question, passageKind: .tableRow, tokenHits: ["40"]),
                       .none(reason: .numbersOnly), "a number that matches a cell is a coincidence")
        XCTAssertEqual(FigureAutoOpenPolicy.decide(turnKind: .statement, passageKind: .tableRow, tokenHits: []),
                       .none(reason: .notAQuestion))
        XCTAssertEqual(FigureAutoOpenPolicy.decide(turnKind: .reading, passageKind: .tableRow, tokenHits: ["40"]),
                       .none(reason: .reading))
        XCTAssertEqual(FigureAutoOpenPolicy.decide(turnKind: .showMe, passageKind: .tableRow, tokenHits: []),
                       .present(reason: .askedForPage), "asked for, it opens like any page")
        for turn in [ManualTurnKind.question, .statement, .reading, .correction, .jobBookkeeping] {
            XCTAssertFalse(FigureAutoOpenPolicy.decide(turnKind: turn, passageKind: .tableRow, tokenHits: [])
                .presentsOnPhone, "\(turn)")
        }
    }

    func testARowPassageCitesItsTableAndIsAnnouncedAsARow() {
        var passage = VaultRetriever.Passage(documentId: "d", documentName: "Invented Manual", chunkIndex: 9,
                                             text: "Table 99 (Conductor ratings), row QXRT: 25 in Rating group 1 \u{2014} page 12",
                                             page: 2, section: "Ratings", similarity: 0.5, score: 0.5,
                                             matchedTokens: [])
        passage.kind = .tableRow
        passage.figure = "Table 99"
        XCTAssertEqual(passage.citation, "Invented Manual, page 2, Table 99")
        XCTAssertEqual(passage.kindLabel, "(table row, Table 99, page 2)")
        XCTAssertNotEqual(passage.kindLabel?.contains("wiring diagram"), true)
    }
}

/// `XCTUnwrap` for an async expression.
private func XCTUnwrapAsync<T>(_ expression: @autoclosure () async throws -> T?, file: StaticString = #filePath,
                               line: UInt = #line) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value, file: file, line: line)
}
