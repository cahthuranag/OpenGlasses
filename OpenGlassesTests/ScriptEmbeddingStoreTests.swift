import XCTest
@testable import OpenGlasses

/// Embedding by script in the store (Plan JY P1): each document is embedded with its own script's
/// model or none, never another script's; a document with no model yet is stored without vectors
/// and healed when one arrives; a vault keeps one index per script; and a mixed library embeds
/// the question once per model. Invented sentences and invented models only — the simulator has
/// none of Apple's script assets, so every model here is a fake injected through the seams.
@MainActor
final class ScriptEmbeddingStoreTests: XCTestCase {

    /// A deterministic bag of character pairs, so it reads every script; it records what it
    /// embedded. `seed` keeps two fakes' vectors apart for the same text.
    final class FakeModel: EmbeddingBackend {
        let modelId: String
        let dimension = 64
        private let seed: UInt32
        private(set) var texts: [String] = []
        init(_ modelId: String, seed: UInt32) { self.modelId = modelId; self.seed = seed }
        func embed(_ text: String) -> [Float]? {
            texts.append(text)
            let letters = Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
            guard letters.count > 1 else { return nil }
            var v = [Float](repeating: 0, count: dimension)
            for i in 0..<(letters.count - 1) {
                var h: UInt32 = 2_166_136_261 ^ seed
                for byte in String([letters[i], letters[i + 1]]).utf8 { h = (h ^ UInt32(byte)) &* 16_777_619 }
                v[Int(h % UInt32(dimension))] += 1
            }
            return v
        }
    }

    final class NoBackgroundTime: BackgroundTaskRunning {
        func begin(name: String) -> Int { 1 }
        func end(_ token: Int) {}
    }

    private var tempRoot: URL!
    private let vaultId = "script_fixture"
    private var vault: String { DocumentStore.vaultNamespace(vaultId) }
    private let latin = FakeModel("nl-contextual.fake-latn", seed: 1)
    private let cyrillic = FakeModel("nl-contextual.fake-cyrl", seed: 2)
    private let cjk = FakeModel("nl-contextual.fake-cjk", seed: 3)
    /// The script models "on the phone"; a test makes one arrive by adding it.
    private var installed: [EmbeddingScript: Embedder] = [:]
    private var providerCalls = 0

    private let english = "Replace the air filter every three months. The compressor discharge temperature must stay below one hundred and twenty degrees."
    private let ukrainian = "Повітряний фільтр слід замінювати кожні три місяці. Температура нагнітання компресора не повинна перевищувати ста двадцяти градусів."
    private let chinese = "空气过滤器每三个月更换一次。压缩机的排气温度不得超过一百二十度，否则设备会自动停机保护。"
    private let chineseSecond = "控制面板上的故障代码可以通过按住复位按钮五秒钟来清除，然后重新启动设备。"

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptEmbeddingStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        installed = [:]
        providerCalls = 0
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func makeStore() -> DocumentStore {
        let store = DocumentStore(directory: tempRoot, embedder: Embedder(backend: latin))
        store.fieldAssistEmbedder = Embedder(backend: latin)
        store.scriptEmbedderProvider = { [unowned self] script in
            self.providerCalls += 1
            return self.installed[script]
        }
        return store
    }

    private func install(_ script: EmbeddingScript, _ model: FakeModel) {
        installed[script] = Embedder(script: script, backend: model)
    }

    private func tag(_ model: FakeModel) -> String { "\(model.modelId)#\(model.dimension)" }

    private func ingest(_ store: DocumentStore, _ name: String, _ text: String, namespace: String? = nil) async -> String {
        let ref = await store.ingest(name: name, text: text, sourceType: "vault_document", namespace: namespace ?? vault)
        return try! XCTUnwrap(ref).id
    }

    private var manifest: VaultManifest {
        VaultManifest(id: vaultId, name: "Script Fixture", version: "1.0.0", files: ["safety.md"], proceduresDir: nil,
                      documentsDir: "documents",
                      documents: [VaultDocument(file: "a.txt", title: "Invented Manual A"),
                                  VaultDocument(file: "b.txt", title: "Invented Manual B")],
                      gating: .init(iap: "enterprise"), promptRules: ["Never fabricate."])
    }

