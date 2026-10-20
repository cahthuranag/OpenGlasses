import Foundation

/// Gives manuals indexed before passages knew their place on the page (Plan IN P0) the place, on a
/// later launch, without anyone importing anything again.
///
/// The `EmbeddingVersion` pattern for positions: a row whose `location_version` is older than
/// `DocumentStore.locationVersion` is re-read from the vault's own copy of the file and chunked
/// again. When the new chunking is the stored one row for row — the usual case, since the chunker's
/// packing did not change — only the place is written onto the existing rows, so the document id,
/// the chunk text and the embedding are exactly as they were and every ledger entry, citation and
/// page-evidence label that names them still does. When the text no longer chunks the same way
/// (an extractor change since import), the document is re-chunked under the same id.
///
/// A manual any page of which was read by recognition is left as it is: reading it again would
/// mean recognising every scanned page a second time, and a recognised page has no text layer to
/// mark anyway. Its rows keep working; the locator splits their sentences itself.
///
/// **Tables (Plan JJ P0, location version 3).** The same pass reads each document's tables from
/// its PDF — the document itself, or the original a text import was made from, when that is still
/// on the phone — and adds their row passages beside the existing chunks, which are only located,
/// never re-chunked, when their text is unchanged. A document with no PDF has no positions to read
/// tables from; it is located as before and the log says its tables were skipped.
@MainActor
enum PassageLocationMigration {

    enum Outcome: String, Equatable {
        case current
        case located
        case rechunked
        case recognisedSkipped = "recognised_skipped"
        case unreadable
    }

    struct Report: Equatable {
        var located = 0
        var rechunked = 0
        var skipped = 0
    }

    /// Every installed vault, one at a time, each under its own operation lock so an import, a
    /// removal or an uninstall never sees a half-migrated document.
    @discardableResult
    static func run(store: DocumentStore,
                    manifests: [VaultManifest]? = nil) async -> Report {
        var report = Report()
        for manifest in manifests ?? VaultImporter.installedManifests() {
            await VaultOperationLock.withLock(manifest.id) {
                let ledger = VaultImporter.documentLedger(for: manifest.id)
                for entry in ledger.entries {
                    guard let document = manifest.documents.first(where: { $0.file == entry.file }) else { continue }
                    let root = VaultImporter.baselineDirectory(for: manifest.id)
                    let url = root.appendingPathComponent(manifest.documentRelativePath(document))
                    let original = manifest.documentSourceRelativePath(document).map { root.appendingPathComponent($0) }
                    switch await migrate(entry: entry, fileURL: url, originalURL: original, store: store) {
                    case .located: report.located += 1
                    case .rechunked: report.rechunked += 1
                    case .recognisedSkipped, .unreadable: report.skipped += 1
                    case .current: break
                    }
                }
            }
        }
        if report.located + report.rechunked > 0 {
            PrivacyLog.store(.ragDocuments, .migrated, count: report.located,
                             total: report.located + report.rechunked)
        }
        return report
    }

    /// One document. Extraction and chunking run off the main actor; the store is written on it.
    /// `originalURL` is the original a text document was extracted from, when the vault has one.
    static func migrate(entry: VaultDocumentLedger.Entry, fileURL: URL, originalURL: URL? = nil,
                        store: DocumentStore) async -> Outcome {
        guard store.needsLocation(documentId: entry.documentId) else { return .current }
        guard !entry.usedRecognition else { return .recognisedSkipped }
        let tablesPDF = VaultDocumentExtractor.tablesSource(document: fileURL, original: originalURL)
        let read: (chunks: [DocumentChunker.Chunk], labels: [PageLabel], tables: PDFTableReader.Result?)?
            = await Task.detached(priority: .utility) {
            guard let extracted = try? VaultDocumentExtractor.extract(from: fileURL) else { return nil }
            let text = extracted.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (DocumentChunker().chunk(text), extracted.pageLabels,
                    tablesPDF.flatMap { VaultDocumentExtractor.tables(from: $0) })
        }.value
        guard let read, !read.chunks.isEmpty else { return .unreadable }
        store.setPageLabels(read.labels, documentId: entry.documentId)
        let outcome: Outcome
        if store.writeLocations(documentId: entry.documentId, chunks: read.chunks) {
            outcome = .located
        } else if await store.rechunk(documentId: entry.documentId, chunks: read.chunks) {
            outcome = .rechunked
        } else {
            return .unreadable
        }
        var dropped = 0
        if let tables = read.tables {
            dropped = await store.replaceTables(tables.tables, documentId: entry.documentId).rowsDropped
        }
        VaultDocumentExtractor.logTables(read.tables, rowsDropped: dropped)
        return outcome
    }
}
