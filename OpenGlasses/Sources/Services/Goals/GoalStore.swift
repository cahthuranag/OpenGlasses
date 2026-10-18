import Foundation

/// Where the wearer's goals live (Plan IW P1).
///
/// One JSON file, `Application Support/Goals/goals.json`, loaded at construction and written on
/// every change. First-unlock protection — goals are changed from voice turns that run with the
/// phone locked — and excluded from backup, because the subject-erasure walk reaches it. Registered
/// in `DataStoreRegistry` as `goals`.
///
/// At most 50 goals. A goal marked done or set aside is kept 90 days from when it finished (fewer
/// when a HIPAA retention shorter than that is set), then it goes; an active or paused goal is the
/// wearer's live list and never expires. Goals are the wearer's objects, not inferred knowledge, so
/// they are never ingested into memory.
///
/// A file that is there and cannot be read is refused, not overwritten: the store stays empty and
/// unwritable until it is read or reset, so one bad moment can never replace someone's goals with
/// nothing. One goal that does not decode costs that goal only.
@MainActor
final class GoalStore: ObservableObject {

    static let shared = GoalStore()

    nonisolated static let fileProtection = FileProtectionType.completeUntilFirstUserAuthentication
    nonisolated static let capacity = 50
    nonisolated static let finishedRetentionDays = 90

    private struct File: Codable {
        var version: Int
        var goals: [LossyGoal]
    }

    private struct LossyGoal: Codable {
        let goal: Goal?
        init(_ goal: Goal) { self.goal = goal }
        init(from decoder: Decoder) throws { goal = try? Goal(from: decoder) }
        func encode(to encoder: Encoder) throws { try goal?.encode(to: encoder) }
    }

    private static let formatVersion = 1

    /// In the order they were added.
    @Published private(set) var goals: [Goal]
    /// The file exists and could not be read. Nothing is written while this is true.
    @Published private(set) var isUnreadable: Bool

    private let fileURL: URL
    private let clock: () -> Date
    private let hipaaRetentionDays: () -> Int?

    init(directory: URL? = nil,
         clock: @escaping () -> Date = Date.init,
         hipaaRetentionDays: @escaping () -> Int? = { Config.hipaaMode ? Config.hipaaRetentionDays : nil }) {
        let folder = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("goals.json")
        self.clock = clock
        self.hipaaRetentionDays = hipaaRetentionDays
        goals = []
        isUnreadable = false
        reload()
    }

