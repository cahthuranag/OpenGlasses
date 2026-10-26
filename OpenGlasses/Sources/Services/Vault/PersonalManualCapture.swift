import Foundation
import UIKit
import VisionKit

/// A library destination for the same document camera and local PDF/OCR pipeline. No job, signed
/// job-capture contract or Office outbox is involved. A saved PDF is durable before indexing.
/// Durable sources belong to VaultStore through the library/importer; this adapter owns only
/// task-local page images and the unsaved camera request.
@MainActor
final class PersonalManualCapture: ObservableObject {
    static let shared = PersonalManualCapture()
    struct Request: Identifiable {
        let id: UUID
        let title: String
    }
    @Published private(set) var request: Request?
    @Published private(set) var status = ""
    private var saving = false
    private var starting = false

    func start(title: String = "Photographed manual") async -> String {
        guard request == nil, !saving, !starting else { return "A manual capture is already in progress." }
        starting = true
        defer { starting = false }
        guard PersonalManualLibrary.canManage else { return MyManualsPaywallCopy.locked }
        guard VNDocumentCameraViewController.isSupported else { return "This phone cannot open the document camera." }
        do {
            let token = try await Task.detached(priority: .utility) { try ManualLibraryAdmission.reserveCapture() }.value
            guard PersonalManualLibrary.canManage else { ManualLibraryAdmission.release(token); return MyManualsPaywallCopy.locked }
            request = .init(id: token, title: String(title.prefix(240)))
            status = "Photograph your manual on the phone and save the pages."
        } catch { status = error.localizedDescription }
        return status
    }

    func cancel(_ id: UUID, message: String = "Manual capture cancelled.") {
        guard request?.id == id else { return }
        request = nil
        ManualLibraryAdmission.release(id)
        status = message
    }

    private final class ImageTransfer: @unchecked Sendable {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
        func jpeg() throws -> Data {
            let scale = min(1, 2200 / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            guard let cg = upright.cgImage else { throw CapturedManualStore.Failure.missingPage }
            return try CapturedManualMedia.jpeg(cg)
        }
    }

    func accept(_ scan: VNDocumentCameraScan, request frozen: Request) {
        guard request?.id == frozen.id else { return }
        request = nil
        guard PersonalManualLibrary.canManage, (1...CapturedManualContract.maximumPages).contains(scan.pageCount) else {
            ManualLibraryAdmission.release(frozen.id)
            status = "This capture is unavailable or has too many pages. Photograph at most \(CapturedManualContract.maximumPages) pages at a time."
            return
        }
        saving = true
        Task {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("PersonalManualScan-\(frozen.id.uuidString)")
            defer {
                try? FileManager.default.removeItem(at: root)
                ManualLibraryAdmission.release(frozen.id)
                saving = false
            }
            do {
                try ManualLibraryAdmission.validateCapture(frozen.id, pages: scan.pageCount)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                for index in 0..<scan.pageCount {
                    guard PersonalManualLibrary.canManage else { throw ManualLibraryAdmission.Failure.refused(MyManualsPaywallCopy.locked) }
                    let transfer = ImageTransfer(scan.imageOfPage(at: index))
                    try await Task.detached(priority: .utility) {
                        let bytes = try autoreleasepool { try transfer.jpeg() }
                        try bytes.write(to: root.appendingPathComponent("\(index + 1).jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }.value
                    status = "Saving photographed page \(index + 1) of \(scan.pageCount)…"
                }
                let count = scan.pageCount
                let pdf = try await Task.detached(priority: .utility) {
                    let data = try CapturedManualMedia.pdf(title: frozen.title, capturedAt: Int64(Date().timeIntervalSince1970), pageCount: count) {
                        try Data(contentsOf: root.appendingPathComponent("\($0).jpg"))
                    }
                    let url = root.appendingPathComponent("pages.pdf")
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    return url
                }.value
                await PersonalManualLibrary.shared.addPDF(pdf, title: frozen.title, photographed: true, reservation: frozen.id)
                status = PersonalManualLibrary.shared.status
            } catch { status = error.localizedDescription }
        }
    }
}
