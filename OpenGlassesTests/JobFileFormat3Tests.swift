import CryptoKit
import XCTest
@testable import OpenGlasses

/// Job-file format 3 (Contracts/job-file.md §10; Plans HT P0 and HU P0): the golden files the Go
/// reference writes, format 3's own signature domain, format 2's rules held at version 3, and
/// formats 1 and 2 read exactly as before.
@MainActor
final class JobFileFormat3Tests: XCTestCase {

    private typealias F = JobFileFormat3Fixtures
    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    private static func refusal(_ data: Data) -> JobFileValidator.Refusal? {
        if case .failure(let refusal) = JobFileValidator.validate(data) { return refusal }
        return nil
    }

    private func golden(_ name: String) throws -> Data { try F.golden(name, in: Bundle(for: Self.self)) }

    private func outcome(_ data: Data, key: String) throws -> JobFileSignatureCheck.Outcome {
        JobFileSignatureCheck.check(try JobFileValidator.validate(data).get(),
                                    organisationKey: key, organisationName: "Fixture Service Ltd")
    }

    // MARK: - The golden files

    func testTheExternalFixtureVerifiesAndDecodesEndToEnd() throws {
        let data = try golden("job-file-v3-external")
        let file = try JobFileValidator.validate(data).get()
        XCTAssertEqual(file.body.formatVersion, 3)
        XCTAssertEqual(file.identity?.jobID, "job-3031")
        XCTAssertEqual(file.identity?.revision, 1)
        XCTAssertEqual(try outcome(data, key: F.fixturePublicKey), .signed(organisation: "Fixture Service Ltd"))

        let external = try XCTUnwrap(file.format3?.external)
        XCTAssertEqual(external.system, "fixture-fsm")
        XCTAssertEqual(external.systemName, "Fixture FSM")
        XCTAssertEqual(external.jobID, "FSM-J-88001")
        XCTAssertEqual(external.jobNumber, "88001")
        XCTAssertEqual(external.customerID, "FSM-C-77/a+b=", "an encoded identifier is kept exactly")
        XCTAssertEqual(external.equipmentIDs, ["0001": "FSM-E-9001", "u1": "FSM-E-9002"])
        XCTAssertEqual(file.format3?.units.map(\.unitKey), [nil, "u1"])
        XCTAssertEqual(file.format3?.units.map(\.label), ["Plant room", "Roof, AHU-2"])

        let provenance = JobFileProvenance(fileName: "88001.ogjob", signature: .signed, signer: "Fixture Service Ltd",
                                           digest: JobFile.digest(data), identity: file.identity,
                                           external: external)
        let job = file.upcomingJob(provenance: provenance)
        XCTAssertEqual(job.jobReference, "88001", "the other system's number is the job's")
        XCTAssertEqual(job.officeReference, "FX-3031")
        XCTAssertEqual(job.equipment.map(\.make), ["Fixture Make", "Fixture Make"])
        XCTAssertEqual(job.equipment.last?.unitKey, "u1")
        XCTAssertEqual(job.provenance?.external, external)
    }

