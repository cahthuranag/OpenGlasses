import Combine
import Foundation
import UIKit
import VisionKit

/// One frozen camera request, followed by worker-owned durable recognition. The active job is
/// never re-read to decide where a saved scan belongs.
@MainActor
final class ManualCaptureService: ObservableObject {
    static let shared = ManualCaptureService()
    struct Request: Identifiable, Sendable { let metadata: CapturedManualStore.Metadata; var id: String { metadata.key } }
    @Published var request: Request?
    @Published private(set) var status = ""
    @Published private(set) var revision = 0
    private var jobs: [String: Task<Void, Never>] = [:]
    private var observations: [AnyCancellable] = []
    /// P4 installs an authorised Office-only sender. Absence means local, never sent.
    var completed: ((CapturedManualContract.Manifest) -> Void)?
    private let sessions: FieldSessionService
    private let catalog: CapturedManualCatalog
    private let cameraSupported: @MainActor () -> Bool
    init(sessions: FieldSessionService? = nil, catalog: CapturedManualCatalog? = nil,
         cameraSupported: @escaping @MainActor () -> Bool = { VNDocumentCameraViewController.isSupported }) {
        self.sessions = sessions ?? .shared
        self.catalog = catalog ?? .shared
        self.cameraSupported = cameraSupported
        self.sessions.$activeSession.sink { [weak self] session in
            guard let self, let pending = self.request else { return }
            if session?.id != pending.metadata.sessionID || session?.continuityScope != pending.metadata.unitID
                || session?.equipment?.unitKey ?? "" != pending.metadata.confirmedModelToken {
                self.cancel("The job or equipment changed. Photograph the manual again on the intended job.")
            }
        }.store(in:&observations)
    }
    func start(title: String? = nil) -> String {
        if request != nil { return "A manual camera request is already waiting on the phone." }
        guard catalog.accessAllowed() else { return "Photographing manuals is unavailable under the current Field Assist, privacy or organisation policy." }
        guard cameraSupported() else { return "This phone cannot open the document camera." }
        guard let session = sessions.activeSession else { return "Start the intended Field Assist job before photographing its manual." }
        guard let source = catalog.source else { return "Manual storage is unavailable. Unlock the phone and try again." }
        let equipment = session.equipment
        guard (equipment?.stated.utf8.count ?? 0) <= 160, (equipment?.unitKey.utf8.count ?? 0) <= 160,
              (session.jobReference?.utf8.count ?? 0) <= 120 else { return "The job reference or model is too long to bind a photographed manual." }
        let serial = session.visitedUnits.last { $0.continuityScope == session.continuityScope }?.serial ?? ""
        let cleanedTitle = Self.display(title ?? equipment?.stated ?? "",limit:240)
        let m = CapturedManualStore.Metadata(captureID:UUID().uuidString.lowercased(),revision:1,sessionID:session.id,
            jobReference:session.jobReference ?? "",jobID:session.jobFile?.identity?.jobID ?? "",
            jobRevision:Int64(session.jobFile?.identity?.revision ?? 0),scope:catalog.scopeForVault(session.vaultId),
            unitID:session.continuityScope,statedModel:equipment?.stated ?? "",confirmedModelToken:equipment?.unitKey ?? "",
            serial:Self.display(serial,limit:160),title:cleanedTitle.isEmpty ? "Photographed manual" : cleanedTitle,
            author:Self.display(Config.technicianDisplayName,limit:160),capturedAt:Int64(Date().timeIntervalSince1970),
            policy:Config.capturedManualsPolicy,poolIntent:"jobOnly",conversationThreadID:session.conversationThreadId)
        _ = source // Verify protected storage before opening the camera, not after forty pages.
        request = Request(metadata:m)
        let hint = sessions.activeVault?.manifest.hasDocuments == true
            ? " A manual is already loaded; photograph this book if it is the revision you need." : ""
        status = "Photograph the manual on the phone, not the service log or customer paperwork.\(hint)"
        return status
    }
    func cancel(_ message: String = "Manual capture cancelled.") { request = nil; status = message }
    func cancel(requestID: String, message: String = "Manual capture cancelled.") {
        guard request?.id == requestID else { return }
        cancel(message)
    }
    private final class ImageTransfer: @unchecked Sendable {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
        func jpeg() throws -> Data {
            // Drawing honours UIImage's orientation. Only this one page is decoded/rendered.
            let edge = ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical ? 1650 : 2200
            let scale = min(1,CGFloat(edge)/max(image.size.width,image.size.height))
            let size = CGSize(width:max(1,image.size.width*scale),height:max(1,image.size.height*scale))
            let format = UIGraphicsImageRendererFormat();format.scale = 1;format.opaque = true
            let upright = UIGraphicsImageRenderer(size:size,format:format).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }
            guard let cg = upright.cgImage else { throw CapturedManualStore.Failure.missingPage }
            return try CapturedManualMedia.jpeg(cg,longEdge:edge)
        }
    }
    func accept(_ scan: VNDocumentCameraScan, request frozen: Request) {
        guard request?.id == frozen.id else { return }
        guard allowed(frozen.metadata), let store = catalog.source else {
            cancel(requestID:frozen.id,message:"The manual request is no longer available.");return
        }
        request = nil
        guard scan.pageCount > 0, scan.pageCount <= store.limits.pages else { status = "Too many pages. Photograph at most \(store.limits.pages) pages in one capture.";return }
        let metadata = frozen.metadata
        jobs[metadata.key] = Task { [weak self] in
            guard let self else { return }
            defer { self.jobs[metadata.key] = nil; self.revision += 1 }
            do {
                let languages = try await Task.detached(priority:.utility) {
                    try CapturedManualMedia.languages(preferred:Locale.preferredLanguages)
                }.value
                guard self.allowed(metadata) else { throw CapturedManualStore.Failure.cancelled }
                _ = try await Task.detached(priority:.utility) {
                    try store.begin(metadata,languages:languages.identifiers,fallback:languages.fallback,
                                    encoderVersion:"jpeg-adaptive-2200-q80-pdf-v1")
                }.value
                for index in 0..<scan.pageCount {
                    try Task.checkCancellation()
                    guard self.allowed(metadata) else { throw CapturedManualStore.Failure.cancelled }
                    let transfer = ImageTransfer(scan.imageOfPage(at:index))
                    let bytes = try await Task.detached(priority:.utility) { try autoreleasepool { try transfer.jpeg() } }.value
                    guard self.allowed(metadata) else { throw CapturedManualStore.Failure.cancelled }
                    try await Task.detached(priority:.utility) { try store.appendImage(bytes,to:metadata.key) }.value
                    self.status = "Saving photographed page \(index+1) of \(scan.pageCount)."
                }
                try await Task.detached(priority:.utility) { try store.finishStaging(metadata.key) }.value
                try await self.recognize(metadata.key,store:store)
            } catch {
                self.status = "Manual capture is incomplete. Unlock the phone and resume it, or discard it and photograph again."
            }
        }
    }
    private func allowed(_ metadata: CapturedManualStore.Metadata) -> Bool {
        catalog.accessAllowed() && metadata.scope == catalog.scopeForVault(metadata.scope.vaultID)
            && sessions.history.contains { $0.id == metadata.sessionID }
    }
    private func recognize(_ key: String, store: CapturedManualStore) async throws {
        let worker = CapturedManualAssembler(store:store,
            read:{try await CapturedManualMedia.recognize($0,languages:$1,fallback:$2)},
            makePDF:{try CapturedManualMedia.pdf($0,imageAt:$1)},pageCount:{try CapturedManualMedia.pageCount($0)},
            allowed:{ [weak self] metadata in
                guard let self else {return false};return await self.allowed(metadata)
            },progress:{ [weak self] done,total in await self?.progress(done,total) })
        let manifest = try await Task.detached(priority:.utility) { try await worker.assemble(key) }.value
        guard allowed(metadata(for:manifest)) else { throw CapturedManualStore.Failure.cancelled }
        try await catalog.index(manifest)
        status = "Manual saved locally: \(manifest.pageCount) photographed pages, \(manifest.lowConfidencePages) low confidence. Text recognised from a scan; verify figures against the printed page."
        if manifest.failedPages > 0 {status += " \(manifest.failedPages) pages could not be recognised and contribute no searchable text."}
        if manifest.recognitionFallback { status += " An unsupported language preference used automatic detection." }
        completed?(manifest)
    }
    private func progress(_ done: Int, _ total: Int) {status = "Recognising manual page \(done) of \(total)."}
    private func metadata(for m: CapturedManualContract.Manifest) -> CapturedManualStore.Metadata {
        .init(captureID:m.captureID,revision:m.captureRevision,sessionID:m.sessionID,jobReference:m.jobReference,
            jobID:m.jobID,jobRevision:m.jobRevision,scope:m.scope,unitID:m.unitID,statedModel:m.statedModel,
            confirmedModelToken:m.confirmedModelToken,serial:m.serial,title:m.title,author:m.author,
            capturedAt:m.capturedAt,policy:m.capturePolicy,poolIntent:m.poolIntent)
    }
    func resume() async {
        guard catalog.accessAllowed(), let store = catalog.source else { return }
        await catalog.recoverIndex()
        for m in ((try? store.manifests()) ?? []) where allowed(metadata(for:m)) {completed?(m)}
        guard let pending = try? store.pending() else { status = "Saved manual recovery is unavailable while the phone is locked.";return }
        for draft in pending where jobs[draft.metadata.key] == nil && allowed(draft.metadata) {
            guard draft.stagingComplete else { status = "An incomplete page capture remains. Discard it and photograph again.";continue }
            let key = draft.metadata.key
            jobs[key] = Task { [weak self] in
                guard let self else { return };defer { self.jobs[key] = nil;self.revision += 1 }
                do { try await self.recognize(key,store:store) }
                catch { self.status = "Manual recognition is waiting. Unlock the phone and resume it." }
            }
        }
    }
    func discard(_ id: String) throws {
        guard let store = catalog.source else { throw CapturedManualStore.Failure.unavailable }
        for draft in (try? store.pending()) ?? [] where draft.metadata.captureID == id { jobs[draft.metadata.key]?.cancel() }
        try catalog.forget(id);status = "Photographed manual forgotten.";revision += 1
    }
    func list() -> String {
        let scope = sessions.activeSession.map { catalog.scopeForVault($0.vaultId) }
        let items = ((try? catalog.source?.manifests()) ?? []).filter {
            $0.scope == catalog.scopeForVault($0.vaultID) && (scope == nil || $0.scope == scope)
        }
        let lines = items.map { "\($0.captureID): \($0.title), \($0.pageCount) pages, local capture (not pool approved)." }
        return ([status] + lines).filter { !$0.isEmpty }.joined(separator:"\n")
    }
    private static func display(_ raw: String, limit: Int) -> String {
        var value = String(String.UnicodeScalarView(raw.unicodeScalars.map { $0.value < 32 || $0.value == 127 ? UnicodeScalar(32)! : $0 }))
            .trimmingCharacters(in:.whitespacesAndNewlines)
        while value.utf8.count > limit { value.removeLast() }
        return value
    }
}
