import Foundation

// MARK: - The model call (Plan IW P1)

/// The one structured completion behind a proposed goal. A protocol so `GoalDrafterTests` can hand
/// back a fixed answer without a network.
@MainActor
protocol GoalDraftModel: AnyObject {
    /// The model's JSON object for the wearer's request, or nil when no answer came back.
    func draftGoal(system: String, request: String, schema: [String: Any]) async -> Data?
}

/// The production model: the app's own stateless structured completion for whichever provider is
/// configured (forced tool use or JSON mode on the cloud providers, prompted JSON on device). It
/// never touches the conversation history.
@MainActor
final class LLMGoalDraftModel: GoalDraftModel {
    private weak var llm: LLMService?

    init(llm: LLMService?) {
        self.llm = llm
    }

    func draftGoal(system: String, request: String, schema: [String: Any]) async -> Data? {
        guard let llm,
              let object = await llm.completeStructured(systemPrompt: system, userText: request,
                                                         jsonSchema: schema, toolName: "goal",
                                                         maxTokens: 1024) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }
}

// MARK: - Proposal → read-back → yes, edit or no

/// Turns "make a goal …" into a goal the wearer has agreed to (Plan IW P1).
///
/// A proposal — drafted by the model, or built from steps the wearer dictated — goes through
/// `GoalProposalParser`, is read back through `GoalPhraser`, and is held here. **Nothing is stored
/// until the wearer says yes** (`accept`); they can drop or rename a step first (`revise`), or say
/// no (`decline`), and an unanswered proposal lapses after fifteen minutes. One proposal at a time:
/// a new one replaces the last.
@MainActor
final class GoalDrafter {

    struct Pending: Equatable {
        var proposal: GoalProposal
        let droppedActions: [DroppedAction]
        let fromWearer: Bool
        let createdAt: Date
    }

    static let pendingLifetime: TimeInterval = 15 * 60

    private let model: @MainActor () -> GoalDraftModel?
    private var held: Pending?

    init(model: @escaping @MainActor () -> GoalDraftModel?) {
        self.model = model
    }

    /// The proposal waiting for an answer, if it has not lapsed.
    func pending(at now: Date) -> Pending? {
        guard let held, now.timeIntervalSince(held.createdAt) <= Self.pendingLifetime else { return nil }
        return held
    }

    // MARK: Proposing

    /// Ask the model to break the wearer's goal into steps, then hold and read back the proposal.
    func propose(request: String, parser: GoalProposalParser, phraser: GoalPhraser,
                 agentModeEnabled: Bool) async -> String {
        guard let model = model() else {
            return "I can't suggest steps without a model to ask. Tell me the steps and I'll set it up."
        }
        let system = Self.systemPrompt(now: parser.now, calendar: parser.calendar,
                                       agentModeEnabled: agentModeEnabled)
        guard let data = await model.draftGoal(system: system, request: request,
                                               schema: Self.schema) else {
            return "I couldn't work out steps for that just now. Tell me the steps, or try again in a moment."
        }
        return hold(parser.parse(data), fromWearer: false, phraser: phraser, now: parser.now)
    }

    /// Hold a parsed proposal and say it back, or say why it could not be held.
    func hold(_ outcome: GoalProposalOutcome, fromWearer: Bool, phraser: GoalPhraser,
              now: Date) -> String {
        switch outcome {
        case .rejected(let problems):
            return Self.refusal(problems, fromWearer: fromWearer)
        case .accepted(let proposal, let dropped):
            held = Pending(proposal: proposal, droppedActions: dropped, fromWearer: fromWearer,
                           createdAt: now)
            return phraser.readBack(proposal) + Self.droppedNote(dropped)
        }
    }

    // MARK: Answering

    enum Acceptance: Equatable {
        case stored(Goal)
        case nothingPending
        case full
        case unavailable
    }

    /// The wearer said yes: the held proposal becomes a goal. `checkIn` nil takes the default —
    /// one check-in two days before it is due, none without a due date.
    func accept(checkIn: CheckInCadence?, persona: String?, store: GoalStore, now: Date,
                makeID: () -> UUID = UUID.init) -> Acceptance {
        guard let pending = pending(at: now) else { return .nothingPending }
        let proposal = pending.proposal
        let goal = Goal(id: makeID(), title: proposal.title, why: proposal.why, createdAt: now,
                        dueAt: proposal.dueAt, state: .active,
                        checkIn: checkIn ?? CheckInCadence.defaultCadence(dueAt: proposal.dueAt),
                        steps: proposal.steps.map {
                            GoalStep(id: makeID(), title: $0.title, suggestedAction: $0.action)
                        },
                        persona: persona, source: pending.fromWearer ? .wearer : .proposed)
        switch store.add(goal) {
        case .added:
            held = nil
            return .stored(goal)
        case .full:
            return .full
        case .unavailable:
            return .unavailable
        }
    }

    enum Revision: Equatable {
        case revised(GoalProposal)
        case nothingPending
        case noSuchStep
        case lastStep
        case invalidTitle
    }

    /// The wearer changed a step before saying yes: drop it, or rename it. `step` is a 1-based
    /// number or words from the step's title.
    func revise(step: String, renameTo newTitle: String?, now: Date) -> Revision {
        guard var pending = pending(at: now) else { return .nothingPending }
        guard let index = GoalMatching.stepIndex(step, in: pending.proposal.steps.map(\.title)) else {
            return .noSuchStep
        }
        var steps = pending.proposal.steps
        if let newTitle {
            let cleaned = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count <= GoalLimits.stepTitleLength else { return .invalidTitle }
            steps[index] = GoalProposal.Step(title: cleaned, action: steps[index].action)
        } else {
            guard steps.count > 1 else { return .lastStep }
            steps.remove(at: index)
        }
        let old = pending.proposal
        pending.proposal = GoalProposal(title: old.title, why: old.why, dueAt: old.dueAt, steps: steps)
        held = pending
        return .revised(pending.proposal)
    }

