import Foundation

/// A third reference corpus in the existing factory, not another retriever. The source store's
/// current/supersession/erasure journal is consulted again when a passage is about to be used.
@MainActor
final class CapturedManualCatalog {
    static let shared = CapturedManualCatalog()
    var documents: DocumentStore?
    var injectedSource: CapturedManualStore?
    var onForget: ((String) -> Void)?
    var accessAllowed: () -> Bool = { CapturedManualCatalog.mayUse }
    var scopeForVault: (String) -> CapturedManualContract.Scope = { CapturedManualCatalog.scope(vaultID: $0) }
    var source: CapturedManualStore? { injectedSource ?? CapturedManualStore.shared }

    static var mayUse: Bool {
        Config.fieldAssistActive && !Config.hipaaMode && Config.capturedManualsPolicy != "off"
            && FieldAssistEntitlement.shared.check(.ownVaults).isGranted
            && !OrgProfileManager.shared.contentLocked && OrgDepartureService.shared.departure?.isPending != true
    }
    static func scope(vaultID: String) -> CapturedManualContract.Scope {
        let manager = OrgProfileManager.shared
        if let record = manager.record, let profile = manager.profile {
            let org = profile.officeAuthority?.organizationID ?? ("profile-" + CapturedManualContract.digest(Data(profile.profileId.utf8)).prefix(24))
            return .init(ownershipScope:"organization",organizationID:String(org),enrolmentID:record.enrolmentId,vaultID:vaultID)
        }
        return .init(ownershipScope:"personal",organizationID:"",enrolmentID:"",vaultID:vaultID)
    }
    func eligible(for session: FieldSession?, vaultID: String) -> [CapturedManualContract.Manifest] {
        guard accessAllowed(), let session, session.vaultId == vaultID, let source,
              let all = try? source.manifests() else { return [] }
        let token = session.equipment?.unitKey ?? ""
        let context = CapturedManualAccess(scope:scopeForVault(vaultID),sessionID:session.id,
                                          unitID:session.continuityScope,confirmedModelToken:token)
        return all.filter(context.permits)
    }
    nonisolated static func namespace(_ m: CapturedManualContract.Manifest) -> String { m.documentID }
    nonisolated static func citationName(_ m: CapturedManualContract.Manifest) -> String {
        let date = ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:TimeInterval(m.capturedAt))).prefix(10)
        let digest = (try? CapturedManualContract.canonicalBytes(m)).map(CapturedManualContract.digest) ?? "unavailable"
        let title = m.title.replacingOccurrences(of: ",", with: " ·")
        let job = m.jobReference.replacingOccurrences(of: ",", with: " ·")
        return "Photographed manual · \(title) · job \(job.isEmpty ? m.sessionID.prefix(8).description : job) · \(date) · capture \(m.captureID)/\(m.captureRevision)/\(digest)"
    }
    func available(_ documentID: String, session: FieldSession?, vaultID: String) -> Bool {
        eligible(for:session,vaultID:vaultID).contains { $0.documentID == documentID }
    }
    func index(_ m: CapturedManualContract.Manifest) async throws {
        guard accessAllowed(), m.scope == scopeForVault(m.vaultID), let documents, let source else { return }
        let textURL = try source.file(m,name:"text.md")
        let pages = try await Task.detached(priority:.utility) {
            let data = try Data(contentsOf:textURL)
            return m.pages.map { p in (number:p.index,text:String(decoding:data.subdata(in:p.textOffset..<(p.textOffset+p.textBytes)),as:UTF8.self)) }
        }.value
        let id = m.documentID
        let current = { [weak self] in
            guard let self, self.accessAllowed(), m.scope == self.scopeForVault(m.vaultID) else { return false }
            return (try? self.source?.manifests().contains { $0.documentID == id }) == true
        }
        // Empty failed pages contribute no text, but remain in the source map/PDF for viewing.
        guard await documents.ingestPages(documentId:id,name:Self.citationName(m),pages:pages,
            sourceType:"captured_manual_ocr",namespace:Self.namespace(m),stillAllowed:current) else {
            throw CapturedManualStore.Failure.cancelled
        }
        // Remove previous live revisions without touching historical source PDFs/citations.
        for document in documents.documents where document.namespace.hasPrefix("captured:\(m.captureID):") && document.id != id {
            documents.forget(documentId:document.id)
        }
    }
    func recoverIndex() async {
        guard accessAllowed(), let source, let all = try? source.manifests() else { return }
        for m in all where m.scope == scopeForVault(m.vaultID) {
            if documents?.documents.contains(where:{$0.id == m.documentID}) != true { try? await index(m) }
        }
    }
    func historical(citation: String) -> CapturedManualContract.Manifest? {
        guard accessAllowed(), let all = try? source?.manifests(currentOnly:false) else { return nil }
        return all.first { $0.scope == scopeForVault($0.vaultID) && Self.citationName($0) == citation }
    }
    func forget(_ id: String) throws {
        guard let source else { throw CapturedManualStore.Failure.unavailable }
        // The source lock serialises tombstoning with assembler writes; a failed delete remains
        // suppressed. Remove derived rows even if a protected source unlink has to be retried.
        defer {
            onForget?(id)
            for document in documents?.documents ?? [] where document.id.hasPrefix("captured:\(id):") {
                documents?.forget(documentId:document.id)
            }
        }
        try source.forget(id)
    }
}