    func testTheHistoryFixtureVerifiesAndDecodesEndToEnd() throws {
        let data = try golden("job-file-v3-history")
        let file = try JobFileValidator.validate(data).get()
        XCTAssertEqual(try outcome(data, key: F.fixturePublicKey), .signed(organisation: "Fixture Service Ltd"))
        let history = try XCTUnwrap(file.format3?.history)
        XCTAssertEqual(history.asOf, "2027-01-10T18:00:00Z")
        XCTAssertNotNil(history.asOfDate)
        XCTAssertEqual(history.units.map(\.key), ["0002", "u1"])
        XCTAssertEqual(history.units.first?.installed, "2021-03-04")
        XCTAssertEqual(history.units.first?.warranty?.status, .inWarranty)
        XCTAssertEqual(history.units.first?.warranty?.until, "2027-03-01")
        XCTAssertEqual(history.units.last?.warranty?.status, .unknown)
        XCTAssertEqual(history.units.first?.visits.map(\.jobNumber), ["0993", "0871"])
        XCTAssertEqual(history.units.first?.visits.first?.partsReplaced, ["Inducer motor FX-IM1"])
        XCTAssertEqual(history.visitCount, 3)
        XCTAssertEqual(history.flags.count, 2)
        XCTAssertEqual(history.flags[0].kind, .replacementPattern)
        XCTAssertEqual(history.flags[0].effectiveBasis, .rule)
        XCTAssertEqual(history.flags[0].evidence, ["0871", "0993"])
        XCTAssertEqual(history.flags[1].kind, .maintenanceDue)
        XCTAssertEqual(history.flags[1].basis, .schedule)
        XCTAssertTrue(history.flags[1].isSiteWide)
        XCTAssertEqual(history.flags[1].due, "2027-02-01")
        XCTAssertEqual(history.flags[1].schedule, "Annual service")
        XCTAssertTrue(history.flags[1].evidence.isEmpty)
        let requirements = try XCTUnwrap(file.format3?.siteRequirements)
        XCTAssertEqual(requirements.items.map(\.kind), [.induction, .ppe, .access])
        XCTAssertEqual(requirements.items.map(\.severity), [.warning, .warning, .info])

        let job = file.upcomingJob(provenance: JobFileProvenance(
            fileName: "88002.ogjob", signature: .signed, signer: "Fixture Service Ltd", digest: JobFile.digest(data),
            identity: file.identity, external: file.format3?.external))
        XCTAssertEqual(job.officeHistory, history)
        XCTAssertEqual(job.siteRequirements, requirements)
        XCTAssertNil(job.officeReference, "the two numbers are the same")
    }

    // MARK: - The signature domain