    private func monitor() -> VaultIndexingMonitor {
        let monitor = VaultIndexingMonitor()
        monitor.backgroundTasks = NoBackgroundTime()
        return monitor
    }

    // MARK: - Model by script

    func testEachDocumentIsEmbeddedWithItsOwnScriptsModel() async {
        install(.cyrillic, cyrillic)
        install(.cjk, cjk)
        let store = makeStore()
        let englishId = await ingest(store, "Invented Manual A", english)
        let ukrainianId = await ingest(store, "Інструкція", ukrainian)
        let chineseId = await ingest(store, "手册", chinese)

        XCTAssertEqual(store.embeddingScript(documentId: englishId), .latin)
        XCTAssertEqual(store.embeddingScript(documentId: ukrainianId), .cyrillic)
        XCTAssertEqual(store.embeddingScript(documentId: chineseId), .cjk)
        XCTAssertEqual(store.servingVersionTag(namespace: vault, script: .latin), tag(latin))
        XCTAssertEqual(store.servingVersionTag(namespace: vault, script: .cyrillic), tag(cyrillic))
        XCTAssertEqual(store.servingVersionTag(namespace: vault, script: .cjk), tag(cjk))
        XCTAssertEqual(store.servingVersionTag(namespace: vault), tag(latin), "the unscoped tag is the Latin index's")
        for id in [englishId, ukrainianId, chineseId] {
            let diagnostic = try! XCTUnwrap(store.languageDiagnostic(documentId: id))
            XCTAssertEqual(diagnostic.chunksWithVectors, diagnostic.chunks)
            XCTAssertFalse(diagnostic.searchesByWords)
        }
        XCTAssertFalse(latin.texts.contains { $0.contains("Повітряний") || $0.contains("空气") },
                       "the Latin model never embedded another script's passage")
        XCTAssertTrue(cyrillic.texts.allSatisfy { $0.contains("Повітряний") || $0.contains("Температура") })
    }

    // MARK: - Never another script's model

    func testWithoutItsModelADocumentIsStoredByItsWordsAlone() async throws {
        let store = makeStore()
        let chineseId = await ingest(store, "手册", chinese)
        let globalId = await ingest(store, "笔记", chineseSecond, namespace: "global")

        XCTAssertTrue(latin.texts.isEmpty, "no model of its own is not a reason to use another script's")
        for id in [chineseId, globalId] {
            let diagnostic = try XCTUnwrap(store.languageDiagnostic(documentId: id))
            XCTAssertEqual(diagnostic.chunksWithVectors, 0)
            XCTAssertEqual(diagnostic.modelClass, "none")
            XCTAssertTrue(diagnostic.searchesByWords)
        }
        XCTAssertNil(store.servingVersionTag(namespace: vault, script: .cjk))

        // The semantic route has nothing to compare it with; the words still reach it, flagged
        // for the gate.
        XCTAssertTrue(store.query("压缩机排气温度", namespace: vault).isEmpty)
        let lexical = store.passages(sharingTermsWith: "压缩机的排气温度是多少？", namespace: vault)
        XCTAssertEqual(lexical.first?.documentId, chineseId)
        XCTAssertEqual(lexical.first?.vectorPending, true)
        XCTAssertEqual(lexical.first?.similarity, 0)
        let globalLexical = store.passages(sharingTermsWith: "故障代码怎么清除？", namespace: "global")
        XCTAssertEqual(globalLexical.first?.vectorPending, true)
        XCTAssertTrue(store.query("故障代码", namespace: "global").isEmpty)
        XCTAssertFalse(latin.texts.contains(chinese) || latin.texts.contains(chineseSecond))
    }

    func testAChunkAnOlderBuildEmbeddedWithTheLatinModelIsNotComparedWithIt() async {
        let store = makeStore()
        _ = await ingest(store, "手册", chinese)
        let vectors = DocumentStore.QueryVectors(text: "压缩机", store: store)
        XCTAssertNotNil(vectors.vector(forVersionTag: tag(latin), script: .latin))
        XCTAssertNil(vectors.vector(forVersionTag: tag(latin), script: .cjk),
                     "a Chinese chunk stamped by the Latin model reads as having no vector")
        XCTAssertNil(store.embedderProducing(versionTag: tag(latin), script: .cjk))
    }