    nonisolated static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Goals", isDirectory: true)
    }

    /// Read the file again — after an unlock, when an unreadable file may have become readable.
    func reload() {
        switch Self.read(fileURL) {
        case .absent:
            goals = []
            isUnreadable = false
        case .unreadable:
            goals = []
            isUnreadable = true
        case .loaded(let stored):
            isUnreadable = false
            goals = stored
            let pruned = Self.retained(stored, now: clock(), finishedDays: finishedHorizonDays)
            if pruned != stored {
                goals = pruned
                save()
            }
        }
    }

    // MARK: - Reading

    func goal(id: UUID) -> Goal? { goals.first { $0.id == id } }

    /// Active and paused goals — what "my goals" means.
    var openGoals: [Goal] { goals.filter { $0.state == .active || $0.state == .paused } }

    // MARK: - Writing

    enum AddOutcome: Equatable {
        case added
        /// Fifty goals already, none of them finished.
        case full
        /// The file on disk could not be read; nothing was written.
        case unavailable
    }

    /// Keep a new goal. At the cap, the goal that finished longest ago makes room; when every goal
    /// is still open the new one is refused rather than an open one dropped.
    @discardableResult
    func add(_ goal: Goal) -> AddOutcome {
        guard !isUnreadable else { return .unavailable }
        var working = Self.retained(goals, now: clock(), finishedDays: finishedHorizonDays)
        if working.count >= Self.capacity {
            let finished = working.enumerated()
                .filter { $0.element.state == .done || $0.element.state == .abandoned }
                .min { ($0.element.finishedAt ?? $0.element.createdAt) < ($1.element.finishedAt ?? $1.element.createdAt) }
            guard let oldest = finished else { return .full }
            working.remove(at: oldest.offset)
        }
        working.append(goal)
        goals = working
        save()
        return .added
    }

    /// Change one goal and keep the result. A change into done or abandoned stamps `finishedAt`;
    /// a change back out of them clears it. Nil when there is no such goal or the file is
    /// unreadable.
    @discardableResult
    func update(_ id: UUID, _ change: (inout Goal) -> Void) -> Goal? {
        guard !isUnreadable, let index = goals.firstIndex(where: { $0.id == id }) else { return nil }
        var goal = goals[index]
        let wasFinished = goal.state == .done || goal.state == .abandoned
        change(&goal)
        let isFinished = goal.state == .done || goal.state == .abandoned
        if isFinished && !wasFinished { goal.finishedAt = clock() }
        if !isFinished { goal.finishedAt = nil }
        guard goal != goals[index] else { return goal }
        goals[index] = goal
        save()
        return goal
    }

    /// Delete one goal — the Goals screen's delete (Plan IW P2). Its check-in task goes with it,
    /// because every change to the goals reconciles the check-ins. False when there is no such
    /// goal or the file is unreadable.
    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard !isUnreadable, let index = goals.firstIndex(where: { $0.id == id }) else { return false }
        goals.remove(at: index)
        save()
        return true
    }

    /// Everything — the registry's "delete all", and the way out of an unreadable file.
    func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
        goals = []
        isUnreadable = false
    }

    /// Remove every goal that names `token` anywhere — its title, its reason or any step — for a
    /// subject erasure. A goal is the wearer's own list, so the whole goal goes rather than a step
    /// being quietly rewritten. Returns how many went.
    @discardableResult
    func forget(matching token: String) -> Int {
        let needle = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isUnreadable, !needle.isEmpty else { return 0 }
        let kept = goals.filter { !Self.mentions($0, needle) }
        let removed = goals.count - kept.count
        guard removed > 0 else { return 0 }
        goals = kept
        save()
        return removed
    }

    static func mentions(_ goal: Goal, _ needle: String) -> Bool {
        var texts = [goal.title, goal.why ?? ""]
        for step in goal.steps {
            texts.append(step.title)
            if let action = step.suggestedAction { texts.append(contentsOf: action.texts) }
        }
        return texts.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    // MARK: - Retention

    private var finishedHorizonDays: Int {
        guard let hipaa = hipaaRetentionDays(), hipaa > 0 else { return Self.finishedRetentionDays }
        return min(Self.finishedRetentionDays, hipaa)
    }

    /// Open goals stay; a finished one stays until `finishedDays` after it finished. Pure.
    nonisolated static func retained(_ goals: [Goal], now: Date, finishedDays: Int = finishedRetentionDays) -> [Goal] {
        let cutoff = now.addingTimeInterval(-TimeInterval(finishedDays) * 86_400)
        return goals.filter { goal in
            switch goal.state {
            case .active, .paused: return true
            case .done, .abandoned: return (goal.finishedAt ?? goal.createdAt) >= cutoff
            }
        }
    }

    // MARK: - Storage

    private enum Stored {
        case absent
        case unreadable
        case loaded([Goal])
    }

    private static func read(_ url: URL) -> Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url),
              let file = try? RecordJSONCodec.decoder().decode(File.self, from: data),
              file.version == formatVersion else { return .unreadable }
        return .loaded(file.goals.compactMap(\.goal))
    }

    private func save() {
        let file = File(version: Self.formatVersion, goals: goals.map(LossyGoal.init))
        guard let data = try? RecordJSONCodec.encoder().encode(file) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        StoreProtection.apply(Self.fileProtection, backupExcluded: true, to: fileURL)
    }
}

extension StepAction {
    /// The free text an action carries — what a subject erasure has to search.
    var texts: [String] {
        switch self {
        case .reminder(let text, _): return [text]
        case .calendarHold(let title, _, _): return [title]
        case .search(let query): return [query]
        case .draft(_, let prompt): return [prompt]
        case .scheduledCheck(let prompt, _): return [prompt]
        case .ask(let question): return [question]
        }
    }
}
