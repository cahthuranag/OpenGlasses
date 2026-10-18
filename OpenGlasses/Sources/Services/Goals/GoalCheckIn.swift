import Foundation

// MARK: - Goal check-ins (Plan IW P2)
//
// A check-in is the assistant bringing a goal up by itself, at the cadence the wearer chose. It is
// background work, so it runs on the agent scheduler and only with Agent Mode on — turning Agent
// Mode off pauses check-ins and leaves the goals alone. A check-in is a *typed* scheduled task
// (`ScheduledTaskKind.goalCheckIn`), never a prompt string: it makes no model call, and it can only
// ever say the sentence `GoalPhraser.checkIn(for:)` builds.
//
// Everything here is pure. The scheduler hands in its tasks, the goals, the clock and whether the
// wearer is there to hear it, and gets back the tasks to keep and what to say and file.

/// What kind of scheduled task a task is, beyond the default prompt run. Persisted as a single
/// string — `goal_check_in:<uuid>` — so the stored list stays readable and a kind a newer build
/// writes does not stop an older one decoding the rest of the list.
enum ScheduledTaskKind: Equatable, Sendable {
    /// The check-in for one goal.
    case goalCheckIn(goalID: UUID)
    /// A kind this build does not know. Kept so the list still decodes; never run.
    case unrecognised(String)

    var codeValue: String {
        switch self {
        case .goalCheckIn(let id): return "goal_check_in:\(id.uuidString.lowercased())"
        case .unrecognised(let raw): return raw
        }
    }

    init(codeValue: String) {
        let prefix = "goal_check_in:"
        if codeValue.hasPrefix(prefix), let id = UUID(uuidString: String(codeValue.dropFirst(prefix.count))) {
            self = .goalCheckIn(goalID: id)
        } else {
            self = .unrecognised(codeValue)
        }
    }
}

extension ScheduledTaskKind: Codable {
    init(from decoder: Decoder) throws {
        self.init(codeValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(codeValue)
    }
}

extension AgentScheduler.ScheduledTask {
    /// The goal this task checks in on, when it is a goal check-in.
    var goalCheckInID: UUID? {
        if case .goalCheckIn(let id)? = kind { return id }
        return nil
    }

    /// An ordinary prompt task — the only kind the scheduler sends to the model.
    var isPromptTask: Bool { kind == nil }
}

/// Keeps one check-in task per goal that wants one (Plan IW P2).
enum GoalCheckInSchedule {

    /// The task's name. Deliberately not the goal's title: the scheduled-task list lives in
    /// `UserDefaults`, and a copy of the wearer's words there is a copy a goal's erasure would have
    /// to chase. The Scheduled Tasks screen shows the goal's title by looking the goal up.
    static let taskName = "Goal check-in"
    static let createdBy = "goals"

    static func taskID(for goalID: UUID) -> String {
        "goal-check-in-\(goalID.uuidString.lowercased())"
    }

