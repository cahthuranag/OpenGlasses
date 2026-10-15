import Combine
import Foundation

/// Standalone books use signed records, with their original job and exact saved source bytes.
/// Production compatibility remains denied until an explicitly qualified peer is selected.
@MainActor
final class CapturedManualOutbox: ObservableObject {
    static let shared = CapturedManualOutbox()
    @Published private(set) var changes = 0
    var queue: OfflineQueue?
    var evidence: OfficeReportEvidenceStore?
    var reports: OfficeReportService?
    var source: () -> CapturedManualStore? = { CapturedManualStore.shared }
    var officeConfigured: () -> Bool = { AppState.officeIsReportDestination }
    var compatiblePeer: () -> Bool = { false }
    var presentationAllowed: (CapturedManualContract.Manifest) -> Bool = { m in
        CapturedManualCatalog.mayUse && m.scope == CapturedManualCatalog.scope(vaultID:m.vaultID)
    }
    var policyAllows: (CapturedManualContract.Manifest) -> Bool = { m in
        !Config.hipaaMode && Config.fieldAssistActive && Config.capturedManualsPolicy != "off"
            && !OrgProfileManager.shared.contentLocked && m.poolIntent == "jobOnly"
            && m.ownershipScope == "organization" && m.scope == CapturedManualCatalog.scope(vaultID:m.vaultID)
    }

