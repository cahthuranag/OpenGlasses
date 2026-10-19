import CryptoKit
import XCTest
@testable import OpenGlasses

/// Shared builders for the format-3 job-file tests (Contracts/job-file.md §10). Every value is
/// invented: no real customer, site, serial or system.
enum JobFileFormat3Fixtures {

    /// The fictional organisation key the golden files are signed with: seed = SHA-256 of a
    /// public label. It has no authority.
    static var fixtureKey: Curve25519.Signing.PrivateKey {
        let seed = Data(SHA256.hash(data: Data("Avenkin public fixture organisation job key v1".utf8)))
        return try! Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    }

    static var fixturePublicKey: String { fixtureKey.publicKey.rawRepresentation.base64EncodedString() }

    static func golden(_ name: String, in bundle: Bundle) throws -> Data {
        try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: "ogjob")))
    }

    /// A job with two machines: one by serial, one with only the office's `unit_key`.
    static func job(_ rest: String = "") -> String {
        let head = #"{"job_id":"job-1","revision":1,"job_reference":"1007","equipment":[{"model":"FX-90","serial":"S1"},{"model":"FX-AHU","unit_key":"u1"}]"#
        return rest.isEmpty ? head + "}" : head + "," + rest + "}"
    }

    static func history(units: String = "", flags: String = "") -> String {
        var out = #""history":{"as_of":"2027-01-10T18:00:00Z""#
        if !units.isEmpty { out += #","units":[\#(units)]"# }
        if !flags.isEmpty { out += #","flags":[\#(flags)]"# }
        return out + "}"
    }

    static let visit = #"{"date":"2026-11-14","summary":"No heat."}"#

    static func file(_ jobJSON: String, version: Int = 3, key: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        let job = Data(jobJSON.utf8)
        let privateKey = key?.rawRepresentation.base64EncodedString()
        return version == 2
            ? try JobFileSignatureCheck.format2File(job: job, privateKeyBase64: privateKey)
            : try JobFileSignatureCheck.format3File(job: job, privateKeyBase64: privateKey)
    }

    static func refusal(_ jobJSON: String, version: Int = 3) -> JobFileValidator.Refusal? {
        guard let data = try? file(jobJSON, version: version) else { return .notAJobFile }
        if case .failure(let refusal) = JobFileValidator.validate(data) { return refusal }
        return nil
    }

    static func parsed(_ jobJSON: String) throws -> JobFile {
        try JobFileValidator.validate(file(jobJSON)).get()
    }

    static func many(_ item: String, _ count: Int) -> String {
        Array(repeating: item, count: count).joined(separator: ",")
    }

    static func long(_ count: Int, _ character: String = "a") -> String {
        String(repeating: character, count: count)
    }
}
