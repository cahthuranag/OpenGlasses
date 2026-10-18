import Foundation

// The four app types the retrieval sources reach that a command-line build doesn't need: the
// logging and file-protection calls become no-ops, and the contextual-embedding switch is read
// from the environment (RETRIEVAL_EVAL_EMBEDDER=contextual) instead of the app's settings.

enum ManualStructure { static let diagramMarker = "<!-- page: diagram -->" }

enum Config {
    static var contextualEmbeddingEnabled: Bool {
        ProcessInfo.processInfo.environment["RETRIEVAL_EVAL_EMBEDDER"] == "contextual"
    }
    static var fieldAssistContextualSearchEnabled: Bool { contextualEmbeddingEnabled }
}

enum StoreProtection { static func applyDatabase(at url: URL) {} }

struct PrivacyToken { init(_ value: String) {} }

enum PrivacyLog {
    enum Store { case ragDocuments }
    enum Event { case opened, ingested, cleared, reembedded, openFailed, indexed, queryEmbedded }
    enum Failure { case sqlite(code: Int32, extended: Int32) }
    static func store(_ store: Store, _ event: Event, count: Int? = nil, total: Int? = nil, characters: Int? = nil,
                      error: Failure? = nil, detail: PrivacyToken? = nil, durationMs: Int? = nil) {}
}
