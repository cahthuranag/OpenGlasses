import Foundation
import Combine

struct WorkizDelivery: Codable {
    let report: WorkizWriteBack.Report
    var fieldWritten = false
    var endedForOffice = false
    var noteAttempted = false
    var noteID: String?
    var blockedGeneration: String?
    var retryAfter: Date?
    var status = "Waiting for a connection"
}

/// The durable queue owns progress as well as payload: a crash after a POST was attempted never
/// causes a second POST. Recovery scans all bounded client-note pages for the report's marker.
@MainActor
final class WorkizSyncSink: SyncSink, ObservableObject {
    @Published private(set) var statuses: [String: String] = [:]
    static let officeHandover = "Not sent to Workiz — your office posts reports now"
    private let queue: OfflineQueue
    private let connection: WorkizConnection
    private let client: WorkizAPIClient
    private let fallback: SyncSink
    private let now: () -> Date
    private let retry: (Date) -> Void
    init(queue: OfflineQueue, connection: WorkizConnection, client: WorkizAPIClient, fallback: SyncSink, now: @escaping () -> Date = Date.init, retry: @escaping (Date) -> Void = { _ in }) {
        self.queue = queue; self.connection = connection; self.client = client; self.fallback = fallback; self.now = now; self.retry = retry
        reloadStatuses()
    }
    func reloadStatuses() {
        for op in queue.all(limit: 100_000).reversed() where op.kind == .workizReport {
            if let delivery = try? JSONDecoder().decode(WorkizDelivery.self, from: op.payload) { statuses[op.sessionId] = delivery.status }
        }
    }
    func enqueue(_ record: WorkRecord) {
        guard connection.isRunning, let report = WorkizWriteBack.report(record, fieldName: connection.fieldName, clientNote: connection.clientNotes) else { return }
        let id = "workiz:" + record.sessionId + ":" + report.marker
        if let existing = queue.all(limit: 100_000).first(where: { $0.id == id }) {
            guard existing.state == .failed, var delivery = try? JSONDecoder().decode(WorkizDelivery.self, from: existing.payload), !delivery.endedForOffice else { return }
            delivery.retryAfter = nil; delivery.status = "Waiting for a connection"
            if save(delivery, op: existing) { queue.mark(id, state: .pending, attempts: 0) }
            return
        }
        let payload = WorkizDelivery(report: report)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        queue.enqueue(QueuedOp(id: "workiz:" + record.sessionId + ":" + report.marker, kind: .workizReport, sessionId: record.sessionId, payload: data))
        statuses[record.sessionId] = payload.status
    }
    func endForOffice() {
        for op in queue.all(limit: 100_000) where op.kind == .workizReport && op.state != .done {
            guard var delivery = try? JSONDecoder().decode(WorkizDelivery.self, from: op.payload) else { continue }
            delivery.endedForOffice = true; delivery.status = Self.officeHandover; save(delivery, op: op); queue.mark(op.id, state: .failed)
        }
    }
    func status(sessionID: String) -> String? {
        statuses[sessionID]
    }
    @discardableResult
    private func save(_ value: WorkizDelivery, op: QueuedOp) -> Bool {
        guard let data = try? JSONEncoder().encode(value), queue.replacePayload(op.id, data: data) else { return false }
        statuses[op.sessionId] = value.status; return true
    }
    func deliveryExhausted(_ op: QueuedOp) {
        guard op.kind == .workizReport,
              let latest = queue.all(limit: 100_000).first(where: { $0.id == op.id }),
              var delivery = try? JSONDecoder().decode(WorkizDelivery.self, from: latest.payload) else { return }
        delivery.status = "Needs attention — Workiz is still unavailable. Try again from Sync status."
        save(delivery, op: op)
    }
    func deliver(_ op: QueuedOp) async -> SyncOutcome {
        guard op.kind == .workizReport else { return await fallback.deliver(op) }
        guard var delivery = try? JSONDecoder().decode(WorkizDelivery.self, from: op.payload) else { return .permanent(reason: "The Workiz report could not be read.") }
        if delivery.endedForOffice || connection.officeRoute {
            delivery.endedForOffice = true; delivery.status = Self.officeHandover; save(delivery, op: op); return .permanent(reason: Self.officeHandover)
        }
        guard connection.isRunning, let generation = connection.credential?.generation else { return .waiting(reason: WorkizFailure.disabled.localizedDescription) }
        if delivery.blockedGeneration == generation { return .waiting(reason: delivery.status) }
        if let date = delivery.retryAfter, date > now() { retry(date); return .waiting(reason: delivery.status) }
        do {
            if !delivery.fieldWritten {
                let fields = try await client.pages(.customFields, decode: WorkizAPI.field)
                let field = try WorkizWriteBack.field(fields, named: connection.fieldName)
                let raw = try await client.get(.job(delivery.report.jobID))
                let object = try WorkizAPI.object(raw)
                if let existing = WorkizAPI.objects(object["customFields"]).first(where: { $0["id"] as? String == field.id }), !(existing["value"] is String) {
                    throw WorkizFailure.malformed
                }
                let job = try WorkizAPI.job(raw)
                let value = try WorkizWriteBack.merging(existing: job.customFields[field.id] ?? "", report: delivery.report)
                _ = try await client.get(.job(job.id), method: "PUT", body: WorkizWriteBack.body(fieldID: field.id, value: value))
                delivery.fieldWritten = true; save(delivery, op: op)
            }
            let notesAllowed = !PolicyEnvelope.isLocked(.workizClientNotes) || connection.clientNotes
            if delivery.report.clientNote, notesAllowed, delivery.report.clientID == nil { throw WorkizFailure.clientMissing }
            if delivery.report.clientNote, notesAllowed, let clientID = delivery.report.clientID, delivery.noteID == nil {
                let notes = try await client.pages(.clientNotes(clientID), decode: { WorkizAPI.note($0) })
                if let existing = notes.first(where: { $0.text.components(separatedBy: "\n").contains(delivery.report.marker) }) {
                    delivery.noteID = existing.id
                } else if delivery.noteAttempted {
                    throw WorkizFailure.noteUncertain
                } else {
                    // Write-ahead, before POST. An ambiguous response is recovered by marker only.
                    delivery.noteAttempted = true
                    guard save(delivery, op: op) else { throw WorkizFailure.unavailable }
                    let body = try JSONSerialization.data(withJSONObject: ["note": delivery.report.noteHeading + "\n" + delivery.report.text])
                    let result: Data
                    do { result = try await client.get(.clientNotes(clientID), method: "POST", body: body) }
                    catch let failure as WorkizFailure {
                        if failure == .badKey || failure == .permission("Clients") || failure == .rateLimited {
                            delivery.noteAttempted = false; save(delivery, op: op)
                        }
                        throw failure
                    }
                    let id = WorkizAPI.text(try WorkizAPI.object(result)["id"], limit: 101)
                    guard WorkizAPI.identifier(id, prefix: "CLN-") else { throw WorkizFailure.noteUncertain }
                    delivery.noteID = id
                }
            }
            delivery.status = "Sent to Workiz"; delivery.retryAfter = nil; delivery.blockedGeneration = nil
            save(delivery, op: op); return .done
        } catch {
            let failure = error as? WorkizFailure ?? .offline
            if connection.officeRoute { delivery.endedForOffice = true; delivery.status = Self.officeHandover; save(delivery, op: op); return .permanent(reason: Self.officeHandover) }
            delivery.status = "Needs attention — " + failure.localizedDescription
            switch failure {
            case .badKey, .permission:
                delivery.blockedGeneration = generation; save(delivery, op: op); return .waiting(reason: delivery.status)
            case .offline, .unavailable, .rateLimited:
                delivery.status = "Waiting for a connection"
                delivery.retryAfter = now().addingTimeInterval(min(3600, 30 * pow(2, Double(min(op.attempts, 7)))))
                save(delivery, op: op)
                if let date = delivery.retryAfter { retry(date) }
                return .transient(reason: delivery.status)
            case .disabled:
                save(delivery, op: op); return .waiting(reason: delivery.status)
            default:
                save(delivery, op: op); return .permanent(reason: delivery.status)
            }
        }
    }
}
