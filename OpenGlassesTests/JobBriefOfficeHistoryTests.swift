import XCTest
@testable import OpenGlasses

/// Plan HU P1 — the office's service history, warranty and site requirements in the brief before
/// site: cited with the date and the system, after this phone's own visits, each visit once, and
/// never merged into this phone's history. Pure: invented fixtures, no vault, no network.
@MainActor
final class JobBriefOfficeHistoryTests: XCTestCase {

    private typealias F = OfficeHistoryFixtures

    private let may14 = Date(timeIntervalSince1970: 1_778_760_000)
    private let april2 = Date(timeIntervalSince1970: 1_775_120_000)

    private var expectedCitation: String {
        "Office service history (\(F.systemName)), as of \(OfficeBriefText.asOf(F.asOf))"
    }

    private func siteItems(_ brief: JobBrief) -> [JobBrief.Item] { brief.section(.siteAndHistory).items }

    // MARK: - The office's visits

    func testOfficeVisitsComeAfterThisPhonesCitedWithTheDateAndTheSystem() {
        let phone = F.phoneVisit(id: "p1", reference: "0500", startedAt: april2, serial: F.serial)
        let items = siteItems(F.brief(F.job(requirements: nil), sessions: [phone]))
        let phoneIndex = items.firstIndex { $0.citation.hasSuffix("this phone's job history") }
        let officeIndex = items.firstIndex { $0.officeOrigin == .history }
        XCTAssertNotNil(phoneIndex)
        XCTAssertNotNil(officeIndex)
        XCTAssertLessThan(phoneIndex ?? 0, officeIndex ?? 0, "this phone's visits first, then the office's")

        let office = items.filter { $0.officeOrigin == .history }
        XCTAssertEqual(office.count, 3)
        XCTAssertTrue(office.allSatisfy { $0.citation == expectedCitation })
        XCTAssertEqual(office[0].text,
                       "Office record, \(OfficeBriefText.day("2026-05-14")), job 0993 (serial \(F.serial)): \(F.visitSummary) Parts replaced: \(F.part).")
        XCTAssertTrue(office[1].text.contains("job 0871"), "newest first")
        XCTAssertTrue(office[2].text.contains("job 0702"))
    }

    func testWithNoSystemNameTheCitationSaysOnlyTheOffice() {
        var provenance = F.provenance()
        provenance = JobFileProvenance(fileName: provenance.fileName, signature: .signed, signer: provenance.signer,
                                       receivedAt: F.now, digest: "d", identity: provenance.identity, external: nil)
        let office = siteItems(F.brief(F.job(provenance: provenance))).filter { $0.officeOrigin == .history }
        XCTAssertFalse(office.isEmpty)
        XCTAssertTrue(office.allSatisfy { $0.citation == "Office service history, as of \(OfficeBriefText.asOf(F.asOf))" })
    }

    func testOnlyThreeOfficeVisitsAreNamedAndTheRestAreCounted() {
        let visits = (1...7).map { day in
            OfficeServiceHistory.Visit(date: String(format: "2026-0%d-1%d", min(day, 9), day % 10),
                                       jobNumber: "J\(day)", summary: "Visit \(day).")
        }.sorted { $0.date > $1.date }
        let history = F.history(units: [.init(serial: F.serial, visits: visits)], flags: [])
        let office = siteItems(F.brief(F.job(history: history, requirements: nil))).filter { $0.officeOrigin == .history }
        XCTAssertEqual(office.count, JobBriefAssembler.officeVisitLimit + 1)
        XCTAssertEqual(office.last?.text, "And 4 more earlier visits from the office: ask for the service history.")
        XCTAssertEqual(OfficeBriefText.moreVisitsLine(1),
                       "And 1 more earlier visit from the office: ask for the service history.")
    }

    func testVisitsAreNewestFirstAcrossTheJobsUnits() {
        let history = F.history(units: [
            .init(serial: F.serial, visits: [.init(date: "2025-01-10", jobNumber: "A1", summary: "Old one.")]),
            .init(serial: F.secondSerial, visits: [.init(date: "2026-02-10", jobNumber: "B1", summary: "New one.")]),
        ], flags: [])
        let job = F.job(equipment: [KnownEquipment(model: "FX-90", serial: F.serial),
                                    KnownEquipment(model: "FX-40", serial: F.secondSerial)],
                        history: history, requirements: nil)
        let office = siteItems(F.brief(job)).filter { $0.officeOrigin == .history }
        XCTAssertEqual(office.map { $0.text.contains("job B1") }, [true, false])
        XCTAssertTrue(office[0].text.contains("serial \(F.secondSerial)"))
    }

