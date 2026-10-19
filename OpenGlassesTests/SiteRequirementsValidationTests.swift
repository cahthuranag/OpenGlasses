import XCTest
@testable import OpenGlasses

/// The `site_requirements` member (Plan HU, amendment 2026-10-18): what the site asks of the
/// person arriving, office-authored, at most eight items and 4 KiB.
final class SiteRequirementsValidationTests: XCTestCase {

    private typealias F = JobFileFormat3Fixtures

    private func requirements(_ items: String, asOf: String = #""as_of":"2027-01-10T18:00:00Z","#) -> String {
        F.job(#""site_requirements":{\#(asOf)"items":[\#(items)]}"#)
    }

    private let item = #"{"kind":"hazard","text":"Asbestos register: plant-room ceiling. Do not disturb.","severity":"warning"}"#

    func testAValidBlockDecodes() throws {
        let all = OfficeSiteRequirements.Item.Kind.allCases
            .map { #"{"kind":"\#($0.rawValue)","text":"x","severity":"info"}"# }.joined(separator: ",")
        let decoded = try XCTUnwrap(F.parsed(requirements(item + "," + all)).format3?.siteRequirements)
        XCTAssertEqual(decoded.asOf, "2027-01-10T18:00:00Z")
        XCTAssertEqual(decoded.items.count, 7)
        XCTAssertEqual(decoded.items.first, .init(kind: .hazard, text: "Asbestos register: plant-room ceiling. Do not disturb.",
                                                  severity: .warning))
        XCTAssertEqual(try JSONDecoder().decode(OfficeSiteRequirements.self, from: JSONEncoder().encode(decoded)), decoded)
        XCTAssertEqual(try F.parsed(requirements("")).format3?.siteRequirements?.items, [])
    }

    func testEveryBoundRefuses() {
        XCTAssertNil(F.refusal(requirements(F.many(item, 8))))
        XCTAssertEqual(F.refusal(requirements(F.many(item, 9))), .tooMany("site requirements"))
        let cases: [(String, JobFileValidator.Refusal)] = [
            (#"{"kind":"parking","text":"x","severity":"info"}"#, .invalidValue("kind")),
            (#"{"text":"x","severity":"info"}"#, .invalidValue("kind")),
            (#"{"kind":"ppe","text":"x","severity":"critical"}"#, .invalidValue("severity")),
            (#"{"kind":"ppe","text":"x"}"#, .invalidValue("severity")),
            (#"{"kind":"ppe","severity":"info"}"#, .invalidValue("text")),
            (#"{"kind":"ppe","text":"\#(F.long(241))","severity":"info"}"#, .tooLong("text")),
            (#"{"kind":"ppe","text":"<b>Hard hat</b>","severity":"info"}"#, .containsMarkup("text")),
            (#"{"kind":"ppe","text":"x","severity":"info","until":"2027-01-01"}"#, .unexpectedField("until")),
            (#""Hard hat""#, .wrongType("items")),
        ]
        for (entry, expected) in cases {
            XCTAssertEqual(F.refusal(requirements(entry)), expected, entry)
        }
        XCTAssertNil(F.refusal(requirements(#"{"kind":"ppe","text":"\#(F.long(240))","severity":"info"}"#)))
        // The member's own bound: eight items at their limit, with their keys, are over 4 KiB.
        let full = #"{"kind":"induction","text":"\#(F.long(240))","severity":"warning"}"#
        XCTAssertGreaterThan(F.many(full, 8).utf8.count, 2 * 1024)
        let wide = #"{"kind":"induction","text":"\#(F.long(240, "é"))","severity":"warning"}"#
        XCTAssertGreaterThan(F.many(wide, 8).utf8.count, JobFileFormat3Validator.maximumSiteRequirementsBytes)
        XCTAssertEqual(F.refusal(requirements(F.many(wide, 8))), .tooLong("site_requirements"))
    }

    func testTheBlockItself() {
        XCTAssertEqual(F.refusal(requirements(item, asOf: "")), .unreadableDate("as_of"))
        XCTAssertEqual(F.refusal(requirements(item, asOf: #""as_of":"tomorrow","#)), .unreadableDate("as_of"))
        XCTAssertEqual(F.refusal(F.job(#""site_requirements":{"as_of":"2027-01-10T18:00:00Z"}"#)), .wrongType("items"))
        XCTAssertEqual(F.refusal(F.job(#""site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[],"site":"x"}"#)),
                       .unexpectedField("site"))
        XCTAssertEqual(F.refusal(F.job(#""site_requirements":[]"#)), .wrongType("site_requirements"))
        XCTAssertEqual(F.refusal(#"{"job_id":"job-1","revision":1,"job_reference":"1","site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[]}}"#, version: 2),
                       .unexpectedField("site_requirements"))
    }
}

/// Format 3's machine members (the office connector survey's changes 1–3): `unit_key`, `make`
/// and `label`.
final class JobFileUnitKeyTests: XCTestCase {

    private typealias F = JobFileFormat3Fixtures

    private func job(_ equipment: String) -> String {
        #"{"job_id":"job-1","revision":1,"job_reference":"1","equipment":[\#(equipment)]}"#
    }

    func testAUnitKeyIsATokenUniqueAndNeverASerial() throws {
        let file = try F.parsed(job(#"{"serial":"S1"},{"unit_key":"u1"},{"unit_key":"roof_ahu-2","model":"FX-AHU"}"#))
        XCTAssertEqual(file.format3?.units.map(\.unitKey), [nil, "u1", "roof_ahu-2"])
        let cases: [(String, String)] = [
            ("upper case", #"{"unit_key":"U1"}"#),
            ("a space", #"{"unit_key":"u 1"}"#),
            ("too long", #"{"unit_key":"\#(F.long(33))"}"#),
            ("empty", #"{"unit_key":""}"#),
            ("not text", #"{"unit_key":1}"#),
            ("twice", #"{"unit_key":"u1"},{"unit_key":"u1"}"#),
            ("another machine's serial", #"{"serial":"u1"},{"unit_key":"u1"}"#),
            ("another machine's serial, in other case", #"{"serial":"AB12"},{"unit_key":"ab12"}"#),
            ("its own serial", #"{"serial":"u1","unit_key":"u1"}"#),
        ]
        for (name, equipment) in cases {
            XCTAssertEqual(F.refusal(job(equipment)), .invalidValue("unit_key"), name)
        }
    }

    func testMakeAndLabelAreBoundedPlainText() throws {
        let file = try F.parsed(job(#"{"model":"FX-90","make":"\#(F.long(64))","label":"\#(F.long(80))"}"#))
        XCTAssertEqual(file.format3?.units.first?.make?.count, 64)
        XCTAssertEqual(file.format3?.units.first?.label?.count, 80)
        XCTAssertEqual(F.refusal(job(#"{"make":"\#(F.long(65))"}"#)), .tooLong("make"))
        XCTAssertEqual(F.refusal(job(#"{"label":"\#(F.long(81))"}"#)), .tooLong("label"))
        XCTAssertEqual(F.refusal(job(#"{"label":"<b>Roof</b>"}"#)), .containsMarkup("label"))
        XCTAssertEqual(F.refusal(job(#"{"make":7}"#)), .wrongType("make"))
        XCTAssertEqual(F.refusal(job(#"{"label":"Roof\nAHU"}"#)), .notPlainText("label"))
        XCTAssertEqual(F.refusal(job(#"{"model":"A","colour":"red"}"#)), .unexpectedField("colour"))
    }

    func testTheJobAheadCarriesThemAndOlderJobsDecodeUnchanged() throws {
        let file = try F.parsed(job(#"{"model":"FX-AHU","unit_key":"u1","make":"Fixture Make","label":"Roof, AHU-2"}"#))
        let ahead = file.upcomingJob(provenance: .init(fileName: "a", signature: .unsigned, signer: nil, digest: "d"))
        XCTAssertEqual(ahead.equipment, [KnownEquipment(model: "FX-AHU", unitKey: "u1", make: "Fixture Make", label: "Roof, AHU-2")])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ahead.equipment[0])) as? [String: String]
        XCTAssertEqual(object, ["model": "FX-AHU", "unit_key": "u1", "make": "Fixture Make", "label": "Roof, AHU-2"])
        // A machine saved before these existed reads, and one without them encodes as before.
        let old = try JSONDecoder().decode(KnownEquipment.self, from: Data(#"{"model":"FX-90","serial":"S1"}"#.utf8))
        XCTAssertEqual(old, KnownEquipment(model: "FX-90", serial: "S1"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(old), as: UTF8.self), #"{"model":"FX-90","serial":"S1"}"#)
        // A machine with only a unit_key is still a machine: the history may name it.
        XCTAssertFalse(KnownEquipment(unitKey: "u1").isEmpty)
    }
}