    /// The wearer said no. Nothing was stored, and now nothing is held.
    @discardableResult
    func decline() -> Bool {
        defer { held = nil }
        return held != nil
    }

    // MARK: Words

    static func refusal(_ problems: [GoalProposalProblem], fromWearer: Bool) -> String {
        for problem in problems {
            switch problem {
            case .tooFewSteps, .tooManySteps:
                return fromWearer
                    ? "A goal needs three to seven steps. Tell me the steps again, or ask me to suggest them."
                    : "I couldn't break that into a sensible number of steps. Tell me the steps, or say it another way."
            case .dueDateInPast:
                return "That date has already gone. When should it be done by?"
            case .dueDateUnreadable:
                return "I didn't catch the date. When should it be done by?"
            case .titleTooLong, .whyTooLong, .stepTitleTooLong:
                return "That's a bit long to keep as a goal. Can you say it more briefly?"
            case .missingTitle, .missingStepTitle, .unreadable:
                continue
            }
        }
        return "I couldn't turn that into a goal. Tell me the goal and its steps, or say it another way."
    }

    /// Said after the read-back when an offer was left off a step.
    static func droppedNote(_ dropped: [DroppedAction]) -> String {
        guard !dropped.isEmpty else { return "" }
        return " I left out " + (dropped.count == 1 ? "one thing I'd have offered" :
            "\(SpokenPhrasing.number(dropped.count)) things I'd have offered")
            + ", because I can't do " + (dropped.count == 1 ? "it" : "them") + " here."
    }

    // MARK: Prompt and schema

    static func systemPrompt(now: Date, calendar: Calendar, agentModeEnabled: Bool) -> String {
        let today = dayStamp(now, calendar: calendar)
        let kinds = agentModeEnabled
            ? "reminder, calendar_hold, search, draft, scheduled_check or ask"
            : "reminder, calendar_hold, search, draft or ask"
        return """
        You turn a goal the wearer stated into a short plan. Return only the JSON object.
        - title: the goal in the wearer's own words, at most 80 characters.
        - why: only if they said why, at most 140 characters.
        - dueAt: only if they named a date or deadline. A day is "YYYY-MM-DD"; a moment is ISO 8601 \
        with its offset. Today is \(today) in \(calendar.timeZone.identifier). It must be in the future.
        - steps: three to seven, in a sensible order, each a short instruction of at most 80 \
        characters ("Book the skip").
        - action: optional, at most one per step, and only where it would genuinely help — one of \
        \(kinds). Never invent another kind.
        """
    }

    private static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The shape the parser reads: `{title, why?, dueAt?, steps: [{title, action?}]}`.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "why": ["type": "string"],
            "dueAt": ["type": "string"],
            "steps": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "action": actionSchema,
                    ],
                    "required": ["title"],
                ],
            ],
        ],
        "required": ["title", "steps"],
    ]

    /// One suggested action. `kind` names the closed set; the other fields are what that kind needs.
    static let actionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "kind": ["type": "string", "enum": StepAction.Kind.allCases.map(\.rawValue)],
            "text": ["type": "string", "description": "reminder: what to remind"],
            "at": ["type": "string", "description": "reminder or calendar_hold: ISO 8601 time"],
            "title": ["type": "string", "description": "calendar_hold: the event title"],
            "minutes": ["type": "integer", "description": "calendar_hold: 5 to 480"],
            "query": ["type": "string", "description": "search: what to search for"],
            "draftKind": ["type": "string", "enum": DraftKind.allCases.map(\.rawValue)],
            "prompt": ["type": "string", "description": "draft or scheduled_check: what to write or check"],
            "every": ["type": "string", "enum": ScheduledCheckInterval.allCases.map(\.rawValue)],
            "question": ["type": "string", "description": "ask: the question for the wearer"],
        ],
        "required": ["kind"],
    ]
}

// MARK: - Finding a goal or a step by what the wearer called it

enum GoalMatching {
    /// The goal `query` names: an exact title, else one title containing it, preferring open goals.
    /// Nil when nothing matches or several do equally.
    static func goal(_ query: String, in goals: [Goal]) -> Goal? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let id = UUID(uuidString: needle), let byID = goals.first(where: { $0.id == id }) { return byID }
        let open = goals.filter { $0.state == .active || $0.state == .paused }
        for pool in [open, goals] {
            let exact = pool.filter { $0.title.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if exact.count == 1 { return exact[0] }
            let containing = pool.filter { $0.title.localizedCaseInsensitiveContains(needle)
                || needle.localizedCaseInsensitiveContains($0.title) }
            if containing.count == 1 { return containing[0] }
            if containing.count > 1 { return nil }
        }
        return nil
    }

    /// The index of the step `query` names: a 1-based number, an exact title, else the one title
    /// containing it.
    static func stepIndex(_ query: String, in titles: [String]) -> Int? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let number = Int(needle) {
            return number >= 1 && number <= titles.count ? number - 1 : nil
        }
        if let exact = titles.firstIndex(where: {
            $0.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) { return exact }
        let containing = titles.indices.filter { titles[$0].localizedCaseInsensitiveContains(needle) }
        return containing.count == 1 ? containing[0] : nil
    }
}
