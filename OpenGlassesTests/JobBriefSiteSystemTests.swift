import XCTest
@testable import OpenGlasses

/// Plan HV P2 — the brief's `knownEquipment` line for a matched site system: after the machines it
/// joins, cited to the vault's site, unconfirmed when probable, and the count of candidates when
/// several sites fit. Pure: the fixture vault's core and site document, no install.
@MainActor
final class JobBriefSiteSystemTests: XCTestCase {

    private typealias F = SiteSystemFixtures
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func brief(equipment: [KnownEquipment], external: ExternalJobReference? = nil,
                       documents: [SiteSystemDocument]? = nil) throws -> (JobBrief, SiteSystemMatch?) {
        var provenance: JobFileProvenance?
        if let external {
            provenance = JobFileProvenance(fileName: "job.ogjob", signature: .unsigned, signer: nil, receivedAt: now,
                                           digest: "d", external: external)
        }
        let job = UpcomingJob(jobReference: "1007", equipment: equipment, origin: provenance == nil ? .typed : .jobFile,
                              provenance: provenance, createdAt: now)
        var inputs = JobBriefAssembler.Inputs(job: job, history: JobHistoryIndex(sessions: []),
                                              vaultName: "Fictional Dual-Fuel Example", coreFiles: try F.coreFiles(),
                                              now: now)
        inputs.siteSystem = SiteSystemMatcher.match(evidence: SiteSystemEvidence(job: job),
                                                    documents: try documents ?? [F.exampleDocument()],
                                                    vaultId: F.vaultId, modelKey: SiteSystemMatcher.modelKey(index: inputs.modelIndex))
        return (JobBriefAssembler.assemble(inputs), inputs.siteSystem)
    }

    private func equipment(_ brief: JobBrief) -> [JobBrief.Item] { brief.section(.knownEquipment).items }

    func testAConfirmedSiteIsOneLineAfterTheMachinesCitedToTheVaultsSite() throws {
        let (brief, match) = try brief(equipment: [KnownEquipment(model: "NV80F060", serial: "AF80-2201")])
        XCTAssertEqual(match?.strength, .confirmed)
        let items = equipment(brief)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].text.hasPrefix("NV80F060, serial AF80-2201: in the vault as NV80F060"), items[0].text)
        XCTAssertEqual(items[1].text, "Part of the Hillside house system, with 2 other units: side-yard heat pump, hall thermostat.")
        XCTAssertEqual(items[1].citation, "Fictional Dual-Fuel Example vault › site Hillside house")
        XCTAssertNil(items[1].officeOrigin, "the vault's line, not the office's: it stays when the job closes")
    }

    func testAProbableSiteIsMarkedUnconfirmed() throws {
        let (brief, match) = try brief(equipment: [KnownEquipment(model: "NV80F060")])
        XCTAssertEqual(match?.strength, .probable)
        XCTAssertEqual(equipment(brief).last?.text,
                       "Probably part of the Hillside house system, with 2 other units: side-yard heat pump, hall thermostat. Matched by model only; the serial will confirm it.")
    }

    func testAJobFileLocationConfirmsWithNoSerial() throws {
        let external = ExternalJobReference(system: "example-fsm", systemName: nil, jobID: "j-1", jobNumber: nil,
                                            appointmentID: nil, locationID: "loc-88412", customerID: nil,
                                            technicianID: nil, equipmentIDs: nil)
        let (brief, match) = try brief(equipment: [], external: external)
        XCTAssertEqual(match?.strength, .confirmed)
        XCTAssertEqual(match?.basis, .location)
        XCTAssertEqual(equipment(brief).last?.text,
                       "Part of the Hillside house system, with 3 units: basement furnace, side-yard heat pump, hall thermostat.")
    }

    func testEveryUnitOnTheJobSaysSo() throws {
        let (brief, _) = try brief(equipment: [KnownEquipment(model: "NV80F060", serial: "AF80-2201"),
                                               KnownEquipment(model: "NV36HP2", serial: "AH36-7713"),
                                               KnownEquipment(model: "NT9C")])
        XCTAssertEqual(equipment(brief).last?.text, "Part of the Hillside house system; every unit in it is on this job.")
    }

    func testSeveralCandidatesSayHowManyAndThatTheSerialWillSay() throws {
        let twin = try F.decoded(F.document(id: "twin", units: [F.unit("f", model: "NV80F060")]))
        let (brief, match) = try brief(equipment: [KnownEquipment(model: "NV80F060")],
                                       documents: [try F.exampleDocument(), twin])
        XCTAssertEqual(match?.strength, .ambiguous)
        let line = try XCTUnwrap(equipment(brief).last)
        XCTAssertEqual(line.text, "2 site systems in the vault use this model; the serial will say which.")
        XCTAssertEqual(line.citation, "Fictional Dual-Fuel Example vault")
    }

    func testNoSiteDocumentsLeavesTheBriefExactlyAsBefore() throws {
        let job = UpcomingJob(jobReference: "1007", equipment: [KnownEquipment(model: "NV80F060", serial: "AF80-2201")],
                              origin: .typed, createdAt: now)
        let inputs = JobBriefAssembler.Inputs(job: job, history: JobHistoryIndex(sessions: []),
                                              vaultName: "Fictional Dual-Fuel Example", coreFiles: try F.coreFiles(), now: now)
        XCTAssertNil(inputs.siteSystem)
        let plain = JobBriefAssembler.assemble(inputs)
        XCTAssertEqual(equipment(plain).count, 1)
        let (withSite, _) = try brief(equipment: job.equipment)
        XCTAssertEqual(Array(equipment(withSite).prefix(1)), equipment(plain), "the machines' own lines are unchanged")
    }

    func testTheModelSeesTheBriefLineInsideItsLimit() throws {
        let (brief, _) = try brief(equipment: [KnownEquipment(model: "NV80F060", serial: "AF80-2201")])
        let lines = JobBriefContract.lines(site: nil, faultReport: nil, brief: brief)
        XCTAssertTrue(lines.contains { $0.hasPrefix("BRIEF KNOWN_EQUIPMENT: \"Part of the Hillside house system") }, "\(lines)")
    }

    func testTheMatchRoundTripsOnTheJobAheadAndOlderJobsDecode() throws {
        let (_, match) = try brief(equipment: [KnownEquipment(model: "NV80F060", serial: "AF80-2201")])
        var job = UpcomingJob(jobReference: "1007", origin: .typed, createdAt: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(job)
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("site_system"), "absent when there is none")
        job.siteSystem = match
        let decoded = try JSONDecoder().decode(UpcomingJob.self, from: encoder.encode(job))
        XCTAssertEqual(decoded.siteSystem, match)
        XCTAssertNil(try JSONDecoder().decode(UpcomingJob.self, from: before).siteSystem)
    }
}