    /// The task list with exactly one check-in task for each goal that has a cadence and is still
    /// open — on while the goal is active, off while it is paused — and none for any other goal
    /// (finished, set aside, cadence off, or gone). Prompt tasks are untouched and keep their order;
    /// a new check-in goes at the end.
    ///
    /// An existing check-in keeps when it last ran and last spoke, which is what makes
    /// `beforeDue(n)` fire once and the daily cap hold across a pause. A new daily or weekly
    /// check-in counts from `now`, so saying "check in every day" does not check in a minute later;
    /// a before-due one has its own window and starts with no run.
    static func reconciled(_ tasks: [AgentScheduler.ScheduledTask], goals: [Goal],
                           now: Date) -> [AgentScheduler.ScheduledTask] {
        let wanted = Dictionary(goals.filter(wantsCheckIn).map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var result: [AgentScheduler.ScheduledTask] = []
        for task in tasks {
            guard let goalID = task.goalCheckInID else {
                result.append(task)
                continue
            }
            guard let goal = wanted[goalID], !seen.contains(goalID) else { continue }
            seen.insert(goalID)
            var kept = task
            kept.name = taskName
            kept.enabled = goal.state == .active
            result.append(kept)
        }
        for goal in goals where wanted[goal.id] != nil && !seen.contains(goal.id) {
            seen.insert(goal.id)
            result.append(newTask(for: goal, now: now))
        }
        return result
    }

    /// What the Scheduled Tasks screen saves: its own edits to the prompt tasks, with the check-in
    /// tasks taken from what is stored now. The screen holds a copy of the list from when it
    /// opened; saving that copy whole would put back a check-in a finished goal has since removed,
    /// or lose a run the scheduler has since recorded.
    static func mergingEdits(_ edited: [AgentScheduler.ScheduledTask],
                             into stored: [AgentScheduler.ScheduledTask]) -> [AgentScheduler.ScheduledTask] {
        edited.filter { $0.goalCheckInID == nil } + stored.filter { $0.goalCheckInID != nil }
    }

    static func wantsCheckIn(_ goal: Goal) -> Bool {
        guard goal.checkIn != .none else { return false }
        return goal.state == .active || goal.state == .paused
    }

    private static func newTask(for goal: Goal, now: Date) -> AgentScheduler.ScheduledTask {
        let countsFromNow: Bool
        switch goal.checkIn {
        case .daily, .weekly: countsFromNow = true
        case .none, .beforeDue: countsFromNow = false
        }
        return AgentScheduler.ScheduledTask(
            id: taskID(for: goal.id), name: taskName, prompt: "", intervalMinutes: 0,
            enabled: goal.state == .active, lastRun: countsFromNow ? now : nil, speakResult: true,
            personaId: nil, modelId: nil, createdBy: createdBy,
            kind: .goalCheckIn(goalID: goal.id))
    }
}

/// What one check-in comes to: a digest line always, and a sentence when the wearer is there and
/// today's allowance is not used up.
struct GoalCheckInOutput: Equatable, Sendable {
    let goalID: UUID
    /// The digest item's stable id — one per goal, so a later check-in replaces the earlier one.
    let digestID: String
    let digestTitle: String
    let digestBody: String
    /// The one sentence to say, or nil when this check-in goes to the digest only.
    let spokenLine: String?
}

/// When check-ins run and what they say (Plan IW P2). Pure.
enum GoalCheckInPolicy {

    /// Which check-ins are due now, in the task list's order. None at all while Agent Mode is off:
    /// a check-in is background work, and the goals themselves do not need Agent Mode.
    static func due(tasks: [AgentScheduler.ScheduledTask], goals: [Goal], agentModeEnabled: Bool,
                    now: Date, calendar: Calendar) -> [(task: AgentScheduler.ScheduledTask, goal: Goal)] {
        guard agentModeEnabled else { return [] }
        return tasks.compactMap { task in
            guard task.enabled, let goalID = task.goalCheckInID,
                  let goal = goals.first(where: { $0.id == goalID }),
                  GoalAdvancePolicy.isCheckInDue(goal: goal, lastCheckIn: task.lastRun,
                                                 now: now, calendar: calendar) else { return nil }
            return (task, goal)
        }
    }

    /// Run every due check-in: what to file and say, and the tasks with each run recorded.
    ///
    /// Every due check-in is filed in the digest. At most `GoalAdvancePolicy.dailySentenceCap`
    /// of them are *said* in a calendar day, across all goals, and only while the wearer is there
    /// (`wearerPresent`); the rest wait in the digest. Each check-in task speaks at most once per
    /// run and each cadence fires at most once a day, so the tasks' own `lastSpokenAt` stamps are
    /// the day's count.
    static func run(tasks: [AgentScheduler.ScheduledTask], goals: [Goal], agentModeEnabled: Bool,
                    wearerPresent: Bool, now: Date,
                    calendar: Calendar) -> (tasks: [AgentScheduler.ScheduledTask], outputs: [GoalCheckInOutput]) {
        let dueNow = due(tasks: tasks, goals: goals, agentModeEnabled: agentModeEnabled,
                         now: now, calendar: calendar)
        guard !dueNow.isEmpty else { return (tasks, []) }
        let phraser = GoalPhraser(now: now, calendar: calendar)
        var spoken = tasks.compactMap(\.lastSpokenAt)
        var updated = tasks
        var outputs: [GoalCheckInOutput] = []
        for (task, goal) in dueNow {
            let line = phraser.checkIn(for: goal)
            let speaks = wearerPresent
                && GoalAdvancePolicy.maySpeakGoalSentence(spokenAt: spoken, now: now, calendar: calendar)
            if speaks { spoken.append(now) }
            outputs.append(GoalCheckInOutput(goalID: goal.id, digestID: digestID(for: goal.id),
                                             digestTitle: goal.title, digestBody: line,
                                             spokenLine: speaks ? line : nil))
            if let index = updated.firstIndex(where: { $0.id == task.id }) {
                updated[index].lastRun = now
                if speaks { updated[index].lastSpokenAt = now }
            }
        }
        return (updated, outputs)
    }

    static func digestID(for goalID: UUID) -> String {
        "goal-check-in:\(goalID.uuidString.lowercased())"
    }
}
