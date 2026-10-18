import Foundation

/// A suggestion that a step looks done, with the activity entry that suggests it. Only ever
/// offered to the wearer ("Looks like that's done — mark it?"); nothing in the app applies it.
struct GoalEvidenceSuggestion: Equatable, Sendable {
    let goalID: UUID
    let stepID: UUID
    let entryID: UUID
}

/// How the assistant moves a goal along (Plan IW). Pure: every input is a value, the clock and the
/// calendar are passed in, and nothing here changes a goal. The assistant never runs a step
/// unasked; this decides what it may *offer* and when it may *speak*.
enum GoalAdvancePolicy {

    // MARK: Next step

    /// The step to offer next: one marked `next`; otherwise the open step due soonest; otherwise
    /// the first open step in the wearer's order. A paused, finished or abandoned goal has none.
    static func nextStep(in goal: Goal) -> GoalStep? {
        guard goal.state == .active else { return nil }
        let actionable = goal.steps.filter { $0.state.isActionable }
        if let marked = actionable.first(where: { $0.state == .next }) { return marked }
        let dated = actionable.compactMap { step in step.dueAt.map { (step, $0) } }
        if let soonest = dated.min(by: { $0.1 < $1.1 }) { return soonest.0 }
        return actionable.first
    }

    /// What the assistant may offer to do when the goal comes up: the next step's suggested
    /// action, if it has one.
    static func offer(for goal: Goal) -> StepAction? {
        nextStep(in: goal)?.suggestedAction
    }

    // MARK: Evidence

    /// Whether an activity entry suggests a step is done.
    ///
    /// Only an entry *linked* to the step counts — a reminder that happens to be completed proves
    /// nothing about a goal it was never tied to. The entry must have finished (`done`, not failed,
    /// uncertain or still waiting), must not be a refusal or a held action, and when the step's
    /// suggested action names a tool, the entry must come from that tool. A step already done or
    /// skipped gets no suggestion. The result is a suggestion for the wearer to accept; it is never
    /// applied here or anywhere else.
    static func evidenceSuggestion(for entry: ActivityEntry, in goal: Goal) -> GoalEvidenceSuggestion? {
        guard goal.state == .active, entry.goalID == goal.id, let stepID = entry.stepID,
              let step = goal.steps.first(where: { $0.id == stepID }), step.state.isActionable,
              entry.outcome == .done else { return nil }
        switch entry.kind {
        case .held, .refused: return nil
        case .action, .plannedStep, .scheduledRun, .toldYou: break
        }
        switch entry.authorisation {
        case .asked, .standingGrant, .scheduled: break
        case .readOnly, .heldForYou, .refused: return nil
        }
        if let expectedTool = step.suggestedAction?.toolName, entry.tool != expectedTool { return nil }
        return GoalEvidenceSuggestion(goalID: goal.id, stepID: stepID, entryID: entry.id)
    }

    // MARK: Speaking about goals unprompted

    /// At most this many sentences about goals a day, from check-ins and offers the wearer did not
    /// ask for. Answers to "how's the garage going?" are not counted.
    static let dailySentenceCap = 2

    /// Whether one more unprompted goal sentence may be spoken now, given when the earlier ones
    /// were spoken. "A day" is the wearer's calendar day.
    static func maySpeakGoalSentence(spokenAt: [Date], now: Date, calendar: Calendar) -> Bool {
        let today = spokenAt.filter { calendar.isDate($0, inSameDayAs: now) }.count
        return today < dailySentenceCap
    }

    // MARK: Check-in cadence

    /// Whether a goal's check-in is due now.
    ///
    /// Only an active goal with something left to do is ever checked in on. `daily` is due once
    /// per calendar day; `weekly` once seven calendar days have passed; `beforeDue(days)` fires
    /// **once**, in the window that opens `days` calendar days before the due date (the goal's,
    /// else the next step's) and closes when it is due.
    static func isCheckInDue(goal: Goal, lastCheckIn: Date?, now: Date, calendar: Calendar) -> Bool {
        guard goal.state == .active, nextStep(in: goal) != nil else { return false }
        switch goal.checkIn {
        case .none:
            return false
        case .daily:
            guard let lastCheckIn else { return true }
            return calendar.startOfDay(for: lastCheckIn) < calendar.startOfDay(for: now)
        case .weekly:
            guard let lastCheckIn else { return true }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCheckIn),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            return days >= 7
        case .beforeDue(let days):
            guard let due = goal.dueAt ?? nextStep(in: goal)?.dueAt,
                  let windowStart = calendar.date(byAdding: .day, value: -days,
                                                  to: calendar.startOfDay(for: due)) else { return false }
            guard now >= windowStart, now < due else { return false }
            guard let lastCheckIn else { return true }
            return lastCheckIn < windowStart
        }
    }
}
