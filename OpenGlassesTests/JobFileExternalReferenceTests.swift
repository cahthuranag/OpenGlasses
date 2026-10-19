import XCTest
@testable import OpenGlasses

/// The `external` block (Plan HT §1, with the office connector survey's format-3 changes): opaque
/// identity in another system, bounded, never a link, keyed to the job's own machines.
final class JobFileExternalReferenceTests: XCTestCase {

    private typealias F = JobFileFormat3Fixtures

    private func external(_ members: String) -> String { F.job(#""external":{\#(members)}"#) }

    func testAFullBlockValidatesAndDecodes() throws {
        let file = try F.parsed(external(#""system":"fixture-fsm","system_name":"Fixture FSM","job_id":"J-1/a+b=","job_number":"88001","appointment_id":"A-1","location_id":"L-1","customer_id":"C-1","technician_id":"T-1","equipment_ids":{"S1":"E-1","u1":"E-2"}"#))
        let block = try XCTUnwrap(file.format3?.external)
        XCTAssertEqual(block, ExternalJobReference(
            system: "fixture-fsm", systemName: "Fixture FSM", jobID: "J-1/a+b=", jobNumber: "88001",
            appointmentID: "A-1", locationID: "L-1", customerID: "C-1", technicianID: "T-1",
            equipmentIDs: ["S1": "E-1", "u1": "E-2"]))
        // The minimum.
        XCTAssertNotNil(try F.parsed(external(#""system":"x","job_id":"J""#)).format3?.external)
    }

    func testEachMemberHasItsTypeLengthCharactersAndNoLinks() {
        let id128 = F.long(128)
        let cases: [(String, String, JobFileValidator.Refusal)] = [
            ("no system", #""job_id":"J""#, .invalidValue("system")),
            ("an upper-case system", #""system":"FSM","job_id":"J""#, .invalidValue("system")),
            ("a system with a space", #""system":"fixture fsm","job_id":"J""#, .invalidValue("system")),
            ("a long system", #""system":"\#(F.long(33))","job_id":"J""#, .invalidValue("system")),
            ("a numeric system", #""system":7,"job_id":"J""#, .invalidValue("system")),
            ("no job id", #""system":"x""#, .invalidValue("job_id")),
            ("an empty job id", #""system":"x","job_id":"""#, .invalidValue("job_id")),
            ("a job id with a space", #""system":"x","job_id":"J 1""#, .invalidValue("job_id")),
            ("a job id beyond ASCII", #""system":"x","job_id":"Jé""#, .invalidValue("job_id")),
            ("a long job id", #""system":"x","job_id":"\#(F.long(129))""#, .invalidValue("job_id")),
            ("a job id that is a link", #""system":"x","job_id":"https://fsm.example/1""#, .containsLink("job_id")),
            ("a numeric customer id", #""system":"x","job_id":"J","customer_id":7"#, .wrongType("customer_id")),
            ("a null location id", #""system":"x","job_id":"J","location_id":null"#, .wrongType("location_id")),
            ("a technician id that is a link", #""system":"x","job_id":"J","technician_id":"a://b""#, .containsLink("technician_id")),
            ("a long appointment id", #""system":"x","job_id":"J","appointment_id":"\#(F.long(129))""#, .invalidValue("appointment_id")),
            ("a long system name", #""system":"x","job_id":"J","system_name":"\#(F.long(41))""#, .tooLong("system_name")),
            ("a system name with markup", #""system":"x","job_id":"J","system_name":"<b>FSM</b>""#, .containsMarkup("system_name")),
            ("a system name that is a link", #""system":"x","job_id":"J","system_name":"see https://x""#, .containsLink("system_name")),
            ("a blank system name", #""system":"x","job_id":"J","system_name":"  ""#, .invalidValue("system_name")),
            ("a long job number", #""system":"x","job_id":"J","job_number":"\#(F.long(65))""#, .tooLong("job_number")),
            ("a job number with a line break", #""system":"x","job_id":"J","job_number":"88\n001""#, .notPlainText("job_number")),
            ("a job number that is a link", #""system":"x","job_id":"J","job_number":"ftp://1""#, .containsLink("job_number")),
            ("a member the contract does not list", #""system":"x","job_id":"J","tenant":"t""#, .unexpectedField("tenant")),
            ("a link member", #""system":"x","job_id":"J","url":"u""#, .unexpectedField("url")),
            ("ids that are not an object", #""system":"x","job_id":"J","equipment_ids":["E"]"#, .wrongType("equipment_ids")),
            ("an id that is a link", #""system":"x","job_id":"J","equipment_ids":{"S1":"https://x"}"#, .containsLink("equipment_ids")),
            ("an id that is not text", #""system":"x","job_id":"J","equipment_ids":{"S1":9}"#, .wrongType("equipment_ids")),
            ("an id with a space", #""system":"x","job_id":"J","equipment_ids":{"S1":"E 1"}"#, .invalidValue("equipment_ids")),
            ("a long id", #""system":"x","job_id":"J","equipment_ids":{"S1":"\#(id128)x"}"#, .invalidValue("equipment_ids")),
        ]
        for (name, members, expected) in cases {
            XCTAssertEqual(F.refusal(external(members)), expected, name)
        }
        XCTAssertEqual(F.refusal(F.job(#""external":"fixture-fsm""#)), .wrongType("external"))
    }

    func testEquipmentIDsAreKeyedByUnitKeyElseSerial() {
        // A serial key for a machine with only a serial, a unit_key key for one with a unit_key.
        XCTAssertNil(F.refusal(external(#""system":"x","job_id":"J","equipment_ids":{"S1":"E-1","u1":"E-2"}"#)))
        let refused: [(String, String)] = [
            ("a serial not on the job", #"{"S9":"E"}"#),
            ("a model", #"{"FX-90":"E"}"#),
            ("a unit_key not on the job", #"{"u9":"E"}"#),
        ]
        for (name, ids) in refused {
            XCTAssertEqual(F.refusal(external(#""system":"x","job_id":"J","equipment_ids":\#(ids)"#)),
                           .invalidValue("equipment_ids"), name)
        }
        // A machine with both is keyed by its unit_key, never its serial.
        let both = #"{"job_id":"job-1","revision":1,"job_reference":"1","equipment":[{"serial":"S1","unit_key":"u1"}],"external":{"system":"x","job_id":"J","equipment_ids":"#
        XCTAssertNil(F.refusal(both + #"{"u1":"E"}}}"#))
        XCTAssertEqual(F.refusal(both + #"{"S1":"E"}}}"#), .invalidValue("equipment_ids"))
    }

    func testTheBlockIsBoundedAt2KiB() {
        // Ten machines with 32-character keys and every identifier at its limit: each value is
        // within its own bound, and the whole is not.
        let keys = (0..<10).map { F.long(31, "k") + String(UnicodeScalar(UInt8(97 + $0))) }
        let equipment = keys.map { #"{"unit_key":"\#($0)"}"# }.joined(separator: ",")
        let ids = keys.map { #""\#($0)":"\#(F.long(128))""# }.joined(separator: ",")
        let every = ["appointment_id", "location_id", "customer_id", "technician_id"]
            .map { #""\#($0)":"\#(F.long(128))""# }.joined(separator: ",")
        let job = #"{"job_id":"job-1","revision":1,"job_reference":"1","equipment":[\#(equipment)],"external":{"system":"\#(F.long(32))","system_name":"\#(F.long(40))","job_id":"\#(F.long(128))","job_number":"\#(F.long(64))",\#(every),"equipment_ids":{\#(ids)}}}"#
        XCTAssertEqual(F.refusal(job), .tooLong("external"))
        XCTAssertGreaterThan(JobFileFormat3Validator.maximumExternalBytes, 0)
    }

    func testFormatOneAndTwoRefuseTheBlock() {
        XCTAssertEqual(F.refusal(#"{"job_id":"job-1","revision":1,"job_reference":"1","external":{"system":"x","job_id":"J"}}"#, version: 2),
                       .unexpectedField("external"))
        let v1 = Data(#"{"format":"openglasses.job","format_version":1,"job_reference":"1","external":{"system":"x","job_id":"J"}}"#.utf8)
        guard case .failure(let refusal) = JobFileValidator.validate(v1) else { return XCTFail() }
        XCTAssertEqual(refusal, .unexpectedField("external"))
    }

    // MARK: - The record

    func testTheBlockRidesTheProvenanceIntoTheRecordAndAbsentChangesNothing() throws {
        let block = ExternalJobReference(system: "fixture-fsm", systemName: "Fixture FSM", jobID: "J-1",
                                         jobNumber: "88001", appointmentID: nil, locationID: "L-1",
                                         customerID: nil, technicianID: nil, equipmentIDs: ["S1": "E-1"])
        let with = JobFileProvenance(fileName: "a.ogjob", signature: .signed, signer: "Org",
                                     receivedAt: Date(timeIntervalSince1970: 1_800_000_000), digest: "d",
                                     identity: .init(jobID: "job-1", revision: 1, sha256: "s"), external: block)
        let decoded = try JSONDecoder().decode(JobFileProvenance.self, from: JSONEncoder().encode(with))
        XCTAssertEqual(decoded.external, block)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(with)) as? [String: Any])
        let external = try XCTUnwrap(object["external"] as? [String: Any])
        XCTAssertEqual(external["job_id"] as? String, "J-1")
        XCTAssertEqual(external["system_name"] as? String, "Fixture FSM")
        XCTAssertEqual(external["equipment_ids"] as? [String: String], ["S1": "E-1"])
        XCTAssertNil(external["appointment_id"], "a member the file left out stays out")

        // A provenance without one encodes exactly as it did before the member existed.
        let without = JobFileProvenance(fileName: "a.ogjob", signature: .signed, signer: "Org",
                                        receivedAt: Date(timeIntervalSince1970: 1_800_000_000), digest: "d",
                                        identity: .init(jobID: "job-1", revision: 1, sha256: "s"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(without), as: UTF8.self),
                       #"{"digest":"d","file_name":"a.ogjob","job_id":"job-1","job_sha256":"s","received_at":821692800,"revision":1,"signature":"signed","signer":"Org"}"#)
        // And a record written before it reads.
        let old = Data(#"{"file_name":"1007.ogjob","signature":"unsigned","received_at":0,"digest":"abc"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(JobFileProvenance.self, from: old).external)
    }
}

/// Which number is the job's (Plan HT §4): the other system's, with the office's kept beside it.
@MainActor
final class JobFileExternalPrecedenceTests: XCTestCase {

    private typealias F = JobFileFormat3Fixtures
    private var previousEntitlement: FieldAssistEntitlementProvider!

    override func setUp() {
        super.setUp()
        previousEntitlement = EntitlementTestScope.grant()
        VaultRegistry.shared.resetCache()
    }

    override func tearDown() {
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    private func job(reference: String?, number: String?) throws -> (JobFile, UpcomingJob) {
        let referenceMember = reference.map { #""job_reference":"\#($0)","# } ?? ""
        let numberMember = number.map { #","job_number":"\#($0)""# } ?? ""
        let file = try F.parsed(#"{"job_id":"job-1","revision":1,\#(referenceMember)"site":{"customer":"Fixture Service"},"external":{"system":"x","job_id":"J"\#(numberMember)}}"#)
        let provenance = JobFileProvenance(fileName: "a.ogjob", signature: .unsigned, signer: nil, digest: "d",
                                           identity: file.identity, external: file.format3?.external)
        return (file, file.upcomingJob(provenance: provenance))
    }

    func testTheOtherSystemsNumberIsTheJobsNumber() throws {
        let (_, upcoming) = try job(reference: "88001", number: "88001")
        XCTAssertEqual(upcoming.jobReference, "88001")
        XCTAssertNil(upcoming.officeReference, "the same number is not shown twice")
        XCTAssertEqual(upcoming.title, "Job 88001")
    }

    func testADifferingOfficeReferenceIsKeptAndShownOnTheReview() throws {
        let (file, upcoming) = try job(reference: "FX-3031", number: "88001")
        XCTAssertEqual(upcoming.jobReference, "88001")
        XCTAssertEqual(upcoming.officeReference, "FX-3031")
        let review = JobFileReview.make(file: file, provenance: try XCTUnwrap(upcoming.provenance), existing: [])
        XCTAssertEqual(review.lines.first?.label, "Job number")
        XCTAssertEqual(review.lines.first?.value, "88001")
        XCTAssertEqual(review.lines.first { $0.label == "Office reference" }?.value, "FX-3031")
        XCTAssertFalse(review.lines.contains { $0.value == "J" }, "the other system's identifier is not shown")
        // A job ahead with the external number is the duplicate the review asks about.
        let held = UpcomingJob(jobReference: "88001", origin: .typed)
        XCTAssertEqual(JobFileReview.make(file: file, provenance: try XCTUnwrap(upcoming.provenance), existing: [held]).duplicate?.id,
                       held.id)
    }

    func testABlockWithNoNumberLeavesTheOfficesNumber() throws {
        let (file, upcoming) = try job(reference: "FX-3031", number: nil)
        XCTAssertEqual(upcoming.jobReference, "FX-3031")
        XCTAssertNil(upcoming.officeReference)
        let review = JobFileReview.make(file: file, provenance: try XCTUnwrap(upcoming.provenance), existing: [])
        XCTAssertNil(review.lines.first { $0.label == "Office reference" })
    }

    func testAnIntakeCorrectionLeavesTheBlockUntouched() throws {
        let (_, upcoming) = try job(reference: "FX-3031", number: "88001")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Precedence-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FieldSessionService(sessionsRoot: root)
        _ = try service.startSession(vaultId: "refrigeration", assetId: nil)
        service.applyJobAhead(upcoming)
        service.setJobReference("88001A")
        let session = try XCTUnwrap(service.activeSession)
        XCTAssertEqual(session.jobReference, "88001A")
        XCTAssertEqual(session.jobFile?.external?.jobNumber, "88001", "the block is the office's, as it arrived")
        XCTAssertEqual(session.jobFile?.external, upcoming.provenance?.external)
    }

    func testRevisingAJobKeepsTheNewRevisionsOfficeData() throws {
        let (_, first) = try job(reference: "FX-3031", number: "88001")
        let (_, second) = try job(reference: "FX-3031B", number: "88001")
        let written = second.replacingIdentity(with: first)
        XCTAssertEqual(written.id, first.id)
        XCTAssertEqual(written.officeReference, "FX-3031B")
    }
}
