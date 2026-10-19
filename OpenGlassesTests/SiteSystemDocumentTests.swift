import XCTest
@testable import OpenGlasses

/// Plan HV P0 — one site document on its own: the example decodes, and every field rule and
/// bound holds. A vault is untrusted input; every refusal here is a test.
final class SiteSystemDocumentTests: XCTestCase {

    private typealias F = SiteSystemFixtures

    private func issues(_ object: [String: Any], path: String? = nil) throws -> [String] {
        let id = object["id"] as? String ?? "x"
        return SiteSystemValidator.check(try F.data(object), path: path ?? "sites/\(id).json",
                                         modelCovered: try F.covered()).issues
    }

    private func assertRefused(_ object: [String: Any], _ needle: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let found = try issues(object)
        XCTAssertTrue(found.contains { $0.contains(needle) }, "expected '\(needle)' in \(found)", file: file, line: line)
    }

    // MARK: - The example

    func testTheExampleDecodesAndPasses() throws {
        let result = SiteSystemValidator.check(try F.exampleData(), path: F.siteFile, modelCovered: try F.covered())
        XCTAssertEqual(result.issues, [])
        let document = try XCTUnwrap(result.document)
        XCTAssertEqual(document.id, "hillside-house")
        XCTAssertEqual(document.units.map(\.id), ["furnace", "heatpump", "tstat"])
        XCTAssertEqual(document.units[2].isCovered, false)
        XCTAssertEqual(document.units[1].externalIDs, [.init(system: "example-fsm", id: "asset-5521")])
        XCTAssertEqual(document.externalLocationIDs, [.init(system: "example-fsm", id: "loc-88412")])
        XCTAssertEqual(document.connections?.map(\.kind), [.fluid, .communication, .communication])
        XCTAssertEqual(document.controls?.first?.mode, .communicating)
        XCTAssertEqual(document.integrations?.first?.kind, .cloudPortal)
        XCTAssertEqual(document.interactionFaults?.first?.seenOn, "heatpump")
        XCTAssertEqual(result.warnings, [], "the worked example fits the session block whole")
    }

    // MARK: - Identity and shape

    func testFormatVersionIdAndNameAreRequired() throws {
        var object = try F.exampleObject()
        object["format"] = "site-system"
        try assertRefused(object, "format must be")
        object = try F.exampleObject(); object["version"] = 2
        try assertRefused(object, "version must be 1")
        object = try F.exampleObject(); object["version"] = true
        try assertRefused(object, "version must be 1")
        object = try F.exampleObject(); object.removeValue(forKey: "name")
        try assertRefused(object, "name is missing")
        object = try F.exampleObject(); object["id"] = "../escape"
        try assertRefused(object, "id must be")
        object = try F.exampleObject(); object.removeValue(forKey: "id")
        try assertRefused(object, "id is missing")
    }

    func testOneFilePerSiteNamedForItsId() throws {
        // A list of sites in one file is refused (decided 2026-10-20).
        let list = try F.data([try F.exampleObject(), try F.exampleObject()])
        let result = SiteSystemValidator.check(list, path: "sites/all.json", modelCovered: try F.covered())
        XCTAssertTrue(result.issues.contains { $0.contains("one file per site") }, "\(result.issues)")
        // …and a file not named for its site is refused.
        let found = try issues(try F.exampleObject(), path: "sites/other.json")
        XCTAssertTrue(found.contains { $0.contains("named for its id: sites/hillside-house.json") }, "\(found)")
    }

    func testUnknownMembersAreRefusedNotIgnored() throws {
        var object = try F.exampleObject()
        object["owner_phone"] = "021 555 0100"
        try assertRefused(object, "unknown member 'owner_phone'")
        var units = try XCTUnwrap(object["units"] as? [[String: Any]])
        units[0]["warranty"] = "yes"
        object = try F.exampleObject(); object["units"] = units
        try assertRefused(object, "units[0] has an unknown member 'warranty'")
    }

    func testAUnitThatNamesAnotherVaultIsRefused() throws {
        var object = try F.exampleObject()
        var units = try XCTUnwrap(object["units"] as? [[String: Any]])
        units[2] = ["id": "tstat", "model": "NT9C", "vault": "controls_vault"]
        object["units"] = units
        try assertRefused(object, "names another vault")
    }

    // MARK: - Kinds and modes

    func testUnknownConnectionKindsControlModesAndIntegrationKindsRefuse() throws {
        var object = try F.exampleObject()
        var connections = try XCTUnwrap(object["connections"] as? [[String: Any]])
        connections[0]["kind"] = "refrigerant"
        object["connections"] = connections
        try assertRefused(object, "connections[0].kind must be one of: power, control, communication, data, fluid, air, mechanical, other")

        object = try F.exampleObject()
        var controls = try XCTUnwrap(object["controls"] as? [[String: Any]])
        controls[0]["mode"] = "smart"
        object["controls"] = controls
        try assertRefused(object, "controls[0].mode must be one of: communicating, conventional, other")

        object = try F.exampleObject()
        var integrations = try XCTUnwrap(object["integrations"] as? [[String: Any]])
        integrations[0]["kind"] = "portal"
        object["integrations"] = integrations
        try assertRefused(object, "integrations[0].kind must be one of")

        object = try F.exampleObject()
        connections = try XCTUnwrap(object["connections"] as? [[String: Any]])
        connections[0]["direction"] = "forward"
        object["connections"] = connections
        try assertRefused(object, "connections[0].direction must be one of: one_way, two_way")
    }

