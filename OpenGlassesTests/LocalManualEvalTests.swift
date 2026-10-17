import XCTest
@testable import OpenGlasses

/// The local retrieval eval, in the simulator (the measurement process for retrieval rounds).
///
/// `testLocalVaultAgainstItsAnswerKey` runs only when a developer points it at their own vault and
/// answer key; it skips in CI. The variables reach the test process with xcodebuild's
/// `TEST_RUNNER_` prefix:
///
///     TEST_RUNNER_RETRIEVAL_EVAL_VAULT=/path/to/vault \
///     TEST_RUNNER_RETRIEVAL_EVAL_ANSWER_KEY=/path/to/answers.jsonl \
///     xcodebuild test … -only-testing:OpenGlassesTests/LocalManualEvalTests
///
/// The vault is imported exactly as a customer's is (manifest, PDF or extracted text) and asked
/// through the session's own retriever factory, so this is the per-turn path on the simulator's
/// embedder. The Mac runner in `Scripts/retrieval-eval` measures the device's embedder. Output is
/// aggregate counts only (`RetrievalEval`).
///
/// The rest of the class is the core's own tests on synthetic fixtures, and always runs.
@MainActor
final class LocalManualEvalTests: XCTestCase {

    private var tempRoot: URL!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var installedVaultId: String?

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalManualEvalTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousEntitlement = EntitlementTestScope.grant()
        VaultRegistry.shared.resetCache()
    }

    override func tearDown() {
        if let installedVaultId { VaultImporter.uninstall(id: installedVaultId) }
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled")
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    // MARK: - The local run

    func testLocalVaultAgainstItsAnswerKey() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let vaultPath = env["RETRIEVAL_EVAL_VAULT"], let keyPath = env["RETRIEVAL_EVAL_ANSWER_KEY"] else {
            throw XCTSkip("set TEST_RUNNER_RETRIEVAL_EVAL_VAULT and TEST_RUNNER_RETRIEVAL_EVAL_ANSWER_KEY to run")
        }
        let questions = RetrievalEval.loadAnswerKey(try String(contentsOfFile: keyPath, encoding: .utf8))
        XCTAssertFalse(questions.isEmpty, "the answer key has no questions")

        let store = makeStore(chunker: RetrievalEval.chunker(named: env["RETRIEVAL_EVAL_CHUNKER"]))
        let (service, vaultStore) = try await installAndStart(URL(fileURLWithPath: vaultPath), store: store)
        let editions = service.documentEditions(of: vaultStore)
        let report = RetrievalEval.run(
            questions,
            gatedFor: { service.manualRetriever(store: vaultStore, editionRequest: EditionRequest.parse($0, editions: editions)) },
            openFor: { RetrievalEval.retriever(over: store, policy: RetrievalEvidencePolicy(similarityFloor: 0), editions: editions, turn: $0) },
            store: store)
        for line in report.lines(label: env["RETRIEVAL_EVAL_LABEL"] ?? "local vault", embedder: Embedder().modelId) {
            print(line)
        }
        XCTAssertGreaterThan(report.scored + report.outOfScope, 0)
    }

    // MARK: - The core, on synthetic fixtures

    /// A clause-numbered fixture: two rules, each printed as its own line after a group heading, a
    /// table, and a page that only cites a rule. Every rule, table and sentence is invented.
    private static let codeText = """
        Page 1

        Fittings
        99-100 Brackets on rails
        A bracket on a rail must carry the rail maker's own mark.
        Page 2

        Sockets
        99-200 Sockets near sinks
        A socket beside a sink needs a test button the user can reach.
        Page 3

        Table 99 Conditions of use for portable lamps
        A portable lamp used outdoors shall be marked for wet locations.
        Page 4

        For a socket on a patio, see Rule 99-200 for the sink rule as well.
        """

    func testAnswerKeyLinesAreReadAndCommentsSkipped() {
        let key = """
            // a comment
            {"q": "what does a sink socket need", "rules": ["99-200"]}

            {"q": "what torque for the set screw", "outOfScope": true}
            {"q": "portable lamp", "tables": ["Table 99"], "multi": false, "doubt": true}
            {"q": "flame signal", "pages": {"Fixture Manual": [34]}}
            not json
            {"rules": ["1-000"]}
            """
        let questions = RetrievalEval.loadAnswerKey(key)
        XCTAssertEqual(questions.count, 4)
        XCTAssertEqual(questions[0].expectsLabels, ["99-200"])
        XCTAssertEqual(questions[1].outOfScope, true)
        XCTAssertEqual(questions[2].doubt, true)
        XCTAssertEqual(questions[3].pages?["Fixture Manual"], [34])
        XCTAssertTrue(questions.allSatisfy { $0.isScorable || $0.outOfScope == true })
    }

    func testARuleCitedIsNotTheRulePrinted() {
        XCTAssertTrue(RetrievalEval.printsAsHeading("99-200", in: "Sockets 99-200 Sockets near sinks A socket", section: nil),
                      "after a group heading, joined by a space, the rule still prints as a heading")
        XCTAssertFalse(RetrievalEval.printsAsHeading("99-200", in: "on a patio, see Rule 99-200 for the sink rule", section: nil))
        XCTAssertFalse(RetrievalEval.printsAsHeading("99-200", in: "in accordance with Rules 99-200 and 99-202", section: nil))
        XCTAssertTrue(RetrievalEval.printsAsHeading("Table 99", in: "Table 99 Conditions of use", section: nil))
        XCTAssertFalse(RetrievalEval.printsAsHeading("Table 99", in: "see Table 99 Conditions", section: nil))
    }

    func testScoringCountsHitsRefusalsAndClassifiesMisses() async throws {
        let store = makeStore()
        _ = await store.ingest(name: "Fixture Code", text: Self.codeText, sourceType: "text")
        let gated = RetrievalEval.retriever(over: store, policy: RetrievalEvidencePolicy(similarityFloor: 0.30, minSharedTerms: 1))
        let open = RetrievalEval.retriever(over: store, policy: RetrievalEvidencePolicy(similarityFloor: 0))
        let questions = RetrievalEval.loadAnswerKey("""
            {"q": "rule 99-200 sink socket test button", "rules": ["99-200"]}
            {"q": "portable lamp marked for wet locations", "tables": ["Table 99"]}
            {"q": "weather forecast tomorrow afternoon", "outOfScope": true}
            {"q": "bracket on a rail with the maker's mark", "rules": ["98-999"], "doubt": true}
            """)
        let report = RetrievalEval.run(questions, gated: gated, open: open, store: store)
        XCTAssertEqual(report.scored, 3)
        XCTAssertEqual(report.outOfScope, 1)
        XCTAssertEqual(report.refused, 1, "nothing in the fixture shares a word with the weather")
        XCTAssertEqual(report.hit4, 2)
        XCTAssertEqual(report.misses[.notInDocuments], 1, "a rule the documents never print is the key's problem")
        XCTAssertEqual(report.doubtQuestions, 1)
        XCTAssertEqual(report.doubtMisses, 1)

        // The output is counts, never a question.
        let lines = report.lines(label: "fixture", embedder: Embedder().modelId).joined(separator: "\n")
        XCTAssertTrue(lines.contains("scored=3"), lines)
        XCTAssertTrue(lines.contains("out-of-scope refused 1 of 1"), lines)
        for q in questions { XCTAssertFalse(lines.contains(q.q), "a question leaked into the output") }
    }

    func testPageExpectationsScoreAndClassifyByPage() async throws {
        let store = makeStore()
        _ = await store.ingest(name: "Fixture Code", text: Self.codeText, sourceType: "text")
        let gated = RetrievalEval.retriever(over: store, policy: RetrievalEvidencePolicy(similarityFloor: 0))
        let questions = RetrievalEval.loadAnswerKey("""
            {"q": "portable lamp marked for wet locations", "pages": {"Fixture Code": [3]}}
            """)
        let report = RetrievalEval.run(questions, gated: gated, open: gated, store: store)
        XCTAssertEqual(report.hit4, 1)
        let own = RetrievalEval.ownPassages(questions[0], store: store)
        XCTAssertFalse(own.isEmpty, "the page's own chunks are located")
    }

    func testNearDuplicatesAreAcrossDocumentsOnly() {
        func p(_ doc: String, _ text: String) -> VaultRetriever.Passage {
            VaultRetriever.Passage(documentId: doc, documentName: doc, chunkIndex: 0, text: text, page: 1,
                                   section: nil, similarity: 0, score: 0, matchedTokens: [])
        }
        let table = "E223 low pressure switch failed open check the hose and the switch"
        XCTAssertTrue(RetrievalEval.nearDuplicate(p("a", table), p("b", table)))
        XCTAssertFalse(RetrievalEval.nearDuplicate(p("a", table), p("a", table)), "one document's own chunks are not duplicates")
        XCTAssertFalse(RetrievalEval.nearDuplicate(p("a", table), p("b", "blower speed taps and DIP switches")))
    }

    /// The store-only retriever the Mac runner and the calibration test use ranks exactly as the
    /// session's per-turn factory does, so their numbers describe what a technician gets.
    func testTheStoreOnlyRetrieverRanksAsTheSessionFactoryDoes() async throws {
        let store = makeStore()
        let vault = try writeVault()
        let (service, vaultStore) = try await installAndStart(vault, store: store)
        let session = service.manualRetriever(store: vaultStore)
        let storeOnly = RetrievalEval.retriever(over: store, policy: service.retrievalPolicy)
        for turn in ["rule 99-200 sink socket", "portable lamp", "Table 99", "bracket on a rail",
                     "what torque for the blower wheel set screw"] {
            let a = session.retrieve(.init(turn: turn, limit: 4))
            let b = storeOnly.retrieve(.init(turn: turn, limit: 4))
            XCTAssertEqual(a.passages.map(\.citation), b.passages.map(\.citation), turn)
            XCTAssertEqual(a.isSufficient, b.isSufficient, turn)
        }
    }

    // MARK: - Fixtures

    /// Small chunks, so the fixture's few lines land in chunks of their own and pages stay apart.
    /// The local run keeps the shipped chunker.
    private func makeStore(chunker: DocumentChunker = DocumentChunker(targetChars: 120, maxChars: 200, overlapChars: 20)) -> DocumentStore {
        let dir = tempRoot.appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return DocumentStore(directory: dir, chunker: chunker)
    }

    private func writeVault() throws -> URL {
        let dir = tempRoot.appendingPathComponent("vault", isDirectory: true)
        let docs = dir.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let manifest = VaultManifest(id: "local_eval_fixture", name: "Eval Fixture", version: "1.0.0",
                                     files: ["safety.md"], proceduresDir: nil, documentsDir: "documents",
                                     documents: [VaultDocument(file: "code.txt", title: "Fixture Code", kind: "standard")],
                                     gating: .init(iap: "enterprise"), promptRules: ["Never fabricate.", "Cite the source."])
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try "# Safety\n\nIsolate the supply first.".write(to: dir.appendingPathComponent("safety.md"), atomically: true, encoding: .utf8)
        try Self.codeText.write(to: docs.appendingPathComponent("code.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Install a vault folder as a customer's is, index its documents, and start a session on it.
    private func installAndStart(_ directory: URL, store: DocumentStore) async throws -> (FieldSessionService, VaultStore) {
        let manifest = try VaultImporter.install(from: directory)
        installedVaultId = manifest.id
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        _ = try await VaultImporter.syncDocuments(manifest: manifest, into: store)
        let service = FieldSessionService(sessionsRoot: tempRoot.appendingPathComponent("sessions", isDirectory: true))
        service.documentStore = store
        _ = try service.startSession(vaultId: manifest.id, assetId: nil)
        let vaultStore = VaultRegistry.shared.store(for: manifest)
        return (service, vaultStore)
    }
}
