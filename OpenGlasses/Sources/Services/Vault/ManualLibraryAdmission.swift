import Foundation
import PDFKit

/// One process-wide admission lock. Installation is synchronous and atomic with respect to other
/// admissions; indexing happens afterwards, so an interrupted index still holds its manual slot.
enum ManualLibraryAdmission {
    final class State: @unchecked Sendable {
        let lock = NSRecursiveLock()
        var reservations: [UUID: ManualQuota.Item] = [:]
    }
    private static let state = State()
    enum Failure: LocalizedError {
        case refused(String)
        var errorDescription: String? { if case .refused(let text) = self { return text }; return nil }
    }

    static func pageCount(_ url: URL) throws -> Int {
        guard url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url), !pdf.isLocked,
              pdf.pageCount > 0 else { throw Failure.refused("This manual needs an unlocked, readable PDF with numbered pages.") }
        return pdf.pageCount
    }

    static func inventory() throws -> [ManualQuota.Item] {
        var items: [ManualQuota.Item] = []
        let registry = VaultImporter.registryDirectory
        let files = FileManager.default.fileExists(atPath: registry.path)
            ? try FileManager.default.contentsOfDirectory(at: registry, includingPropertiesForKeys: nil) : []
        // A corrupt/protected manifest cannot silently disappear from quota accounting.
        let manifests = try files.filter { $0.pathExtension == "json" }.map {
            try JSONDecoder().decode(VaultManifest.self, from: Data(contentsOf: $0))
        }
        for manifest in manifests where manifest.isPersonalLibrary {
            let root = VaultImporter.baselineDirectory(for: manifest.id)
            for document in manifest.documents {
                let path = manifest.documentSourceRelativePath(document) ?? manifest.documentRelativePath(document)
                let pages = try? pageCount(root.appendingPathComponent(path))
                items.append(.init(id: identity(manifest.id, document.file), pages: pages))
            }
        }
        guard Set(items.map(\.id)).count == items.count else {
            throw Failure.refused(ManualQuota.Verdict.unavailable.message!)
        }
        return items
    }

    static func identity(_ vault: String, _ file: String) -> String { "\(vault)/\(file)" }

    private static func held(excluding token: UUID? = nil) throws -> [ManualQuota.Item] {
        var items = Dictionary(uniqueKeysWithValues: try inventory().map { ($0.id, $0) })
        for (key, item) in state.reservations where key != token {
            if let old = items[item.id] {
                items[item.id] = .init(id: item.id, pages: max(old.pages ?? 0, item.pages ?? 0))
            } else { items[item.id] = item }
        }
        return Array(items.values)
    }

    static func reserveCapture(identity: String? = nil) throws -> UUID {
        state.lock.lock(); defer { state.lock.unlock() }
        guard FieldAssistEntitlement.shared.has(.personalManuals) else { throw Failure.refused(MyManualsPaywallCopy.locked) }
        let token = UUID()
        let held = try held()
        let id = identity ?? "pending:\(token.uuidString)"
        let item = ManualQuota.Item(id: id, pages: held.first { $0.id == id }?.pages ?? 1)
        if let message = ManualQuota.decide(limits: FieldAssistEntitlement.shared.manualLimits(), held: held,
                                           replacing: identity.map { [$0] } ?? [], adding: [item]).message {
            throw Failure.refused(message)
        }
        state.reservations[token] = item
        return token
    }

    static func release(_ token: UUID) {
        state.lock.lock(); defer { state.lock.unlock() }
        state.reservations[token] = nil
    }

    static func validateCapture(_ token: UUID, pages: Int) throws {
        state.lock.lock(); defer { state.lock.unlock() }
        guard FieldAssistEntitlement.shared.has(.personalManuals), let item = state.reservations[token] else {
            throw Failure.refused("The capture is no longer authorised.")
        }
        let held = try held(excluding: token)
        let actual = ManualQuota.Item(id: item.id, pages: pages)
        if let reason = ManualQuota.decide(limits: FieldAssistEntitlement.shared.manualLimits(), held: held,
                                          replacing: [item.id], adding: [actual]).message {
            throw Failure.refused(reason)
        }
        state.reservations[token] = actual
    }

    /// The caller must supply measured proposed files, not publisher page-count claims.
    static func install<T>(manifest: VaultManifest, root: URL, reservation: UUID? = nil,
                           _ commit: () throws -> T) throws -> T {
        state.lock.lock(); defer { state.lock.unlock() }
        guard FieldAssistEntitlement.shared.has(.personalManuals) else { throw Failure.refused(MyManualsPaywallCopy.locked) }
        if let reservation, state.reservations[reservation] == nil { throw Failure.refused("This manual capture was cancelled. Photograph it again.") }
        if FieldAssistEntitlement.shared.manualLimits() != nil {
            let held = try held(excluding: reservation)
            let adding = try manifest.documents.map { document in
                let path = manifest.documentSourceRelativePath(document) ?? manifest.documentRelativePath(document)
                return ManualQuota.Item(id: identity(manifest.id, document.file), pages: try pageCount(root.appendingPathComponent(path)))
            }
            let replacing = Set(held.filter { $0.id.hasPrefix(manifest.id + "/") }.map(\.id))
            if let message = ManualQuota.decide(limits: FieldAssistEntitlement.shared.manualLimits(), held: held,
                                               replacing: replacing, adding: adding).message { throw Failure.refused(message) }
        }
        let value = try commit()
        if let reservation { state.reservations[reservation] = nil }
        return value
    }
}

enum MyManualsPaywallCopy {
    static let title = "My Manuals"
    static let locked = "My Manuals needs an active subscription. Your files stay on this phone, and you can still remove them."
    static let summary = "Keep your manuals. Ask by voice, hear the page cited, and open the source on your phone."
    static var pageLimits: String {
        let entitlement = FieldAssistEntitlement.shared
        let limits = entitlement.manualLimits() ?? ManualLimits.personal
        return limitDetails(limits)
    }
    static func limitDetails(_ limits: ManualLimits?) -> String {
        guard let limits else { return "Your subscription includes an unlimited manual library." }
        var parts = ["Up to \(limits.manuals.formatted()) manuals in your library."]
        if let pages = limits.pagesPerManual { parts.append("Up to \(pages.formatted()) pages per manual.") }
        if let pages = limits.totalPages { parts.append("Up to \(pages.formatted()) pages across your library.") }
        return parts.joined(separator: " ")
    }
    static let upgrade = "Field Assist is a separate service for jobs, trade references and professional tools."
    static let disclosure = "Your manuals are indexed on this phone and excluded from library sharing and export. Selected passages and rendered page images may be sent to your chosen AI provider. Supported local models process content on this phone; available manual tools vary by model."
    static var all: [String] { [title, locked, summary, pageLimits, upgrade, disclosure] }
}
