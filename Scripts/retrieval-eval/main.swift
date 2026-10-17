import Foundation
import NaturalLanguage

// The local retrieval eval on a Mac, on the device's embedding model. Compiled by run.sh with the
// app's own DocumentStore, DocumentChunker and VaultRetriever and the shared eval core in
// OpenGlassesTests/RetrievalEval, so what it measures is what the app ships. See README.md.

@main
struct RetrievalEvalMain {
    @MainActor
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let vaultPath = env["RETRIEVAL_EVAL_VAULT"], let keyPath = env["RETRIEVAL_EVAL_ANSWER_KEY"] else {
            fail("set RETRIEVAL_EVAL_VAULT (a vault folder) and RETRIEVAL_EVAL_ANSWER_KEY (a JSON-lines file)")
        }
        let vault = URL(fileURLWithPath: vaultPath, isDirectory: true)
        guard let keyText = try? String(contentsOfFile: keyPath, encoding: .utf8) else { fail("can't read the answer key") }
        let questions = RetrievalEval.loadAnswerKey(keyText)
        guard !questions.isEmpty else { fail("the answer key has no questions") }

        let embedder = Embedder()
        guard embedder.isAvailable else { fail("no NaturalLanguage embedding model on this Mac") }

        // The store lives in a work folder the developer names (and deletes), so a long document is
        // embedded once, not on every run. Never inside the repository.
        let work = URL(fileURLWithPath: env["RETRIEVAL_EVAL_WORKDIR"]
                       ?? NSTemporaryDirectory() + "retrieval-eval-store", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let store = DocumentStore(directory: work)

        for document in manifestDocuments(in: vault) {
            if store.document(named: document.title) != nil { continue }
            let file = document.url
            guard ["md", "txt"].contains(file.pathExtension.lowercased()) else {
                fail("\(file.lastPathComponent): the Mac runner reads extracted text — run "
                     + "Scripts/extract-manual-text.swift on the PDF and list the .md in the manifest")
            }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { fail("can't read \(file.lastPathComponent)") }
            FileHandle.standardError.write("indexing document \(store.documents.count + 1)…\n".data(using: .utf8)!)
            _ = await store.ingest(name: document.title, text: text, sourceType: "vault_document")
        }

        let policy = RetrievalEvidencePolicy.default(for: embedder.modelId)
        let report = RetrievalEval.run(questions,
                                       gated: RetrievalEval.retriever(over: store, policy: policy),
                                       open: RetrievalEval.retriever(over: store, policy: RetrievalEvidencePolicy(similarityFloor: 0)),
                                       store: store)
        for line in report.lines(label: env["RETRIEVAL_EVAL_LABEL"] ?? "local vault", embedder: embedder.modelId) {
            print(line)
        }
    }

    struct Document { let title: String; let url: URL }

    /// The manifest's documents, read with only the fields this needs.
    static func manifestDocuments(in vault: URL) -> [Document] {
        struct Manifest: Decodable {
            struct Entry: Decodable { let file: String; let title: String }
            let documents: [Entry]?
            let documents_dir: String?
        }
        guard let data = try? Data(contentsOf: vault.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            fail("no readable manifest.json in the vault folder")
        }
        let dir = manifest.documents_dir.map { vault.appendingPathComponent($0, isDirectory: true) } ?? vault
        return (manifest.documents ?? []).map { Document(title: $0.title, url: dir.appendingPathComponent($0.file)) }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write("retrieval-eval: \(message)\n".data(using: .utf8)!)
        exit(1)
    }
}
