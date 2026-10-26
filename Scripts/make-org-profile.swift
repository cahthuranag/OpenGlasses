#!/usr/bin/env swift
#if canImport(LicenceIssuance)
import Foundation
import CryptoKit
import LicenceIssuance
import CommonCrypto
import CoreImage

// Mint an OpenGlasses organisation profile (Plan CT) — the document hosted at the URL an
// organisation's QR code or enrolment link points at — or a revocation of one.
//
//   make <input.json> <output.txt> [--key-file <path|->] [--key-id <id>]
//       Reads the profile as JSON (fields below), checks it against the app's allow-list and the
//       direction each setting may move, and writes the signed document. Refuses rather than
//       letting the phone drop an entry: an organisation should find out here, not at enrolment.
//   revoke <profileId> <output.txt> [--key-file <path|->] [--key-id <id>]
//       A whole-link revocation: host it at the profile's URL in place of the profile and every
//       phone enrolled from that link erases the organisation's content when it next checks in.
//       To revoke ONE phone on a shared link, add its enrolment id to `revokedEnrolmentIds` in
//       the input and re-`make` the profile instead.
//   keygen <privateKeyFile>
//       One-off: the private half to a 0600 file, the public half printed — it goes in
//       ProfileVerification.productionKeys under a new key id. Never the licence key.
//   admin-card <card.png>
//       Plan CT 3b, once per organisation: a new admin card. The secret goes into the QR in the PNG
//       and nowhere else; the digest printed goes into every profile for that organisation as
//       `adminCard`. A lost or photographed card is a new card and re-minted profiles.
//   make … --admin-passcode
//       Plan CT 3b: prompt (echo off, twice) for the organisation's administrator passcode and
//       carry a PBKDF2 verifier of it — never the passcode — with a fresh salt. At least eight
//       characters and not all digits. Never taken as an argument.
//   make … --issued-at <ISO 8601>
//       A fixed `issued` time, for fixtures; normal minting uses now.
//
// Input fields:
//   profileId, organizationName, leaseDays (7–365)                                    required
//   policyExpiry (ISO 8601), eraseAfterLapseDays, undeliveredEraseDays (1–365),
//   licenceCode, vaultPack {packId, documentsSource}, skillPacks [..],
//   revokedEnrolmentIds [..], settings {<SettingKey>: {value, disposition}},
//   aiModel {provider, model, baseURL, name}  (the provider and model only — never a key),
//   edition ("fieldAssist"), adminCard (the digest `admin-card` printed),
//   lockdown {open: [category], lock: [category], closedTools: [tool]} (with an edition only;
//     categories as in `settingsCategoryIds` below — everything not pinned open or opened is
//     locked on the technician's phone),
//   officeAuthority {organizationID, administratorPublicKey, transportPolicy}              optional
//   officeAuthority emits schema 2. Older profiles remain schema 1. `transportPolicy` is
//   `privateLan` or `automatic`; it is never a relay URL or a private key.
//
// The signature covers "openglasses.org-profile.v1\n" (or "…org-revocation.v1\n") followed by the
// payload bytes, which are shipped as-is — so the encoding here only has to be valid, not
// canonical. The structs, the allow-list and the directions are LicenceIssuance's ProfileContract.
//
// The private key is read from a FILE (or stdin with `--key-file -`), else from
// secrets/org-profile-signing-key.txt (gitignored), and never taken as an argument.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - The profile contract

// The structs, the allow-list and the directions live in LicenceIssuance's ProfileContract, shared with
// preset-built profiles (Plan JS P0b) so both produce the same bytes. They must stay identical to
// ConfigProfile, ProfileRevocation and SettingKey in the app (OpenGlasses/Sources/Services/OrgProfile).
typealias PasscodeVerifier = ProfileContract.PasscodeVerifier
typealias Input = ProfileContract.Input

/// Mirrors AdminSecrets in the app (OpenGlasses/Sources/Services/OrgProfile/AdminSecrets.swift).
enum AdminSecrets {
    static let iterations = 210_000
    static let cardPrefix = "og-admin:"
    static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func pbkdf2(_ passcode: String, salt: Data, iterations: Int) -> Data {
        let password = Data(passcode.utf8)
        var derived = Data(count: 32)
        let status: Int32 = derived.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                                         saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                         out.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == Int32(kCCSuccess) else { fail("error: PBKDF2 failed") }
        return derived
    }

    static func verifier(for passcode: String) -> PasscodeVerifier {
        var generator = SystemRandomNumberGenerator()
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let hash = pbkdf2(passcode, salt: salt, iterations: iterations)
        return PasscodeVerifier(salt: salt.base64EncodedString(), iterations: iterations,
                                hash: hash.base64EncodedString())
    }

