import Foundation
import PDFKit

// The table lookup scored against a key of cells, on a Mac: the vault's PDFs read as an import on
// the phone reads them (`PDFTableReader`, `TableExtractor`), each question looked up with the app's
// own `TableLookup`, and the counts printed by `TableLookupEval` — never a question, a table's
// label, a row, a column, a cell or a document's name. See README.md.

@main
struct TableLookupEvalRunner {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: table-lookup-eval <vault folder> <key.jsonl>\n".utf8))
            exit(2)
        }
        let environment = ProcessInfo.processInfo.environment
        let label = environment["TABLE_LOOKUP_EVAL_LABEL"] ?? "vault"
        let vault = URL(fileURLWithPath: arguments[0], isDirectory: true)
        guard let key = try? String(contentsOf: URL(fileURLWithPath: arguments[1]), encoding: .utf8) else {
            print("[CELLS] the key could not be read")
            exit(1)
        }

        // The documents: every one the manifest lists that is a PDF or whose original is, with its
        // title; with no manifest, every PDF in the folder.
        var documents: [(url: URL, name: String)] = []
        if let data = try? Data(contentsOf: vault.appendingPathComponent("manifest.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let base = (json["documents_dir"] as? String).map { vault.appendingPathComponent($0, isDirectory: true) } ?? vault
            for entry in json["documents"] as? [[String: Any]] ?? [] {
                guard let file = entry["file"] as? String else { continue }
                let title = entry["title"] as? String ?? file
                let url = base.appendingPathComponent(file)
                if url.pathExtension.lowercased() == "pdf" {
                    documents.append((url, "\(title) \(file)"))
                } else if let source = entry["source"] as? String, source.lowercased().hasSuffix(".pdf") {
                    documents.append((base.appendingPathComponent(source), "\(title) \(source)"))
                }
            }
        } else if let walker = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil) {
            for case let url as URL in walker where url.pathExtension.lowercased() == "pdf" {
                documents.append((url, url.lastPathComponent))
            }
        }

        let started = Date()
        var sources: [TableLookup.Source] = []
        var unreadable = 0
        for (index, document) in documents.enumerated() {
            guard let result = PDFTableReader.read(url: document.url) else { unreadable += 1; continue }
            sources += result.stored.map { TableLookup.Source(documentId: "document-\(index)", documentName: document.name, table: $0) }
        }
        print(String(format: "[CELLS] documents=%d unreadable=%d tables=%d read=%d seconds=%.1f",
                     documents.count, unreadable, sources.count, sources.filter(\.table.isExtracted).count,
                     Date().timeIntervalSince(started)))

        let parsed = TableLookupEval.parseCounting(key)
        var report = TableLookupEval.score(parsed.questions, unreadable: parsed.unreadable.values.reduce(0, +), sources: sources)
        report.unreadableBy = Dictionary(uniqueKeysWithValues: parsed.unreadable.map { ($0.key.rawValue, $0.value) })
        for line in TableLookupEval.render(report, label: label, checked: environment["TABLE_LOOKUP_EVAL_KEY_CHECKED"] == "1") {
            print(line)
        }
    }
}
