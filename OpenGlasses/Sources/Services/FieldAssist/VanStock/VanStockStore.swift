import Foundation

/// Where the van's stock lives (Plan IH §4).
///
/// One JSON file in Application Support beside the delivery queue, loaded at construction and
/// written on every change. Registered in `DataStoreRegistry` as `vanStock`: part numbers,
/// quantities and job references, and nothing about a person — movements carry no free text. It is
/// protected, and **left in the device backup** on purpose: it is the technician's own working
/// record, and a new phone should still know what is on the truck.
///
/// A file that is there and cannot be read is refused, not half-read and not overwritten: the
/// store stays empty and unwritable until it is reset, so one bad write can never silently replace
/// a truck's worth of counts with nothing.
@MainActor
final class VanStockStore: ObservableObject {

    static let shared = VanStockStore()

    /// How long a movement is kept before it is folded into its line's opening figure. Levels are
    /// exact either way; only the history gets shorter.
    static let historyDays = 400

    /// What is on disk: the log and which van it is, under a format number so a later shape can
    /// be told apart.
    private struct File: Codable {
        var version: Int
        var log: VanStockLog
        /// Which vehicle this is (Plan IH P5). Absent in a file written before vans had names.
        var van: VanIdentity?
    }

    private static let formatVersion = 1

    @Published private(set) var log: VanStockLog
    /// Which vehicle the list belongs to. Nil until it has been named or taken over.
    @Published private(set) var van: VanIdentity?
    /// The file exists and could not be read. Nothing is written while this is true.
    @Published private(set) var isUnreadable: Bool

    private let fileURL: URL
    /// The list as it was before the last takeover: one generation, kept so taking over the wrong
    /// van is not the end of the right one's list.
    private let archiveURL: URL

    init(directory: URL? = nil, now: Date = Date()) {
        let folder = directory ?? DeliveryQueueStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("van-stock.json")

        archiveURL = folder.appendingPathComponent("van-stock-previous.json")
        switch Self.read(fileURL) {
        case .absent:
            log = VanStockLog()
            van = nil
            isUnreadable = false
        case .unreadable:
            log = VanStockLog()
            van = nil
            isUnreadable = true
        case .loaded(let stored, let identity):
            isUnreadable = false
            van = identity
            let cutoff = now.addingTimeInterval(-Double(Self.historyDays) * 86_400)
            let folded = stored.compacted(before: cutoff)
            log = folded
            if folded != stored { save() }
        }
        protectFile()
    }

    // MARK: - Changing

    /// Change the log and keep the result. Nil — and nothing changed — while the file on disk is
    /// unreadable.
    @discardableResult
    func update<Result>(_ change: (inout VanStockLog) -> Result) -> Result? {
        guard !isUnreadable else { return nil }
        var working = log
        let result = change(&working)
        if working != log {
            log = working
            save()
        }
        return result
    }

    /// Name the van, or rename it. The identifier is made once and kept, so a renamed truck is
    /// still the same truck to the next phone that takes it over.
    func nameVan(_ name: String, makeID: () -> String = { UUID().uuidString }) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isUnreadable, !cleaned.isEmpty, cleaned != van?.name else { return }
        van = VanIdentity(id: van?.id ?? makeID(), name: cleaned)
        save()
    }

    /// Take a van over: the list a handover describes replaces the phone's own. The list that was
    /// here is kept beside it, one generation deep, and never merged in.
    func replace(with log: VanStockLog, van: VanIdentity?) {
        guard !isUnreadable else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.copyItem(at: fileURL, to: archiveURL)
            protect(archiveURL)
        }
        self.log = log
        self.van = van
        save()
    }

    /// Whether there is a list from before the last takeover to go back to.
    var hasPrevious: Bool { FileManager.default.fileExists(atPath: archiveURL.path) }

    /// Go back to the list from before the last takeover. False when there is none to read.
    @discardableResult
    func restorePrevious() -> Bool {
        guard case .loaded(let stored, let identity) = Self.read(archiveURL) else { return false }
        try? FileManager.default.removeItem(at: archiveURL)
        log = stored
        van = identity
        isUnreadable = false
        save()
        return true
    }

    /// Everything, for a wipe or to start again after an unreadable file — what the registry's
    /// "delete all" column names.
    func removeAll() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: archiveURL)
        log = VanStockLog()
        van = nil
        isUnreadable = false
    }

    // MARK: - Storage

    private enum Stored {
        case absent
        case unreadable
        case loaded(VanStockLog, VanIdentity?)
    }

    private static func read(_ url: URL) -> Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data),
              file.version == formatVersion else { return .unreadable }
        return .loaded(file.log, file.van)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(File(version: Self.formatVersion, log: log, van: van)) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        protectFile()
    }

    /// Complete protection. Not excluded from backup: see the type's note.
    private func protectFile() { protect(fileURL) }

    private func protect(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}
