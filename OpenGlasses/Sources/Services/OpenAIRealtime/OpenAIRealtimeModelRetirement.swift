import Foundation

/// OpenAI's removed and retiring realtime model IDs, each with its date and the replacement this
/// app moves saved OpenAI live models to (Plan KC P1).
///
/// Taken from OpenAI's deprecations page, 2026-10-29. Every replacement is in the 2.1 family, even
/// for the `gpt-4o-realtime-preview` models OpenAI pointed at `gpt-realtime-1.5` in 2025, so a saved
/// model moves once rather than twice (owner decision 2). Pure: no clock, no storage.
enum OpenAIRealtimeModelRetirement {
    struct Entry: Equatable {
        /// The ID as OpenAI publishes it, lowercased.
        let id: String
        /// `true` when dated snapshots (`<id>-2024-12-17`) share the entry. `gpt-realtime` itself is
        /// exact, or it would swallow `gpt-realtime-2.1`.
        let includesSnapshots: Bool
        /// The day OpenAI removes it (UTC). On or after this day the ID no longer connects.
        let removal: DateComponents
        let replacement: String

        func matches(_ model: String) -> Bool {
            let model = OpenAIRealtimeModelRetirement.normalized(model)
            return model == id || (includesSnapshots && model.hasPrefix(id + "-"))
        }
        var removalDate: Date { OpenAIRealtimeModelRetirement.utc.date(from: removal)! }
        func isRemoved(on date: Date) -> Bool { date >= removalDate }
    }

    static let full = "gpt-realtime-2.1"
    static let mini = "gpt-realtime-2.1-mini"

    private static let previewRemoval = DateComponents(year: 2026, month: 5, day: 7)
    private static let retirement = DateComponents(year: 2027, month: 1, day: 20)

    /// Order matters only for readability: no ID matches two entries.
    static let entries: [Entry] = [
        .init(id: "gpt-4o-realtime-preview", includesSnapshots: true, removal: previewRemoval, replacement: full),
        .init(id: "gpt-4o-mini-realtime-preview", includesSnapshots: true, removal: previewRemoval, replacement: mini),
        .init(id: "gpt-realtime", includesSnapshots: false, removal: retirement, replacement: full),
        .init(id: "gpt-realtime-2025-08-28", includesSnapshots: false, removal: retirement, replacement: full),
        .init(id: "gpt-4o-realtime", includesSnapshots: false, removal: retirement, replacement: full),
        .init(id: "gpt-realtime-mini", includesSnapshots: true, removal: retirement, replacement: mini),
        .init(id: "gpt-4o-mini-realtime", includesSnapshots: false, removal: retirement, replacement: mini),
    ]

    static func entry(for model: String) -> Entry? { entries.first { $0.matches(model) } }

    /// Whether OpenAI has already removed this ID on `date`. Unknown IDs are never removed.
    static func isRemoved(_ model: String, on date: Date = Date()) -> Bool {
        entry(for: model)?.isRemoved(on: date) ?? false
    }

    /// One saved model's move.
    struct Rename: Equatable {
        let from: String
        let to: String
        let removal: Date
    }

    /// The models with every OpenAI-provider ID in the table rewritten to its replacement, and what
    /// moved; nil when nothing needs moving. Compatible models keep whatever ID they were saved
    /// with, because a compatible server's model names are its own.
    static func rewriting(_ models: [RealtimeModelConfig]) -> (models: [RealtimeModelConfig], renames: [Rename])? {
        var renames: [Rename] = []
        let rewritten = models.map { model -> RealtimeModelConfig in
            guard model.providerID == "openai", let entry = entry(for: model.model) else { return model }
            let rename = Rename(from: model.model.trimmingCharacters(in: .whitespacesAndNewlines),
                                to: entry.replacement, removal: entry.removalDate)
            if !renames.contains(rename) { renames.append(rename) }
            var moved = model
            moved.model = entry.replacement
            return moved
        }
        return renames.isEmpty ? nil : (rewritten, renames)
    }

    /// The one notice for a rewrite, naming each old and new ID. Says "has removed" or "is retiring"
    /// from the date the rewrite ran.
    static func notice(for renames: [Rename], on date: Date = Date()) -> String? {
        guard let first = renames.first else { return nil }
        if renames.count == 1 {
            if first.removal <= date {
                return String(localized: "OpenAI no longer offers the realtime model \(first.from), so your saved OpenAI live model now uses \(first.to).")
            }
            let day = first.removal.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: utc.timeZone))
            return String(localized: "OpenAI retires the realtime model \(first.from) on \(day), so your saved OpenAI live model now uses \(first.to).")
        }
        let moves = renames.map { "\($0.from) → \($0.to)" }.formatted(.list(type: .and))
        return String(localized: "OpenAI is retiring older realtime models, so your saved OpenAI live models now use newer ones: \(moves).")
    }

    static func normalized(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    fileprivate static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
