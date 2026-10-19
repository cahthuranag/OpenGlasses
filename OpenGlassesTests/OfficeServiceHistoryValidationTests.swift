import XCTest
@testable import OpenGlasses

/// The `history` member (Plan HU §1, with the 2026-10-18 warranty amendment and the office
/// connector survey's format-3 changes): bounded, dated, keyed to the job's own machines by
/// exactly one of serial or `unit_key`, with flags the office's rules or schedules raised.
final class OfficeServiceHistoryValidationTests: XCTestCase {

    private typealias F = JobFileFormat3Fixtures

    private func refusal(units: String = "", flags: String = "") -> JobFileValidator.Refusal? {
        F.refusal(F.job(F.history(units: units, flags: flags)))
    }

    private func history(units: String = "", flags: String = "") throws -> OfficeServiceHistory {
        try XCTUnwrap(F.parsed(F.job(F.history(units: units, flags: flags))).format3?.history)
    }

    private let s1 = #"{"serial":"S1"}"#
    private func flag(_ extra: String = "", kind: String = "recurring_failure", unit: String? = "S1",
                      evidence: String? = #"["0871"]"#) -> String {
        var members = [#""kind":"\#(kind)""#, #""text":"Fails the same way.""#, #""severity":"warning""#]
        if let unit { members.append(#""unit":"\#(unit)""#) }
        if let evidence { members.append(#""evidence":\#(evidence)"#) }
        return "{" + members.joined(separator: ",") + extra + "}"
    }

    // MARK: - What decodes

    func testAValidBlockDecodes() throws {
        let decoded = try history(
            units: #"{"serial":"S1","installed":"2021-03-04","visits":[{"date":"2026-11-14","job_number":"0993","summary":"No heat, E200.","findings":["Inducer bearing noisy"],"parts_replaced":["Inducer motor"],"technician_initials":"AB","source":"fixture-fsm"},{"date":"2026-11-14","summary":"Same day, second call."}]},{"unit_key":"u1"}"#,
            flags: flag())
        XCTAssertEqual(decoded.units.count, 2)
        XCTAssertEqual(decoded.units[0].serial, "S1")
        XCTAssertNil(decoded.units[0].unitKey)
        XCTAssertEqual(decoded.units[1].unitKey, "u1")
        XCTAssertEqual(decoded.units[1].visits, [])
        XCTAssertEqual(decoded.units[0].visits[0], OfficeServiceHistory.Visit(
            date: "2026-11-14", jobNumber: "0993", summary: "No heat, E200.", findings: ["Inducer bearing noisy"],
            partsReplaced: ["Inducer motor"], technicianInitials: "AB", source: "fixture-fsm"))
        XCTAssertEqual(decoded.flags.first?.unit, "S1")
        // It survives the job ahead's own store.
        XCTAssertEqual(try JSONDecoder().decode(OfficeServiceHistory.self, from: JSONEncoder().encode(decoded)), decoded)
        // The smallest block: when it was compiled, and nothing on file.
        XCTAssertEqual(try history(), OfficeServiceHistory(asOf: "2027-01-10T18:00:00Z"))
    }

    // MARK: - The block

    func testTheBlockItself() {
        XCTAssertEqual(F.refusal(F.job(#""history":[]"#)), .wrongType("history"))
        XCTAssertEqual(F.refusal(F.job(#""history":{"units":[]}"#)), .unreadableDate("as_of"))
        XCTAssertEqual(F.refusal(F.job(#""history":{"as_of":"7 Oct 2026"}"#)), .unreadableDate("as_of"))
        XCTAssertEqual(F.refusal(F.job(#""history":{"as_of":"2026-10-07"}"#)), .unreadableDate("as_of"))
        XCTAssertEqual(F.refusal(F.job(#""history":{"as_of":"2027-01-10T18:00:00Z","summary":"x"}"#)),
                       .unexpectedField("summary"))
        XCTAssertNil(F.refusal(F.job(#""history":{"as_of":"2027-01-10T18:00:00.250Z"}"#)))
        XCTAssertEqual(F.refusal(#"{"job_id":"job-1","revision":1,"job_reference":"1",\#(F.history())}"#, version: 2),
                       .unexpectedField("history"))
    }

    // MARK: - Units: exactly one key, a machine on the job, once

    func testAUnitIsKeyedByExactlyOneOfSerialOrUnitKey() {
        XCTAssertNil(refusal(units: s1))
        XCTAssertNil(refusal(units: #"{"unit_key":"u1"}"#))
        XCTAssertEqual(refusal(units: #"{"serial":"S1","unit_key":"u1"}"#), .invalidValue("units"), "both")
        XCTAssertEqual(refusal(units: #"{"visits":[]}"#), .invalidValue("units"), "neither")
        XCTAssertEqual(refusal(units: #"{"model":"FX-90"}"#), .unexpectedField("model"), "never by model")
        XCTAssertEqual(refusal(units: #"{"serial":"S9"}"#), .invalidValue("serial"), "a serial not on the job")
        XCTAssertEqual(refusal(units: #"{"serial":"s1"}"#), .invalidValue("serial"), "serials match exactly")
        XCTAssertEqual(refusal(units: #"{"unit_key":"u9"}"#), .invalidValue("unit_key"), "a unit_key not on the job")
        XCTAssertEqual(refusal(units: #"{"unit_key":"U1"}"#), .invalidValue("unit_key"), "not a token")
        XCTAssertEqual(refusal(units: #"{"serial":7}"#), .invalidValue("serial"))
        XCTAssertEqual(refusal(units: s1 + "," + s1), .invalidValue("units"), "one unit twice")
        // A machine with both may be named by either, but only once.
        let both = #"{"job_id":"job-1","revision":1,"job_reference":"1","equipment":[{"serial":"S1","unit_key":"u1"}],"#
        XCTAssertNil(F.refusal(both + F.history(units: #"{"unit_key":"u1"}"#) + "}"))
        XCTAssertNil(F.refusal(both + F.history(units: s1) + "}"))
        XCTAssertEqual(F.refusal(both + F.history(units: s1 + #",{"unit_key":"u1"}"#) + "}"), .invalidValue("units"))
        XCTAssertEqual(refusal(units: F.many(s1, 11)), .tooMany("units"))
        XCTAssertEqual(F.refusal(F.job(#""history":{"as_of":"2027-01-10T18:00:00Z","units":{}}"#)), .wrongType("units"))
        XCTAssertEqual(refusal(units: #""S1""#), .wrongType("units"))
    }

    func testInstalledIsAnISODate() throws {
        XCTAssertEqual(try history(units: #"{"serial":"S1","installed":"2024-02-29"}"#).units.first?.installed, "2024-02-29")
        for bad in ["2023-02-29", "2021-13-01", "2021-3-4", "2021-03-04T00:00:00Z", "04/03/2021", ""] {
            XCTAssertEqual(refusal(units: #"{"serial":"S1","installed":"\#(bad)"}"#), .unreadableDate("installed"), bad)
        }
        XCTAssertEqual(refusal(units: #"{"serial":"S1","installed":20210304}"#), .unreadableDate("installed"))
    }

    func testWarranty() throws {
        let decoded = try history(units: #"{"serial":"S1","warranty":{"status":"in_warranty","until":"2027-03-01","note":"Parts only; labour excluded."}},{"unit_key":"u1","warranty":{"status":"expired"}}"#)
        XCTAssertEqual(decoded.units[0].warranty, .init(status: .inWarranty, until: "2027-03-01", note: "Parts only; labour excluded."))
        XCTAssertEqual(decoded.units[1].warranty?.status, .expired)
        XCTAssertNil(try history(units: s1).units.first?.warranty, "no member, no status")
        let cases: [(String, JobFileValidator.Refusal)] = [
            (#"{"status":"maybe"}"#, .invalidValue("status")),
            (#"{"until":"2027-03-01"}"#, .invalidValue("status")),
            (#"{"status":"unknown","until":"March 2027"}"#, .unreadableDate("until")),
            (#"{"status":"unknown","note":"\#(F.long(161))"}"#, .tooLong("note")),
            (#"{"status":"unknown","note":"<i>x</i>"}"#, .containsMarkup("note")),
            (#"{"status":"unknown","provider":"x"}"#, .unexpectedField("provider")),
            (#""in_warranty""#, .wrongType("warranty")),
        ]
        for (warranty, expected) in cases {
            XCTAssertEqual(refusal(units: #"{"serial":"S1","warranty":\#(warranty)}"#), expected, warranty)
        }
        XCTAssertNil(refusal(units: #"{"serial":"S1","warranty":{"status":"unknown","note":"\#(F.long(160))"}}"#))
    }

    // MARK: - Visits

    func testVisitBounds() {
        func unit(_ visits: String) -> String { #"{"serial":"S1","visits":[\#(visits)]}"# }
        XCTAssertNil(refusal(units: unit(F.many(F.visit, 10))))
        XCTAssertEqual(refusal(units: unit(F.many(F.visit, 11))), .tooMany("visits for one unit"))
        let cases: [(String, JobFileValidator.Refusal)] = [
            (#"{"summary":"x"}"#, .invalidValue("date")),
            (#"{"date":"2026-11-31","summary":"x"}"#, .unreadableDate("date")),
            (#"{"date":"2026-11-14"}"#, .invalidValue("summary")),
            (#"{"date":"2026-11-14","summary":"  "}"#, .invalidValue("summary")),
            (#"{"date":"2026-11-14","summary":"\#(F.long(601))"}"#, .tooLong("summary")),
            (#"{"date":"2026-11-14","summary":"<script>x</script>"}"#, .containsMarkup("summary")),
            (#"{"date":"2026-11-14","summary":"a\nb"}"#, .notPlainText("summary")),
            (#"{"date":"2026-11-14","summary":"x","job_number":"\#(F.long(65))"}"#, .tooLong("job_number")),
            (#"{"date":"2026-11-14","summary":"x","findings":[\#(F.many(#""f""#, 7))]}"#, .tooMany("findings")),
            (#"{"date":"2026-11-14","summary":"x","findings":["\#(F.long(201))"]}"#, .tooLong("findings")),
            (#"{"date":"2026-11-14","summary":"x","findings":"f"}"#, .wrongType("findings")),
            (#"{"date":"2026-11-14","summary":"x","parts_replaced":[\#(F.many(#""p""#, 9))]}"#, .tooMany("parts replaced")),
            (#"{"date":"2026-11-14","summary":"x","parts_replaced":["\#(F.long(81))"]}"#, .tooLong("parts_replaced")),
            (#"{"date":"2026-11-14","summary":"x","technician_initials":"ABCDE"}"#, .invalidValue("technician_initials")),
            (#"{"date":"2026-11-14","summary":"x","technician_initials":"A1"}"#, .invalidValue("technician_initials")),
            (#"{"date":"2026-11-14","summary":"x","technician_initials":""}"#, .invalidValue("technician_initials")),
            (#"{"date":"2026-11-14","summary":"x","source":"Fixture FSM"}"#, .invalidValue("source")),
            (#"{"date":"2026-11-14","summary":"x","technician":"A. Person"}"#, .unexpectedField("technician")),
            (#""2026-11-14""#, .wrongType("visits")),
        ]
        for (visit, expected) in cases {
            XCTAssertEqual(refusal(units: unit(visit)), expected, visit)
        }
        XCTAssertNil(refusal(units: unit(#"{"date":"2026-11-14","summary":"x","technician_initials":"JR"}"#)))
        XCTAssertNil(refusal(units: unit(#"{"date":"2026-11-14","summary":"x","findings":[\#(F.many(#""f""#, 6))],"parts_replaced":[\#(F.many(#""p""#, 8))]}"#)))
    }

    func testVisitsAreNewestFirst() {
        func unit(_ visits: String) -> String { #"{"serial":"S1","visits":[\#(visits)]}"# }
        XCTAssertNil(refusal(units: unit(#"{"date":"2026-11-14","summary":"a"},{"date":"2025-09-02","summary":"b"}"#)))
        XCTAssertEqual(refusal(units: unit(#"{"date":"2025-09-02","summary":"a"},{"date":"2026-11-14","summary":"b"}"#)),
                       .invalidValue("visits"))
    }

    func testAVisitIsAtMost2KiBAndTheBlock24KiB() {
        // Each member within its bound, the visit as a whole over 2 KiB.
        let big = #"{"date":"2026-11-14","summary":"\#(F.long(600))","findings":[\#(F.many(#""\#(F.long(200))""#, 6))],"parts_replaced":[\#(F.many(#""\#(F.long(80))""#, 8))]}"#
        XCTAssertEqual(refusal(units: #"{"serial":"S1","visits":[\#(big)]}"#), .tooLong("visits"))
        // Visits each under 2 KiB, ten to a unit, two units: over 24 KiB in all.
        let visit = #"{"date":"2026-11-14","summary":"\#(F.long(600))","findings":[\#(F.many(#""\#(F.long(190))""#, 6))]}"#
        XCTAssertLessThan(visit.utf8.count, JobFileFormat3Validator.maximumVisitBytes)
        let ten = F.many(visit, 10)
        XCTAssertNil(refusal(units: #"{"serial":"S1","visits":[\#(ten)]}"#))
        XCTAssertEqual(refusal(units: #"{"serial":"S1","visits":[\#(ten)]},{"unit_key":"u1","visits":[\#(ten)]}"#),
                       .tooLong("history"))
    }

    // MARK: - Flags

    func testFlagKindsSeverityAndText() {
        for kind in OfficeServiceHistory.Flag.Kind.allCases where !kind.isMaintenance {
            XCTAssertNil(refusal(units: s1, flags: flag(kind: kind.rawValue)), kind.rawValue)
        }
        XCTAssertEqual(refusal(units: s1, flags: flag(kind: "vibes")), .invalidValue("kind"))
        XCTAssertEqual(refusal(units: s1, flags: #"{"kind":"recurring_failure","unit":"S1","text":"x","evidence":["1"],"severity":"urgent"}"#),
                       .invalidValue("severity"))
        XCTAssertEqual(refusal(units: s1, flags: #"{"kind":"recurring_failure","unit":"S1","evidence":["1"],"severity":"info"}"#),
                       .invalidValue("text"))
        XCTAssertEqual(refusal(units: s1, flags: #"{"kind":"recurring_failure","unit":"S1","text":"\#(F.long(241))","evidence":["1"],"severity":"info"}"#),
                       .tooLong("text"))
        XCTAssertEqual(refusal(units: s1, flags: flag(#","confidence":0.9"#)), .unexpectedField("confidence"))
        XCTAssertEqual(refusal(units: s1, flags: #""flag""#), .wrongType("flags"))
    }

    func testAFlagNamesAUnitInTheHistory() {
        XCTAssertNil(refusal(units: #"{"unit_key":"u1"}"#, flags: flag(unit: "u1")))
        XCTAssertEqual(refusal(units: s1, flags: flag(unit: "u1")), .invalidValue("unit"), "a machine with no history entry")
        XCTAssertEqual(refusal(units: s1, flags: flag(unit: "S9")), .invalidValue("unit"))
        XCTAssertEqual(refusal(units: s1, flags: flag(unit: nil)), .invalidValue("unit"), "only a schedule speaks for the site")
    }

    func testFlagBounds() {
        XCTAssertNil(refusal(units: s1, flags: F.many(flag(), 3)))
        XCTAssertEqual(refusal(units: s1, flags: F.many(flag(), 4)), .tooMany("flags for one unit"))
        let siteWide = #"{"kind":"maintenance_due","basis":"schedule","text":"x","severity":"info"}"#
        // Site-wide flags count in the twelve, not in any unit's three.
        XCTAssertNil(refusal(units: s1, flags: F.many(flag(), 3) + "," + F.many(siteWide, 9)))
        XCTAssertEqual(refusal(units: s1, flags: F.many(flag(), 3) + "," + F.many(siteWide, 10)), .tooMany("maintenance flags"))
        XCTAssertNil(refusal(units: s1, flags: flag(evidence: "[" + F.many(#""1""#, 10) + "]")))
        XCTAssertEqual(refusal(units: s1, flags: flag(evidence: "[" + F.many(#""1""#, 11) + "]")), .tooMany("evidence jobs"))
        XCTAssertEqual(refusal(units: s1, flags: flag(evidence: #"["\#(F.long(65))"]"#)), .tooLong("evidence"))
        XCTAssertEqual(refusal(units: s1, flags: flag(evidence: #""0871""#)), .wrongType("evidence"))
    }

    func testARulesFlagShowsItsEvidence() {
        XCTAssertEqual(refusal(units: s1, flags: flag(evidence: nil)), .invalidValue("evidence"))
        XCTAssertEqual(refusal(units: s1, flags: flag(evidence: "[]")), .invalidValue("evidence"))
        XCTAssertEqual(refusal(units: s1, flags: flag(#","basis":"rule""#, evidence: "[]")), .invalidValue("evidence"))
    }

    // MARK: - maintenance_due, by each basis

    func testMaintenanceDueByRule() throws {
        let decoded = try history(units: s1, flags: flag(#","basis":"rule","due":"2027-02-01""#, kind: "maintenance_due"))
        XCTAssertEqual(decoded.flags.first?.kind, .maintenanceDue)
        XCTAssertEqual(decoded.flags.first?.basis, .rule)
        XCTAssertEqual(decoded.flags.first?.due, "2027-02-01")
        // Absent basis is a rule.
        XCTAssertEqual(try history(units: s1, flags: flag(kind: "maintenance_due")).flags.first?.effectiveBasis, .rule)
        XCTAssertEqual(refusal(units: s1, flags: flag(#","schedule":"Annual service""#, kind: "maintenance_due")),
                       .invalidValue("schedule"), "only a schedule's flag names a schedule")
    }

    func testMaintenanceDueBySchedule() throws {
        let onUnit = #"{"kind":"maintenance_due","unit":"S1","basis":"schedule","due":"2027-02-01","schedule":"Annual service","text":"Annual service due.","severity":"info"}"#
        let decoded = try history(units: s1, flags: onUnit)
        XCTAssertEqual(decoded.flags.first?.schedule, "Annual service")
        XCTAssertEqual(decoded.flags.first?.evidence, [], "a schedule's evidence is the schedule")
        XCTAssertFalse(decoded.flags.first?.isSiteWide ?? true)
        // `due` is optional; a schedule's flag may still name jobs.
        XCTAssertNil(refusal(units: s1, flags: #"{"kind":"maintenance_due","unit":"S1","basis":"schedule","evidence":["0871"],"text":"x","severity":"info"}"#))
        let bad: [(String, JobFileValidator.Refusal)] = [
            (#"{"kind":"maintenance_due","basis":"schedule","due":"next month","text":"x","severity":"info"}"#, .unreadableDate("due")),
            (#"{"kind":"maintenance_due","basis":"schedule","schedule":"\#(F.long(81))","text":"x","severity":"info"}"#, .tooLong("schedule")),
            (#"{"kind":"maintenance_due","basis":"schedule","schedule":"","text":"x","severity":"info"}"#, .invalidValue("schedule")),
            (#"{"kind":"maintenance_due","basis":"calendar","text":"x","severity":"info"}"#, .invalidValue("basis")),
            (#"{"kind":"recurring_failure","unit":"S1","basis":"schedule","text":"x","severity":"info"}"#, .invalidValue("basis")),
            (#"{"kind":"recall_or_bulletin","unit":"S1","due":"2027-02-01","text":"x","evidence":["1"],"severity":"info"}"#, .invalidValue("due")),
        ]
        for (flag, expected) in bad {
            XCTAssertEqual(refusal(units: s1, flags: flag), expected, flag)
        }
    }

    func testASiteWideScheduleFlag() throws {
        // No units at all: a routine on the property.
        let decoded = try history(flags: #"{"kind":"maintenance_due","basis":"schedule","due":"2027-02-01","schedule":"Annual service","text":"Annual site service due.","severity":"info"}"#)
        XCTAssertTrue(decoded.units.isEmpty)
        XCTAssertEqual(decoded.flags.first?.isSiteWide, true)
        XCTAssertNil(decoded.flags.first?.unit)
        // An overdue schedule may speak for the site too, as the survey's schedule rules raise.
        XCTAssertNil(refusal(flags: #"{"kind":"overdue_maintenance","basis":"schedule","due":"2026-12-01","text":"x","severity":"warning"}"#))
        // A rule's maintenance flag may not.
        XCTAssertEqual(refusal(flags: #"{"kind":"maintenance_due","text":"x","evidence":["1"],"severity":"info"}"#), .invalidValue("unit"))
    }
}
