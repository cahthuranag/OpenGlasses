import Foundation

/// The kinds of thing a draft can be. Closed, so a drafting turn knows what it is writing.
enum DraftKind: String, Codable, Equatable, Sendable, CaseIterable {
    case message = "message"
    case email = "email"
    case note = "note"
    case listing = "listing"
    case document = "document"
}

/// How often a scheduled check on a step repeats.
enum ScheduledCheckInterval: String, Codable, Equatable, Sendable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
}

/// The **closed set** of things the assistant may offer to do for a step (Plan IW).
///
/// Each case maps to a tool that already exists and therefore to the authorization boundary that
/// tool already sits behind: a step can only ever suggest what the assistant could have been asked
/// to do directly. There is no argument bag and no arbitrary tool name — a model that wants
/// something else gets its action dropped by `GoalProposalParser`, and the step stays.
enum StepAction: Equatable, Sendable {
    case reminder(text: String, at: Date?)
    case calendarHold(title: String, at: Date, minutes: Int)
    case search(query: String)
    case draft(kind: DraftKind, prompt: String)
    case scheduledCheck(prompt: String, every: ScheduledCheckInterval)
    case ask(question: String)

    /// The persisted discriminator. Stable: renaming a case does not change it.
    enum Kind: String, Codable, Equatable, Sendable, CaseIterable {
        case reminder = "reminder"
        case calendarHold = "calendar_hold"
        case search = "search"
        case draft = "draft"
        case scheduledCheck = "scheduled_check"
        case ask = "ask"
    }

    var kind: Kind {
        switch self {
        case .reminder: return .reminder
        case .calendarHold: return .calendarHold
        case .search: return .search
        case .draft: return .draft
        case .scheduledCheck: return .scheduledCheck
        case .ask: return .ask
        }
    }

    /// The registered tool this action would run through, or nil when it runs through none: a
    /// draft is a drafting turn whose sending (if any) goes through its own tool and confirmation
    /// later, and a question is asked of the wearer.
    var toolName: String? { kind.toolName }

    /// Whether running it is background work, which needs Agent Mode (goals themselves do not).
    var needsAgentMode: Bool { kind == .scheduledCheck }
}

extension StepAction.Kind {
    var toolName: String? {
        switch self {
        case .reminder: return "reminder"
        case .calendarHold: return "calendar"
        case .search: return "web_search"
        case .scheduledCheck: return "manage_schedule"
        case .draft, .ask: return nil
        }
    }
}

// MARK: - Permission seam

/// Decides whether a suggested action may be offered at all. `GoalProposalParser` takes this as a
/// plain predicate so the scoped-grant work can plug its own rule in later; this is the rule the
/// app can state today.
enum StepActionPermission {
    /// An action is offered only when the tool it runs through is enabled, the integration behind
    /// it is not read-only, and — for background work — Agent Mode is on. An action with no tool
    /// (a draft, a question) is always offerable.
    static func predicate(enabledTools: Set<String>,
                          readOnlyTools: Set<String> = [],
                          agentModeEnabled: Bool) -> (StepAction) -> Bool {
        return { action in
            if action.needsAgentMode && !agentModeEnabled { return false }
            guard let tool = action.toolName else { return true }
            return enabledTools.contains(tool) && !readOnlyTools.contains(tool)
        }
    }
}

// MARK: - Codec

extension StepAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, text, at, title, minutes, query, draftKind, prompt, every, question
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .reminder:
            self = .reminder(text: try container.decode(String.self, forKey: .text),
                             at: try container.decodeIfPresent(Date.self, forKey: .at))
        case .calendarHold:
            self = .calendarHold(title: try container.decode(String.self, forKey: .title),
                                 at: try container.decode(Date.self, forKey: .at),
                                 minutes: try container.decode(Int.self, forKey: .minutes))
        case .search:
            self = .search(query: try container.decode(String.self, forKey: .query))
        case .draft:
            self = .draft(kind: try container.decode(DraftKind.self, forKey: .draftKind),
                          prompt: try container.decode(String.self, forKey: .prompt))
        case .scheduledCheck:
            self = .scheduledCheck(prompt: try container.decode(String.self, forKey: .prompt),
                                   every: try container.decode(ScheduledCheckInterval.self, forKey: .every))
        case .ask:
            self = .ask(question: try container.decode(String.self, forKey: .question))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .reminder(let text, let at):
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(at, forKey: .at)
        case .calendarHold(let title, let at, let minutes):
            try container.encode(title, forKey: .title)
            try container.encode(at, forKey: .at)
            try container.encode(minutes, forKey: .minutes)
        case .search(let query):
            try container.encode(query, forKey: .query)
        case .draft(let kind, let prompt):
            try container.encode(kind, forKey: .draftKind)
            try container.encode(prompt, forKey: .prompt)
        case .scheduledCheck(let prompt, let every):
            try container.encode(prompt, forKey: .prompt)
            try container.encode(every, forKey: .every)
        case .ask(let question):
            try container.encode(question, forKey: .question)
        }
    }
}
