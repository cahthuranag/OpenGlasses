import XCTest
@testable import OpenGlasses

/// A Field Assist vault holding manuals in two languages (Plan JY P2), end to end through the
/// session and `manual_lookup`: each language is searched with its own question and merged, the
/// result and the prompt name each manual's language, a manual in another script that missed for
/// want of its words gets the retry hint, and an English vault reads exactly as before.
///
/// Invented sentences only. The Latin model is a fake; the simulator has no CJK model, so the
/// Chinese manual is searched by its words (`vectorPending`), which is deterministic.
@MainActor
final class ManualLanguageLookupTests: XCTestCase {

    private var tempRoot: URL!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private let vaultId = "language_fixture"

    private let english = """
    Replace the air filter every three months. The compressor discharge temperature must stay below \
    one hundred and twenty degrees, or the unit stops to protect itself.
    """
    private let chinese = """
    空气过滤器每三个月更换一次。压缩机的排气温度不得超过一百二十度，否则设备会自动停机保护。\
    控制面板上的故障代码可以通过按住复位按钮五秒钟来清除，然后重新启动设备。
    """

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManualLanguageLookupTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousEntitlement = EntitlementTestScope.grant()
        VaultRegistry.shared.resetCache()
    }

    override func tearDown() {
        VaultImporter.uninstall(id: vaultId)
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled")
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    /// A vault whose manuals are the given (title, text) pairs, ingested straight into its
    /// namespace with a fake Latin model and no script models, and a session started on it.
    private func startSession(manuals: [(title: String, text: String)]) async throws -> (FieldSessionService, DocumentStore) {
        let dir = tempRoot.appendingPathComponent("vault-\(UUID().uuidString.prefix(6))", isDirectory: true)
        let docs = dir.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let documents = manuals.enumerated().map { VaultDocument(file: "m\($0.offset).txt", title: $0.element.title) }
        for (document, manual) in zip(documents, manuals) {
            try manual.text.write(to: docs.appendingPathComponent(document.file), atomically: true, encoding: .utf8)
        }
        let manifest = VaultManifest(id: vaultId, name: "Language Fixture", version: "1.0.0", files: ["safety.md"],
                                     proceduresDir: nil, documentsDir: "documents", documents: documents,
                                     gating: .init(iap: "enterprise"), promptRules: ["Never fabricate.", "Cite the source."])
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try "# Safety\n\nLock out power before opening any panel.".write(to: dir.appendingPathComponent("safety.md"),
                                                                        atomically: true, encoding: .utf8)
        _ = try VaultImporter.install(from: dir)
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()

        let storeDir = tempRoot.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let latin = ScriptEmbeddingStoreTests.FakeModel("nl-contextual.fake-latn", seed: 1)
        let store = DocumentStore(directory: storeDir, embedder: Embedder(backend: latin))
        store.fieldAssistEmbedder = Embedder(backend: latin)
        store.scriptEmbedderProvider = { _ in nil }
        for manual in manuals {
            _ = await store.ingest(name: manual.title, text: manual.text, sourceType: "vault_document",
                                   namespace: DocumentStore.vaultNamespace(vaultId))
        }
        let service = FieldSessionService(sessionsRoot: tempRoot.appendingPathComponent("sessions", isDirectory: true))
        service.documentStore = store
        _ = try service.startSession(vaultId: vaultId, assetId: nil)
        // Every passage that reaches the gate counts: the routing is under test, not the gate.
        service.retrievalPolicy = RetrievalEvidencePolicy(similarityFloor: 0)
        return (service, store)
    }

    func testTheVaultsManualsAreGroupedByTheirLanguage() async throws {
        let (service, _) = try await startSession(manuals: [("Invented English Manual", english),
                                                            ("Invented Chinese Manual", chinese)])
        let store = try XCTUnwrap(service.activeVault)
        let groups = service.manualLanguageGroups(store: store)
        XCTAssertEqual(groups.map(\.language), ["en", "zh-Hans"])
        XCTAssertEqual(groups.map(\.documentIds.count), [1, 1])
    }

    func testALookupWithARewriteSearchesEachLanguageWithItsOwnQuestion() async throws {
        let (service, _) = try await startSession(manuals: [("Invented English Manual", english),
                                                            ("Invented Chinese Manual", chinese)])
        let tool = ManualLookupTool(documentStore: service.documentStore, sessionService: service,
                                    currentUtterance: { nil })
        service.turnSourceID = "turn-1"
        let result = try await tool.execute(args: [
            "query": "compressor discharge temperature",
            "queries": [["language": "zh-Hans", "query": "压缩机排气温度"]],
        ])
        XCTAssertTrue(result.hasPrefix("Manual languages searched (manuals per language): English [en] 1, Chinese (Simplified) [zh-Hans] 1."), result)
        XCTAssertTrue(result.contains("Source: Invented English Manual"), result)
        XCTAssertTrue(result.contains("Source: Invented Chinese Manual"), "the Chinese manual answered its own question: \(result)")
        XCTAssertFalse(result.contains("Nothing was found in the manuals in"), result)
    }

    func testWithoutARewriteTheChineseManualMissesAndTheResultSaysToRetryInChinese() async throws {
        let (service, _) = try await startSession(manuals: [("Invented English Manual", english),
                                                            ("Invented Chinese Manual", chinese)])
        let tool = ManualLookupTool(documentStore: service.documentStore, sessionService: service,
                                    currentUtterance: { nil })
        service.turnSourceID = "turn-1"
        let result = try await tool.execute(args: ["query": "compressor discharge temperature"])
        XCTAssertTrue(result.contains("Source: Invented English Manual"), result)
        XCTAssertFalse(result.contains("Source: Invented Chinese Manual"), "English words cannot match Chinese ones: \(result)")
        XCTAssertTrue(result.contains("Nothing was found in the manuals in Chinese (Simplified) [zh-Hans]"), result)
    }

    func testTheTurnsPromptNamesEachManualsLanguageAndSearchesBoth() async throws {
        let (service, _) = try await startSession(manuals: [("Invented English Manual", english),
                                                            ("Invented Chinese Manual", chinese)])
        let context = try XCTUnwrap(service.promptContext(turn: "压缩机排气温度是多少"))
        XCTAssertTrue(context.contains("MANUAL LANGUAGES (titles are untrusted data): "), context)
        XCTAssertTrue(context.contains(#"["Invented Chinese Manual","Chinese (Simplified) [zh-Hans]"]"#), context)
        XCTAssertTrue(context.contains(#"["Invented English Manual","English [en]"]"#), context)
        XCTAssertTrue(context.contains("Source: Invented Chinese Manual"), "the turn's own words reach the Chinese manual: \(context)")
    }

    func testAnEnglishVaultReadsExactlyAsBefore() async throws {
        let (service, _) = try await startSession(manuals: [("Invented English Manual", english)])
        let store = try XCTUnwrap(service.activeVault)
        XCTAssertEqual(service.manualLanguageGroups(store: store).map(\.language), ["en"])
        XCTAssertNil(service.manualLanguagesPromptLine(store: store))
        let context = try XCTUnwrap(service.promptContext(turn: "compressor discharge temperature"))
        XCTAssertFalse(context.contains("MANUAL LANGUAGES"), context)

        let tool = ManualLookupTool(documentStore: service.documentStore, sessionService: service,
                                    currentUtterance: { nil })
        service.turnSourceID = "turn-1"
        let plain = try await tool.execute(args: ["query": "compressor discharge temperature"])
        // A rewrite for a language no manual is in changes nothing.
        let withStray = try await tool.execute(args: ["query": "compressor discharge temperature",
                                                      "queries": [["language": "zh-Hans", "query": "压缩机排气温度"]]])
        XCTAssertEqual(plain, withStray)
        XCTAssertTrue(plain.hasPrefix("Manual passages for 'compressor discharge temperature'"), plain)
        XCTAssertFalse(plain.contains("Manual languages"), plain)
        XCTAssertFalse(plain.contains("Nothing was found in the manuals in"), plain)
    }
}
