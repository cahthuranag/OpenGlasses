import SwiftUI

@main
struct JQBenchmarkApp: App {
    @State private var status = "Measuring synthetic diagnostic histories…"
    var body: some Scene {
        WindowGroup {
            Text(status).padding().task {
                UIApplication.shared.isIdleTimerDisabled = true
                defer { UIApplication.shared.isIdleTimerDisabled = false }
                do {
                    print("JQ_BENCHMARK_START")
                    let result = try await Task.detached { try benchmark() }.value
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
                    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url)
                    status = "Benchmark complete. Synthetic data only."
                    print("JQ_BENCHMARK_COMPLETE")
                } catch {
                    status = "Benchmark failed: \(error)"
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("error.txt")
                    try? status.write(to: url, atomically: true, encoding: .utf8)
                    print(status)
                }
            }
        }
    }
}

func benchmark() throws -> [[String: Any]] {
    let now = Date()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("JQBenchmark")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var results: [[String: Any]] = []
    for capacity in [2000, 14000] {
        for multiplier in [1, 2] {
            let count = capacity * multiplier
            for length in [100, 300] {
                let url = folder.appendingPathComponent("events.json")
                let line = "[app] app event=completed duration_ms=125 count=1 outcome=success "
                let entries = (0..<count).map { index in
                    DiagnosticRing.Entry(timestamp: now.addingTimeInterval(-Double(count-index)), category: .app,
                        name: .app, line: line + String(repeating: "x", count: max(0, length-line.count)),
                        run: String(format: "%08x", index / 2000))
                }
                let store = DiagnosticBreadcrumbStore(url: url, writeDelay: 0)
                store.schedule(entries)
                store.waitForPendingWrites()
                let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize!
                var times: [Double] = []
                for _ in 0..<9 {
                    let started = DispatchTime.now().uptimeNanoseconds
                    let ring = DiagnosticRing(capacity: capacity, clock: { now }, persistenceURL: url)
                    guard ring.previousEntries.count == capacity else {
                        throw NSError(domain: "benchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Count mismatch"])
                    }
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                }
                let sorted = times.sorted()
                results.append(["capacity": capacity, "persistedEntries": count, "lineCharacters": length,
                    "bytes": bytes, "firstLoadMilliseconds": times[0], "medianMilliseconds": sorted[4],
                    "maximumMilliseconds": sorted.last!, "samples": times])
            }
        }
    }
    try? FileManager.default.removeItem(at: folder)
    return results
}