    func testAUnitWithNoSerialIsNamedByWhereItSitsNeverByItsKey() {
        let history = F.history(units: [.init(unitKey: F.unitKey, visits: [.init(date: "2026-01-02", summary: "Belt replaced.")])],
                                flags: [])
        let job = F.job(equipment: [KnownEquipment(model: "FX-AH", unitKey: F.unitKey, label: "Roof, AHU-2")],
                        history: history, requirements: nil)
        let line = siteItems(F.brief(job)).first { $0.officeOrigin == .history }?.text ?? ""
        XCTAssertTrue(line.contains("(the unit at Roof, AHU-2)"), line)
        XCTAssertFalse(line.contains(F.unitKey), "the office's handle is never shown")
    }

    // MARK: - One visit, once

    func testAVisitBothHoldIsShownOnceAsThePhonesLine() {
        // The phone's own job 0993 on the same serial is the office's 0993.
        let phone = F.phoneVisit(id: "p1", reference: "0993", startedAt: may14, serial: F.serial)
        let items = siteItems(F.brief(F.job(requirements: nil), sessions: [phone]))
        let phoneLine = items.first { $0.citation.hasSuffix("this phone's job history") }
        XCTAssertTrue(phoneLine?.text.hasSuffix("(also in the office's history).") == true, phoneLine?.text ?? "")
        let office = items.filter { $0.officeOrigin == .history }
        XCTAssertFalse(office.contains { $0.text.contains("job 0993") }, "the office's copy is not shown again")
        XCTAssertEqual(office.count, 2, "the other two office visits still are")
    }

    func testTheSameNumberOnAnotherSerialIsNotTheSameVisit() {
        let phone = F.phoneVisit(id: "p1", reference: "0993", startedAt: may14, serial: "OTHER-1", model: "FX-90")
        let items = siteItems(F.brief(F.job(requirements: nil), sessions: [phone]))
        XCTAssertFalse(items.contains { $0.text.contains("also in the office's history") })
        XCTAssertTrue(items.contains { $0.officeOrigin == .history && $0.text.contains("job 0993") })
    }

    func testTheSharedVisitsAreComparedAsSerialsAndNumbersAre() {
        let phone = JobHistoryIndex(sessions: [
            F.phoneVisit(id: "p1", reference: "0993", startedAt: may14, serial: "fx90-s001"),
        ]).visits
        let shared = JobBriefAssembler.sharedVisits(phone: phone, office: F.history())
        XCTAssertEqual(shared.phone, ["p1"])
        XCTAssertEqual(shared.office, [JobBriefAssembler.OfficeVisitRef(unit: 0, visit: 0)])
    }

    // MARK: - Nothing on file, and nothing from the office

    func testTheEmptyLineSaysNothingCameFromTheOffice() {
        XCTAssertEqual(JobBrief.SectionKind.siteAndHistory.emptyLine,
                       "Nothing on file about the site, no earlier visit on this phone, and no history from the office.")
        let job = UpcomingJob(id: "e", origin: .typed, createdAt: F.now)
        let spoken = JobBriefSpeech.spoken(F.brief(job), title: job.title)
        XCTAssertTrue(spoken.contains("Site and history: \(JobBrief.SectionKind.siteAndHistory.emptyLine)"))
    }

    func testAJobWithoutABlockAssemblesByteForByteAsBefore() throws {
        let phone = F.phoneVisit(id: "p1", reference: "0993", startedAt: may14, serial: F.serial)
        let job = F.job(history: nil, requirements: nil)
        let brief = F.brief(job, sessions: [phone])
        XCTAssertNil(brief.flags)
        XCTAssertFalse(brief.hasOfficeContent)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970
        let json = String(decoding: try encoder.encode(brief), as: UTF8.self)
        for key in ["office_origin", "severity", "\"flags\""] {
            XCTAssertFalse(json.contains(key), "\(key) is absent from a brief without the office's blocks")
        }
        // The same brief built the way a brief was built before: items with only text and citation.
        let rebuilt = JobBrief(jobReference: brief.jobReference, assembledAt: brief.assembledAt,
                               sections: brief.sections.map { section in
                                   JobBrief.Section(kind: section.kind, items: section.items.map {
                                       JobBrief.Item(text: $0.text, citation: $0.citation)
                                   })
                               }, faultUnmatched: brief.faultUnmatched)
        XCTAssertEqual(try encoder.encode(rebuilt), try encoder.encode(brief))
        XCTAssertFalse(brief.allItems.contains { $0.text.contains("also in the office's history") })
    }

