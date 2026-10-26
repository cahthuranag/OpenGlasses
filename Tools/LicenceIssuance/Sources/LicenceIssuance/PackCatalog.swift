import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto // swift-crypto: the same API on Linux (the service's containers)
#endif

/// A catalog must be vendor-verified before its keys can be used by policy. A partner cannot supply free text.
public struct VerifiedPackCatalog {
    public let keys: Set<String>
    // Fixture seam accessible only under @testable or when compiled into the app's test bundle.
    init(verifiedKeys: Set<String>) { keys = verifiedKeys }
    public struct PackProof: Codable {
        public let manifest: Data
        /// Every file except pack.json, as extracted by VaultPackArchive, including manifest.json.
        public let files: [String: Data]
        public init(manifest: Data, files: [String: Data]) { self.manifest = manifest; self.files = files }
    }
    public struct Proof: Codable {
        public let envelope: Data
        public let packsById: [String: PackProof]
        public init(envelope: Data, packsById: [String: PackProof]) { self.envelope = envelope; self.packsById = packsById }
    }
    public enum Refusal: Error { case invalidCatalog, invalidPack }
    /// Same envelope and per-pack signing message as the deployed VaultPackCatalog / VaultPackSignature.
    public static func verify(_ proof: Proof, publicKeyBase64: String) throws -> VerifiedPackCatalog {
        struct Envelope: Decodable { let payload: Data; let signature: Data }
        struct Entry: Decodable { let id: String; let vaultId: String; let version: String; let packSignature: Data }
        struct Index: Decodable { let version: Int; let packs: [Entry] }
        struct Manifest: Decodable { let id: String; let vaultId: String; let version: String; let licensePack: String? }
        guard let keyData = Data(base64Encoded: publicKeyBase64), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: proof.envelope),
              key.isValidSignature(envelope.signature, for: envelope.payload),
              let index = try? JSONDecoder().decode(Index.self, from: envelope.payload), index.version == 1,
              Set(index.packs.map(\.id)).count == index.packs.count else { throw Refusal.invalidCatalog }
        var keys = Set<String>()
        for entry in index.packs {
            guard let pack = proof.packsById[entry.id], pack.files["manifest.json"] != nil,
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: pack.manifest),
                  manifest.id == entry.id, manifest.vaultId == entry.vaultId, manifest.version == entry.version else { throw Refusal.invalidPack }
            var message = pack.manifest
            for path in pack.files.keys.sorted() {
                message.append(Data("\nsha256(\(path))=\(IssuanceWire.digest(pack.files[path]!))".utf8))
            }
            guard key.isValidSignature(entry.packSignature, for: message) else { throw Refusal.invalidPack }
            let packKey = manifest.licensePack ?? manifest.vaultId
            guard !packKey.isEmpty else { throw Refusal.invalidPack }
            keys.insert(packKey)
        }
        return VerifiedPackCatalog(verifiedKeys: keys)
    }
}