    // MARK: - Self-heal when the model arrives

    func testAVaultManualIsReindexedWhenItsScriptsModelArrives() async throws {
        let saved = VaultEmbeddingUpgrade.target
        VaultEmbeddingUpgrade.target = { [latin] in Embedder(backend: latin) }
        defer { VaultEmbeddingUpgrade.target = saved }
        let store = makeStore()
        let englishId = await ingest(store, "Invented Manual A", english)
        let chineseId = await ingest(store, "手册", chinese)
        let latinOutcomes = await VaultEmbeddingUpgrade.run(store: store, manifests: [manifest], monitor: monitor())
        XCTAssertEqual(latinOutcomes[vaultId], .current)
        XCTAssertNil(latinOutcomes[VaultEmbeddingUpgrade.outcomeKey(vaultId: vaultId, script: .cjk)],
                     "no model on the phone: nothing to re-index onto")

        // The CJK asset lands.
        install(.cjk, cjk)
        let outcomes = await VaultEmbeddingUpgrade.run(store: store, manifests: [manifest], monitor: monitor())
        XCTAssertEqual(outcomes[vaultId], .current, "the Latin index is left as it is")
        guard case .completed = outcomes[VaultEmbeddingUpgrade.outcomeKey(vaultId: vaultId, script: .cjk)] else {
            return XCTFail("\(outcomes)")
        }
        let healed = try XCTUnwrap(store.languageDiagnostic(documentId: chineseId))
        XCTAssertEqual(healed.chunksWithVectors, healed.chunks)
        XCTAssertFalse(healed.searchesByWords)
        XCTAssertEqual(store.servingVersionTag(namespace: vault, script: .cjk), tag(cjk))
        XCTAssertEqual(store.servingVersionTag(namespace: vault, script: .latin), tag(latin))
        XCTAssertEqual(store.query("压缩机的排气温度", limit: 4, namespace: vault).first?.documentId, chineseId)
        XCTAssertEqual(store.passages(sharingTermsWith: "压缩机的排气温度是多少？", namespace: vault).first?.vectorPending, false)
        XCTAssertEqual(store.languageDiagnostic(documentId: englishId)?.chunksWithVectors,
                       store.languageDiagnostic(documentId: englishId)?.chunks)

        let again = await VaultEmbeddingUpgrade.run(store: store, manifests: [manifest], monitor: monitor())
        XCTAssertEqual(again[VaultEmbeddingUpgrade.outcomeKey(vaultId: vaultId, script: .cjk)], .current)
    }

    func testTheIndexThatAnswersIsUntouchedUntilTheNewOneIsComplete() async throws {
        install(.cjk, cjk)
        let store = makeStore()
        let chineseId = await ingest(store, "手册", chinese)
        _ = await ingest(store, "手册二", chineseSecond)
        // A newer CJK model: the re-index stops after one chunk.
        let newer = FakeModel("nl-contextual.fake-cjk2", seed: 9)
        var budget = 1
        let outcome = await store.upgradeVaultEmbeddings(namespace: vault, script: .cjk,
                                                         to: Embedder(script: .cjk, backend: newer),
                                                         shouldContinue: { defer { budget -= 1 }; return budget > 0 })
        guard case .interrupted = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(store.servingVersionTag(namespace: vault, script: .cjk), tag(cjk), "still served by the old index")
        XCTAssertEqual(store.query("压缩机的排气温度", limit: 1, namespace: vault).first?.documentId, chineseId)
        // A Latin target is refused for a CJK index.
        let refused = await store.upgradeVaultEmbeddings(namespace: vault, script: .cjk, to: Embedder(backend: latin))
        XCTAssertEqual(refused, .current)
        XCTAssertFalse(latin.texts.contains(chinese))
    }