    /// 26 Crockford characters: 130 random bits.
    static func newCardSecret() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<26).map { _ in crockford[Int.random(in: 0..<32, using: &generator)] })
    }

    static func cardDigest(secret: String) -> String {
        SHA256.hash(data: Data(("openglasses.admin-card.v1\n" + secret).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// Read a passcode from the terminal with echo off, twice, and hold it to the app's floor.
func promptPasscode() -> String {
    guard let first = getpass("Administrator passcode: ").map({ String(cString: $0) }),
          let second = getpass("Again: ").map({ String(cString: $0) }) else {
        fail("error: could not read the passcode from the terminal")
    }
    guard first == second else { fail("error: the two entries differ") }
    guard first.count >= 8 else { fail("error: the passcode must be at least eight characters") }
    guard !first.allSatisfy({ $0.isNumber }) else { fail("error: the passcode must not be all digits") }
    return first
}

struct ProfileRevocation: Codable {
    let format: String
    let keyId: String
    let profileId: String
    let issued: Date
}

func check(_ input: Input) {
    do { try ProfileContract.check(input, adminPasscode: adminPasscodeRequested, now: Date()) }
    catch let invalid as ProfileContract.Invalid { fail("error: " + invalid.message) }
    catch { fail("error: \(error)") }
}

// MARK: - Keys

/// Refuse a private key handed in on the command line, whatever its position (W06.4). An argument
/// is rejected only if it is not an existing path and decodes from base64 to exactly 32 bytes;
/// nothing about it is echoed.
func refuseInlineKey(_ arguments: [String]) {
    let base64Alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
    for argument in arguments.dropFirst() {
        guard argument.count >= 40,
              !FileManager.default.fileExists(atPath: argument),
              argument.allSatisfy({ base64Alphabet.contains($0) }),
              let decoded = Data(base64Encoded: argument),
              decoded.count == 32 else { continue }
        fail("""
        error: a private key was passed on the command line. Refusing to use it.

          Command-line arguments are visible in `ps`, recorded in shell history, printed by CI
          logs and captured in crash reports. Treat that key as compromised: mint a new one with
          `keygen`, add its public half under a new key id, and re-issue every profile.

          Pass a file instead: --key-file <path>, or --key-file - to read it from stdin.
        """)
    }
}

func readKey(_ path: String?) -> Curve25519.Signing.PrivateKey {
    let text: String
    if path == "-" {
        text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    } else {
        let scriptDir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        let candidates = path.map { [$0] } ?? [
            scriptDir.deletingLastPathComponent().appendingPathComponent("secrets/org-profile-signing-key.txt").path,
            FileManager.default.currentDirectoryPath + "/secrets/org-profile-signing-key.txt",
        ]
        guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let contents = try? String(contentsOfFile: found, encoding: .utf8) else {
            fail("error: no signing key. Pass --key-file <path>, or put it at secrets/org-profile-signing-key.txt")
        }
        if let mode = (try? FileManager.default.attributesOfItem(atPath: found)[.posixPermissions]) as? NSNumber,
           mode.intValue & 0o077 != 0 {
            FileHandle.standardError.write(Data("warning: \(found) is readable beyond its owner. Run: chmod 600 \(found)\n".utf8))
        }
        text = contents
    }
    // First non-comment, non-empty line: the key files `keygen` writes carry a comment header.
    guard let line = text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
          let data = Data(base64Encoded: line),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
        fail("error: the key file does not hold a Curve25519 private key")
    }
    return key
}

func sign(_ payload: Data, domain: String, key: Curve25519.Signing.PrivateKey) -> String {
    guard let document = try? IssuanceWire.sign(payload, domain: domain, signer: key.signature(for:)) else { fail("error: signing failed") }
    return document
}

let encoder = IssuanceWire.encoder(profile: true)

/// Whole seconds, so what is signed reads back as exactly what was shown.
func now() -> Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }

// MARK: - Main

let arguments = CommandLine.arguments
refuseInlineKey(arguments)

var positional: [String] = []
var keyFile: String?
var keyId = "og-profile-2026-09"
var adminPasscodeRequested = false
var issuedAt: Date?
var iterator = arguments.dropFirst().makeIterator()
while let argument = iterator.next() {
    switch argument {
    case "--admin-passcode":
        adminPasscodeRequested = true
    case "--key-file":
        guard let path = iterator.next() else { fail("error: --key-file needs a path") }
        keyFile = path
    case "--issued-at":
        guard let text = iterator.next(), let date = ISO8601DateFormatter().date(from: text) else { fail("error: --issued-at needs an ISO 8601 time") }
        issuedAt = date
    case "--key-id":
        guard let id = iterator.next() else { fail("error: --key-id needs a value") }
        keyId = id
    default: positional.append(argument)
    }
}

let usage = """
usage: make-org-profile.swift make <input.json> <output.txt> [--key-file <path|->] [--key-id <id>] [--admin-passcode] [--issued-at <ISO 8601>]
       make-org-profile.swift admin-card <card.png>
       make-org-profile.swift revoke <profileId> <output.txt> [--key-file <path|->] [--key-id <id>]
       make-org-profile.swift keygen <privateKeyFile>
"""

switch positional.first ?? "" {
case "keygen":
    guard positional.count == 2 else { fail(usage) }
    let path = positional[1]
    guard !FileManager.default.fileExists(atPath: path) else {
        fail("\(path) already exists — refusing to overwrite an existing key. Move it aside first.")
    }
    let key = Curve25519.Signing.PrivateKey()
    let contents = """
    # OpenGlasses organisation-profile signing key (Plan CT). Not the licence key.
    # Curve25519 signing PRIVATE key (base64, raw representation).
    # Generated \(ISO8601DateFormatter().string(from: Date())).
    # Vendor secret: never commit it, never paste it into a terminal, a chat, or a log.
    \(key.rawRepresentation.base64EncodedString())

    """
    guard FileManager.default.createFile(atPath: path, contents: Data(contents.utf8),
                                         attributes: [.posixPermissions: 0o600]) else {
        fail("could not write \(path)")
    }
    print("private key written (mode 0600): \(path)")
    print("public  (embed in app under a new key id):  \(key.publicKey.rawRepresentation.base64EncodedString())")

case "admin-card":
    guard positional.count == 2 else { fail(usage) }
    let path = positional[1]
    guard !FileManager.default.fileExists(atPath: path) else {
        fail("\(path) already exists — refusing to overwrite another card")
    }
    let secret = AdminSecrets.newCardSecret()
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { fail("error: no QR generator") }
    filter.setValue(Data((AdminSecrets.cardPrefix + secret).utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let qr = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        fail("error: could not render the card")
    }
    do {
        try CIContext().writePNGRepresentation(of: qr, to: URL(fileURLWithPath: path),
                                               format: .RGBA8, colorSpace: colorSpace)
    } catch {
        fail("error: could not write \(path): \(error)")
    }
    print("admin card written: \(path)")
    print("adminCard (put this in every profile for the organisation): \(AdminSecrets.cardDigest(secret: secret))")
    FileHandle.standardError.write(Data("""
    The card's secret is in the PNG and nowhere else. Print it or send it to the administrator,
    then delete the file. A lost or photographed card is a new card and re-minted profiles.

    """.utf8))

case "make":
    guard positional.count == 3 else { fail(usage) }
    guard let raw = FileManager.default.contents(atPath: positional[1]) else { fail("error: cannot read \(positional[1])") }
    let input: Input
    do { input = try JSONDecoder().decode(Input.self, from: raw) } catch { fail("error: the input is not a profile: \(error)") }
    check(input)
    let key = readKey(keyFile)
    let profile = ProfileContract.document(input, keyId: keyId, issued: issuedAt ?? now(),
        adminPasscode: adminPasscodeRequested ? AdminSecrets.verifier(for: promptPasscode()) : nil)
    guard let payload = try? encoder.encode(profile) else { fail("error: could not encode the profile") }
    let document = sign(payload, domain: "openglasses.org-profile.v1\n", key: key)
    guard FileManager.default.createFile(atPath: positional[2], contents: Data((document + "\n").utf8)) else {
        fail("error: could not write \(positional[2])")
    }
    FileHandle.standardError.write(payload + Data("\n".utf8))
    print(input.officeAuthority == nil
        ? "profile written: \(positional[2]) — use the existing profile URL or link"
        : "office-capable profile written: \(positional[2]) — signed inline delivery is supported; no hosting URL is required")

case "revoke":
    guard positional.count == 3 else { fail(usage) }
    let key = readKey(keyFile)
    let revocation = ProfileRevocation(format: "openglasses.org-revocation", keyId: keyId,
                                       profileId: positional[1], issued: now())
    guard let payload = try? encoder.encode(revocation) else { fail("error: could not encode the revocation") }
    let document = sign(payload, domain: "openglasses.org-revocation.v1\n", key: key)
    guard FileManager.default.createFile(atPath: positional[2], contents: Data((document + "\n").utf8)) else {
        fail("error: could not write \(positional[2])")
    }
    print("revocation written: \(positional[2]) — host it at the profile's URL in place of the profile")

default:
    fail(usage)
}

#else
import Foundation
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", "run", "--quiet", "--package-path", repo.appendingPathComponent("Tools/LicenceIssuance").path, "make-org-profile"] + CommandLine.arguments.dropFirst()
process.standardInput = FileHandle.standardInput
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
#endif
