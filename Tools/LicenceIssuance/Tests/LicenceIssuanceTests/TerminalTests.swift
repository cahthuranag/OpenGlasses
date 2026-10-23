import Foundation
import XCTest
import CryptoKit
@testable import LicenceIssuance

final class TerminalTests: XCTestCase {
    private var binaryDirectory: URL {
        var path = Bundle(for: TerminalTests.self).bundleURL
        while !FileManager.default.fileExists(atPath: path.appendingPathComponent("licence-issuance").path) && path.path != "/" {
            path.deleteLastPathComponent()
        }
        return path
    }
    private func run(_ name: String, _ args: [String], input: String = "") throws -> (Int32, String, String) {
        let p = Process(); p.executableURL = binaryDirectory.appendingPathComponent(name); p.arguments = args
        let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        p.standardOutput = stdout; p.standardError = stderr; p.standardInput = stdin
        try p.run(); stdin.fileHandleForWriting.write(Data(input.utf8)); try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
    func testManualGeneratorPayloadBytesAndSignatureMatchLibrary() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let key = Curve25519.Signing.PrivateKey(), keyFile = tmp.appendingPathComponent("synthetic-key.txt")
        try key.rawRepresentation.base64EncodedString().write(to: keyFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        let result = try run("generate-field-license", ["Fixture Ltd", "--key-file", keyFile.path, "--issued-at", "2027-01-15T08:00:00Z", "--days", "365", "--tier", "team", "--plan", "team", "--seats", "2", "--reference", "fixture-order", "--pack", "hvac", "--pack", "electrical", "--profile", "https://fixture.invalid/p/customer"])
        XCTAssertEqual(result.0, 0)
        let parts = result.1.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        XCTAssertEqual(parts.count, 2); guard parts.count == 2 else { return }
        let issued = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z"))
        let payload = IssuedLicensePayload(licensee: "Fixture Ltd", issued: issued, expires: issued.addingTimeInterval(365 * 86_400), tier: "team", plan: "team", seats: 2, reference: "fixture-order", packs: ["electrical", "hvac"], profile: "https://fixture.invalid/p/customer")
        let bytes = try IssuanceWire.encoder().encode(payload)
        XCTAssertEqual(Data(base64Encoded: String(parts[0])), bytes)
        XCTAssertTrue(key.publicKey.isValidSignature(try XCTUnwrap(Data(base64Encoded: String(parts[1]))), for: bytes))
        let fixedSignature = try XCTUnwrap(Data(base64Encoded: String(parts[1])))
        XCTAssertEqual(try IssuanceWire.code(payload, signer: { _ in fixedSignature }), result.1.trimmingCharacters(in: .whitespacesAndNewlines))
        let privateText = key.rawRepresentation.base64EncodedString()
        XCTAssertFalse(result.1.contains(privateText)); XCTAssertFalse(result.2.contains(privateText))
    }
    func testJournalReopensAcrossProcessesAndPaymentConfirmationAndTamperDetection() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let key = Curve25519.Signing.PrivateKey(), keyFile = tmp.appendingPathComponent("synthetic-key.txt")
        try key.rawRepresentation.base64EncodedString().write(to: keyFile, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let grant = PartnerGrant(partnerId: "fixture", packs: [], maxTermDays: 365, maxSeatsPerCode: 10, seatQuota: 100,
            pilotsAllowed: true, maxPilotDays: 14, validFrom: now.addingTimeInterval(-86_400), validUntil: now.addingTimeInterval(86_400),
            prices: PriceTable(currency: "XXX", taxTreatment: "fixture", perSeatByTermDays: [365: 100]), maxUnpaidSeats: 10)
        let index = Data("{\"version\":1,\"packs\":[]}".utf8)
        let envelope = try JSONSerialization.data(withJSONObject: ["payload": index.base64EncodedString(), "signature": key.signature(for: index).base64EncodedString()])
        let proof = VerifiedPackCatalog.Proof(envelope: envelope, packsById: [:])
        func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: IssuanceWire.encoder().encode(value)) }
        let journal = tmp.appendingPathComponent("ledger.jsonl").path
        let commandFile = tmp.appendingPathComponent("command.json")
        func command(_ fields: [String: Any]) throws {
            var fields = fields; fields["operatorId"] = "fixture-vendor"
            try JSONSerialization.data(withJSONObject: fields).write(to: commandFile)
        }
        var codes: [String] = []
        for id in ["one", "two"] {
            let r = IssuanceRequest(licensee: "Fixture Ltd", seats: 2, termDays: 365, reference: id, profile: "https://fixture.invalid/p/\(id)")
            try command(["action": "order", "id": id, "request": object(r), "grant": object(grant), "catalogProof": object(proof), "catalogPublicKey": key.publicKey.rawRepresentation.base64EncodedString(), "profileId": id, "bankDetails": "FIXTURE"])
            let issued = try run("licence-issuance", [journal, commandFile.path, keyFile.path]); XCTAssertEqual(issued.0, 0, issued.2)
            codes.append(issued.1.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Each CLI process timestamps its own invoice. The setup time can predate that invoice
        // if creating the orders crosses a second, so timestamp receipt only after they exist.
        // Match the CLI's whole-second clock so receipt cannot appear to be in its future.
        let receivedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let payment = Payment(id: "transfer", invoiceNumber: "INV-000001", amountMinor: 200, receivedAt: receivedAt, bankReference: "fixture")
        try command(["action": "payment", "payment": object(payment)])
        let refused = try run("licence-issuance", [journal, commandFile.path, keyFile.path], input: "no\n")
        XCTAssertNotEqual(refused.0, 0)
        let paid = try run("licence-issuance", [journal, commandFile.path, keyFile.path], input: "PAY INV-000001 200\n")
        XCTAssertEqual(paid.0, 0, paid.2); codes.append(paid.1.trimmingCharacters(in: .whitespacesAndNewlines))
        try command(["action": "inspect"])
        let reopened = try run("licence-issuance", [journal, commandFile.path]); XCTAssertEqual(reopened.0, 0)
        let ledger = try IssuanceWire.decoder().decode(Ledger.self, from: Data(reopened.1.utf8))
        XCTAssertEqual(ledger.entries.count, 3); XCTAssertEqual(ledger.invoices.map(\.number), ["INV-000001", "INV-000002"])
        XCTAssertTrue(ledger.isPaid(ledger.invoices[0])); try ledger.verify()
        let serialized = try String(contentsOfFile: journal, encoding: .utf8)
        for code in codes { XCTAssertFalse(code.isEmpty); XCTAssertFalse(serialized.contains(code)) }
        try String(serialized.dropLast()).write(toFile: journal, atomically: true, encoding: .utf8)
        let torn = try run("licence-issuance", [journal, commandFile.path]); XCTAssertNotEqual(torn.0, 0)
        try serialized.replacingOccurrences(of: "Fixture Ltd", with: "Tampered Ltd").write(toFile: journal, atomically: true, encoding: .utf8)
        let tampered = try run("licence-issuance", [journal, commandFile.path]); XCTAssertNotEqual(tampered.0, 0)
    }
}
