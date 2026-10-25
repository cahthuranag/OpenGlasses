import Darwin
import PDFKit
import SwiftUI

@main
struct ManualLibraryBenchmarkApp: App {
    @State private var status = "Preparing private manual benchmark…"
    @State private var started = false
    var body: some Scene {
        WindowGroup {
            Text(status).padding().task {
                guard !started else { return }; started = true
                UIApplication.shared.isIdleTimerDisabled = true
                defer { UIApplication.shared.isIdleTimerDisabled = false }
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try await runBenchmark { stage in await MainActor.run { status = stage } }
                    }.value
                    status = "Measurement complete. Counts and timings saved; no manual content in the results."
                } catch { status = "Benchmark stopped: \(error.localizedDescription)" }
            }
        }
    }
}

private func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}

private func runBenchmark(progress: @escaping @Sendable (String) async -> Void) async throws {
    let fm = FileManager.default
    let root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let inputs = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        .filter { $0.pathExtension.lowercased() == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !inputs.isEmpty else { throw NSError(domain: "ManualBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Copy fixture PDFs into the benchmark app's Documents directory and launch again."]) }
    let work = root.appendingPathComponent("index")
    try? fm.removeItem(at: work)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    let store = await DocumentStore(directory: work)
    var rows: [[String: Any]] = []
    func persist(_ row: [String: Any]) throws {
        let result: [String: Any] = ["environment": "physical iPhone; app extraction, OCR, chunking and embedding cores; telemetry adapted",
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
            "fieldContextualPreference": Config.fieldAssistContextualSearchEnabled,
            "completed": rows, "current": row]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("results.json"), options: .atomic)
    }
    for (index, input) in inputs.enumerated() {
        let started = Date()
        var row: [String: Any] = ["fixture": index + 1,
            "inputBytes": try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
            "residentBeforeBytes": residentBytes(), "thermalBefore": ProcessInfo.processInfo.thermalState.rawValue]
        guard let pdf = PDFDocument(url: input), !pdf.isLocked else { throw NSError(domain: "ManualBenchmark", code: 2) }
        row["pages"] = pdf.pageCount
        row["stage"] = "extracting"
        try persist(row)
        await progress("Extracting manual \(index + 1) of \(inputs.count) (\(pdf.pageCount) pages)…")
        let extracted = try await VaultDocumentExtractor.extract(from: input, reader: VisionScannedPageReader())
        row["extractionSeconds"] = Date().timeIntervalSince(started)
        row["characters"] = extracted.text.count
        row["ocrPages"] = extracted.ocrPages
        row["lowConfidencePages"] = extracted.lowConfidencePages
        row["residentAfterExtractionBytes"] = residentBytes()
        row["stage"] = "reading_tables"
        try persist(row)
        await progress("Reading the tables in manual \(index + 1)…")
        let tablesStart = Date()
        let tables = await VaultDocumentExtractor.tables(from: input, pictures:
            PictureTableReading.context(VisionTableReader(), checkpointIn: work.appendingPathComponent("tables-\(index)"), contentHash: "fixture-\(index)"))
        row["tableSeconds"] = Date().timeIntervalSince(tablesStart)
        row["tables"] = tables?.extracted ?? 0
        row["recognisedTables"] = tables?.recognised ?? 0
        row["residentAfterTablesBytes"] = residentBytes()
        row["stage"] = "embedding"
        try persist(row)
        await progress("Indexing manual \(index + 1)…")
        let embeddingStart = Date()
        let document = await store.ingest(name: "Fixture \(index + 1)", text: extracted.text,
            sourceType: "vault_document", namespace: "vault:benchmark-\(index)", pageLabels: extracted.pageLabels,
            tables: tables?.stored ?? [])
        row["embeddingSeconds"] = Date().timeIntervalSince(embeddingStart)
        row["chunks"] = document?.chunkCount ?? 0
        let queryStart = Date()
        row["retrievedPassages"] = await store.query("engine oil drain plug tightening torque", namespace: "vault:benchmark-\(index)").count
        row["querySeconds"] = Date().timeIntervalSince(queryStart)
        row["totalSeconds"] = Date().timeIntervalSince(started)
        row["residentAfterIndexBytes"] = residentBytes()
        row["thermalAfter"] = ProcessInfo.processInfo.thermalState.rawValue
        row["indexBytes"] = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: [.fileSizeKey])
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        row["stage"] = "complete"
        rows.append(row)
        try persist(["stage": "between_fixtures"])
    }
    try persist(["stage": "complete"])
}
