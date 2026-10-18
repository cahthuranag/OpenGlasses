import Foundation

/// The wearer's goals, by voice (Plan IW P1): make one, ask how it is going, mark steps done, pause,
/// finish or drop it.
///
/// Goals are the wearer's own list and work without Agent Mode; only a step's scheduled check —
/// background work — needs it. A proposed goal is read back and stored only when the wearer says
/// yes. The assistant never takes a step's suggested action from here: it offers it, and the
/// action runs through its own tool and confirmation if the wearer agrees. Not for a Field Assist
/// job's task list, which stays the job's.
@MainActor
final class GoalsTool: NativeTool {
    let name = "goals"
    let description = """
    The wearer's own goals: something they want done, broken into a few steps, kept on the phone. \
    Use it when they say "make a goal", "how's the garage going?", "what's next on …", "I've done …", \
    or want to pause, finish or drop a goal. Actions: 'list'; 'status' (pass 'goal'); 'next' (pass \
    'goal', or nothing for every goal); 'add' (pass 'title', and 'why' and 'due' if they said them; \
    pass 'steps' only when the wearer named the steps, otherwise three to seven are suggested — \
    nothing is saved yet, so read the result back); 'accept' once the wearer says yes to the \
    proposal (pass 'check_in' 'none' if they want it kept without check-ins); 'revise' to drop a \
    proposed step ('step') or rename it ('step' and 'new_title') before they say yes; 'decline' \
    when they say no; 'step_done' and 'skip' (pass 'goal' and 'step', a number or its words); \
    'complete', 'pause', 'resume' and 'abandon' (pass 'goal'); 'edit' (pass 'goal' and any of \
    'new_title', 'why', 'due', 'add_step', 'remove_step', 'check_in', or 'step' with 'new_title' \
    or 'step_action'). Never do a step's suggested action unasked: offer it, and only if the \
    wearer says yes do it with its own tool. Goals don't need Agent Mode; a scheduled check on a \
    step does. Not for a Field Assist job's tasks — a job keeps its own task list.
    """

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": ["type": "string", "enum": Self.actions],
                "goal": ["type": "string", "description": "Which goal: words from its title."],
                "title": ["type": "string", "description": "add: the goal, in the wearer's words."],
                "why": ["type": "string", "description": "add or edit: why it matters, if they said."],
                "due": ["type": "string",
                        "description": "add or edit: when it should be done by — YYYY-MM-DD or ISO 8601; 'none' clears it."],
                "steps": [
                    "type": "array",
                    "description": "add: only the steps the wearer named.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "action": GoalDrafter.actionSchema,
                        ],
                        "required": ["title"],
                    ],
                ],
                "step": ["type": "string", "description": "A step: its number or words from its title."],
                "new_title": ["type": "string", "description": "edit or revise: the new name, for the goal or for 'step'."],
                "add_step": ["type": "string", "description": "edit: a step to add at the end."],
                "remove_step": ["type": "string", "description": "edit: a step to remove."],
                "step_action": GoalDrafter.actionSchema.merging(
                    ["description": "edit: what the assistant may offer to do for 'step'."]) { _, new in new },
                "check_in": ["type": "string", "enum": ["none", "daily", "weekly", "before_due"],
                             "description": "accept or edit: how often to bring the goal up."],
            ],
            "required": ["action"],
        ]
    }

    static let actions = ["list", "status", "next", "add", "accept", "revise", "decline", "step_done",
                          "skip", "complete", "pause", "resume", "abandon", "edit"]

    private let store: @MainActor () -> GoalStore
    let drafter: GoalDrafter
    var agentModeEnabled: () -> Bool = { Config.agentModeEnabled }
    var enabledActionTools: () -> Set<String> = GoalsTool.liveEnabledActionTools
    var persona: () -> String? = { Config.activePersonaId }
    var clock: () -> Date = Date.init
    var calendar: () -> Calendar = { Calendar.current }

    /// `drafter` nil drafts with the app's own model, resolved when a goal is proposed.
    init(store: @escaping @MainActor () -> GoalStore = { GoalStore.shared },
         drafter: GoalDrafter? = nil) {
        self.store = store
        self.drafter = drafter ?? GoalDrafter(model: {
            LLMGoalDraftModel(llm: AppStateProvider.shared?.llmService)
        })
    }

    /// The tools a step's offer would run through, as the wearer has them switched on today.
    static func liveEnabledActionTools() -> Set<String> {
        Set(StepAction.Kind.allCases.compactMap(\.toolName).filter { tool in
            Config.isToolEnabled(tool) && !(Config.hipaaMode && Config.hipaaDisabledTools.contains(tool))
        })
    }

    static let agentModeRefusal =
        "Checking on a step by itself is background work, and that needs Agent Mode, which is off."

    // MARK: - Execute

    func execute(args: [String: Any]) async throws -> String {
        let action = (args["action"] as? String ?? "list").trimmingCharacters(in: .whitespaces).lowercased()
        let now = clock()
        let calendar = calendar()
        let phraser = GoalPhraser(now: now, calendar: calendar)
        let store = store()
        if store.isUnreadable && action != "list" && action != "decline" {
            store.reload()
        }
        if store.isUnreadable {
            return "Your goals can't be opened right now — the phone may need unlocking. Nothing was changed."
        }

        switch action {
        case "list":
            return list(store.goals, phraser: phraser)

        case "status":
            return withGoal(args, in: store) { phraser.status(of: $0) }

        case "next":
            if args["goal"] as? String != nil {
                return withGoal(args, in: store) { phraser.next(for: $0) }
            }
            return nextAcross(store.goals, now: now, calendar: calendar)

        case "add":
            return await add(args, now: now, calendar: calendar, phraser: phraser)

        case "accept":
            let cadence = Self.cadence(args["check_in"] as? String)
            switch drafter.accept(checkIn: cadence, persona: persona(), store: store, now: now) {
            case .stored(let goal):
                return Self.savedLine(goal, now: now, calendar: calendar)
            case .nothingPending:
                return "There's no goal waiting for a yes. Tell me the goal and I'll suggest steps."
            case .full:
                return "You have fifty goals already. Finish one or set one aside, then I can keep this one."
            case .unavailable:
                return "Your goals can't be opened right now, so nothing was saved."
            }

        case "revise":
            guard let step = Self.text(args["step"]) else { return "Which step should I change?" }
            switch drafter.revise(step: step, renameTo: Self.text(args["new_title"]), now: now) {
            case .revised(let proposal):
                return phraser.readBack(proposal)
            case .nothingPending:
                return "There's no proposed goal to change. Tell me the goal and I'll suggest steps."
            case .noSuchStep:
                return "I couldn't tell which step you meant. Say its number or some of its words."
            case .lastStep:
                return "That's the only step left. Say no to the goal instead, or rename the step."
            case .invalidTitle:
                return "That name is too long for a step. Can you say it more briefly?"
            }

        case "decline":
            return drafter.decline() ? "Okay, I won't keep that one." : "Okay. There was no goal waiting."

        case "step_done", "skip":
            return changeStep(args, in: store, to: action == "skip" ? .skipped : .done,
                              now: now, phraser: phraser)

        case "complete":
            return changeState(args, in: store, to: .done, from: [.active, .paused]) {
                "Marked done: \($0.title)."
            }
        case "pause":
            return changeState(args, in: store, to: .paused, from: [.active]) {
                "Paused: \($0.title). I won't bring it up until you pick it back up."
            }
        case "resume":
            return changeState(args, in: store, to: .active, from: [.paused, .abandoned]) {
                "Back on: \($0.title). " + phraser.progress(of: $0)
            }
        case "abandon":
            return changeState(args, in: store, to: .abandoned, from: [.active, .paused]) {
                "Set aside: \($0.title)."
            }

        case "edit":
            return edit(args, in: store, now: now, calendar: calendar, phraser: phraser)

        default:
            return "Unknown action '\(action)'. Use one of: \(Self.actions.joined(separator: ", "))."
        }
    }

    // MARK: - Reading

    private func list(_ goals: [Goal], phraser: GoalPhraser) -> String {
        let open = goals.filter { $0.state == .active || $0.state == .paused }
        guard !open.isEmpty else {
            return "You don't have any goals on the go. Say \"make a goal\" to start one."
        }
        let lines = open.map { goal -> String in
            let state = goal.state == .paused ? "paused" : phraser.progress(of: goal)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return "\(goal.title): \(SpokenPhrasing.listCased(state))."
        }
        let opening = open.count == 1 ? "You have one goal." :
            "You have \(SpokenPhrasing.number(open.count)) goals."
        return ([opening] + lines).joined(separator: " ")
    }

    private func nextAcross(_ goals: [Goal], now: Date, calendar: Calendar) -> String {
        let active = goals.filter { $0.state == .active && GoalAdvancePolicy.nextStep(in: $0) != nil }
        guard !active.isEmpty else { return "Nothing's next on your goals." }
        return ActivityPhraser(now: now, timeZone: calendar.timeZone)
            .whatsNext(goals: active, scheduled: [], entries: [])
    }

    // MARK: - Proposing

    private func add(_ args: [String: Any], now: Date, calendar: Calendar,
                     phraser: GoalPhraser) async -> String {
        guard let title = Self.text(args["title"]) else {
            return "What's the goal? Tell me what you want done, and by when if there's a date."
        }
        let agentMode = agentModeEnabled()
        let parser = GoalProposalParser(
            now: now, calendar: calendar,
            isPermitted: StepActionPermission.predicate(enabledTools: enabledActionTools(),
                                                        agentModeEnabled: agentMode))
        let rawSteps = Self.rawSteps(args["steps"])
        guard !rawSteps.isEmpty else {
            // Only a title: the drafter asks the model for three to seven steps.
            var request = title
            if let why = Self.text(args["why"]) { request += ". Why: \(why)" }
            if let due = Self.text(args["due"]) { request += ". Due: \(due)" }
            return await drafter.propose(request: request, parser: parser, phraser: phraser,
                                         agentModeEnabled: agentMode)
        }
        var proposal: [String: Any] = ["title": title, "steps": rawSteps]
        if let why = Self.text(args["why"]) { proposal["why"] = why }
        if let due = Self.text(args["due"]) { proposal["dueAt"] = due }
        guard let data = try? JSONSerialization.data(withJSONObject: proposal) else {
            return "I couldn't read those steps. Tell me them again."
        }
        var said = drafter.hold(parser.parse(data), fromWearer: true, phraser: phraser, now: now)
        let askedForChecks = rawSteps.contains {
            (($0["action"] as? [String: Any])?["kind"] as? String) == StepAction.Kind.scheduledCheck.rawValue
        }
        if askedForChecks, !agentMode { said += " " + Self.agentModeRefusal }
        return said
    }

    // MARK: - Changing

    private func withGoal(_ args: [String: Any], in store: GoalStore, _ body: (Goal) -> String) -> String {
        switch resolveGoal(args, in: store) {
        case .found(let goal): return body(goal)
        case .missing(let line): return line
        }
    }

    private enum Resolved {
        case found(Goal)
        case missing(String)
    }

    /// The goal the call names, or — with no name and exactly one open goal — that one.
    private func resolveGoal(_ args: [String: Any], in store: GoalStore) -> Resolved {
        if let query = Self.text(args["goal"]) {
            if let goal = GoalMatching.goal(query, in: store.goals) { return .found(goal) }
            return .missing("I couldn't tell which goal you meant. Your goals are: "
                            + Self.titles(store.openGoals) + ".")
        }
        let open = store.openGoals
        if open.count == 1 { return .found(open[0]) }
        if open.isEmpty { return .missing("You don't have any goals on the go.") }
        return .missing("Which goal? You have: " + Self.titles(open) + ".")
    }

    private func changeStep(_ args: [String: Any], in store: GoalStore, to state: GoalStepState,
                            now: Date, phraser: GoalPhraser) -> String {
        let goal: Goal
        switch resolveGoal(args, in: store) {
        case .found(let found): goal = found
        case .missing(let line): return line
        }
        guard let query = Self.text(args["step"]) ?? GoalAdvancePolicy.nextStep(in: goal)?.title,
              let index = GoalMatching.stepIndex(query, in: goal.steps.map(\.title)) else {
            return "I couldn't tell which step you meant on \(goal.title)."
        }
        let step = goal.steps[index]
        guard let updated = store.update(goal.id, { changed in
            changed.steps[index].state = state
            changed.steps[index].doneAt = state == .done ? now : nil
        }) else { return "That goal can't be changed right now." }
        let done = state == .done ? "Marked done: \(step.title)." : "Skipped: \(step.title)."
        if updated.state == .active, GoalAdvancePolicy.nextStep(in: updated) == nil {
            return done + " That was the last step. Want me to mark the goal done?"
        }
        return done + " " + phraser.status(of: updated)
    }

    private func changeState(_ args: [String: Any], in store: GoalStore, to state: GoalState,
                             from allowed: Set<GoalState>, said: (Goal) -> String) -> String {
        switch resolveGoal(args, in: store) {
        case .missing(let line):
            return line
        case .found(let goal):
            guard allowed.contains(goal.state) else {
                return goal.state == state ? "\(goal.title) is already \(Self.word(state))."
                    : "\(goal.title) is \(Self.word(goal.state)), so I left it as it is."
            }
            guard let updated = store.update(goal.id, { $0.state = state }) else {
                return "That goal can't be changed right now."
            }
            return said(updated)
        }
    }

    private func edit(_ args: [String: Any], in store: GoalStore, now: Date, calendar: Calendar,
                      phraser: GoalPhraser) -> String {
        let goal: Goal
        switch resolveGoal(args, in: store) {
        case .found(let found): goal = found
        case .missing(let line): return line
        }
        let parser = GoalProposalParser(
            now: now, calendar: calendar,
            isPermitted: StepActionPermission.predicate(enabledTools: enabledActionTools(),
                                                        agentModeEnabled: agentModeEnabled()))
        var working = goal
        var changes: [String] = []

        if let stepQuery = Self.text(args["step"]) {
            guard let index = GoalMatching.stepIndex(stepQuery, in: working.steps.map(\.title)) else {
                return "I couldn't tell which step you meant on \(goal.title)."
            }
            if let renamed = Self.text(args["new_title"]) {
                guard renamed.count <= GoalLimits.stepTitleLength else {
                    return "That name is too long for a step. Can you say it more briefly?"
                }
                working.steps[index].title = renamed
                changes.append("renamed the step")
            }
            if let raw = args["step_action"] as? [String: Any] {
                if (raw["kind"] as? String) == StepAction.Kind.scheduledCheck.rawValue, !agentModeEnabled() {
                    return Self.agentModeRefusal + " I left \(goal.title) as it was."
                }
                guard let data = try? JSONSerialization.data(withJSONObject: raw) else {
                    return "I couldn't read that offer."
                }
                switch parser.parseAction(data) {
                case .accepted(let action):
                    working.steps[index].suggestedAction = action
                    changes.append("changed what I'll offer for that step")
                case .dropped(.notPermitted):
                    return "I can't offer that here — the tool it needs is switched off. I left the step as it was."
                case .dropped(.dateInPast):
                    return "That time has already gone, so I left the step as it was."
                case .dropped:
                    return "I couldn't use that offer, so I left the step as it was."
                }
            }
        } else if let renamed = Self.text(args["new_title"]) {
            guard renamed.count <= GoalLimits.titleLength else {
                return "That's a bit long for a goal. Can you say it more briefly?"
            }
            working.title = renamed
            changes.append("renamed it")
        }

        if let why = Self.text(args["why"]) {
            guard why.count <= GoalLimits.whyLength else { return "That reason is a bit long. Can you say it more briefly?" }
            working.why = why
            changes.append("noted why")
        }
        if let due = Self.text(args["due"]) {
            if due.lowercased() == "none" {
                working.dueAt = nil
                changes.append("took the date off")
            } else {
                guard let date = parser.parseDate(due) else { return "I didn't catch the date." }
                guard date > now else { return "That date has already gone." }
                working.dueAt = date
                changes.append("set it for \(SpokenPhrasing.day(date, now: now, calendar: calendar))")
            }
        }
        if let added = Self.text(args["add_step"]) {
            guard added.count <= GoalLimits.stepTitleLength else {
                return "That step is a bit long. Can you say it more briefly?"
            }
            working.steps.append(GoalStep(id: UUID(), title: added))
            changes.append("added a step")
        }
        if let removing = Self.text(args["remove_step"]) {
            guard let index = GoalMatching.stepIndex(removing, in: working.steps.map(\.title)) else {
                return "I couldn't tell which step to remove from \(goal.title)."
            }
            working.steps.remove(at: index)
            changes.append("removed a step")
        }
        if let raw = args["check_in"] as? String, let cadence = Self.cadence(raw) {
            working.checkIn = cadence
            changes.append(cadence == .none ? "stopped the check-ins" : "changed the check-ins")
        }

        guard !changes.isEmpty else { return "What should I change about \(goal.title)?" }
        guard store.update(goal.id, { $0 = working }) != nil else {
            return "That goal can't be changed right now."
        }
        return "Done: I " + SpokenPhrasing.joined(changes) + ". " + phraser.progress(of: working)
    }

    // MARK: - Words and arguments

    static func savedLine(_ goal: Goal, now: Date, calendar: Calendar) -> String {
        let steps = SpokenPhrasing.count(goal.steps.count, "step")
        var line = "Saved: \(goal.title), with \(steps)."
        switch goal.checkIn {
        case .none: break
        case .daily: line += " I'll check in once a day."
        case .weekly: line += " I'll check in once a week."
        case .beforeDue(let days):
            line += " I'll check in \(SpokenPhrasing.count(days, "day")) before it's due."
        }
        return line
    }

    /// `check_in` as a cadence. Nil for "not said" — the default then applies. `before_due` counts
    /// the default two days back.
    static func cadence(_ raw: String?) -> CheckInCadence? {
        switch raw?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "none": return CheckInCadence.none
        case "daily": return .daily
        case "weekly": return .weekly
        case "before_due": return .beforeDue(days: CheckInCadence.defaultBeforeDueDays)
        default: return nil
        }
    }

    private static func word(_ state: GoalState) -> String {
        switch state {
        case .active: return "on"
        case .paused: return "paused"
        case .done: return "done"
        case .abandoned: return "set aside"
        }
    }

    private static func titles(_ goals: [Goal]) -> String {
        goals.isEmpty ? "none on the go" : SpokenPhrasing.joined(goals.map(\.title))
    }

    static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// Steps as the parser reads them: objects with a title, or plain titles.
    static func rawSteps(_ value: Any?) -> [[String: Any]] {
        if let objects = value as? [[String: Any]] { return objects }
        if let titles = value as? [String] { return titles.map { ["title": $0] } }
        if let mixed = value as? [Any] {
            return mixed.compactMap { item in
                if let object = item as? [String: Any] { return object }
                if let title = item as? String { return ["title": title] }
                return nil
            }
        }
        return []
    }
}
