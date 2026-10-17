import Combine
import XCTest
@testable import OpenGlasses

/// A vault's manuals on their own embedding model, re-indexed beside the index that answers,
/// resumably (Plan IV P4). Two invented models stand in for the standard and contextual ones, so
/// nothing here needs the real contextual model, which the simulator may not have.
@MainActor
final class VaultEmbeddingUpgradeTests: XCTestCase {

    /// A deterministic bag-of-words embedder. `offset` makes its vectors differ from another
    /// model's for the same text, as two real models' do; `calls` counts what it embedded.
    final class FakeModel: EmbeddingBackend {
        let modelId: String
        let dimension = 32
        private let offset: Int
        private(set) var calls = 0
        init(_ modelId: String, offset: Int) { self.modelId = modelId; self.offset = offset }
        func embed(_ text: String) -> [Float]? {
            calls += 1
            var v = [Float](repeating: 0, count: dimension)
            for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
                v[(abs(word.hashValue) + offset) % dimension] += 1
            }
            return v.contains { $0 != 0 } ? v : nil
        }
    }

    private var tempRoot: URL!
    private let vault = DocumentStore.vaultNamespace("upgrade_fixture")
    private let standard = FakeModel("nl-sentence.fake", offset: 0)
    private let contextual = FakeModel("nl-contextual.fake", offset: 7)

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultEmbeddingUpgradeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    /// Small chunks, so each page's sentences land in chunks of their own.
    private let smallChunks = DocumentChunker(targetChars: 120, maxChars: 200, overlapChars: 20)

    private func makeStore() -> DocumentStore {
        let store = DocumentStore(directory: tempRoot, chunker: smallChunks, embedder: Embedder(backend: standard))
        store.fieldAssistEmbedder = Embedder(backend: standard)
        return store
    }

    private let manual = """
        Page 1

        The blue cover goes on before the first power-up. Keep the spare cover in the lid pocket.
        Page 2

        Turn the dial left until the green lamp lights. Wait ten seconds before you close the door.
        Page 3

        Wipe the filter rack with a dry cloth. Never use water on the rack.
        """

    private func ingestManual(_ store: DocumentStore, name: String = "Fixture Manual") async {
        _ = await store.ingest(name: name, text: manual, sourceType: "vault_document", namespace: vault)
    }

    // MARK: - One model per index

    func testAVaultIsSearchedWithTheModelThatIndexedItWhateverTheTarget() async {
        let store = makeStore()
        await ingestManual(store)
        XCTAssertEqual(store.servingVersionTag(namespace: vault), Embedder(backend: standard).version.tag)

        // The target moves to the contextual model; until the re-index completes the question is
        // embedded with the standard model, the one the index was built with.
        store.fieldAssistEmbedder = Embedder(backend: contextual)
        let before = contextual.calls
        let hits = store.query("green lamp dial", limit: 2, namespace: vault)
        XCTAssertEqual(hits.first?.text.contains("green lamp"), true, "\(hits.map(\.text))")
        XCTAssertEqual(contextual.calls, before, "the target model never embeds a question for an index it didn't build")
        XCTAssertEqual(store.servingModelId(namespace: vault), "nl-sentence.fake")
    }

    func testAReindexIsBuiltBesideTheIndexAndSwapsInWhole() async {
        let store = makeStore()
        await ingestManual(store)
        let target = Embedder(backend: contextual)
        store.fieldAssistEmbedder = target

        // Stopped after one chunk: the standard index still answers, nothing half-built does.
        var allowed = 1
        let first = await store.upgradeVaultEmbeddings(namespace: vault, to: target, shouldContinue: {
            defer { allowed -= 1 }
            return allowed > 0
        })
        guard case .interrupted(let done, let total) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(done, 1)
        XCTAssertGreaterThan(total, 1)
        XCTAssertEqual(store.servingModelId(namespace: vault), "nl-sentence.fake")
        XCTAssertEqual(store.query("green lamp dial", limit: 1, namespace: vault).first?.text.contains("green lamp"), true)

        // Resumed: only what's missing is embedded, then the whole vault swaps.
        let callsBefore = contextual.calls
        let second = await store.upgradeVaultEmbeddings(namespace: vault, to: target)
        XCTAssertEqual(second, .completed(chunks: total - 1))
        XCTAssertEqual(contextual.calls - callsBefore, total - 1, "the chunk embedded before the stop is not embedded again")
        XCTAssertEqual(store.servingModelId(namespace: vault), "nl-contextual.fake")
        XCTAssertEqual(store.upgradeProgress(namespace: vault, targetTag: target.version.tag).done, total)

        // Now the question is embedded with the contextual model, and still finds its page.
        let questionCalls = contextual.calls
        XCTAssertEqual(store.query("green lamp dial", limit: 1, namespace: vault).first?.text.contains("green lamp"), true)
        XCTAssertEqual(contextual.calls, questionCalls + 1)

        // Nothing left to do.
        let third = await store.upgradeVaultEmbeddings(namespace: vault, to: target)
        XCTAssertEqual(third, .current)
    }

    func testAManualImportedMidReindexJoinsTheIndexThatAnswers() async {
        let store = makeStore()
        await ingestManual(store)
        store.fieldAssistEmbedder = Embedder(backend: contextual)
        await ingestManual(store, name: "Second Manual")
        // The vault is still served by the standard model, so the new manual is too.
        XCTAssertEqual(store.servingModelId(namespace: vault), "nl-sentence.fake")
        let outcome = await store.upgradeVaultEmbeddings(namespace: vault, to: Embedder(backend: contextual))
        guard case .completed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(store.servingModelId(namespace: vault), "nl-contextual.fake")
    }

    func testOtherNamespacesKeepTheStoresEmbedder() async {
        let store = makeStore()
        store.fieldAssistEmbedder = Embedder(backend: contextual)
        _ = await store.ingest(name: "Notes", text: "The red kettle is in the second cupboard.", namespace: "global")
        let callsBefore = contextual.calls
        XCTAssertEqual(store.query("red kettle", limit: 1, namespace: "global").count, 1)
        XCTAssertEqual(contextual.calls, callsBefore, "a personal document never meets Field Assist's model")
        XCTAssertEqual(store.servingModelId(namespace: "global"), "nl-sentence.fake")
        // The app-wide re-index leaves a vault's manuals to their own model.
        await ingestManual(store)
        _ = await store.upgradeVaultEmbeddings(namespace: vault, to: Embedder(backend: contextual))
        XCTAssertEqual(store.outdatedChunkCount, 0)
        let reembedded = await store.reindexOutdated()
        XCTAssertEqual(reembedded, 0)
        XCTAssertEqual(store.servingModelId(namespace: vault), "nl-contextual.fake")
    }

    // MARK: - The orchestrator

    final class NoBackgroundTime: BackgroundTaskRunning {
        func begin(name: String) -> Int { 1 }
        func end(_ token: Int) {}
    }

    func testTheUpgradeRunsEachVaultUnderItsLockAndReportsProgress() async throws {
        let store = makeStore()
        await ingestManual(store)
        let monitor = VaultIndexingMonitor()
        monitor.backgroundTasks = NoBackgroundTime()
        let saved = VaultEmbeddingUpgrade.target
        VaultEmbeddingUpgrade.target = { Embedder(backend: self.contextual) }
        defer { VaultEmbeddingUpgrade.target = saved }
        let manifest = VaultManifest(id: "upgrade_fixture", name: "Upgrade Fixture", version: "1.0.0",
                                     files: ["safety.md"], proceduresDir: nil, documentsDir: "documents",
                                     documents: [VaultDocument(file: "m.txt", title: "Fixture Manual")],
                                     gating: .init(iap: "enterprise"), promptRules: ["Never fabricate."])
        var sawProgress = false
        let watcher = monitor.$runs.sink { runs in if let run = runs["upgrade_fixture"], run.total > 0 { sawProgress = true } }
        defer { watcher.cancel() }
        let outcomes = await VaultEmbeddingUpgrade.run(store: store, manifests: [manifest], monitor: monitor)
        guard case .completed = outcomes["upgrade_fixture"] else { return XCTFail("\(outcomes)") }
        XCTAssertTrue(sawProgress, "the indexing screen saw the re-index")
        XCTAssertNil(monitor.run(for: "upgrade_fixture"), "and the run ended")

        // On the target already: nothing runs.
        let again = await VaultEmbeddingUpgrade.run(store: store, manifests: [manifest], monitor: monitor)
        XCTAssertEqual(again["upgrade_fixture"], .current)
    }

    func testWithoutTheContextualModelAVaultStaysOnTheStandardModel() async {
        // Asking for the contextual model when it isn't on the device gives the standard model —
        // the fallback the simulator exercises — and a vault already on it has nothing to do.
        let fallback = Embedder(preference: .contextual)
        XCTAssertTrue(fallback.isAvailable)
        if !Embedder.contextualModelAvailable {
            XCTAssertEqual(fallback.modelId, Embedder(preference: .standard).modelId)
        }
        let store = DocumentStore(directory: tempRoot, chunker: smallChunks)
        store.fieldAssistEmbedder = Embedder(preference: .standard)
        _ = await store.ingest(name: "Fixture Manual", text: manual, sourceType: "vault_document", namespace: vault)
        let outcome = await store.upgradeVaultEmbeddings(namespace: vault, to: Embedder(preference: .standard))
        XCTAssertEqual(outcome, .current)
        XCTAssertFalse(store.query("green lamp dial", limit: 1, namespace: vault).isEmpty, "the vault stays searchable")
    }

    // MARK: - The gate follows the serving model

    func testTheGateIsChosenByTheModelAVaultIsServedBy() async throws {
        let store = makeStore()
        await ingestManual(store)
        let session = FieldSessionService(sessionsRoot: tempRoot.appendingPathComponent("sessions", isDirectory: true))
        session.documentStore = store
        XCTAssertEqual(session.retrievalPolicy(forVault: "upgrade_fixture"), .default(for: "nl-sentence.fake"))
        _ = await store.upgradeVaultEmbeddings(namespace: vault, to: Embedder(backend: contextual))
        XCTAssertEqual(session.retrievalPolicy(forVault: "upgrade_fixture"), .default(for: "nl-contextual.fake"))
        session.retrievalPolicy = RetrievalEvidencePolicy(similarityFloor: 0)
        XCTAssertEqual(session.retrievalPolicy(forVault: "upgrade_fixture"), RetrievalEvidencePolicy(similarityFloor: 0),
                       "a pinned gate wins")
    }

    // MARK: - Support-report timing

    func testIndexingAndQueriesLogCountsAndDurationsOnly() async {
        var events: [String] = []
        let tap = PrivacyLog.addTap { _, line in events.append(line) }
        defer { PrivacyLog.removeTap(tap) }
        let store = makeStore()
        await ingestManual(store)
        _ = store.query("green lamp dial", limit: 1, namespace: vault)
        let indexed = events.filter { $0.contains("indexed") }
        let queried = events.filter { $0.contains("queryEmbedded") }
        XCTAssertFalse(indexed.isEmpty, "\(events)")
        XCTAssertFalse(queried.isEmpty, "\(events)")
        for line in indexed + queried {
            XCTAssertTrue(line.contains("duration"), line)
            XCTAssertFalse(line.contains("green") || line.contains("Fixture"), "no question and no title: \(line)")
        }
    }

    // MARK: - Input longer than the contextual model reads

    func testALongInputSplitsAtASentenceAndKeepsEveryWord() throws {
        let text = "The blue cover goes on first. Keep the spare in the lid. Turn the dial left. Wait ten seconds."
        let (a, b) = try XCTUnwrap(ContextualInput.halves(of: text))
        XCTAssertTrue(a.hasSuffix(".") , a)
        XCTAssertEqual((a + " " + b).split(separator: " "), text.split(separator: " "))
        let words = (0..<40).map { "word\($0)" }.joined(separator: " ")
        let (c, d) = try XCTUnwrap(ContextualInput.halves(of: words), "no sentence end: split at a space")
        XCTAssertEqual((c + " " + d).split(separator: " ").count, 40)
        XCTAssertNil(ContextualInput.halves(of: "single"))
    }
}
