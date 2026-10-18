import Combine
import Foundation

/// The Activity screen's presentation model (Plan IW P2): the trail grouped by day, newest first,
/// with each row's authorisation in plain words and a destination where one exists. Pure over its
/// inputs — the entries, the goals, which conversation threads still exist, the clock and the
/// calendar — so the screen's story is tested headless.
///
/// The trail is the assistant's own actions: never a read, never what the wearer said. The screen
/// says so, and in HIPAA mode it shows each row's title only.
@MainActor
final class ActivityScreenModel: ObservableObject {

    enum Filter: String, CaseIterable, Identifiable {
        case all, actions, held, scheduled, refused
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return String(localized: "All", comment: "Activity screen filter.")
            case .actions: return String(localized: "Actions", comment: "Activity screen filter.")
            case .held: return String(localized: "Held", comment: "Activity screen filter.")
            case .scheduled: return String(localized: "Scheduled", comment: "Activity screen filter.")
            case .refused: return String(localized: "Refused", comment: "Activity screen filter.")
            }
        }

        func includes(_ entry: ActivityEntry) -> Bool {
            switch self {
            case .all: return true
            case .actions: return [.action, .plannedStep, .toldYou].contains(entry.kind)
            case .held: return entry.kind == .held
            case .scheduled: return entry.kind == .scheduledRun || entry.authorisation == .scheduled
            case .refused: return entry.kind == .refused
            }
        }
    }

    /// Where a row opens.
    enum Destination: Hashable {
        case goal(UUID)
        case thread(String)
    }

    struct Row: Identifiable, Equatable {
        let id: UUID
        let at: Date
        let title: String
        /// Nil in HIPAA mode, and when the entry has none.
        let detail: String?
        /// "You approved it", "Held for you", "Scheduled", "Refused: you said no".
        let authorisation: String
        /// "Didn't finish", "May not have gone through", "Waiting on you", or nil when it is done.
        let outcome: String?
        /// The goal it served, by its title, when the goal is still there.
        let goalTitle: String?
        let destination: Destination?
        let systemImage: String
    }

    enum Day: Equatable {
        case today, yesterday, earlier(Date)
    }

    struct DaySection: Identifiable, Equatable {
        let start: Date
        let day: Day
        let rows: [Row]
        var id: Date { start }
    }

    @Published var filter: Filter = .all

    private let store: ActivityStore
    private let goals: @MainActor () -> [Goal]
    private let threadExists: (String) -> Bool
    private let titlesOnly: () -> Bool
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var storeChanges: AnyCancellable?

    init(store: ActivityStore,
         goals: @escaping @MainActor () -> [Goal] = { GoalStore.shared.goals },
         threadExists: @escaping (String) -> Bool = { _ in false },
         titlesOnly: @escaping () -> Bool = { Config.hipaaMode },
         now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { Calendar.current }) {
        self.store = store
        self.goals = goals
        self.threadExists = threadExists
        self.titlesOnly = titlesOnly
        self.now = now
        self.calendar = calendar
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isEmpty: Bool { store.entries.isEmpty }
    var showsTitlesOnly: Bool { titlesOnly() }

    /// The filtered trail, a section per calendar day, newest day and newest row first.
    var sections: [DaySection] {
        let calendar = calendar()
        let today = calendar.startOfDay(for: now())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let goalsByID = Dictionary(goals().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hideDetail = titlesOnly()
        let entries = store.entries.filter(filter.includes).sorted { $0.at > $1.at }
        var order: [Date] = []
        var byDay: [Date: [Row]] = [:]
        for entry in entries {
            let start = calendar.startOfDay(for: entry.at)
            if byDay[start] == nil { order.append(start) }
            byDay[start, default: []].append(row(entry, goals: goalsByID, hideDetail: hideDetail))
        }
        return order.map { start in
            let day: Day = start == today ? .today : (start == yesterday ? .yesterday : .earlier(start))
            return DaySection(start: start, day: day, rows: byDay[start] ?? [])
        }
    }

    /// The Clear button — every entry, after the screen has asked.
    func clear() {
        store.deleteAll()
    }

    // MARK: - One row

    func row(_ entry: ActivityEntry, goals: [UUID: Goal], hideDetail: Bool) -> Row {
        let linkedGoalID = entry.goalID ?? entry.refs.lazy.compactMap(\.goalUUID).first
        let goal = linkedGoalID.flatMap { goals[$0] }
        let destination: Destination?
        if let goal {
            destination = .goal(goal.id)
        } else if let thread = entry.refs.lazy.compactMap(\.threadID).first(where: threadExists) {
            destination = .thread(thread)
        } else {
            destination = nil
        }
        return Row(id: entry.id, at: entry.at, title: entry.title,
                   detail: hideDetail ? nil : entry.detail,
                   authorisation: Self.authorisationWords(entry.authorisation),
                   outcome: Self.outcomeWords(entry),
                   goalTitle: goal?.title, destination: destination,
                   systemImage: Self.symbol(for: entry.kind))
    }

    static func authorisationWords(_ authorisation: ActivityAuthorisation) -> String {
        switch authorisation {
        case .asked:
            return String(localized: "You approved it", comment: "Activity screen: the wearer asked for or approved this.")
        case .standingGrant:
            return String(localized: "Under a permission you gave", comment: "Activity screen: a standing permission.")
        case .readOnly:
            return String(localized: "Refused: that connection is read-only", comment: "Activity screen: a read-only connection.")
        case .heldForYou:
            return String(localized: "Held for you", comment: "Activity screen: kept for the wearer to approve.")
        case .refused(let reason):
            return String(localized: "Refused: \(refusalWords(reason))", comment: "Activity screen: why it was refused.")
        case .scheduled:
            return String(localized: "Scheduled", comment: "Activity screen: a scheduled task did this.")
        }
    }

    /// A stable refusal code, in words. An unknown code still reads as a refusal.
    static func refusalWords(_ code: String) -> String {
        switch code {
        case ActivityFeed.RefusalCode.declined:
            return String(localized: "you said no", comment: "Activity screen: refusal reason.")
        case ActivityFeed.RefusalCode.blockedBySafety:
            return String(localized: "a safety rule stopped it", comment: "Activity screen: refusal reason.")
        case ActivityFeed.RefusalCode.noConfirmation:
            return String(localized: "there was no way to ask you", comment: "Activity screen: refusal reason.")
        case ActivityFeed.RefusalCode.consentWithdrawn:
            return String(localized: "you had withdrawn your consent", comment: "Activity screen: refusal reason.")
        case ToolRefusalReason.featureDisabled.rawValue:
            return String(localized: "that feature is off", comment: "Activity screen: refusal reason.")
        default:
            return String(localized: "it wasn't allowed", comment: "Activity screen: refusal reason.")
        }
    }

    /// Said only when it adds something: a held row already says it is waiting, and a refusal
    /// already says it did not run.
    static func outcomeWords(_ entry: ActivityEntry) -> String? {
        switch entry.outcome {
        case .done:
            return nil
        case .failed:
            return entry.kind == .refused ? nil
                : String(localized: "Didn't finish", comment: "Activity screen: an action that failed.")
        case .uncertain:
            return String(localized: "May not have gone through", comment: "Activity screen: an uncertain outcome.")
        case .waitingOnYou:
            return entry.kind == .held ? nil
                : String(localized: "Waiting on you", comment: "Activity screen: waiting on the wearer.")
        }
    }

    static func symbol(for kind: ActivityKind) -> String {
        switch kind {
        case .action: return "checkmark.circle"
        case .plannedStep: return "list.number"
        case .scheduledRun: return "clock"
        case .toldYou: return "speaker.wave.2"
        case .held: return "hand.raised"
        case .refused: return "nosign"
        }
    }
}

extension ActivityRef {
    /// The goal a `goal:<id>` link names.
    var goalUUID: UUID? {
        if case .goal(let id) = self { return UUID(uuidString: id) }
        return nil
    }

    /// The conversation thread a `thread:<id>` link names.
    var threadID: String? {
        if case .thread(let id) = self { return id }
        return nil
    }
}
