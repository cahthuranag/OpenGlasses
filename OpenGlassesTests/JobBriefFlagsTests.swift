import XCTest
@testable import OpenGlasses

/// Plan HU P1/P3 — the office's maintenance flags in the brief: carried with their kind and
/// evidence beside the five sections, said warnings first, `info` ones never unprompted, within
/// the model copy's limit, and worded naturally for a schedule's flag and a site-wide one.
@MainActor
final class JobBriefFlagsTests: XCTestCase {

    private typealias F = OfficeHistoryFixtures

    func testFlagsAreCarriedWithTheirKindAndTheOfficesEvidence() throws {
        let brief = F.brief(F.job())
        XCTAssertEqual(brief.sections.count, 5, "flags are not a sixth section")
        let flags = try XCTUnwrap(brief.flags)
        XCTAssertEqual(flags.count, 2)
        XCTAssertEqual(flags[0].text, "Replacement pattern: \(F.flagText)")
        XCTAssertEqual(flags[0].citation,
                       "Flagged by the office, as of \(OfficeBriefText.asOf(F.asOf)) (evidence: jobs 0871, 0993)")
        XCTAssertEqual(flags[0].severity, .warning)
        XCTAssertEqual(flags[0].officeOrigin, .flag)
        XCTAssertEqual(flags[1].citation,
                       "Flagged by the office from its maintenance schedule, as of \(OfficeBriefText.asOf(F.asOf))")
        XCTAssertFalse(brief.allItems.contains { $0.officeOrigin == .flag }, "and they are in no section")
    }

    func testWarningFlagsComeFirstWhateverTheOfficesOrder() throws {
        let history = F.history(flags: [
            .init(kind: .recallOrBulletin, unit: F.serial, text: "Bulletin FB-7 applies.", evidence: ["0702"], severity: .info),
            .init(kind: .recurringFailure, unit: F.serial, text: "Flame loss three times.", evidence: ["0871"], severity: .warning),
        ])
        let flags = try XCTUnwrap(F.brief(F.job(history: history)).flags)
        XCTAssertEqual(flags.map(\.severity), [.warning, .info])
        XCTAssertEqual(flags[0].text, "Recurring failure: Flame loss three times.")
        XCTAssertEqual(flags[1].text, "Recall or bulletin: Bulletin FB-7 applies.")
        XCTAssertEqual(flags[1].citation, "Flagged by the office, as of \(OfficeBriefText.asOf(F.asOf)) (evidence: job 0702)")
    }

