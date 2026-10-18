import Foundation

/// The exact words the assistant says about goals (Plan IW). Second person, the assistant's own
/// voice, and short enough to hear on the glasses. Every string is pinned by `GoalPhraserTests`.
struct GoalPhraser: Sendable {
    let now: Date
    let calendar: Calendar

    init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    // MARK: Status — "How's the garage going?"

    /// "Two of four done. Next: List the bike for sale, due Saturday. Want me to draft the listing?"
    func status(of goal: Goal) -> String {
        switch goal.state {
        case .paused:
            return "That goal's paused. " + progress(of: goal)
        case .done:
            return "That goal's done."
        case .abandoned:
            return "You set that goal aside."
        case .active:
            break
        }
        var sentences = [progress(of: goal)]
        if let step = GoalAdvancePolicy.nextStep(in: goal) {
            sentences.append(nextClause(step))
            if let action = step.suggestedAction { sentences.append(offer(action)) }
        } else if !goal.countedSteps.isEmpty {
            sentences.append("Want me to mark the goal done?")
        }
        return sentences.joined(separator: " ")
    }

    /// "Two of four done." — skipped steps are left out of the count; the goal's due date, when it
    /// has one, rides on the same sentence.
    func progress(of goal: Goal) -> String {
        let total = goal.countedSteps.count
        let done = goal.doneStepCount
        let due = goal.dueAt.map { ", due \(SpokenPhrasing.day($0, now: now, calendar: calendar))" } ?? ""
        let clause: String
        if total == 0 {
            clause = "There are no steps on it yet"
        } else if done == total {
            clause = total == 1 ? "The one step is done" : "All \(SpokenPhrasing.number(total)) done"
        } else if done == 0 {
            clause = total == 1 ? "Not started yet" : "None of \(SpokenPhrasing.number(total)) done yet"
        } else {
            clause = "\(SpokenPhrasing.capitalisedFirst(SpokenPhrasing.number(done))) of "
                + "\(SpokenPhrasing.number(total)) done"
        }
        return clause + due + "."
    }

    // MARK: Next — "What's next on the garage?"

    /// "Next on Clear the garage: Book the skip, due tomorrow. Want me to search for skip hire?"
    func next(for goal: Goal) -> String {
        guard goal.state == .active else { return status(of: goal) }
        guard let step = GoalAdvancePolicy.nextStep(in: goal) else {
            return "Nothing's left to do on \(goal.title)."
        }
        var sentences = ["Next on \(goal.title): " + stepClause(step) + "."]
        if let action = step.suggestedAction { sentences.append(offer(action)) }
        return sentences.joined(separator: " ")
    }

    // MARK: Proposal read-back — before anything is stored

    /// "Okay. I'd break that into: book the skip, sort the shelves, list the bike for sale, and
    /// drop the paint at the depot. Want me to keep an eye on it?"
    func readBack(_ proposal: GoalProposal) -> String {
        let opening = proposal.dueAt.map {
            "Okay, by \(SpokenPhrasing.day($0, now: now, calendar: calendar))."
        } ?? "Okay."
        let steps = SpokenPhrasing.joined(proposal.steps.map { SpokenPhrasing.listCased($0.title) })
        return "\(opening) I'd break that into: \(steps). Want me to keep an eye on it?"
    }

    // MARK: Evidence — suggested, never applied

    /// "Looks like this one's done: Book the skip. Want me to mark it done?"
    func evidenceSuggestion(for step: GoalStep) -> String {
        "Looks like this one's done: \(step.title). Want me to mark it done?"
    }

    // MARK: Offers

    /// The question that offers a step's suggested action. Always a question: the action runs only
    /// if the wearer says yes, and then through its own tool and confirmation.
    func offer(_ action: StepAction) -> String {
        switch action {
        case .reminder(_, let at):
            guard let at else { return "Want me to set a reminder?" }
            return "Want me to remind you \(SpokenPhrasing.dayAndTime(at, now: now, calendar: calendar))?"
        case .calendarHold(_, let at, let minutes):
            return "Want me to hold \(Self.duration(minutes)) in your calendar "
                + "\(SpokenPhrasing.dayAndTime(at, now: now, calendar: calendar))?"
        case .search(let query):
            return "Want me to search for \(query)?"
        case .draft(let kind, _):
            return "Want me to draft the \(kind.rawValue)?"
        case .scheduledCheck(_, let every):
            return "Want me to check on it every \(every == .daily ? "day" : "week")?"
        case .ask(let question):
            let trimmed = question.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix("?") ? trimmed : SpokenPhrasing.sentence(trimmed)
        }
    }

    // MARK: Pieces

    private func nextClause(_ step: GoalStep) -> String {
        "Next: " + stepClause(step) + "."
    }

    private func stepClause(_ step: GoalStep) -> String {
        let due = step.dueAt.map { ", due \(SpokenPhrasing.day($0, now: now, calendar: calendar))" } ?? ""
        return step.title + due
    }

    /// "30 minutes", "an hour", "two hours", "90 minutes".
    static func duration(_ minutes: Int) -> String {
        if minutes == 60 { return "an hour" }
        if minutes > 60, minutes % 60 == 0 { return SpokenPhrasing.count(minutes / 60, "hour") }
        return "\(minutes) minutes"
    }
}