    func allows(_ op: QueuedOp) -> Bool {
        guard compatiblePeer(),officeConfigured(),let m = try? CapturedManualContract.read(op.payload),
              op.sessionId == m.sessionID,policyAllows(m),let source = source() else {return false}
        return (try? source.file(m,name:"manifest.json")) != nil
    }
    func forPresentation(_ request:DeliveryRequest) -> DeliveryRequest {
        let manuals = request.attachments.filter {$0.kind == .capturedManualPDF || $0.kind == .capturedManualText}
        guard !manuals.isEmpty else {return request}
        let all = (try? source()?.manifests(currentOnly:false)) ?? []
        let allowed = request.transcript?.audience == .office && manuals.allSatisfy { file in
            all.contains { m in
                guard presentationAllowed(m),let source = source() else {return false}
                let name = file.kind == .capturedManualPDF ? "pages.pdf" : "text.md"
                return (try? source.file(m,name:name)) == file.url
            }
        }
        guard !allowed else {return request}
        var payload = request.payload
        if case .workRecord(var record,let ids) = payload {record.capturedManuals = nil;payload = .workRecord(record,partsRequestIds:ids)}
        let note = "Photographed manual files stayed on this phone under the current destination or privacy policy."
        return .init(id:request.id,channel:request.channel,recipients:request.recipients,subject:request.subject,
            body:request.body + "\n\n" + note,shortBody:request.shortBody + "\n" + note,
            attachments:request.attachments.filter {$0.kind != .capturedManualPDF && $0.kind != .capturedManualText},
            payload:payload,clipPlan:request.clipPlan,clipItems:request.clipItems,transcript:request.transcript)
    }
    func allows(_ entry: OfficeReportService.Entry) -> Bool {
        guard entry.recordKind == OfficeReport.RecordKind.capturedManual.rawValue else {return true}
        guard compatiblePeer(),officeConfigured(),let source = source(),
              let all = try? source.manifests(currentOnly:false),let m = all.first(where:{
                  $0.captureID == entry.recordID && ((try? CapturedManualContract.canonicalBytes($0)).map(CapturedManualContract.digest)) == entry.recordSHA256
              }),policyAllows(m) else {return false}
        return (try? source.file(m,name:"manifest.json")) != nil
    }
    func enqueue(_ m: CapturedManualContract.Manifest) async throws {
        guard officeConfigured(),policyAllows(m),let queue,let evidence else {return}
        guard let source = source() else {throw CapturedManualStore.Failure.unavailable}
        let request = DeliveryRequest.make(capturedManual:m,pdf:try source.file(m,name:"pages.pdf"),text:try source.file(m,name:"text.md"))
        let op = request.payload.queuedOp()
        guard !op.payload.isEmpty else {throw CapturedManualStore.Failure.invalidRequest}
        if queue.all(limit:Int.max).contains(where:{$0.kind == .capturedManual && $0.payload == op.payload}) {return}
        // Freeze evidence before making the operation visible to a flush. A crash here may leave
        // an unreferenced snapshot, but cannot queue a half capture or substitute fresh OCR.
        _ = try await evidence.evidence(for:op)
        guard policyAllows(m),(try? source.file(m,name:"manifest.json")) != nil else {
            evidence.remove(operationIDs:[op.id]);throw CapturedManualStore.Failure.cancelled
        }
        queue.enqueue(op);changes += 1
    }
    func documents(for op: QueuedOp) async throws -> OfficeReportEvidenceStore.Rendered {
        guard op.kind == .capturedManual,let m = try? CapturedManualContract.read(op.payload),
              m.sessionID == op.sessionId,policyAllows(m),let source = source() else {throw CapturedManualStore.Failure.cancelled}
        let rendered = try await Task.detached(priority:.utility) {
            let pdf = try Data(contentsOf:source.file(m,name:"pages.pdf"))
            let text = try Data(contentsOf:source.file(m,name:"text.md"))
            return OfficeReportEvidenceStore.Rendered(documents:[
                .init(role:.capturedManualPDF,mediaType:"application/pdf",name:"pages.pdf",requirement:.required,audience:.office,bytes:pdf),
                .init(role:.capturedManualText,mediaType:"text/markdown",name:"text.md",requirement:.required,audience:.office,bytes:text)
            ],transcript:.none)
        }.value
        guard policyAllows(m),(try? source.file(m,name:"manifest.json")) != nil else {throw CapturedManualStore.Failure.cancelled}
        return rendered
    }
    func forget(_ captureID: String) {
        let ids = Set((queue?.all(limit:Int.max) ?? []).filter {
            $0.kind == .capturedManual && (try? CapturedManualContract.read($0.payload).captureID) == captureID
        }.map(\.id))
        reports?.suppress(recordIDs:[captureID])
        for id in ids {queue?.delete(id:id)}
        let published = Set(reports?.ledger.entries.filter {$0.recordID == captureID}.map(\.operationID) ?? [])
        evidence?.remove(operationIDs:ids.union(published));changes += 1
    }
    func captureIDs(sessionIDs: Set<String>) -> Set<String> {
        var ids = Set(((try? source()?.manifests(currentOnly:false)) ?? []).filter {sessionIDs.contains($0.sessionID)}.map(\.captureID))
        for op in queue?.all(limit:Int.max) ?? [] where op.kind == .capturedManual && sessionIDs.contains(op.sessionId) {
            if let m = try? CapturedManualContract.read(op.payload) {ids.insert(m.captureID)}
        }
        return ids
    }
    func standing(_ m: CapturedManualContract.Manifest) -> String {
        if m.ownershipScope == "personal" {return "local personal capture"}
        let bytes = try? CapturedManualContract.canonicalBytes(m)
        guard let op = queue?.all(limit:Int.max).first(where:{$0.kind == .capturedManual && $0.payload == bytes}) else {return "local · awaiting Office configuration"}
        switch reports?.status(operationID:op.id) {
        case .recordAccepted?,.fullyAccepted?:return "office accepted (job only)"
        case .evidencePending?:return "office has the record; evidence pending"
        default:return compatiblePeer() ? "queued for the office" : "queued · compatible Office required"
        }
    }
    /// An organisation-owned book without any queued send still belongs to its original job.
    /// Leaving the organisation must not erase it as though an ordinary job report carried it.
    func unqueuedCount(sessionIDs:Set<String>) -> Int {
        let ops = queue?.all(limit:Int.max) ?? []
        return ((try? source()?.manifests()) ?? []).filter { m in
            guard m.ownershipScope == "organization",sessionIDs.contains(m.sessionID),
                  let bytes = try? CapturedManualContract.canonicalBytes(m) else {return false}
            return !ops.contains {$0.kind == .capturedManual && $0.payload == bytes}
        }.count
    }
}
