import Foundation

/// A workbook on its way into the van's stock (Plan IH §6).
///
/// Reading a workbook changes nothing. It raises a review — what would be counted, added and
/// changed, what is missing, what was refused — and the one button on that review is the write.
/// Whichever way the file arrived, from Mail or from the Van Stock screen, it comes through here.
@MainActor
final class VanStockImportService: ObservableObject {

    static let shared = VanStockImportService()

    /// Why a file was not read into a review.
    enum Refusal: Equatable {
        case fieldAssistOff
        case switchedOffByOrganisation
        case listUnreadable
        case fileUnreadable
        case workbook(XLSXReader.Failure)
        case noRecognisableHeader
        /// It was read, and applying it would change nothing.
        case nothingToChange
    }

    enum Stage: Equatable {
        case idle
        case refused(Refusal)
        case reviewing(VanStockSheet.Proposal, fileName: String)
    }

    @Published private(set) var stage: Stage = .idle

    private let store: VanStockStore
    private let service: VanStockService
    private let isAllowed: () -> Refusal?

    init(store: VanStockStore? = nil, service: VanStockService? = nil, isAllowed: (() -> Refusal?)? = nil) {
        self.store = store ?? .shared
        self.service = service ?? .shared
        self.isAllowed = isAllowed ?? {
            if !Config.fieldAssistActive { return .fieldAssistOff }
            if Config.organizationForbidsVanStock { return .switchedOffByOrganisation }
            return nil
        }
    }

    /// Read a file the system handed over, then let go of the system's copy.
    func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Refuse by size before reading, so a huge file is never pulled into memory.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= XLSXReader.maximumFileBytes else {
            stage = .refused(.workbook(.tooLarge))
            Self.discardInboxCopy(url)
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            stage = .refused(.fileUnreadable)
            return
        }
        handle(data: data, fileName: url.lastPathComponent)
        Self.discardInboxCopy(url)
    }

    /// The pure half of `open`, for a file's bytes and name.
    func handle(data: Data, fileName: String) {
        if let refusal = isAllowed() {
            stage = .refused(refusal)
            return
        }
        guard !store.isUnreadable else {
            stage = .refused(.listUnreadable)
            return
        }
        switch VanStockSheet.proposal(from: data, log: store.log) {
        case .failure(.workbook(let failure)):
            stage = .refused(.workbook(failure))
        case .failure(.noRecognisableHeader):
            stage = .refused(.noRecognisableHeader)
        case .success(let proposal):
            stage = proposal.changesNothing && proposal.refusals.isEmpty && proposal.missing.isEmpty
                ? .refused(.nothingToChange)
                : .reviewing(proposal, fileName: fileName)
        }
    }

    /// The one write: apply what is being reviewed, as a single batch, and close the review.
    @discardableResult
    func apply(keepingPhoneFigure: Set<String> = []) -> Bool {
        guard case .reviewing(let proposal, _) = stage else { return false }
        let applied = service.apply(proposal, keepingPhoneFigure: keepingPhoneFigure)
        stage = .idle
        return applied
    }

    func dismiss() {
        stage = .idle
    }

    /// A file opened from another app arrives as a copy in the app's Inbox; it has been read, so
    /// it goes. A file picked in place is somebody's own and is left alone.
    private static func discardInboxCopy(_ url: URL) {
        guard url.deletingLastPathComponent().lastPathComponent == "Inbox",
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              url.standardizedFileURL.path.hasPrefix(documents.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