    func testAFormatThreeSignatureIsNotAFormatTwoSignatureNorTheReverse() throws {
        XCTAssertEqual(JobFile.signatureDomainV3, Data("Avenkin.JobFile.v3\0".utf8))
        XCTAssertNotEqual(JobFile.signatureDomainV3, JobFile.signatureDomainV2)
        // A job format 2 can carry too, so the only difference is the version and the domain.
        let job = #"{"job_id":"job-1","revision":1,"job_reference":"1007","equipment":[{"model":"FX-90","serial":"S1"}]}"#
        let v3 = String(decoding: try F.file(job, key: key), as: UTF8.self)
        let v2 = String(decoding: try F.file(job, version: 2, key: key), as: UTF8.self)
        XCTAssertEqual(try outcome(Data(v3.utf8), key: publicKey), .signed(organisation: "Fixture Service Ltd"))
        XCTAssertEqual(try outcome(Data(v2.utf8), key: publicKey), .signed(organisation: "Fixture Service Ltd"))
        // The same job and the same key, relabelled: neither signature carries over.
        let v2AsV3 = Data(v2.replacingOccurrences(of: #""format_version":2"#, with: #""format_version":3"#).utf8)
        let v3AsV2 = Data(v3.replacingOccurrences(of: #""format_version":3"#, with: #""format_version":2"#).utf8)
        XCTAssertEqual(try outcome(v2AsV3, key: publicKey), .invalid)
        XCTAssertEqual(try outcome(v3AsV2, key: publicKey), .invalid)
        // No domain, and format 1's canonical encoding, do not verify either.
        func wrapped(_ message: Data) throws -> Data {
            let value = try key.signature(for: message).base64EncodedString()
            return Data(#"{"format":"openglasses.job","format_version":3,"job":"\#(Data(job.utf8).base64EncodedString())","signature":{"algorithm":"ed25519","value":"\#(value)"}}"#.utf8)
        }
        XCTAssertEqual(try outcome(wrapped(Data(job.utf8)), key: publicKey), .invalid)
        XCTAssertEqual(try outcome(wrapped(JobFile.signatureDomainV3 + Data(job.utf8)), key: publicKey),
                       .signed(organisation: "Fixture Service Ltd"))
        // A format-3 file that is not signed is said to be unsigned, as in format 2.
        XCTAssertEqual(try outcome(F.file(job), key: publicKey), .unsigned)
    }

    // MARK: - Format 2's rules, at version 3

    func testEveryFormatTwoRefusalStillRefusesAtVersionThree() throws {
        let good = String(decoding: try F.file(F.job(), key: key), as: UTF8.self)
        func changed(_ old: String, _ new: String) -> Data {
            XCTAssertTrue(good.contains(old), old)
            return Data(good.replacingOccurrences(of: old, with: new).utf8)
        }
        func refusal(_ data: Data) -> JobFileValidator.Refusal? {
            if case .failure(let refusal) = JobFileValidator.validate(data) { return refusal }
            return nil
        }
        XCTAssertEqual(refusal(changed(#"{"format""#, #"{"note":"x","format""#)), .unexpectedField("note"))
        XCTAssertEqual(refusal(changed(#"{"format""#, #"{"format":"openglasses.job","format""#)), .notAJobFile)
        XCTAssertEqual(refusal(changed(#""format_version":3"#, #""format_version":3.0"#)), .notAJobFile)
        XCTAssertEqual(refusal(changed(#""format_version":3"#, #""format_version":4"#)), .unsupportedVersion(4))
        XCTAssertEqual(refusal(Data((good + "{}").utf8)), .notAJobFile)
        XCTAssertEqual(refusal(changed(#""algorithm":"ed25519""#, #""algorithm":"rsa""#)), .malformedSignature)
        XCTAssertEqual(refusal(Data(#"{"format":"openglasses.job","format_version":3,"job":"{}"}"#.utf8)), .notAJobFile)

        let cases: [(String, String, JobFileValidator.Refusal)] = [
            ("a job that is not an object", "[]", .notAJobFile),
            ("no identifier", #"{"revision":1,"job_reference":"1007"}"#, .noIdentity),
            ("an identifier that is a path", #"{"job_id":"../1007","revision":1,"job_reference":"1007"}"#, .noIdentity),
            ("no revision", #"{"job_id":"job-1","job_reference":"1007"}"#, .noIdentity),
            ("revision zero", #"{"job_id":"job-1","revision":0,"job_reference":"1007"}"#, .noIdentity),
            ("a fractional revision", #"{"job_id":"job-1","revision":1.0,"job_reference":"1007"}"#, .noIdentity),
            ("a revision in text", #"{"job_id":"job-1","revision":"1","job_reference":"1007"}"#, .noIdentity),
            ("a field this version does not know", #"{"job_id":"job-1","revision":1,"start_job":true}"#,
             .unexpectedField("start_job")),
            ("format 1's own members inside the job", #"{"job_id":"job-1","revision":1,"format":"openglasses.job"}"#,
             .unexpectedField("format")),
            ("a member named twice", #"{"job_id":"job-1","job_id":"job-2","revision":1,"job_reference":"1007"}"#, .notAJobFile),
            ("a member named twice inside external",
             F.job(#""external":{"system":"x","system":"y","job_id":"J"}"#), .notAJobFile),
            ("a member named twice inside a visit",
             F.job(F.history(units: #"{"serial":"S1","visits":[{"date":"2026-01-01","date":"2025-01-01","summary":"x"}]}"#)),
             .notAJobFile),
            ("markup", #"{"job_id":"job-1","revision":1,"notes":"<b>urgent</b>"}"#, .containsMarkup("notes")),
            ("an embedded attachment",
             #"{"job_id":"job-1","revision":1,"job_reference":"1","attachments":[{"name":"x","reference":"data:text/plain,hi"}]}"#,
             .embeddedAttachment),
            ("nothing to propose", #"{"job_id":"job-1","revision":1}"#, .empty),
        ]
        for (name, jobJSON, expected) in cases {
            XCTAssertEqual(F.refusal(jobJSON), expected, name)
        }
    }

    // MARK: - Formats 1 and 2, unchanged

    func testFormatOneAndTwoFilesReadExactlyAsBefore() throws {
        // The format-2 golden file: the same job, identity and bytes, and nothing of format 3.
        let v2 = try golden("job-file-v2")
        let parsed = try JobFileValidator.validate(v2).get()
        XCTAssertEqual(parsed.body.formatVersion, 2)
        XCTAssertNil(parsed.format3)
        XCTAssertEqual(parsed.identity?.jobID, "job-2031")
        XCTAssertEqual(parsed.signatureDomain, JobFile.signatureDomainV2)
        XCTAssertEqual(try outcome(v2, key: F.fixturePublicKey), .signed(organisation: "Fixture Service Ltd"))
        let job = parsed.upcomingJob(provenance: JobFileProvenance(
            fileName: "FX-1007.ogjob", signature: .signed, signer: "Fixture Service Ltd", digest: JobFile.digest(v2),
            identity: parsed.identity))
        XCTAssertEqual(job.jobReference, "FX-1007")
        XCTAssertNil(job.officeReference)
        XCTAssertNil(job.officeHistory)
        XCTAssertNil(job.siteRequirements)
        XCTAssertEqual(job.equipment, [KnownEquipment(model: "FX-90", serial: "0001")])
        // A format-2 provenance encodes exactly the members it always had.
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(job.provenance))) as? [String: Any]
        XCTAssertEqual(Set((encoded ?? [:]).keys),
                       ["file_name", "signature", "signer", "received_at", "digest", "job_id", "revision", "job_sha256"])

        // Format 1's canonical encoding — what its signature covers — has no new member either.
        let v1 = Data(#"{"format":"openglasses.job","format_version":1,"job_reference":"1007","equipment":[{"model":"FX-90","serial":"S1"}]}"#.utf8)
        let body = try JobFileValidator.validate(v1).get().body
        XCTAssertEqual(String(decoding: try body.canonicalData(), as: UTF8.self),
                       #"{"equipment":[{"model":"FX-90","serial":"S1"}],"format":"openglasses.job","format_version":1,"job_reference":"1007"}"#)
        XCTAssertNil(try JobFileValidator.validate(v1).get().format3)
    }

    func testFormatOneAndTwoNeverCarryFormatThreeMembers() {
        for member in [#""external":{"system":"x","job_id":"J"}"#, F.history(),
                       #""site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[]}"#] {
            let name = String(member.dropFirst().prefix { $0 != "\"" })
            XCTAssertEqual(F.refusal(#"{"job_id":"job-1","revision":1,"job_reference":"1",\#(member)}"#, version: 2),
                           .unexpectedField(name))
            let v1 = Data(#"{"format":"openglasses.job","format_version":1,"job_reference":"1",\#(member)}"#.utf8)
            XCTAssertEqual(Self.refusal(v1), .unexpectedField(name))
        }
        // Nor a format-3 machine member.
        for member in ["unit_key", "make", "label"] {
            XCTAssertEqual(F.refusal(#"{"job_id":"job-1","revision":1,"job_reference":"1","equipment":[{"model":"A","\#(member)":"x"}]}"#, version: 2),
                           .unexpectedField(member))
        }
    }

    func testAFormatThreeJobMayGiveItsNumberOnlyAsTheOtherSystems() throws {
        let file = try F.parsed(#"{"job_id":"job-1","revision":1,"external":{"system":"x","job_id":"J","job_number":"88001"}}"#)
        XCTAssertEqual(file.upcomingJob(provenance: .init(fileName: "a", signature: .unsigned, signer: nil, digest: "d")).jobReference,
                       "88001")
        XCTAssertEqual(F.refusal(#"{"job_id":"job-1","revision":1,"external":{"system":"x","job_id":"J"}}"#), .empty)
    }

    func testTheWholeFileIsStillBoundedAt64KiB() {
        let notes = F.long(1_000)
        let big = F.job(#""notes":"\#(notes)","fault_report":"\#(notes)","history":{"as_of":"2027-01-10T18:00:00Z","units":[\#(F.many(#"{"serial":"S1"}"#, 1))]}"#)
        XCTAssertNil(F.refusal(big))
        let padded = Data(String(decoding: (try? F.file(big)) ?? Data(), as: UTF8.self).utf8)
            + Data(repeating: 0x20, count: JobFile.maximumBytes)
        XCTAssertEqual(Self.refusal(padded), .tooLarge(padded.count))
    }
}