    func testADocumentsLibraryEntryHealsOnTheNextSearchOnceTheModelIsHere() async throws {
        let store = makeStore()
        let id = await ingest(store, "笔记", chinese, namespace: "global")
        XCTAssertEqual(store.outdatedChunkCount, 0, "nothing to heal with yet")
        install(.cjk, cjk)
        XCTAssertGreaterThan(store.outdatedChunkCount, 0)
        XCTAssertEqual(store.query("压缩机的排气温度", namespace: "global").first?.documentId, id)
        let diagnostic = try XCTUnwrap(store.languageDiagnostic(documentId: id))
        XCTAssertEqual(diagnostic.chunksWithVectors, diagnostic.chunks)
        XCTAssertEqual(store.outdatedChunkCount, 0)
    }

    func testReindexingTheDocumentsLibraryUsesEachScriptsOwnModel() async {
        let store = makeStore()
        let id = await ingest(store, "笔记", chinese, namespace: "global")
        install(.cjk, cjk)
        let done = await store.reindexOutdated()
        XCTAssertEqual(done, store.chunkCount(documentId: id))
        XCTAssertTrue(cjk.texts.contains { $0.contains("压缩机") })
        XCTAssertFalse(latin.texts.contains { $0.contains("压缩机") })
    }

    // MARK: - One index per (namespace, script)

    func testAMixedLibraryKeepsOneModelPerScript() async {
        install(.cjk, cjk)
        let store = makeStore()
        _ = await ingest(store, "Invented Manual A", english)
        _ = await ingest(store, "手册", chinese)
        XCTAssertEqual(store.embeddingScripts(namespace: vault), [.latin, .cjk])
        // A second Chinese manual joins the CJK index, an English one the Latin index.
        XCTAssertEqual(store.ingestEmbedder(namespace: vault, script: .cjk)?.version.tag, tag(cjk))
        XCTAssertEqual(store.ingestEmbedder(namespace: vault, script: .latin)?.version.tag, tag(latin))
        XCTAssertNil(store.ingestEmbedder(namespace: vault, script: .cyrillic), "no Cyrillic model: words only")
        XCTAssertEqual(store.upgradeProgress(namespace: vault, script: .cjk, targetTag: tag(cjk)).total,
                       store.documentIds(namespace: vault, script: .cjk).reduce(0) { $0 + store.chunkCount(documentId: $1) })
    }

    func testAMixedLibraryEmbedsTheQuestionOncePerModel() async {
        install(.cyrillic, cyrillic)
        install(.cjk, cjk)
        let store = makeStore()
        _ = await ingest(store, "Invented Manual A", english)
        _ = await ingest(store, "Інструкція", ukrainian)
        _ = await ingest(store, "手册", chinese)
        let question = "compressor discharge temperature"
        let before = (latin.texts.count, cyrillic.texts.count, cjk.texts.count)
        let vectors = DocumentStore.QueryVectors(text: question, store: store)
        for (script, model) in [(EmbeddingScript.latin, latin), (.cyrillic, cyrillic), (.cjk, cjk)] {
            XCTAssertNotNil(vectors.vector(forVersionTag: tag(model), script: script))
            XCTAssertNotNil(vectors.vector(forVersionTag: tag(model), script: script), "asked twice, embedded once")
        }
        XCTAssertEqual(vectors.embeddedModelCount, 3)
        XCTAssertEqual(latin.texts.count - before.0, 1)
        XCTAssertEqual(cyrillic.texts.count - before.1, 1)
        XCTAssertEqual(cjk.texts.count - before.2, 1)
        XCTAssertNotNil(store.embedderProducing(versionTag: tag(cjk)), "the unscoped lookup knows the script models")

        // One search over the library: each model embeds the question once, whatever the rows.
        let counts = (latin.texts.count, cyrillic.texts.count, cjk.texts.count)
        _ = store.query("压缩机的排气温度", limit: 8, namespace: vault)
        XCTAssertEqual(latin.texts.count - counts.0, 1)
        XCTAssertEqual(cyrillic.texts.count - counts.1, 1)
        XCTAssertEqual(cjk.texts.count - counts.2, 1)
    }

    // MARK: - Latin, unchanged

