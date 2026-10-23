import Foundation
import CryptoKit
import Darwin
import LicenceIssuance

// JSON input avoids fragile argument parsing and prevents keys being passed as arguments.
// The operator owns the journal. This is a local vendor terminal, not an authentication boundary.
struct Command: Decodable {
    let action: String
    let from: Date?
    let until: Date?
    let id: String?
    let grant: PartnerGrant?
    let request: IssuanceRequest?
    let catalogProof: VerifiedPackCatalog.Proof?
    let catalogPublicKey: String?
    let profileId: String?
    let renewalOf: String?
    let bankDetails: String?
    let payment: Payment?
    let credit: CreditNote?
    let operatorId: String
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
func require<T>(_ value: T?) throws -> T {
    guard let value else { throw SalesError.invalidOrder }; return value
}
func signer(_ path: String) throws -> ByteSigner {
    // A path only. Refuse an inline key without ever echoing it.
    guard FileManager.default.fileExists(atPath: path) else { throw SalesError.invalidOrder }
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    guard let line = contents.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) })
        .first(where: { !$0.isEmpty && !$0.hasPrefix("#") }), let bytes = Data(base64Encoded: line) else {
        throw SalesError.invalidOrder
    }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
    return key.signature(for:)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { fail("usage: licence-issuance JOURNAL COMMAND.json [SIGNING_KEY_FILE]\nActions: order, issue, payment (prompts), credit, inspect. Use --help in the package README for JSON contracts.") }
do {
    let command = try IssuanceWire.decoder().decode(Command.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    // Stable sibling lock survives atomic journal replacement. All writers must use this protocol.
    let lockFD = open(args[0] + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard lockFD >= 0, flock(lockFD, LOCK_EX) == 0 else { fail("cannot lock journal") }
    defer { flock(lockFD, LOCK_UN); close(lockFD) }
    let url = URL(fileURLWithPath: args[0])
    var ledger = Ledger()
    if FileManager.default.fileExists(atPath: url.path) {
        let data = try Data(contentsOf: url)
        guard data.isEmpty || data.last == 10 else { throw Ledger.IntegrityError.invalidRecord }
        // JSONL: each durable command adds exactly one row; a torn tail is an error, never ignored.
        var decoded: [LedgerEntry] = []
        for line in data.split(separator: 10) { decoded.append(try IssuanceWire.decoder().decode(LedgerEntry.self, from: Data(line))) }
        let object = try IssuanceWire.encoder().encode(["entries": decoded])
        ledger = try IssuanceWire.decoder().decode(Ledger.self, from: object)
        try ledger.verify()
    }
    var book = try SalesBook(ledger: ledger)
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    var output: IssuedCode?
    if command.action == "inspect" {
        print(String(decoding: try IssuanceWire.encoder().encode(book.ledger), as: UTF8.self)); exit(0)
    }
    if command.action == "export" {
        print(String(decoding: try IssuanceWire.encoder().encode(book.ledger.accounting(from: require(command.from), until: require(command.until))), as: UTF8.self)); exit(0)
    }
    // Defer key access until a signing operation actually needs it.
    let sign: ByteSigner = { bytes in try signer(require(args.count == 3 ? args[2] : nil))(bytes) }
    switch command.action {
    case "order":
        output = try book.order(id: require(command.id), request: require(command.request), grant: require(command.grant),
                                catalog: VerifiedPackCatalog.verify(require(command.catalogProof), publicKeyBase64: require(command.catalogPublicKey)), profileId: require(command.profileId),
                                bankDetails: command.bankDetails ?? "", renewalOf: command.renewalOf,
                                operatorId: command.operatorId, now: now, signer: sign)
    case "issue":
        output = try book.issue(id: require(command.id), request: require(command.request), grant: require(command.grant),
                                catalog: VerifiedPackCatalog.verify(require(command.catalogProof), publicKeyBase64: require(command.catalogPublicKey)), operatorId: command.operatorId, now: now, signer: sign)
    case "payment":
        let payment = try require(command.payment)
        let confirmation = "PAY \(payment.invoiceNumber) \(payment.amountMinor)"
        FileHandle.standardError.write(Data(("Publishing a full code cannot be undone offline. Type '\(confirmation)' to confirm: ").utf8))
        guard readLine() == confirmation else { throw SalesError.confirmationRequired }
        output = try book.recordPayment(payment, confirmed: true, operatorId: command.operatorId, now: now, signer: sign)
    case "credit": try book.credit(require(command.credit), now: now)
    default: throw SalesError.invalidOrder
    }
    guard let row = book.ledger.entries.last, book.ledger.entries.count == ledger.entries.count + 1 else { fail("no journal row") }
    let bytes = try IssuanceWire.encoder().encode(row) + Data([10])
    let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { fail("cannot open journal") }
    defer { close(fd) }
    // A failed write emits no bearer code; recovery must inspect/restore the journal before retrying.
    let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    guard count == bytes.count, fsync(fd) == 0 else { fail("journal write failed; inspect journal before retrying") }
    if let output { print(output.code) } else { print("recorded") }
    FileHandle.standardError.write(Data(("journal row \(row.sequence): \(row.rowHash)\n").utf8))
} catch {
    // Never interpolate decoding errors: they can include source JSON or credential bytes.
    if let refusal = error as? IssuanceRefusal { fail("refused: \(refusal)") }
    if let refusal = error as? SalesError { fail("refused: \(refusal)") }
    fail("operation failed; no code delivered. Check input, key path and journal integrity.")
}
