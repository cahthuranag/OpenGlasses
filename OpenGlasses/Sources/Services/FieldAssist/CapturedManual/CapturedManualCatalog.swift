import Foundation

/// A third reference corpus in the existing factory, not another retriever. The source store's
/// current/supersession/erasure journal is consulted again when a passage is about to be used.
@MainActor
final class CapturedManualCatalog {
    static let shared = CapturedManualCatalog()
    /// Weak: the store belongs to whoever hands it over (AppState's lives for the process). A
    /// strong hold here kept every store a test gave the shared catalog — and its SQLite
    /// connection — alive after the test deleted the file under it.
    weak var documents: DocumentStore?
    var injectedSource: CapturedManualStore?
    var onForget: ((String) -> Void)?
    var accessAllowed: () -> Bool = { CapturedManualCatalog.mayUse }
    var scopeForVault: (String) -> CapturedManualContract.Scope = { CapturedManualCatalog.scope(vaultID: $0) }
    var source: CapturedManualStore? { injectedSource ?? CapturedManualStore.shared }
    /// Reads the tables printed on the photographed pages (Plan JN P4): Vision on the phone by
    /// default, the same switch a vault import reads pictured tables with; nil reads none.
    var pictureReader: PictureTableReader? = VaultImporter.defaultPictureReader
    /// The phone's own checks of tables, where a photographed manual's checks are kept (Plan JN P4).
    var tableChecks = TableCheckStore()
    /// One indexing per captured revision at a time: a relaunch's recovery and the capture's own job
    /// share it rather than reading the same pages twice.
    private var indexing: [String: Task<Void, Error>] = [:]

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
        return all.filter {context.permits($0) && !replacedByReadyCopy($0)}
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
        let id = m.documentID
        if let running = indexing[id] { return try await running.value }
        let task = Task { try await self.indexNow(m) }
        indexing[id] = task
        defer { indexing[id] = nil }
        try await task.value
    }
    private func indexNow(_ m: CapturedManualContract.Manifest) async throws {
        guard accessAllowed(), m.scope == scopeForVault(m.vaultID), let documents, let source else { return }
        let textURL = try source.file(m,name:"text.md")
        let pages = try await Task.detached(priority:.utility) {
            let data = try Data(contentsOf:textURL)
            return m.pages.map { p in (number:p.index,text:String(decoding:data.subdata(in:p.textOffset..<(p.textOffset+p.textBytes)),as:UTF8.self)) }
        }.value
        let id = m.documentID
        let current = { [weak self] in
            guard let self, self.accessAllowed(), m.scope == self.scopeForVault(m.vaultID) else { return false }
            return !self.replacedByReadyCopy(m) && (try? self.source?.manifests().contains { $0.documentID == id }) == true
        }
        guard current() else {throw CapturedManualStore.Failure.cancelled}
        if pages.allSatisfy({$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}) {
            // Keep a complete unreadable book viewable without publishing empty evidence.
            for document in documents.documents where document.namespace.hasPrefix("captured:\(m.captureID):") {
                documents.forget(documentId:document.id)
            }
            return
        }
        // The tables printed on the photographed pages (Plan JN P4): only pages whose recognised
        // text names one, read off the main actor, redacted before anything keeps them, and never
        // checkpointed. They are published with the text in one transaction, so a reading cut off
        // by a relaunch is done again when recovery indexes the revision.
        let tablePages = CapturedManualTables.pagesNamingTables(pages)
        var tables: PDFTableReader.Result?
        if let reader = pictureReader, !tablePages.isEmpty {
            let labels = CapturedManualTables.printedLabels(m)
            tables = try await Task.detached(priority:.utility) {
                let pdf = try source.file(m,name:"pages.pdf")
                return await CapturedManualTables.read(pdf:pdf,pages:tablePages,printedLabels:labels,
                                                       context:CapturedManualTables.context(reader))
            }.value
            guard current() else {throw CapturedManualStore.Failure.cancelled}
        }
        // Empty failed pages contribute no text, but remain in the source map/PDF for viewing.
        guard await documents.ingestPages(documentId:id,name:Self.citationName(m),pages:pages,
            sourceType:"captured_manual_ocr",namespace:Self.namespace(m),tables:tables?.stored ?? [],
            stillAllowed:current) else {
            throw CapturedManualStore.Failure.cancelled
        }
        if let tables { VaultDocumentExtractor.logTables(tables,rowsDropped:documents.lastTableRowsDropped) }
        // Remove previous live revisions without touching historical source PDFs/citations.
        for document in documents.documents where document.namespace.hasPrefix("captured:\(m.captureID):") && document.id != id {
            documents.forget(documentId:document.id)
        }
    }
    func recoverIndex() async {
        guard accessAllowed(), let source, let all = try? source.manifests() else { return }
        for m in all where m.scope == scopeForVault(m.vaultID) {
            if replacedByReadyCopy(m) {try? reconcileReviewedVault(m.vaultID);continue}
            if documents?.documents.contains(where:{$0.id == m.documentID}) != true { try? await index(m) }
        }
    }
    func historical(citation: String) -> CapturedManualContract.Manifest? {
        guard accessAllowed(), let all = try? source?.manifests(currentOnly:false) else { return nil }
        return all.first { $0.scope == scopeForVault($0.vaultID) && Self.citationName($0) == citation }
    }
    private func readyReviews(_ vaultID:String) -> [CapturedManualReview] {
        guard accessAllowed(),let receipt = VaultImporter.receipt(for:vaultID),receipt.verification == .signed,
              receipt.capturedOrganizationID == scopeForVault(vaultID).organizationID,
              let manifest = VaultImporter.installedManifests().first(where:{$0.id == vaultID}) else {return []}
        return VaultImporter.documentLedger(for:vaultID).entries.compactMap { entry in
            guard let review = entry.capturedManual,review.valid,let binding = entry.capturedBinding,
                  receipt.capturedDocumentBindings?[entry.file] == binding,
                  manifest.documents.contains(where:{$0.file == entry.file && $0.capturedManual == review}),
                  documents?.documents.contains(where:{$0.id == entry.documentId && $0.namespace == DocumentStore.vaultNamespace(vaultID) && $0.chunkCount > 0}) == true else {return nil}
            return review
        }
    }
    private func replacedByReadyCopy(_ m:CapturedManualContract.Manifest) -> Bool {
        guard m.scope == scopeForVault(m.vaultID),let bytes = try? CapturedManualContract.canonicalBytes(m) else {return false}
        let digest = CapturedManualContract.digest(bytes)
        return readyReviews(m.vaultID).contains { review in review.origins.contains {
            $0.captureID == m.captureID && $0.captureRevision == m.captureRevision && $0.bundleSHA256 == digest && $0.pageCount == m.pageCount
        }}
    }
    func reviewedDocumentAllowed(_ documentID:String,vaultID:String) -> Bool {
        guard let entry = VaultImporter.documentLedger(for:vaultID).entries.first(where:{$0.documentId == documentID}),
              let review = entry.capturedManual,let binding = entry.capturedBinding,
              VaultImporter.receipt(for:vaultID)?.capturedDocumentBindings?[entry.file] == binding,
              documents?.documents.contains(where:{$0.id == documentID && $0.chunkCount > 0}) == true else {return false}
        return readyReviews(vaultID).contains(review)
    }
    func reconcileReviewedVault(_ vaultID:String) throws {
        guard accessAllowed(),let source,let all = try? source.manifests(currentOnly:false) else {return}
        for m in all where m.vaultID == vaultID && replacedByReadyCopy(m) {
            guard (try? source.file(m,name:"manifest.json")) != nil else {continue}
            let digest = CapturedManualContract.digest(try CapturedManualContract.canonicalBytes(m))
            try source.supersede(id:m.captureID,revision:m.captureRevision,digest:digest)
            documents?.forget(documentId:m.documentID)
        }
    }
    func forget(_ id: String) throws {
        guard let source else { throw CapturedManualStore.Failure.unavailable }
        // The source lock serialises tombstoning with assembler writes; a failed delete remains
        // suppressed. Remove derived rows even if a protected source unlink has to be retried.
        // Its tables' checks go with it (Plan JN P4), every revision's, read before the source is.
        let revisions = ((try? source.manifests(currentOnly:false)) ?? []).filter { $0.captureID == id }
        defer {
            onForget?(id)
            for document in documents?.documents ?? [] where document.id.hasPrefix("captured:\(id):") {
                documents?.forget(documentId:document.id)
            }
            CapturedManualTables.forgetChecks(of:revisions,in:tableChecks)
        }
        try source.forget(id)
    }
}
