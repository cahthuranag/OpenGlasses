import Foundation

/// A goal the model has proposed and the parser has accepted, before the wearer says yes. Nothing
/// is stored until then; `makeGoal` is what the yes turns it into.
struct GoalProposal: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        let title: String
        let action: StepAction?
    }

    let title: String
    let why: String?
    let dueAt: Date?
    let steps: [Step]

    func makeGoal(id: UUID, createdAt: Date, checkIn: CheckInCadence,
                  persona: String? = nil, stepID: () -> UUID) -> Goal {
        Goal(id: id, title: title, why: why, createdAt: createdAt, dueAt: dueAt, state: .active,
             checkIn: checkIn,
             steps: steps.map { GoalStep(id: stepID(), title: $0.title, suggestedAction: $0.action) },
             persona: persona, source: .proposed)
    }
}

/// Why a proposal was refused as a whole. The drafter can ask again; nothing is half-kept.
enum GoalProposalProblem: Equatable, Sendable {
    case unreadable
    case missingTitle
    case titleTooLong(count: Int)
    case whyTooLong(count: Int)
    case dueDateUnreadable
    case dueDateInPast
    case tooFewSteps(count: Int)
    case tooManySteps(count: Int)
    case missingStepTitle(index: Int)
    case stepTitleTooLong(index: Int, count: Int)
}

/// Why one step lost its suggested action. The step is kept; only the offer goes.
enum DroppedActionReason: Equatable, Sendable {
    /// The kind is not in the closed set.
    case unknownKind(String)
    /// A field the kind needs is missing, unreadable or over its limit.
    case invalid(field: String)
    /// A time the action needs is not in the future.
    case dateInPast
    /// The tool is disabled, the integration is read-only, or it needs Agent Mode and that is off.
    case notPermitted
}

struct DroppedAction: Equatable, Sendable {
    let stepIndex: Int
    let reason: DroppedActionReason
}

enum GoalProposalOutcome: Equatable, Sendable {
    case accepted(GoalProposal, droppedActions: [DroppedAction])
    case rejected([GoalProposalProblem])
}

/// Validates the model's goal proposal (Plan IW).
///
/// The input is the structured completion's JSON: `{title, why?, dueAt?, steps: [{title,
/// action?}]}`. Problems with the goal itself — a title that is missing or too long, a due date in
/// the past, fewer than three or more than seven steps — refuse the proposal, all of them reported
/// at once. A problem with one step's *action* drops only that action: an unknown kind, a field
/// out of bounds, a time already gone, or an action the permission predicate turns down (a
/// disabled tool, a read-only integration). The predicate is injected so the scoped-grant rules
/// can replace the app's current one without touching this type.
struct GoalProposalParser {
    let now: Date
    let calendar: Calendar
    let isPermitted: (StepAction) -> Bool

    init(now: Date, calendar: Calendar, isPermitted: @escaping (StepAction) -> Bool) {
        self.now = now
        self.calendar = calendar
        self.isPermitted = isPermitted
    }

    func parse(_ json: String) -> GoalProposalOutcome {
        parse(Data(json.utf8))
    }

    func parse(_ data: Data) -> GoalProposalOutcome {
        guard let raw = try? JSONDecoder().decode(RawProposal.self, from: data) else {
            return .rejected([.unreadable])
        }
        var problems: [GoalProposalProblem] = []

        let title = Self.cleaned(raw.title)
        if title == nil { problems.append(.missingTitle) }
        if let title, title.count > GoalLimits.titleLength {
            problems.append(.titleTooLong(count: title.count))
        }
        let why = Self.cleaned(raw.why)
        if let why, why.count > GoalLimits.whyLength {
            problems.append(.whyTooLong(count: why.count))
        }

        var dueAt: Date?
        if let rawDue = Self.cleaned(raw.dueAt) {
            if let parsed = parseDate(rawDue) {
                if parsed <= now { problems.append(.dueDateInPast) } else { dueAt = parsed }
            } else {
                problems.append(.dueDateUnreadable)
            }
        }

        let rawSteps = raw.steps ?? []
        if rawSteps.count < GoalLimits.minimumProposedSteps {
            problems.append(.tooFewSteps(count: rawSteps.count))
        } else if rawSteps.count > GoalLimits.maximumProposedSteps {
            problems.append(.tooManySteps(count: rawSteps.count))
        }

        var steps: [GoalProposal.Step] = []
        var dropped: [DroppedAction] = []
        for (index, rawStep) in rawSteps.enumerated() {
            guard let stepTitle = Self.cleaned(rawStep.title) else {
                problems.append(.missingStepTitle(index: index))
                continue
            }
            guard stepTitle.count <= GoalLimits.stepTitleLength else {
                problems.append(.stepTitleTooLong(index: index, count: stepTitle.count))
                continue
            }
            var action: StepAction?
            if let rawAction = rawStep.action {
                switch resolve(rawAction) {
                case .success(let resolved):
                    if isPermitted(resolved) {
                        action = resolved
                    } else {
                        dropped.append(DroppedAction(stepIndex: index, reason: .notPermitted))
                    }
                case .failure(let reason):
                    dropped.append(DroppedAction(stepIndex: index, reason: reason.reason))
                }
            }
            steps.append(GoalProposal.Step(title: stepTitle, action: action))
        }

        guard problems.isEmpty, let title else { return .rejected(problems) }
        return .accepted(GoalProposal(title: title, why: why, dueAt: dueAt, steps: steps),
                         droppedActions: dropped)
    }

