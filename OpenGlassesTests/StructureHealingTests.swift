import SQLite3
import XCTest
@testable import OpenGlasses

/// Plan JY P4, location version 8: a document stored before P4 has its text read again once. One
/// whose text chunks as stored keeps its rows, ids and vectors, and only its page, section and
/// figure are rewritten — here, the pages a footer folio had moved. Invented text only.
@MainActor
final class StructureHealingTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StructureHealingTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func rows(_ directory: URL) -> [(index: Int, text: String, page: Int?, embedding: Data?)] {
        var db: OpaquePointer?
        sqlite3_open(directory.appendingPathComponent("documents.sqlite").path, &db)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT chunk_index, text, page, embedding FROM doc_chunks ORDER BY chunk_index", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        var out: [(Int, String, Int?, Data?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let page = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 2))
            let blob = sqlite3_column_blob(stmt, 3).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(stmt, 3))) }
            out.append((Int(sqlite3_column_int(stmt, 0)), String(cString: sqlite3_column_text(stmt, 1)), page, blob))
        }
        return out
    }

    private func exec(_ sql: String, in directory: URL) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("documents.sqlite").path, &db), SQLITE_OK)
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)
    }

    func testAFolioMovedPageIsRewrittenWithoutReindexing() async throws {
        let dir = tempRoot.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: dir)
        let pages = (31...34).map { number in
            "Page \(number)\n\n" + (1...12).map { "Invented step \($0) on sheet \(number) checks the relief valve." }
                .joined(separator: " ") + "\n\n- \(number - 6) -\n"
        }
        let text = pages.joined(separator: "\n")
        let file = tempRoot.appendingPathComponent("folios.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let maybe = await store.ingest(name: "Invented Folio Book", text: text,
                                                              sourceType: "vault_document", namespace: "vault:f")
        let ref = try XCTUnwrap(maybe)
        let fresh = rows(dir)
        XCTAssertEqual(Set(fresh.compactMap(\.page)), [31, 32, 33, 34], "a fresh import cites the PDF's own pages")
        // What a build before P4 stored: each page after the first under the folio printed at the
        // foot of the page before it, at location version 7.
        exec("UPDATE doc_chunks SET page = page - 7 WHERE page > 31", in: dir)
        exec("UPDATE doc_chunks SET location_version = 7", in: dir)
        XCTAssertTrue(store.needsLocation(documentId: ref.id))
        let before = rows(dir)

        let entry = VaultDocumentLedger.Entry(file: "folios.md", title: ref.name, documentId: ref.id,
                                              contentHash: "h", chunkCount: ref.chunkCount)
        let outcome = await PassageLocationMigration.migrate(entry: entry, fileURL: file, store: store, pictureReader: nil)
        XCTAssertEqual(outcome, PassageLocationMigration.Outcome.located, "the text chunks as stored, so it is never re-chunked")
        let after = rows(dir)
        XCTAssertEqual(after.map(\.text), before.map(\.text))
        XCTAssertEqual(after.map(\.embedding), before.map(\.embedding), "no chunk was re-embedded")
        XCTAssertEqual(after.map(\.page), fresh.map(\.page), "the pages are the PDF's own again")
        XCTAssertFalse(store.needsLocation(documentId: ref.id))
        let again = await PassageLocationMigration.migrate(entry: entry, fileURL: file, store: store, pictureReader: nil)
        XCTAssertEqual(again, PassageLocationMigration.Outcome.current, "a second launch has nothing to do")
    }

    func testAnEnglishDocumentWithoutFoliosIsLeftExactlyAsItWas() async throws {
        let dir = tempRoot.appendingPathComponent("store-en", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: dir)
        let text = (1...3).map { number in
            "Page \(number)\n\n## Invented Section \(number)\n\n" + (1...10).map { "Invented sentence \($0) about the blower." }
                .joined(separator: " ")
        }.joined(separator: "\n\n")
        let file = tempRoot.appendingPathComponent("plain.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let maybe = await store.ingest(name: "Invented Plain Book", text: text,
                                                              sourceType: "vault_document", namespace: "vault:e")
        let ref = try XCTUnwrap(maybe)
        exec("UPDATE doc_chunks SET location_version = 7", in: dir)
        let before = rows(dir)
        let entry = VaultDocumentLedger.Entry(file: "plain.md", title: ref.name, documentId: ref.id,
                                              contentHash: "h", chunkCount: ref.chunkCount)
        let outcome = await PassageLocationMigration.migrate(entry: entry, fileURL: file, store: store, pictureReader: nil)
        XCTAssertEqual(outcome, PassageLocationMigration.Outcome.located)
        let after = rows(dir)
        XCTAssertEqual(after.map(\.text), before.map(\.text))
        XCTAssertEqual(after.map(\.page), before.map(\.page))
        XCTAssertEqual(after.map(\.embedding), before.map(\.embedding))
    }

    func testCJKAndArabicScriptManualsTakeTheLargerPassageBudget() async throws {
        let dir = tempRoot.appendingPathComponent("store-budget", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: dir)
        func ingest(_ name: String, _ text: String) async throws -> String {
            let maybe = await store.ingest(name: name, text: text, sourceType: "vault_document", namespace: "vault:b")
            return try XCTUnwrap(maybe).id
        }
        let chinese = try await ingest("Invented Chinese", String(repeating: "先检查阀门的压力，再打开盖板。", count: 20))
        let arabic = try await ingest("Invented Arabic", String(repeating: "افحص الصمام قبل فتح الغطاء. ", count: 20))
        let english = try await ingest("Invented English", String(repeating: "Check the valve before opening the cover. ", count: 20))
        XCTAssertTrue(store.usesClausePassageBudget(documentId: chinese))
        XCTAssertTrue(store.usesClausePassageBudget(documentId: arabic))
        XCTAssertFalse(store.usesClausePassageBudget(documentId: english))
        XCTAssertEqual(ManualPassageLimit().requestLimit(searchesClauseNumbered: store.usesClausePassageBudget(documentId: chinese)), 6)
    }
}
