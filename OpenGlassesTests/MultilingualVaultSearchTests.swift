import XCTest
@testable import OpenGlasses

/// Plan JY P5a, item 3: `equipment_lookup`'s manual fall-through and the nearest-headings search
/// go through the language groups as `manual_lookup` does. A custom vault of two invented manuals,
/// one English and one Chinese, installed from a temporary folder into a temporary store.
@MainActor
final class MultilingualVaultSearchTests: XCTestCase {

    private var root: URL!
    private var store: DocumentStore!
    private var sessions: FieldSessionService!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var previousEnabled: Any?
    private var previousHipaa = false
    private let vaultId = "jy_p5a_two_languages"

    // Each section runs past a chunk, so each chunk carries its own section.
    private var english: String { englishCore + "\n" + (1...12).map { "Invented note \($0): keep the panel closed while the unit runs." }.joined(separator: " ") }
    private var chinese: String { chineseCore + "\n" + (1...12).map { "虚构说明第\($0)条：机组运行时请保持面板关闭。" }.joined() }

    private let englishCore = """
    INVENTED UNIT SERVICE MANUAL

    1 FAULT CODES
    Fault code ZX9 means the invented unit has a low refrigerant charge. Check the sight glass and the subcooling before adding charge.
    \((1...10).map { "Invented check \($0) on the charge reads the gauge twice before any refrigerant is added." }.joined(separator: " "))

    2 CONDENSER FAN
    When the condenser fan stops, test the fan relay and the run capacitor, then replace the one that fails its test.
    \((1...10).map { "Invented fan step \($0) checks the relay contacts and the capacitor before the motor is replaced." }.joined(separator: " "))
    """

    private let chineseCore = """
    虚构机组维修手册

    1 故障代码
    故障代码ZX9表示虚构机组的制冷剂充注量不足。添加制冷剂之前，请检查视液镜和过冷度。
    \((1...10).map { "虚构检查第\($0)项：添加制冷剂之前请读取压力表两次并记录。" }.joined())

    2 冷凝风扇
    冷凝风扇停止运转时，请检查风扇继电器和运行电容，然后更换未通过测试的部件。
    \((1...10).map { "虚构风扇步骤第\($0)项：更换电机之前检查继电器触点和电容。" }.joined())
    """

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MultilingualVaultSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        previousEnabled = UserDefaults.standard.object(forKey: "fieldAssistEnabled")
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousHipaa = Config.hipaaMode
        Config.hipaaMode = false
        previousEntitlement = EntitlementTestScope.grant(tier: .team)
        VaultRegistry.shared.resetCache()

        let docs = root.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        store = DocumentStore(directory: docs)
        let dir = root.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("documents", isDirectory: true),
                                                withIntermediateDirectories: true)
        let manifest = VaultManifest(id: vaultId, name: "Two languages", version: "1.0.0", files: ["safety.md"],
                                     proceduresDir: nil, documentsDir: "documents",
                                     documents: [VaultDocument(file: "en.txt", title: "Invented Manual", kind: "service_manual"),
                                                 VaultDocument(file: "zh.txt", title: "虚构手册", kind: "service_manual")],
                                     gating: .init(iap: "enterprise"), promptRules: ["Never fabricate.", "Cite the source."])
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try "# Safety\n\n## Lockout\n\nLock out power before opening any panel.".write(
            to: dir.appendingPathComponent("safety.md"), atomically: true, encoding: .utf8)
        try english.write(to: dir.appendingPathComponent("documents/en.txt"), atomically: true, encoding: .utf8)
        try chinese.write(to: dir.appendingPathComponent("documents/zh.txt"), atomically: true, encoding: .utf8)
        let installed = try VaultImporter.install(from: dir)
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        _ = try await VaultImporter.syncDocuments(manifest: installed, into: store)

        sessions = FieldSessionService(sessionsRoot: root.appendingPathComponent("sessions", isDirectory: true))
        sessions.documentStore = store
        _ = try sessions.startSession(vaultId: vaultId, assetId: nil)
    }

    override func tearDown() async throws {
        sessions = nil
        store = nil
        VaultImporter.uninstall(id: vaultId)
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        try? FileManager.default.removeItem(at: root)
        if let previousEnabled { UserDefaults.standard.set(previousEnabled, forKey: "fieldAssistEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled") }
        Config.hipaaMode = previousHipaa
        EntitlementTestScope.restore(previousEntitlement)
        try await super.tearDown()
    }

    func testTheVaultIsTwoLanguageGroups() throws {
        let vault = try XCTUnwrap(sessions.activeVault)
        XCTAssertEqual(sessions.manualLanguageGroups(store: vault).map(\.language), ["en", "zh-Hans"])
    }

    func testTheEquipmentFallThroughSearchesEachLanguageAndKeepsItsThreePassages() throws {
        let vault = try XCTUnwrap(sessions.activeVault)
        sessions.retrievalPolicy = RetrievalEvidencePolicy(similarityFloor: 0)
        let retriever = sessions.makeRetriever(store: vault, documentStore: store)
        let result = sessions.retrieveByLanguage(.init(turn: "ZX9", limit: 3), with: retriever, store: vault, fixedLimit: 3)
        XCTAssertTrue(result.searchedByLanguage, "each language with its own search, merged by rank")
        XCTAssertLessThanOrEqual(result.outcome.passages.count, 3)
        let names = Set(result.outcome.passages.map(\.documentName))
        XCTAssertTrue(names.contains("Invented Manual") && names.contains("虚构手册"),
                      "the code is found in both manuals, each through its own group")
    }

    func testTheNearestHeadingsComeFromEachGroupsOwnQuestion() throws {
        let vault = try XCTUnwrap(sessions.activeVault)
        let rewrites = ManualLanguageSearch.Rewrites([["language": "zh-Hans", "query": "冷凝风扇继电器"]])
        let sections = sessions.closestSections(for: "condenser fan relay 冷凝风扇继电器", store: vault, documentIds: nil,
                                                editionRequest: .newest, asked: "condenser fan relay", rewrites: rewrites)
        XCTAssertFalse(sections.isEmpty)
        let chinese = sections.filter { $0.contains { TextScript.of($0)?.isCJK == true } }
        XCTAssertFalse(chinese.isEmpty, "the Chinese manual's headings, through its rewrite")
        XCTAssertTrue(sections.contains { !chinese.contains($0) }, "and the English manual's, through the question")
        XCTAssertEqual(sections.first.map { chinese.contains($0) }, false,
                       "each group's first heading before any group's second, the earlier group first")
        XCTAssertLessThanOrEqual(sections.count, 3)
    }
}