    // MARK: - Actions

    private struct Drop: Error { let reason: DroppedActionReason }

    private func resolve(_ raw: RawAction) -> Result<StepAction, Drop> {
        guard let kindName = Self.cleaned(raw.kind) else {
            return .failure(Drop(reason: .invalid(field: "kind")))
        }
        guard let kind = StepAction.Kind(rawValue: kindName) else {
            return .failure(Drop(reason: .unknownKind(kindName)))
        }
        func text(_ value: String?, _ field: String, limit: Int) -> Result<String, Drop> {
            guard let value = Self.cleaned(value), value.count <= limit else {
                return .failure(Drop(reason: .invalid(field: field)))
            }
            return .success(value)
        }
        func futureDate(_ value: String?, _ field: String) -> Result<Date, Drop> {
            guard let value = Self.cleaned(value), let date = parseDate(value) else {
                return .failure(Drop(reason: .invalid(field: field)))
            }
            return date > now ? .success(date) : .failure(Drop(reason: .dateInPast))
        }

        do {
            switch kind {
            case .reminder:
                let body = try text(raw.text, "text", limit: GoalLimits.actionTextLength).get()
                var at: Date?
                if raw.at != nil { at = try futureDate(raw.at, "at").get() }
                return .success(.reminder(text: body, at: at))
            case .calendarHold:
                let title = try text(raw.title, "title", limit: GoalLimits.titleLength).get()
                let at = try futureDate(raw.at, "at").get()
                guard let minutes = raw.minutes, GoalLimits.holdMinutes.contains(minutes) else {
                    return .failure(Drop(reason: .invalid(field: "minutes")))
                }
                return .success(.calendarHold(title: title, at: at, minutes: minutes))
            case .search:
                return .success(.search(query: try text(raw.query, "query",
                                                        limit: GoalLimits.actionTextLength).get()))
            case .draft:
                guard let name = Self.cleaned(raw.draftKind), let draftKind = DraftKind(rawValue: name) else {
                    return .failure(Drop(reason: .invalid(field: "draftKind")))
                }
                return .success(.draft(kind: draftKind,
                                       prompt: try text(raw.prompt, "prompt",
                                                        limit: GoalLimits.actionPromptLength).get()))
            case .scheduledCheck:
                guard let name = Self.cleaned(raw.every),
                      let every = ScheduledCheckInterval(rawValue: name) else {
                    return .failure(Drop(reason: .invalid(field: "every")))
                }
                return .success(.scheduledCheck(prompt: try text(raw.prompt, "prompt",
                                                                 limit: GoalLimits.actionPromptLength).get(),
                                                every: every))
            case .ask:
                return .success(.ask(question: try text(raw.question, "question",
                                                        limit: GoalLimits.actionTextLength).get()))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Dates

    /// A full ISO 8601 date-time, or a bare `yyyy-MM-dd` meaning the end of that day in the
    /// wearer's calendar — "before the twentieth" is still open all of the twentieth.
    func parseDate(_ raw: String) -> Date? {
        if let date = RecordJSONCodec.parse(raw) { return date }
        let parts = raw.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: start) == day,
              let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return next.addingTimeInterval(-1)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Raw shape

    /// Lenient on purpose: a field of the wrong type reads as absent and is then judged by the
    /// rules above, so one odd field produces a named reason instead of "unreadable".
    private struct RawProposal: Decodable {
        let title: String?
        let why: String?
        let dueAt: String?
        let steps: [RawStep]?

        private enum CodingKeys: String, CodingKey { case title, why, dueAt, steps }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            why = try? c.decodeIfPresent(String.self, forKey: .why)
            dueAt = try? c.decodeIfPresent(String.self, forKey: .dueAt)
            steps = try? c.decodeIfPresent([RawStep].self, forKey: .steps)
        }
    }

    private struct RawStep: Decodable {
        let title: String?
        let action: RawAction?

        private enum CodingKeys: String, CodingKey { case title, action }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            action = try? c.decodeIfPresent(RawAction.self, forKey: .action)
        }
    }

    private struct RawAction: Decodable {
        let kind, text, at, title, query, draftKind, prompt, every, question: String?
        let minutes: Int?

        private enum CodingKeys: String, CodingKey {
            case kind, text, at, title, query, draftKind, prompt, every, question, minutes
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func string(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
            kind = string(.kind)
            text = string(.text)
            at = string(.at)
            title = string(.title)
            query = string(.query)
            draftKind = string(.draftKind)
            prompt = string(.prompt)
            every = string(.every)
            question = string(.question)
            minutes = try? c.decodeIfPresent(Int.self, forKey: .minutes)
        }
    }
}
