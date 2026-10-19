import XCTest
@testable import OpenGlasses

/// Plan HV P0 — the validator's site rules over a vault folder: references, uniqueness within a
/// file and across files, cross-vault references, the render warning, and a vault without
/// `sites` validating exactly as before.
final class SiteSystemValidatorTests: XCTestCase {

    private typealias F = SiteSystemFixtures
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteSystemValidatorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func validate(_ sites: [String: [String: Any]], listed: [String]? = nil) throws -> VaultValidator.Result {
        VaultValidator.validate(directory: try F.copyVault(to: root, sites: sites, listed: listed))
    }

    private func assertIssue(_ result: VaultValidator.Result, _ needle: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(result.issues.contains { $0.contains(needle) }, "expected '\(needle)' in \(result.issues)",
                      file: file, line: line)
    }

    // MARK: - The fixture vault

    func testTheFixtureVaultValidates() {
        let result = VaultValidator.validate(directory: F.vaultDirectory)
        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.manifest?.sites, [F.siteFile])
    }

    // MARK: - Models

    func testAUnitModelNotInTheIndexRefusesAndCoveredFalseAdmitsIt() throws {
        let typo = F.document(id: "typo", units: [F.unit("a", model: "NV80F06O")])
        assertIssue(try validate(["sites/typo.json": typo]), "model 'NV80F06O' is not a model this vault has a section for")
        let honest = F.document(id: "honest", units: [F.unit("a", model: "NT9C", covered: false)])
        XCTAssertEqual(try validate(["sites/honest.json": honest]).issues, [])
        // An alias spelling the heading lists resolves.
        let alias = F.document(id: "alias", units: [F.unit("a", model: "NV80-F060")])
        XCTAssertEqual(try validate(["sites/alias.json": alias]).issues, [])
    }

    func testAModelOnlyAnotherVaultCoversIsRefused() throws {
        // No unit references across vaults (decided 2026-10-20): a model this vault has no
        // section for is refused even if another installed vault has one.
        let other = F.document(id: "other", units: [F.unit("a", model: "QX5500ZT20")])
        assertIssue(try validate(["sites/other.json": other]), "is not a model this vault has a section for")
    }

    // MARK: - Uniqueness

    func testDuplicateUnitIdsAndSerialsWithinAFileRefuse() throws {
        let doubled = F.document(id: "d", units: [F.unit("a", model: "NV80F060", serial: "X-1"),
                                                  F.unit("a", model: "NV36HP2", serial: "x1")])
        let result = try validate(["sites/d.json": doubled])
        assertIssue(result, "unit id 'a' is used twice")
        assertIssue(result, "serial 'x1' is given to two units")
    }

    func testSerialsLocationsAndUnitIdentifiersRepeatedAcrossFilesRefuse() throws {
        let location = [["system": "example-fsm", "id": "loc-1"]]
        let ref = [["system": "example-fsm", "id": "asset-1"]]
        let one = F.document(id: "one", units: [F.unit("a", model: "NV80F060", serial: "AF80-1", externalIDs: ref)],
                             locations: location)
        let two = F.document(id: "two", units: [F.unit("a", model: "NV80F060", serial: "af80 1", externalIDs: ref)],
                             locations: location)
        let result = try validate(["sites/one.json": one, "sites/two.json": two])
        assertIssue(result, "serial 'af80 1' is also listed in sites/one.json")
        assertIssue(result, "location example-fsm 'loc-1' is also given to sites/one.json")
        assertIssue(result, "unit identifier example-fsm 'asset-1' is also given to a unit in sites/one.json")
    }

    func testTheSameIdInAnotherSystemIsNotARepeat() throws {
        let one = F.document(id: "one", units: [F.unit("a", model: "NV80F060")],
                             locations: [["system": "fsm-a", "id": "loc-1"]])
        let two = F.document(id: "two", units: [F.unit("a", model: "NV80F060")],
                             locations: [["system": "fsm-b", "id": "loc-1"]])
        XCTAssertEqual(try validate(["sites/one.json": one, "sites/two.json": two]).issues, [])
    }

    func testIntegrationIdsShareTheUnitNamespace() throws {
        let clash = F.document(id: "c", units: [F.unit("a", model: "NV80F060")],
                               extra: ["integrations": [["id": "a", "name": "BMS", "kind": "bms", "units": ["a"]]]])
        assertIssue(try validate(["sites/c.json": clash]), "units and integrations share one set of ids")
    }

    // MARK: - References

    func testDanglingReferencesRefuse() throws {
        let units = [F.unit("a", model: "NV80F060"), F.unit("b", model: "NV36HP2")]
        let document = F.document(id: "r", units: units, extra: [
            "connections": [["from": "a", "to": "ghost", "kind": "power"], ["from": "a", "to": "a", "kind": "power"]],
            "controls": [["controller": "ghost", "commands": ["b", "nobody"], "mode": "conventional"]],
            "settings": [["unit": "ghost", "name": "n", "value": "v"]],
            "interaction_faults": [["seen_on": "ghost", "link": "elsewhere", "text": "t"]],
            "integrations": [["id": "bms", "name": "BMS", "kind": "bms", "units": ["ghost"]]],
        ])
        let result = try validate(["sites/r.json": document])
        assertIssue(result, "connections[0].to names 'ghost'")
        assertIssue(result, "connections[1] connects 'a' to itself")
        assertIssue(result, "controls[0].controller names 'ghost'")
        assertIssue(result, "controls[0].commands names 'nobody'")
        assertIssue(result, "settings[0].unit names 'ghost'")
        assertIssue(result, "interaction_faults[0].seen_on names 'ghost'")
        assertIssue(result, "interaction_faults[0].link names 'elsewhere'")
        assertIssue(result, "integrations[0].units names 'ghost'")
    }

    func testAConnectionAndAFaultMayNameAnIntegration() throws {
        let document = F.document(id: "ok", units: [F.unit("a", model: "NV80F060")], extra: [
            "integrations": [["id": "bms", "name": "Building management", "kind": "bms", "units": ["a"],
                              "direction": "both"]],
            "connections": [["from": "a", "to": "bms", "kind": "data", "protocol": "BACnet/IP"]],
            "interaction_faults": [["seen_on": "a", "link": "bms", "text": "Schedule override from the BMS."],
                                   ["seen_on": "a", "link": "data", "text": "Lost points after a switch change."]],
        ])
        XCTAssertEqual(try validate(["sites/ok.json": document]).issues, [])
    }

    // MARK: - Paths

    func testListedPathsAreSafeListedOnceAndPresent() throws {
        let document = F.document(id: "p", units: [F.unit("a", model: "NV80F060")])
        let result = try validate(["sites/p.json": document],
                                  listed: ["sites/p.json", "sites/p.json", "../p.json", "sites/sub/p.json",
                                           "notes.md", "sites/missing.json"])
        assertIssue(result, "site document listed twice: sites/p.json")
        assertIssue(result, "directly inside sites/: ../p.json")
        assertIssue(result, "directly inside sites/: sites/sub/p.json")
        assertIssue(result, "directly inside sites/: notes.md")
        assertIssue(result, "listed site document missing: sites/missing.json")
    }

    func testMoreThanAHundredSiteDocumentsRefuse() throws {
        let listed = (0...100).map { "sites/s\($0).json" }
        let result = try validate([:], listed: listed)
        assertIssue(result, "a vault may carry at most 100")
    }

    // MARK: - The render bound

    func testAnOverLongRenderWarnsAndStillInstalls() throws {
        let units = (0..<12).map { F.unit("u\($0)", model: "NV80F060", serial: "S-\($0)", label: "unit number \($0)") }
        let connections = (1..<12).map { ["from": "u0", "to": "u\($0)", "kind": "communication",
                                          "detail": "a long run through the plant room and the riser"] as [String: Any] }
        let faults = (1..<8).map { ["seen_on": "u\($0)", "text": "Fault number \($0) comes from the link."] as [String: Any] }
        let long = F.document(id: "long", units: units, extra: ["connections": connections, "interaction_faults": faults])
        let result = try validate(["sites/long.json": long])
        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.warnings.count, 1)
        let warning = try XCTUnwrap(result.warnings.first)
        XCTAssertTrue(warning.contains("held to 1600 characters"), warning)
        XCTAssertTrue(warning.contains("interaction faults"), "names what clips: \(warning)")
    }

    // MARK: - A vault without sites

    func testAVaultWithNoSitesValidatesExactlyAsBefore() throws {
        let dir = try F.copyVault(to: root, withoutSites: true)
        let without = VaultValidator.validate(directory: dir)
        XCTAssertEqual(without.issues, [])
        XCTAssertEqual(without.warnings, [])
        XCTAssertNil(without.manifest?.sites)
        // A stray sites/ folder the manifest does not list is not read at all.
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sites"), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("sites/stray.json"))
        let stray = VaultValidator.validate(directory: dir)
        XCTAssertEqual(stray.issues, without.issues)
        XCTAssertEqual(stray.warnings, without.warnings)
    }

    func testAManifestWithoutSitesEncodesByteForByteAsBefore() throws {
        let legacy = Data(#"{"files":["a.md"],"id":"v","name":"V","prompt_rules":["Never fabricate.","Cite."],"version":"1"}"#.utf8)
        let manifest = try JSONDecoder().decode(VaultManifest.self, from: legacy)
        XCTAssertNil(manifest.sites)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = String(decoding: try encoder.encode(manifest), as: UTF8.self)
        XCTAssertFalse(encoded.contains("sites"), encoded)
        // And the same manifest built in code, as every older caller builds it, is equal.
        let built = VaultManifest(id: "v", name: "V", version: "1", files: ["a.md"], promptRules: ["Never fabricate.", "Cite."],
                                  sourceAttributionFormat: nil)
        XCTAssertEqual(try encoder.encode(built), try encoder.encode(manifest))
    }

    func testAMalformedSitesListRefusesTheManifest() throws {
        let dir = try F.copyVault(to: root)
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appendingPathComponent("manifest.json"))) as? [String: Any])
        manifest["sites"] = "sites/hillside-house.json"
        try F.data(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        XCTAssertFalse(VaultValidator.validate(directory: dir).isValid)
    }
}
