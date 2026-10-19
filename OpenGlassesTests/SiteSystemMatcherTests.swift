import XCTest
@testable import OpenGlasses

/// Plan HV P1 — matching a job to a site: a serial, a unit's `{system, id}` (reached by its
/// serial or its `unit_key`) or the location's `{system, id}` confirms; a model alone is at best
/// probable; several candidates is nothing.
final class SiteSystemMatcherTests: XCTestCase {

    private typealias F = SiteSystemFixtures

    private func match(_ evidence: SiteSystemEvidence, documents: [SiteSystemDocument]? = nil) throws -> SiteSystemMatch? {
        SiteSystemMatcher.match(evidence: evidence, documents: try documents ?? [F.exampleDocument()],
                                vaultId: F.vaultId, modelKey: try F.modelKey())
    }

    private func external(locationID: String? = nil, equipmentIDs: [String: String]? = nil,
                          system: String = "example-fsm") -> ExternalJobReference {
        ExternalJobReference(system: system, systemName: nil, jobID: "job-1", jobNumber: nil, appointmentID: nil,
                             locationID: locationID, customerID: nil, technicianID: nil, equipmentIDs: equipmentIDs)
    }

    // MARK: - Confirmed

    func testASerialConfirms() throws {
        let m = try XCTUnwrap(try match(SiteSystemEvidence(equipment: [KnownEquipment(model: "NV80F060", serial: "af80 2201")],
                                                            external: nil)))
        XCTAssertEqual(m.strength, .confirmed)
        XCTAssertEqual(m.basis, .serial)
        XCTAssertEqual(m.siteId, "hillside-house")
        XCTAssertEqual(m.siteName, "Hillside house, whole-home system")
        XCTAssertEqual(m.matchedUnitIDs, ["furnace"])
        XCTAssertEqual(m.otherUnits.map(\.name), ["side-yard heat pump", "hall thermostat"])
    }

    func testTheLocationConfirmsOnlyWithTheSameSystem() throws {
        let same = try XCTUnwrap(try match(SiteSystemEvidence(equipment: [], external: external(locationID: "loc-88412"))))
        XCTAssertEqual(same.strength, .confirmed)
        XCTAssertEqual(same.basis, .location)
        // The same id in another system is another location.
        let other = try match(SiteSystemEvidence(equipment: [], external: external(locationID: "loc-88412", system: "other-fsm")))
        XCTAssertNotEqual(other?.strength, .confirmed)
    }

    func testAUnitIdentifierConfirmsThroughItsUnitKey() throws {
        // A machine with no serial is keyed in equipment_ids by its unit_key (Plan HT, FX27 §6).
        let job = [KnownEquipment(model: "NV36HP2", unitKey: "u1")]
        let m = try XCTUnwrap(try match(SiteSystemEvidence(equipment: job, external: external(equipmentIDs: ["u1": "asset-5521"]))))
        XCTAssertEqual(m.strength, .confirmed)
        XCTAssertEqual(m.basis, .equipmentID)
        XCTAssertEqual(m.matchedUnitIDs, ["heatpump"])
    }

    func testAUnitIdentifierConfirmsThroughItsSerialKey() throws {
        let job = [KnownEquipment(model: "NV36HP2", serial: "ZZ-1")]
        let m = try XCTUnwrap(try match(SiteSystemEvidence(equipment: job, external: external(equipmentIDs: ["ZZ-1": "asset-5521"]))))
        XCTAssertEqual(m.strength, .confirmed)
        XCTAssertEqual(m.basis, .equipmentID)
    }

    func testAUnitIdentifierFromAnotherSystemDoesNotConfirm() throws {
        let job = [KnownEquipment(unitKey: "u1")]
        let m = try match(SiteSystemEvidence(equipment: job, external: external(equipmentIDs: ["u1": "asset-5521"], system: "other-fsm")))
        XCTAssertNotEqual(m?.strength, .confirmed)
    }

