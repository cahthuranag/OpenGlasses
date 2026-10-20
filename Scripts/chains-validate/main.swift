import Foundation
import PDFKit

// A vault's chains.md checked against the tables its own PDFs print, on a Mac, reading each PDF as
// an import on the phone does (`PDFTableReader`, `TableExtractor`) and the chains as the import
// does (`ChainParser`). Prints counts, line numbers and kinds, and names only from the chains file
// — never a table's title, a heading, a cell or a document's name. See README.md.

@main
struct ChainsValidateRunner {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let vaultPath = arguments.first else {
            FileHandle.standardError.write(Data("usage: chains-validate <vault folder> [chains.md]\n".utf8))
            exit(2)
        }
        let environment = ProcessInfo.processInfo.environment
        let names = environment["CHAINS_VALIDATE_NAMES"] != "0"
        let vault = URL(fileURLWithPath: vaultPath, isDirectory: true)

        // The manifest: the files it lists, and where its documents are.
        var listed: [String]?
        var documents: [(file: String, source: String?)] = []
        var documentsDir: String?
        if let data = try? Data(contentsOf: vault.appendingPathComponent("manifest.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            listed = json["files"] as? [String] ?? []
            documentsDir = json["documents_dir"] as? String
            for entry in json["documents"] as? [[String: Any]] ?? [] {
                guard let file = entry["file"] as? String else { continue }
                documents.append((file, entry["source"] as? String))
            }
        }

        // The chains file: the one given, else the one the manifest lists, else chains.md.
        let chainsURL: URL
        if arguments.count > 1 {
            chainsURL = URL(fileURLWithPath: arguments[1])
        } else if let file = listed?.first(where: VaultChains.isChainsFile) {
            chainsURL = vault.appendingPathComponent(file)
        } else {
            chainsURL = vault.appendingPathComponent(VaultChains.fileName)
        }
        guard let contents = try? String(contentsOf: chainsURL, encoding: .utf8) else {
            print("[CHAINS] the chains file could not be read")
            exit(1)
        }

        // The tables: every listed document that is a PDF, or whose original is; with no manifest,
        // every PDF in the folder.
        var pdfs: [URL] = []
        if listed != nil {
            let base = documentsDir.map { vault.appendingPathComponent($0, isDirectory: true) } ?? vault
            for document in documents {
                let url = base.appendingPathComponent(document.file)
                if url.pathExtension.lowercased() == "pdf" { pdfs.append(url); continue }
                if let source = document.source, source.lowercased().hasSuffix(".pdf") {
                    pdfs.append(base.appendingPathComponent(source))
                }
            }
        } else if let walker = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil) {
            for case let url as URL in walker where url.pathExtension.lowercased() == "pdf" { pdfs.append(url) }
        }
        var tables: [ManualTable] = []
        var unreadable = 0
        let started = Date()
        for pdf in pdfs {
            guard let result = PDFTableReader.read(url: pdf) else { unreadable += 1; continue }
            tables += result.stored
        }
        print(String(format: "[CHAINS] documents=%d pdfs_read=%d unreadable=%d seconds=%.1f",
                     documents.count, pdfs.count - unreadable, unreadable, Date().timeIntervalSince(started)))

        let report = ChainsValidate.check(.init(fileName: chainsURL.lastPathComponent, contents: contents,
                                                listedFiles: listed, tables: tables))
        for line in ChainsValidate.render(report, names: names) { print(line) }
    }
}
