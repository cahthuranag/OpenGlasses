import Foundation

/// A code book opens on request, never by itself (Plan IN decision 1).
///
/// The partner's electrician keeps the phone in a pocket and the spoken answer with its clause is
/// usually enough; he asks for the page when he wants to check it. A manual keeps today's diagram
/// auto-open — a wiring diagram is the answer to a wiring question — but a document the vault
/// marks as a `standard` is put on screen only through its citation (`show_source`), whatever kind
/// of passage it is and whatever the turn's wording. A spoken "show me the page" in Direct mode is
/// classified as a request too, and it is still not the automatic path's to answer: that path
/// would open whatever the words "show me the page" retrieved, where `show_source` opens what the
/// last answer cited (decision 2).
enum StandardDocumentOpenPolicy {

    /// The manifest kind that marks a code or standard. Matched without regard to case; the field
    /// is free text an author writes.
    static let standardKind = "standard"

    static func isStandard(_ documentKind: String?) -> Bool {
        documentKind?.trimmingCharacters(in: .whitespaces).lowercased() == standardKind
    }

    /// Whether the automatic path must leave this document's page closed.
    static func keepsToRequest(documentKind: String?) -> Bool { isStandard(documentKind) }

    /// The manifest kind of the document a passage came from, through the ledger that recorded
    /// which file it was ingested from.
    static func documentKind(of documentId: String, in manifest: VaultManifest) -> String? {
        guard let file = VaultImporter.documentLedger(for: manifest.id).entries
            .first(where: { $0.documentId == documentId })?.file else { return nil }
        return manifest.documents.first { $0.file == file }?.kind
    }
}