    func testALatinLibraryNeverConsultsAScriptModel() async {
        let saved = VaultEmbeddingUpgrade.target
        VaultEmbeddingUpgrade.target = { [latin] in Embedder(backend: latin) }
        defer { VaultEmbeddingUpgrade.target = saved }
        let store = makeStore()
        let id = await ingest(store, "Invented Manual A", english)
        _ = await ingest(store, "Invented Manual B", "Wipe the filter rack with a dry cloth and never use water on the rack.",
                         namespace: "global")
        _ = store.query("air filter months", namespace: vault)
        _ = store.passages(sharingTermsWith: "compressor discharge temperature", namespace: vault)
        _ = store.query("filter rack cloth", namespace: "global")
        _ = await VaultEmbeddingUpgrade.run(store: store, manifests: [manifest], monitor: monitor())
        XCTAssertEqual(providerCalls, 0, "a Latin document never asks for a script model")
        XCTAssertEqual(store.servingVersionTag(namespace: vault), tag(latin))
        XCTAssertEqual(store.servingModelId(namespace: vault), latin.modelId)
        XCTAssertEqual(store.passages(sharingTermsWith: "compressor discharge temperature", namespace: vault).first?.vectorPending, false)
        XCTAssertEqual(store.languageDiagnostic(documentId: id)?.searchesByWords, false)
        XCTAssertEqual(DocumentStore.indexDetail(modelId: latin.modelId, script: .latin), "contextual",
                       "a Latin index's log detail is today's")
        XCTAssertEqual(DocumentStore.indexDetail(modelId: nil, script: .cjk), "none.cjk")
    }

    // MARK: - Indexing waits briefly for the model

    func testIndexingAManualAsksForItsModelAndWaitsOnlyBriefly() async throws {
        let assets = ScriptModelAssets()
        assets.waitLimit = .milliseconds(300)
        var arrived: [EmbeddingScript] = []
        var release: CheckedContinuation<Void, Never>?
        assets.isReady = { [unowned self] in self.installed[$0] != nil }
        assets.download = { @MainActor _ in
            await withCheckedContinuation { release = $0 }
            return true
        }
        assets.onArrival = { arrived.append($0) }
        let store = makeStore()
        store.scriptModelRequest = { await assets.requestAndWait($0) }

        let started = ContinuousClock.now
        let id = await ingest(store, "手册", chinese)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "a download is never a prerequisite")
        XCTAssertTrue(assets.isDownloading(.cjk))
        XCTAssertEqual(store.languageDiagnostic(documentId: id)?.searchesByWords, true)

        // The download finishes later: the arrival is announced, for the re-index.
        install(.cjk, cjk)
        release?.resume()
        for _ in 0..<50 where arrived.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(arrived, [.cjk])
        XCTAssertFalse(assets.isDownloading(.cjk))
    }

    func testAModelThatLandsWithinTheWaitIsUsedAtOnce() async throws {
        let assets = ScriptModelAssets()
        assets.waitLimit = .seconds(10)
        assets.isReady = { [unowned self] in self.installed[$0] != nil }
        assets.download = { @MainActor [unowned self] script in
            try? await Task.sleep(for: .milliseconds(100))
            self.install(script, self.cjk)
            return true
        }
        let store = makeStore()
        store.scriptModelRequest = { await assets.requestAndWait($0) }
        let id = await ingest(store, "手册", chinese)
        let diagnostic = try XCTUnwrap(store.languageDiagnostic(documentId: id))
        XCTAssertEqual(diagnostic.chunksWithVectors, diagnostic.chunks)
        XCTAssertEqual(store.servingVersionTag(namespace: vault, script: .cjk), tag(cjk))
    }

    func testTheDocumentsLibraryNeverAsksForAModel() async {
        var asked = 0
        let store = makeStore()
        store.scriptModelRequest = { _ in asked += 1 }
        _ = await ingest(store, "笔记", chinese, namespace: "global")
        _ = await ingest(store, "Invented Manual A", english)
        XCTAssertEqual(asked, 0, "neither a document nor a Latin manual asks")
        _ = await ingest(store, "手册", chinese)
        XCTAssertEqual(asked, 1, "a Chinese manual asks once")
    }
}
