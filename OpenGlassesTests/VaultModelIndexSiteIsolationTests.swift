import XCTest
@testable import OpenGlasses

/// Plan HV P0 — site documents are neither core nor reference: installing them leaves the model
/// index, the core prompt and the core budget's accounting exactly as they were, so a vault with
/// forty documented sites spends nothing on the thirty-nine the technician is not at.
@MainActor
final class VaultModelIndexSiteIsolationTests: XCTestCase {

    private typealias F = SiteSystemFixtures
    private var root: URL!
    private let withId = "site_isolation_with"
    private let withoutId = "site_isolation_without"

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultModelIndexSiteIsolationTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        VaultImporter.uninstall(id: withId)
        VaultImporter.uninstall(id: withoutId)
        VaultRegistry.shared.reloadUserManifests()
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func store(_ manifest: VaultManifest) -> VaultStore {
        VaultStore(manifest: manifest, bundleRoot: VaultImporter.baselineDirectory(for: manifest.id),
                   overlayRoot: root.appendingPathComponent("overlay-\(manifest.id)", isDirectory: true))
    }

    func testSitesLeaveTheModelIndexTheCorePromptAndTheBudgetUnchanged() throws {
        // A site document written to look like core content, headings and all.
        var object = try F.exampleObject()
        object["notes"] = "## NV99ZZ999 (a heading that must never become a model)"
        let with = try VaultImporter.install(from: F.copyVault(to: root, id: withId, sites: [F.siteFile: object]))
        let without = try VaultImporter.install(from: F.copyVault(to: root, id: withoutId, withoutSites: true))

        let withStore = store(with), withoutStore = store(without)
        XCTAssertEqual(withStore.siteDocuments().count, 1)
        XCTAssertEqual(withStore.readAll().map(\.filename), withoutStore.readAll().map(\.filename))

        let withIndex = VaultModelIndex(store: withStore), withoutIndex = VaultModelIndex(store: withoutStore)
        XCTAssertEqual(withIndex.models.map(\.heading), withoutIndex.models.map(\.heading))
        XCTAssertEqual(withIndex.knownModelTokens, withoutIndex.knownModelTokens)
        XCTAssertFalse(withIndex.knownModelTokens.contains("NV99ZZ999"))
        XCTAssertEqual(withIndex.vaultTokens, withoutIndex.vaultTokens, "nothing in a site file is read as core text")

        // The same core prompt, word for word, but for the vault's own name and id.
        let withPrompt = try XCTUnwrap(VaultPromptBuilder.promptContext(for: withStore))
        let withoutPrompt = try XCTUnwrap(VaultPromptBuilder.promptContext(for: withoutStore))
        XCTAssertEqual(withPrompt, withoutPrompt)
        XCTAssertFalse(withPrompt.contains("Hillside house"))

        // The core budget counts the same characters: no warning either way, and a site file that
        // would push a near-budget core over adds nothing to it.
        let withResult = VaultValidator.validate(directory: root.appendingPathComponent(withId))
        let withoutResult = VaultValidator.validate(directory: root.appendingPathComponent(withoutId))
        XCTAssertEqual(withResult.warnings.filter { $0.contains("core files total") },
                       withoutResult.warnings.filter { $0.contains("core files total") })
    }

    func testANearBudgetCoreIsNotPushedOverBySites() throws {
        let dir = try F.copyVault(to: root, id: withId)
        let filler = String(repeating: "Plain reference text. ", count: (VaultValidator.coreBudgetCharacters - 2_000) / 22)
        let models = try String(contentsOf: dir.appendingPathComponent("models.md"), encoding: .utf8)
        try (models + "\n\n" + filler).write(to: dir.appendingPathComponent("models.md"), atomically: true, encoding: .utf8)
        let result = VaultValidator.validate(directory: dir)
        XCTAssertEqual(result.issues, [])
        XCTAssertFalse(result.warnings.contains { $0.contains("core files total") }, "\(result.warnings)")
    }
}