    func testABriefEncodedBeforeFlagsExistedStillDecodes() throws {
        let old = Data(#"{"job_reference":"1007","assembled_at":1790000000,"fault_unmatched":false,"sections":[{"kind":"site_and_history","items":[{"text":"Customer: X.","citation":"Typed on this phone"}]}]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let brief = try decoder.decode(JobBrief.self, from: old)
        XCTAssertNil(brief.flags)
        XCTAssertNil(brief.allItems.first?.officeOrigin)
        XCTAssertFalse(brief.hasOfficeContent)
        // And a brief with flags round-trips them.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let flagged = F.brief(F.job())
        XCTAssertEqual(try decoder.decode(JobBrief.self, from: encoder.encode(flagged)), flagged)
    }

    // MARK: - Wording

    func testAScheduleFlagSaysWhenItFallsDueAndWhatTheServiceIs() {
        let history = F.history()
        let due = OfficeServiceHistory.Flag(kind: .maintenanceDue, unit: F.serial, text: "Filters and belts.",
                                            severity: .warning, basis: .schedule, due: "2026-11-01",
                                            schedule: "Annual service")
        XCTAssertEqual(OfficeBriefText.flagText(due, history: history, equipment: []),
                       "Annual service due on \(OfficeBriefText.day("2026-11-01")): Filters and belts.")
        let overdue = OfficeServiceHistory.Flag(kind: .overdueMaintenance, unit: F.serial, text: "Last service missed",
                                                evidence: ["0702"], severity: .warning, due: "2026-10-01")
        XCTAssertEqual(OfficeBriefText.flagText(overdue, history: history, equipment: []),
                       "Maintenance overdue since \(OfficeBriefText.day("2026-10-01")): Last service missed.")
        let bare = OfficeServiceHistory.Flag(kind: .maintenanceDue, unit: F.serial, text: "Due soon.",
                                             evidence: ["0702"], severity: .info)
        XCTAssertEqual(OfficeBriefText.flagText(bare, history: history, equipment: []), "Maintenance due: Due soon.")
    }

    func testASiteWideScheduleFlagIsAboutTheSite() {
        let site = OfficeServiceHistory.Flag(kind: .maintenanceDue, unit: nil, text: "Filter and belt check.",
                                             severity: .warning, basis: .schedule, due: "2026-11-01",
                                             schedule: "Annual service")
        XCTAssertEqual(OfficeBriefText.flagText(site, history: F.history(), equipment: []),
                       "Annual service due on \(OfficeBriefText.day("2026-11-01")) for the whole site: Filter and belt check.")
    }

    func testWithSeveralUnitsAFlagSaysWhichUnit() {
        let history = F.history(units: [.init(serial: F.serial), .init(unitKey: F.unitKey)], flags: [
            .init(kind: .replacementPattern, unit: F.unitKey, text: "Belt replaced twice.", evidence: ["A1"], severity: .warning),
        ])
        let equipment = [KnownEquipment(model: "FX-90", serial: F.serial),
                         KnownEquipment(model: "FX-AH", unitKey: F.unitKey, label: "Roof, AHU-2")]
        XCTAssertEqual(OfficeBriefText.flagText(history.flags[0], history: history, equipment: equipment),
                       "Replacement pattern on the unit at Roof, AHU-2: Belt replaced twice.")
    }

    // MARK: - The model's copy

    func testTheContractKeepsFlagsInsideItsLimitBeforeTheSections() {
        let brief = F.brief(F.job())
        let lines = JobBriefContract.lines(site: nil, faultReport: nil, brief: brief)
        let flagLines = lines.filter { $0.hasPrefix("OFFICE FLAG: ") }
        XCTAssertEqual(flagLines.count, 2)
        XCTAssertTrue(flagLines[0].contains("(source: \"Flagged by the office"))
        let firstFlag = lines.firstIndex { $0.hasPrefix("OFFICE FLAG: ") } ?? .max
        let firstSection = lines.firstIndex { $0.hasPrefix("BRIEF ") && $0 != JobBriefContract.heading } ?? .max
        XCTAssertLessThan(firstFlag, firstSection, "flags before the sections")
        let kept = lines.dropFirst(2).reduce(0) { $0 + $1.count + 1 }
        XCTAssertLessThanOrEqual(kept + lines[0].count + lines[1].count + 2, JobBriefContract.characterLimit)

        // Twelve long flags cannot push the brief past its limit.
        let many = (1...12).map {
            OfficeServiceHistory.Flag(kind: .recurringFailure, unit: F.serial,
                                      text: String(repeating: "Long flag text \($0). ", count: 10),
                                      evidence: ["J\($0)"], severity: .warning)
        }
        let crowded = F.brief(F.job(history: F.history(flags: many)))
        let bounded = JobBriefContract.lines(site: nil, faultReport: nil, brief: crowded)
        XCTAssertLessThanOrEqual(bounded.reduce(0) { $0 + $1.count + 1 }, JobBriefContract.characterLimit)
    }

    // MARK: - Aloud

    func testInfoFlagsAreNotSpokenAndWarningsComeFirst() {
        let brief = F.brief(F.job(requirements: nil))
        let spoken = JobBriefSpeech.spoken(brief, title: "Job 1007")
        XCTAssertTrue(spoken.hasPrefix("Brief for Job 1007. Office flag: Replacement pattern: \(F.flagText)"), spoken)
        XCTAssertFalse(spoken.contains("Filter and belt check"), "an info flag is not read unprompted")
        // …but "say more about history" reads every flag.
        let more = JobBriefSpeech.more(.siteAndHistory, in: brief)
        XCTAssertTrue(more.contains("Flagged by the office: "))
        XCTAssertTrue(more.contains("Filter and belt check"))
    }

    func testAtMostTwoWarningFlagsAreReadAndTheRestCounted() {
        let flags = (1...4).map {
            OfficeServiceHistory.Flag(kind: .recurringFailure, unit: F.serial, text: "Flag \($0).",
                                      evidence: ["J\($0)"], severity: .warning)
        }
        let spoken = JobBriefSpeech.spoken(F.brief(F.job(history: F.history(flags: flags), requirements: nil)),
                                           title: "Job 1007")
        XCTAssertTrue(spoken.contains("Office flag: Recurring failure: Flag 1."))
        XCTAssertTrue(spoken.contains("Office flag: Recurring failure: Flag 2."))
        XCTAssertFalse(spoken.contains("Flag 3."))
        XCTAssertTrue(spoken.contains("And 2 more office flags, on the job's page."))
    }

    func testWarningRequirementsAreReadInFullBeforeFlagsAndNotAgainInTheirSection() {
        let spoken = JobBriefSpeech.spoken(F.brief(F.job()), title: "Job 1007", characterCap: 200)
        let requirements = spoken.range(of: "Site requirements from the office: Hazard: \(F.hazard) Induction: \(F.induction)")
        let flag = spoken.range(of: "Office flag: ")
        XCTAssertNotNil(requirements, "every warning requirement in full, even under a tiny cap: \(spoken)")
        XCTAssertNotNil(flag)
        XCTAssertLessThan(requirements!.lowerBound, flag!.lowerBound, "requirements before flags")
        XCTAssertEqual(spoken.components(separatedBy: F.hazard).count, 2, "said once")
        XCTAssertFalse(spoken.hasPrefix("Brief for Job 1007. Site and history"))
    }
}
