import Foundation

// Kept apart from both types on purpose: the manual-contract check compiles `VaultManifest.swift`
// without `DocumentEditions.swift`, and the retrieval-eval runner compiles `DocumentEditions.swift`
// without the manifest. A bridge in either file breaks the other build.
extension DocumentEditions {
    /// The editions among a manifest's documents (Plan IV P2).
    init(documents: [VaultDocument]) {
        self.init(entries: documents.map { (title: $0.title, kind: $0.kind, edition: $0.edition) })
    }
}
