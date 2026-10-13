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

    /// What is on disk: the log, under a format number so a later shape can be told apart.
    private struct File: Codable {
        var version: Int
        var log: VanStockLog
    }

    private static let formatVersion = 1

    @Published private(set) var log: VanStockLog
    /// The file exists and could not be read. Nothing is written while this is true.
    @Published private(set) var isUnreadable: Bool

    private let fileURL: URL

    init(directory: URL? = nil, now: Date = Date()) {
        let folder = directory ?? DeliveryQueueStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("van-stock.json")

        switch Self.read(fileURL) {
        case .absent:
            log = VanStockLog()
            isUnreadable = false
        case .unreadable:
            log = VanStockLog()
            isUnreadable = true
        case .loaded(let stored):
            isUnreadable = false
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

    /// Everything, for a wipe or to start again after an unreadable file — what the registry's
    /// "delete all" column names.
    func removeAll() {
        try? FileManager.default.removeItem(at: fileURL)
        log = VanStockLog()
        isUnreadable = false
    }

    // MARK: - Storage

    private enum Stored {
        case absent
        case unreadable
        case loaded(VanStockLog)
    }

    private static func read(_ url: URL) -> Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data),
              file.version == formatVersion else { return .unreadable }
        return .loaded(file.log)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(File(version: Self.formatVersion, log: log)) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        protectFile()
    }

    /// Complete protection. Not excluded from backup: see the type's note.
    private func protectFile() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
    }
}