    func testTheOfficesVisitsNeverEnterThisPhonesHistoryIndex() {
        let job = F.job()
        _ = F.brief(job)
        // The index is built from this phone's sessions and nothing else: the office's visits
        // are a second source beside it.
        let index = JobHistoryIndex(sessions: [])
        XCTAssertTrue(index.visits.isEmpty)
        XCTAssertTrue(index.matches(for: job).isEmpty)
        XCTAssertTrue(index.visits(serial: F.serial).isEmpty)
    }

    // MARK: - Site requirements

    func testSiteRequirementsOpenTheSectionWarningsFirst() {
        let items = siteItems(F.brief(F.job()))
        let requirements = items.prefix { $0.officeOrigin == .siteRequirement }
        XCTAssertEqual(requirements.map(\.text), [
            "Hazard: \(F.hazard)",
            "Induction: \(F.induction)",
            "Access: \(F.access)",
        ])
        XCTAssertEqual(requirements.map(\.severity), [.warning, .warning, .info])
        XCTAssertTrue(requirements.allSatisfy { $0.citation == "From the office, as of \(OfficeBriefText.asOf(F.asOf))" })
        XCTAssertEqual(items[requirements.count].text, "Customer: Fixture Holdings.", "then the job's own details")
    }

    // MARK: - Warranty

    func testTheWarrantyIsAPhraseOnTheUnitsLine() throws {
        let items = F.brief(F.job()).section(.knownEquipment).items
        let index = try XCTUnwrap(items.firstIndex { $0.officeOrigin == .warranty })
        XCTAssertGreaterThan(index, 0, "straight after the unit's own line")
        XCTAssertEqual(items[index].text,
                       "Serial \(F.serial): under warranty until \(OfficeBriefText.day("2027-03-01")) (office, as of \(OfficeBriefText.asOf(F.asOf))).")
        XCTAssertFalse(items[index].text.contains(F.warrantyNote), "the note is the tool's, on request")
    }

    func testAnExpiredWarrantyIsSaidAndAnUnknownOneIsNot() {
        func line(_ warranty: OfficeServiceHistory.Warranty) -> String? {
            let history = F.history(units: [.init(serial: F.serial, warranty: warranty)], flags: [])
            return F.brief(F.job(history: history, requirements: nil)).section(.knownEquipment).items
                .first { $0.officeOrigin == .warranty }?.text
        }
        XCTAssertEqual(line(.init(status: .expired, until: "2026-03-01", note: nil)),
                       "Serial \(F.serial): warranty expired \(OfficeBriefText.day("2026-03-01")) (office, as of \(OfficeBriefText.asOf(F.asOf))).")
        XCTAssertNil(line(.init(status: .unknown, until: nil, note: nil)), "unknown is not said unprompted")
    }

    // MARK: - The model's copy and the page

    func testTheContractCarriesTheOfficeLinesUnderTheOfficeLede() {
        let brief = F.brief(F.job(history: F.history(flags: []), requirements: nil))
        let lines = JobBriefContract.lines(site: nil, faultReport: nil, brief: brief)
        XCTAssertTrue(lines[1].hasSuffix(JobBriefContract.officeLede))
        XCTAssertTrue(lines.contains { $0.hasPrefix("BRIEF SITE_AND_HISTORY: ") && $0.contains("Office record") })
        XCTAssertLessThanOrEqual(lines.dropFirst(2).reduce(0) { $0 + $1.count + 1 }, JobBriefContract.characterLimit)
        // A brief without the office's blocks keeps the lede it had.
        let plain = JobBriefContract.lines(site: nil, faultReport: nil, brief: F.brief(F.job(history: nil, requirements: nil)))
        XCTAssertEqual(plain[1], JobBriefContract.lede)
    }

    func testClosingStripsTheOfficesLinesFromTheBriefAndKeepsTheRest() {
        let brief = F.brief(F.job())
        XCTAssertTrue(brief.hasOfficeContent)
        let kept = brief.withoutOfficeContent()
        XCTAssertFalse(kept.hasOfficeContent)
        XCTAssertNil(kept.flags)
        XCTAssertEqual(kept.allItems, brief.allItems.filter { $0.officeOrigin == nil })
        XCTAssertTrue(kept.allItems.contains { $0.text == "Customer: Fixture Holdings." })
        XCTAssertEqual(kept.assembledAt, brief.assembledAt)
    }
}
