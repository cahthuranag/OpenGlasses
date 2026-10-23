#if DEBUG
import Foundation

/// Only -OGUITest plus -UITestWorkizFixture can select this transport. Shared fixture files,
/// a memory-only key and no network, including error, offline and ambiguous-note states.
@MainActor
final class WorkizFixtureTransport: WorkizTransport {
    static var state: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-UITestWorkizState"), index + 1 < args.count else { return "connected" }
        return args[index + 1]
    }
    static func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: "workiz-" + name, withExtension: "json", subdirectory: "workiz-v2") else { throw WorkizFailure.malformed }
        return try Data(contentsOf: url)
    }
    static func seed(_ app: AppState) {
        guard let first = try? fixture("jobs-page"), let last = try? fixture("jobs-last"),
              let jobs = try? WorkizAPI.page(first, decode: WorkizAPI.job).data + WorkizAPI.page(last, decode: WorkizAPI.job).data else { return }
        let now = Date(); let zone = app.workizConnection.timeZone
        let mapped = jobs.prefix(3).map { WorkizJobMapper.map($0, technicianID: "USR-jamie", now: now, timeZone: zone) }
        app.upcomingJobs.reconcileWorkiz(mapped, at: now.addingTimeInterval(-3600), notice: "Job 1237 was cancelled in Workiz.")
        if state == "offline" { return }
        if state.hasPrefix("closed-") || state == "started" {
            guard let first = mapped.first, let session = try? app.guidedJobFlow.startUpcomingJob(id: first.id) else { return }
            if state == "started" { return }
            _ = try? FieldSessionService.shared.addOperatorTask(title: "Checked fridge cooling", why: "Fixture visit")
            guard let closed = try? app.guidedJobFlow.closeJob() else { return }
            let record = WorkRecord(session: closed, vaultName: "Fixture")
            if let report = WorkizWriteBack.report(record) {
                var delivery = WorkizDelivery(report: report)
                let opState: OpState
                switch state {
                case "closed-sent": delivery.status = "Sent to Workiz"; delivery.fieldWritten = true; opState = .done
                case "closed-attention": delivery.status = "Needs attention — the Workiz key can't write Jobs. Ask the owner to give it Jobs: Read & Write."; opState = .failed
                default: delivery.status = "Waiting for a connection"; delivery.retryAfter = Date().addingTimeInterval(3600); opState = .pending
                }
                if let data = try? JSONEncoder().encode(delivery) {
                    app.offlineQueue.enqueue(QueuedOp(id: "workiz-ui-delivery", kind: .workizReport, sessionId: session.id, payload: data, state: opState))
                }
            }
            app.workizSink.reloadStatuses()
        }
    }
    func cancel() {}
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if Self.state == "testing" { try await Task.sleep(for: .seconds(2)) }
        if Self.state == "offline" { throw WorkizFailure.offline }
        if Self.state == "wrong-key" { return (try Self.fixture("error-401"), 401) }
        if Self.state == "permission" { return (try Self.fixture("error-403"), 403) }
        let path = request.url?.path ?? ""
        if path.hasSuffix("/users") { return (try Self.fixture("users"), 200) }
        if path.hasSuffix("/customfields") { return (try Self.fixture("customfields"), 200) }
        if path.hasSuffix("/jobs") {
            let second = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value == "2"
            var root = try WorkizAPI.object(Self.fixture(second ? "jobs-last" : "jobs-page"))
            let day = Calendar.current.startOfDay(for: Date())
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            let today = f.string(from: day)
            root["data"] = WorkizAPI.objects(root["data"]).map { row in
                var row = row
                if let date = row["date"] as? String { row["date"] = date.replacingOccurrences(of: "2026-10-23", with: today) }
                return row
            }
            return (try JSONSerialization.data(withJSONObject: root), 200)
        }
        if path.contains("/jobs/") { return (try Self.fixture("job"), 200) }
        if path.contains("/clients/") { return (try Self.fixture("client-notes"), 200) }
        throw WorkizFailure.malformed
    }
}
#endif