    func testTwoSitesEachNamedBySerialIsAmbiguousNotEitherOne() throws {
        let other = try F.decoded(F.document(id: "other", units: [F.unit("a", model: "NV80F060", serial: "OT-1")]))
        let evidence = SiteSystemEvidence(serials: ["AF80-2201", "OT-1"])
        let m = try XCTUnwrap(try match(evidence, documents: [try F.exampleDocument(), other]))
        XCTAssertEqual(m.strength, .ambiguous)
        XCTAssertNil(m.siteId)
        XCTAssertEqual(m.candidateCount, 2)
    }

    // MARK: - Probable and none

    func testModelOnlyWithOneCandidateIsProbable() throws {
        let m = try XCTUnwrap(try match(SiteSystemEvidence(models: ["NV80-F060", "NV36HP2"])))
        XCTAssertEqual(m.strength, .probable)
        XCTAssertEqual(m.basis, .model)
        XCTAssertEqual(Set(m.matchedUnitIDs), ["furnace", "heatpump"])
    }

    func testSeveralCandidatesIsNoneWithTheirCount() throws {
        let twin = try F.decoded(F.document(id: "twin", units: [F.unit("f", model: "NV80F060"), F.unit("h", model: "NV48HP2")]))
        let m = try XCTUnwrap(try match(SiteSystemEvidence(models: ["NV80F060"]), documents: [try F.exampleDocument(), twin]))
        XCTAssertEqual(m.strength, .ambiguous)
        XCTAssertEqual(m.candidateCount, 2)
        XCTAssertFalse(m.strength.isMatch)
        XCTAssertEqual(SiteSystemContract.briefLine(m), "2 site systems in the vault use this model; the serial will say which.")
    }

    func testAModelTheSiteDoesNotListIsUnmatched() throws {
        let m = try XCTUnwrap(try match(SiteSystemEvidence(models: ["NV80F060", "NV48HP2"])))
        XCTAssertEqual(m.strength, .unmatched)
        XCTAssertNil(SiteSystemContract.briefLine(m))
    }

    func testNoDocumentsOrNoEvidenceIsNoMatchAtAll() throws {
        XCTAssertNil(try match(SiteSystemEvidence(models: ["NV80F060"]), documents: []))
        XCTAssertNil(try match(SiteSystemEvidence()))
    }

    func testASerialHeardMidJobUpgradesProbableToConfirmed() throws {
        let ahead = try XCTUnwrap(try match(SiteSystemEvidence(models: ["NV80F060"])))
        XCTAssertEqual(ahead.strength, .probable)
        let later = ahead.evidence.merged(with: SiteSystemEvidence(serials: ["AH36-7713"]))
        let upgraded = try XCTUnwrap(try match(later))
        XCTAssertEqual(upgraded.strength, .confirmed)
        XCTAssertEqual(upgraded.basis, .serial)
        XCTAssertEqual(Set(upgraded.matchedUnitIDs), ["heatpump", "furnace"])
    }

    // MARK: - Which unit is in front of the technician

    func testTheActiveUnitIsItsSerialElseTheOnlyUnitOfItsModel() throws {
        let document = try F.exampleDocument()
        let key = try F.modelKey()
        XCTAssertEqual(SiteSystemMatcher.unit(in: document, model: "NV80F060", serial: nil, modelKey: key)?.id, "furnace")
        XCTAssertEqual(SiteSystemMatcher.unit(in: document, model: nil, serial: "ah36 7713", modelKey: key)?.id, "heatpump")
        let pair = try F.decoded(F.document(id: "pair", units: [F.unit("a", model: "NV36HP2"), F.unit("b", model: "NV36HP2")]))
        XCTAssertNil(SiteSystemMatcher.unit(in: pair, model: "NV36HP2", serial: nil, modelKey: key),
                     "two of one model and no serial: which one is not guessed")
    }

    // MARK: - Evidence

    func testEvidenceIsBoundedAndDeduplicated() {
        let serials = (0..<40).map { "S-\($0)" } + ["s-1"]
        let evidence = SiteSystemEvidence(serials: serials, models: ["NV80F060", "nv80-f060"])
        XCTAssertEqual(evidence.serials.count, SiteSystemEvidence.maximumEntries)
        XCTAssertEqual(evidence.models, ["NV80F060"])
    }
}
