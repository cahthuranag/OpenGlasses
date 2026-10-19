import Foundation

/// The parts a job is still waiting to order, as one email to the office.
///
/// A parts request is recorded the moment the technician asks for it, and until now it was only
/// marked sent when a job report that carried it was sent. A technician who said "I used one
/// igniter, order a new one" mid-job had no way to send the order on its own: the only email the
/// app could prepare was the whole job report. This is that order — the requests on one job that
/// have been asked for and have not gone (`PartsRequest.Status.requested`), each line saying what
/// it is, whether the number was found in the manuals, how soon it is needed and what it is for.
///
/// Pure: the selection, the subject, the body and the route are decided here from values, so they
/// are table tests. **No customer details, no transcript, no attachment** — a parts order is what
/// the counter needs to pull a part, and nothing else of the job.
struct PartsOrder: Equatable {
    let sessionId: String
    let jobReference: String?
    /// "Lennox SLP99" — the vault the job was worked from, as the job report's subject names it.
    let vaultName: String
    /// The unit the job is on, when the session knows it; a line whose request carries its own
    /// model uses that instead.
    let equipmentModel: String?
    /// The requests this order carries, in the order they were asked for. Never empty.
    let requests: [PartsRequest]
    /// What the technician asked to have added, if anything.
    let note: String?

    /// The order for a job, or nil when nothing on it is waiting to go.
    ///
    /// - Parameter requestId: one request only. Nil carries every request still waiting.
    init?(sessionId: String, jobReference: String?, vaultName: String, equipmentModel: String?,
          partsRequests: [PartsRequest], requestId: String? = nil, note: String? = nil) {
        let waiting = Self.waiting(partsRequests).filter { requestId == nil || $0.id == requestId }
        guard !waiting.isEmpty else { return nil }
        self.sessionId = sessionId
        self.jobReference = jobReference.flatMap { $0.isEmpty ? nil : $0 }
        self.vaultName = vaultName
        self.equipmentModel = equipmentModel.flatMap { $0.isEmpty ? nil : $0 }
        self.requests = waiting
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// The requests that still have to go: asked for, not sent, not answered. A request already
    /// sent is waiting on base, not on the technician, and is never ordered twice.
    static func waiting(_ requests: [PartsRequest]) -> [PartsRequest] {
        requests.filter { $0.status == .requested }
    }

    var partsRequestIds: [String] { requests.map(\.id) }

    /// "1 × 70W16, 2 × 14T65" — what the order is, said or logged in one breath.
    var spokenList: String {
        requests.map { "\($0.quantity) × \($0.part.number)" }.joined(separator: ", ")
    }

    /// "Parts request — Job 1029 — Lennox SLP99".
    var subject: String {
        if let jobReference { return "Parts request — Job \(jobReference) — \(vaultName)" }
        return "Parts request — \(vaultName) — job record \(sessionId.prefix(8))"
    }

    /// One line per part: "1 × 70W16 (Hot surface igniter) — verified, SLP99 Service Manual,
    /// page 41 — routine — for this job — unit SLP99UH090".
    func line(for request: PartsRequest) -> String {
        var parts = ["\(request.quantity) × \(request.part.summary)", request.urgency.rawValue]
        parts.append(request.onVan ? "to restock the van" : "for this job")
        if let model = request.modelToken.flatMap({ $0.isEmpty ? nil : $0 }) ?? equipmentModel {
            parts.append("unit \(model)")
        }
        return parts.joined(separator: " — ")
    }

    /// The email: what to order, then the job it is for, then the technician's note.
    var body: String {
        var blocks: [String] = [subject]
        blocks.append((["Please order:"] + requests.map { "• " + line(for: $0) }).joined(separator: "\n"))
        var job: [String] = [jobReference.map { "Job: \($0)" } ?? "Job: no job number (record \(sessionId.prefix(8)))"]
        if let equipmentModel { job.append("Unit: \(equipmentModel)") }
        blocks.append(job.joined(separator: "\n"))
        if let note { blocks.append("Note from the technician: \(note)") }
        if requests.contains(where: { !$0.part.verified }) {
            blocks.append("A part marked unverified was not found in the manuals for this unit. "
                          + "Check the number before ordering.")
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The same order in the two lines a message bubble has room for.
    var shortBody: String {
        let job = jobReference.map { "Job \($0)" } ?? vaultName
        let lines = requests.map { "\($0.quantity) × \($0.part.number) (\($0.urgency.rawValue)\($0.part.verified ? "" : ", unverified"))" }
        return "Parts request — \(job): " + lines.joined(separator: ", ") + "."
    }

    // MARK: - Where it goes

    /// The channel and the people, or the sentence saying why it cannot go.
    enum Route: Equatable {
        case ready(channel: DeliveryChannel, recipients: [String])
        case refused(String)
    }

    /// Where the order goes: the job report's own rules, preferring email.
    ///
    /// An address the technician named makes it email, when email is allowed; otherwise it goes
    /// the way a job report would go by default — email to the configured recipients, Messages,
    /// the share sheet, or the organisation's endpoint — and is checked against the same policy.
    static func route(policy: DeliveryPolicy, spoken: [String] = []) -> Route {
        let named = spoken.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let channel: DeliveryChannel?
        if !named.isEmpty, policy.availableChannels.contains(.email) {
            channel = .email
        } else {
            channel = policy.defaultChannel
        }
        guard let channel else {
            return .refused("No channel is allowed for sending from this device. "
                            + "Set one up in Settings → Field Assist → Job reports.")
        }
        switch policy.decide(channel: channel, spoken: channel == .email ? named : []) {
        case .refused(let reason): return .refused(reason)
        case .allowed(let recipients): return .ready(channel: channel, recipients: recipients)
        }
    }
}