    func testEveryGenericKindIsAccepted() throws {
        for kind in SiteSystemDocument.ConnectionKind.allCases {
            var object = try F.exampleObject()
            var connections = try XCTUnwrap(object["connections"] as? [[String: Any]])
            connections[0]["kind"] = kind.rawValue
            object["connections"] = connections
            XCTAssertEqual(try issues(object), [], kind.rawValue)
        }
    }

    // MARK: - Plain text

    func testTextIsPlainBoundedAndCarriesNoLinks() throws {
        var object = try F.exampleObject()
        object["notes"] = "See <b>the panel</b>"
        try assertRefused(object, "notes contains markup")
        object["notes"] = "Line one\nline two"
        try assertRefused(object, "notes contains a line break")
        object["notes"] = "Portal at https://portal.example.test/login"
        try assertRefused(object, "notes contains a link")
        object["notes"] = "Portal at www.example.test"
        try assertRefused(object, "notes contains a link")
        object["notes"] = String(repeating: "a", count: SiteSystemValidator.notesLimit + 1)
        try assertRefused(object, "notes is 601 characters; at most 600")
        object["notes"] = "   "
        try assertRefused(object, "notes is blank")
        object["notes"] = 42
        try assertRefused(object, "notes must be text")
    }

    func testExternalIdentifiersAreSystemAndId() throws {
        var object = try F.exampleObject()
        object["external_location_ids"] = ["loc-88412"]
        try assertRefused(object, "must be {\"system\": …, \"id\": …}")
        object["external_location_ids"] = [["system": "Example FSM", "id": "loc-1"]]
        try assertRefused(object, "system must be 1–32 lowercase")
        object["external_location_ids"] = [["system": "example-fsm", "id": "has space"]]
        try assertRefused(object, ".id must be 1–128 printable")
        object["external_location_ids"] = [["system": "example-fsm", "id": "https://x.test/1"]]
        try assertRefused(object, ".id must be 1–128 printable")
        object["external_location_ids"] = (0..<5).map { ["system": "s\($0)", "id": "loc-\($0)"] }
        try assertRefused(object, "external_location_ids has 5 entries; at most 4")
    }

    func testAUnitHasOneIdentifierPerSystem() throws {
        var object = try F.exampleObject()
        var units = try XCTUnwrap(object["units"] as? [[String: Any]])
        units[1]["external_ids"] = [["system": "example-fsm", "id": "a-1"], ["system": "example-fsm", "id": "a-2"]]
        object["units"] = units
        try assertRefused(object, "a unit has one identifier per system")
    }

    // MARK: - Bounds

    func testCountBoundsAndFileSize() throws {
        let units = (0..<13).map { F.unit("u\($0)", model: "NV80F060", serial: "S-\($0)") }
        try assertRefused(F.document(id: "big", units: units), "units has 13 entries; at most 12")
        try assertRefused(F.document(id: "empty", units: []), "units is empty")

        let base = [F.unit("a", model: "NV80F060"), F.unit("b", model: "NV36HP2")]
        let connection: [String: Any] = ["from": "a", "to": "b", "kind": "power"]
        try assertRefused(F.document(id: "c", units: base, extra: ["connections": Array(repeating: connection, count: 31)]),
                          "connections has 31 entries; at most 30")
        let setting: [String: Any] = ["unit": "a", "name": "n", "value": "v"]
        try assertRefused(F.document(id: "s", units: base, extra: ["settings": Array(repeating: setting, count: 31)]),
                          "settings has 31 entries; at most 30")
        let fault: [String: Any] = ["seen_on": "a", "text": "t"]
        try assertRefused(F.document(id: "f", units: base, extra: ["interaction_faults": Array(repeating: fault, count: 21)]),
                          "interaction_faults has 21 entries; at most 20")
        let integrations = (0..<9).map { ["id": "i\($0)", "name": "I", "kind": "bms", "units": ["a"]] as [String: Any] }
        try assertRefused(F.document(id: "i", units: base, extra: ["integrations": integrations]),
                          "integrations has 9 entries; at most 8")

        var object = try F.exampleObject()
        object["notes"] = String(repeating: "n", count: 500)
        object["location_label"] = String(repeating: "l", count: 60)
        var padded = object
        padded["units"] = (0..<12).map { F.unit("u\($0)", model: "NV80F060", serial: "S-\($0)",
                                               label: String(repeating: "x", count: 80)) }
        padded["connections"] = (0..<30).map { _ in ["from": "u0", "to": "u1", "kind": "power",
                                               "detail": String(repeating: "d", count: 240)] as [String: Any] }
        let data = try F.data(padded)
        XCTAssertGreaterThan(data.count, SiteSystemValidator.maximumFileBytes)
        let result = SiteSystemValidator.check(data, path: F.siteFile, modelCovered: try F.covered())
        XCTAssertTrue(result.issues.first?.contains("a site document may be at most 8192") == true, "\(result.issues)")
    }
}
