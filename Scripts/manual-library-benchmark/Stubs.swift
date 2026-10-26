import Foundation

// Same core extractor/store/embedder sources as the app. Only preference access and telemetry
// are adapted. No manual text, titles, tables, query answers or original file paths are logged.
enum Config {
    static var contextualEmbeddingEnabled: Bool { false }
    static var fieldAssistContextualSearchEnabled: Bool { !CommandLine.arguments.contains("--standard") }
}
struct PrivacyToken { init(_ value: String) {} }
struct SafeErrorSummary { init(_ error: Error) {} }
enum PrivacyLog {
    enum Vision { case ocr }
    enum VisionEvent { case recognitionFailed }
    static func vision(_ source: Vision, _ event: VisionEvent, error: SafeErrorSummary) {}
    enum Store { case ragDocuments }
    enum Event { case opened, ingested, cleared, reembedded, openFailed, indexed, queryEmbedded, saveSkipped, saveFailed, dropped }
    enum Failure { case sqlite(code: Int32, extended: Int32) }
    static func store(_ store: Store, _ event: Event, count: Int? = nil, total: Int? = nil, characters: Int? = nil,
                      error: Failure? = nil, detail: PrivacyToken? = nil, durationMs: Int? = nil) {}
}
