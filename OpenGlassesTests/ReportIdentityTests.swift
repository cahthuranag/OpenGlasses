import XCTest
import PDFKit
@testable import OpenGlasses

@MainActor
final class ReportIdentityTests: XCTestCase {
    private let person = TechnicianIdentity(fullName: "Samuel Tane", shortName: "Sam", technicianID: "TECH-27")

    func testCleaningAndEmptyIdentity() {
        XCTAssertEqual(TechnicianIdentity(fullName: "  Sam\nTane  ", shortName: "  Sam ", technicianID: "  A\u{07}17  "),
                       .init(fullName: "Sam Tane", shortName: "Sam", technicianID: "A17"))
        XCTAssertEqual(TechnicianID.clean(String(repeating: "x", count: 60)).count, 40)
        XCTAssertTrue(ReportIdentity().isEmpty)
        XCTAssertNil(ReportIdentity().customerLine)
        XCTAssertNil(ReportIdentity().fromLine)
        XCTAssertEqual(ReportIdentity().supportLines, [])
    }

    func testCompanyPrecedenceAndCustomerIdentityNeverPrintsID() {
        let identity = ReportIdentity(company: "Profile Company", licensee: "Licence Company", technician: person)
        XCTAssertEqual(identity.customerLine, "Profile Company · Samuel Tane")
        XCTAssertEqual(identity.fromLine, "Profile Company · Samuel Tane · ID TECH-27")
        XCTAssertEqual(identity.supportLines, ["Company: Profile Company", "Technician: Samuel Tane (Sam), ID TECH-27"])
        XCTAssertEqual(ReportIdentity(company: "  ", licensee: "Licence Company").company, "Licence Company")
        XCTAssertEqual(ReportIdentity(technician: .init(shortName: "Sam")).customerLine, "Sam")
    }

    func testFingerprintIsStableAndOnlyEightHexDigits() throws {
        XCTAssertNil(ReportIdentity.fingerprint(code: "  "))
        XCTAssertEqual(ReportIdentity.fingerprint(code: "abc"), "ba7816bf")
        XCTAssertEqual(ReportIdentity.fingerprint(code: " abc\n"), "ba7816bf")
        let value = try XCTUnwrap(ReportIdentity.fingerprint(code: "fixture-code"))
        XCTAssertEqual(value.count, 8)
        XCTAssertTrue(value.allSatisfy { $0.isHexDigit })
        XCTAssertFalse(value.contains("fixture-code"))
    }

    func testNewIdentityFieldsAreProfileOwnedAndPilotSwitchCannotBeLocked() {
        let profile = ConfigProfile(keyId: "k", profileId: "p", organizationName: "N", issued: Date(), leaseDays: 30,
            settings: ["technicianFullName": RawSetting(.string("Samuel Tane"), .default),
                       "technicianID": RawSetting(.string("TECH-27"), .default),
                       "pilotReportsEnabled": RawSetting(.bool(true), .ceiling),
                       "pilotReportRecipients": RawSetting(.strings(["pilot@example.com"]), .default)])
        let result = ProfileApplier.apply(profile: profile, resolvableVaultIds: [])
        XCTAssertEqual(result.owned[.technicianFullName], .string("Samuel Tane"))
        XCTAssertEqual(result.owned[.technicianID], .string("TECH-27"))
        XCTAssertNil(result.startingValues[.pilotReportsEnabled])
        XCTAssertEqual(result.startingValues[.pilotReportRecipients], .strings(["pilot@example.com"]))
        XCTAssertEqual(result.drops.count, 1)
        let keys = ["technicianFullName", "technicianID", "technicianDisplayName"]
        let priors = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            PolicyEnvelope.clear()
            for (key, value) in zip(keys, priors) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        PolicyEnvelope.clear()
        Config.technicianFullName = "Local Name"
        Config.technicianID = "LOCAL"
        Config.technicianDisplayName = "Same key"
        PolicyEnvelope.install(result, organizationName: "N")
        Config.technicianFullName = "Cannot change"
        Config.technicianID = "NO"
        XCTAssertEqual(Config.technicianFullName, "Samuel Tane")
        XCTAssertEqual(Config.technicianID, "TECH-27")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "technicianDisplayName"), "Same key")
        PolicyEnvelope.clear()
        XCTAssertEqual(Config.technicianFullName, "Local Name")
        XCTAssertEqual(Config.technicianID, "LOCAL")
    }

    func testReportSnapshotAndLegacyDecodeAndContractFixture() throws {
        var session = FieldSession(id: "s", vaultId: "test", assetId: nil, mode: .aiOnly,
                                   startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                   outcome: .resolved, escalations: [], billableSeconds: 0)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let legacy = try encoder.encode(session)
        XCTAssertNil(try decoder.decode(FieldSession.self, from: legacy).reportedBy)
        XCTAssertNil((try JSONSerialization.jsonObject(with: legacy) as? [String: Any])?["reportedBy"])
        session.reportedBy = ReportIdentity(company: "Northbridge Mechanical", technician: person)
        let record = WorkRecord(session: session, vaultName: "Test")
        let bytes = try encoder.encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Contracts/fixtures/report-identity-v1.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? NSDictionary)
        XCTAssertEqual(object["reported_by"] as? NSDictionary, fixture)
        XCTAssertEqual(try decoder.decode(WorkRecord.self, from: bytes).reportedBy, session.reportedBy)
        XCTAssertTrue(record.reportSubject.contains("Northbridge Mechanical · Samuel Tane"))
        XCTAssertFalse(record.reportSubject.contains("TECH-27"))
        // Changing the next job's settings cannot rewrite this stored value.
        let prior = UserDefaults.standard.object(forKey: "technicianFullName")
        defer { UserDefaults.standard.set(prior, forKey: "technicianFullName") }
        Config.technicianFullName = "Someone Else"
        XCTAssertEqual(record.reportedBy?.fullName, "Samuel Tane")
    }

    func testFSMTechnicianLabelPrecedesPhoneLabelOnlyForReports() {
        var session = FieldSession(id: "s", vaultId: "test", assetId: nil, mode: .aiOnly,
                                   startedAt: Date(), outcome: .resolved, escalations: [], billableSeconds: 0)
        session.reportedBy = ReportIdentity(company: "Northbridge", technician: person)
        let external = ExternalJobReference(system: "workiz", systemName: "Workiz", jobID: "J-1",
            jobNumber: nil, appointmentID: nil, locationID: nil, customerID: nil,
            technicianID: "FSM-527", equipmentIDs: nil)
        session.jobFile = JobFileProvenance(fileName: "job.ogjob", signature: .signed, signer: "Northbridge",
                                             digest: "fixture", external: external)
        XCTAssertEqual(session.reportedBy?.technicianID, "TECH-27")
        XCTAssertEqual(WorkRecord(session: session, vaultName: "Test").reportedBy?.technicianID, "FSM-527")
        XCTAssertEqual(session.reportIdentity?.customerLine, "Northbridge · Samuel Tane")
    }

    func testSupportHeaderCarriesFromAndNoPlaceholders() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let identity = ReportIdentity(company: "Northbridge", technician: person)
        let plain = JobTranscriptExport.document(scope: .day(date), jobs: [], exportedAt: date,
            timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertFalse(plain.body.contains("From:"))
        let attributed = JobTranscriptExport.document(scope: .day(date), jobs: [], exportedAt: date,
            timeZone: TimeZone(secondsFromGMT: 0)!, from: identity.fromLine)
        XCTAssertTrue(attributed.body.contains("From: Northbridge · Samuel Tane · ID TECH-27"))
    }
}
