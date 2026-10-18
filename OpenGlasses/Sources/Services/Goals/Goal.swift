import Foundation

// MARK: - Goals (Plan IW P0)
//
// A goal is the wearer's own list: a title, an optional reason and due date, and a handful of
// steps, each of which may carry one thing the assistant could offer to do for it. These are pure
// values — nothing here stores, schedules or speaks. The store, the tool and the check-ins arrive
// later and read these types as they are.
//
// Every enum persists as an explicit string, never as a Swift case name or an ordinal, so a goal
// written by this build still reads after a case is renamed or reordered.

/// The length limits the plan sets for a goal. Enforced when a proposal is parsed and again when a
/// stored goal is decoded, so an over-long title can enter by neither door.
enum GoalLimits {
    static let titleLength = 80
    static let whyLength = 140
    static let stepTitleLength = 80
    /// A proposal breaks a goal into at least this many steps…
    static let minimumProposedSteps = 3
    /// …and at most this many. A stored goal may have fewer (the wearer can drop one) but a
    /// proposal outside this range is refused rather than trimmed.
    static let maximumProposedSteps = 7
    /// The text fields inside a suggested action.
    static let actionTextLength = 140
    static let actionPromptLength = 280
    /// A calendar hold is between five minutes and a working day.
    static let holdMinutes = 5...480
    /// How far ahead a "before it's due" check-in may start.
    static let beforeDueDays = 1...30
}

/// Where a goal is in its life.
enum GoalState: String, Codable, Equatable, Sendable, CaseIterable {
    case active = "active"
    case paused = "paused"
    case done = "done"
    case abandoned = "abandoned"
}

/// Where one step is. `next` is the wearer's (or the assistant's, agreed) pick for what comes next;
/// it outranks due dates when the next step is chosen.
enum GoalStepState: String, Codable, Equatable, Sendable, CaseIterable {
    case open = "open"
    case next = "next"
    case inProgress = "in_progress"
    case done = "done"
    case skipped = "skipped"

    /// Whether the step still has work in it.
    var isActionable: Bool {
        switch self {
        case .open, .next, .inProgress: return true
        case .done, .skipped: return false
        }
    }
}

/// Who made the goal: the wearer saying "make a goal", or the assistant proposing one the wearer
/// then agreed to. Proposing on its own is out of scope here; the case exists so a stored goal
/// says how it began.
enum GoalSource: String, Codable, Equatable, Sendable, CaseIterable {
    case wearer = "wearer"
    case proposed = "proposed"
}

/// How often the assistant may bring a goal up by itself. Persisted as a single string —
/// `none`, `daily`, `weekly`, `before_due:<days>` — so the format is readable on disk and a new
/// cadence can be added without breaking the old ones.
enum CheckInCadence: Equatable, Sendable {
    case none
    case daily
    case weekly
    /// Starting this many days before the goal (or its next step) is due, once.
    case beforeDue(days: Int)

    /// What a goal gets when the wearer says "keep an eye on it": a single check-in two days before
    /// it is due, or none when there is no due date to count back from. Nagging is the risk the
    /// plan names, so the default is the quietest cadence that is still useful.
    static func defaultCadence(dueAt: Date?) -> CheckInCadence {
        dueAt == nil ? .none : .beforeDue(days: defaultBeforeDueDays)
    }

    static let defaultBeforeDueDays = 2

    var codeValue: String {
        switch self {
        case .none: return "none"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .beforeDue(let days): return "before_due:\(days)"
        }
    }

    init?(codeValue: String) {
        switch codeValue {
        case "none": self = .none
        case "daily": self = .daily
        case "weekly": self = .weekly
        default:
            let prefix = "before_due:"
            guard codeValue.hasPrefix(prefix),
                  let days = Int(codeValue.dropFirst(prefix.count)),
                  GoalLimits.beforeDueDays.contains(days) else { return nil }
            self = .beforeDue(days: days)
        }
    }
}

extension CheckInCadence: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let cadence = CheckInCadence(codeValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "unknown check-in cadence")
        }
        self = cadence
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(codeValue)
    }
}

/// One step toward a goal.
struct GoalStep: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var title: String
    var state: GoalStepState
    var dueAt: Date?
    /// The one thing the assistant may offer to do for this step. Never run unasked.
    var suggestedAction: StepAction?
    var doneAt: Date?
    /// Activity entries that bear on this step — what a "looks like that's done" suggestion cites.
    var evidence: [ActivityRef]

    init(id: UUID, title: String, state: GoalStepState = .open, dueAt: Date? = nil,
         suggestedAction: StepAction? = nil, doneAt: Date? = nil, evidence: [ActivityRef] = []) {
        self.id = id
        self.title = title
        self.state = state
        self.dueAt = dueAt
        self.suggestedAction = suggestedAction
        self.doneAt = doneAt
        self.evidence = evidence
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, state, dueAt, suggestedAction, doneAt, evidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        guard title.count <= GoalLimits.stepTitleLength else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: container,
                                                   debugDescription: "step title over the limit")
        }
        state = try container.decode(GoalStepState.self, forKey: .state)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        // An action a newer build added (or an older one dropped) loses the offer, not the step:
        // the step itself is the wearer's and must survive.
        suggestedAction = try? container.decodeIfPresent(StepAction.self, forKey: .suggestedAction)
        doneAt = try container.decodeIfPresent(Date.self, forKey: .doneAt)
        evidence = try container.decodeIfPresent([ActivityRef].self, forKey: .evidence) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(dueAt, forKey: .dueAt)
        try container.encodeIfPresent(suggestedAction, forKey: .suggestedAction)
        try container.encodeIfPresent(doneAt, forKey: .doneAt)
        try container.encode(evidence, forKey: .evidence)
    }
}

/// A goal: the wearer's object, not inferred knowledge, so it is never a memory fact.
struct Goal: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var title: String
    var why: String?
    let createdAt: Date
    var dueAt: Date?
    var state: GoalState
    var checkIn: CheckInCadence
    var steps: [GoalStep]
    /// The persona the goal was made under, when one was active.
    var persona: String?
    let source: GoalSource
    /// When the goal was marked done or set aside (Plan IW P1) — what the store's 90-day retention
    /// of finished goals counts from. Nil while the goal is active or paused.
    var finishedAt: Date?

    init(id: UUID, title: String, why: String? = nil, createdAt: Date, dueAt: Date? = nil,
         state: GoalState = .active, checkIn: CheckInCadence = .none, steps: [GoalStep] = [],
         persona: String? = nil, source: GoalSource, finishedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.why = why
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.state = state
        self.checkIn = checkIn
        self.steps = steps
        self.persona = persona
        self.source = source
        self.finishedAt = finishedAt
    }

    /// Steps that count toward progress: everything the wearer has not skipped.
    var countedSteps: [GoalStep] { steps.filter { $0.state != .skipped } }
    var doneStepCount: Int { steps.filter { $0.state == .done }.count }

    private enum CodingKeys: String, CodingKey {
        case id, title, why, createdAt, dueAt, state, checkIn, steps, persona, source, finishedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        guard !title.isEmpty, title.count <= GoalLimits.titleLength else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: container,
                                                   debugDescription: "goal title empty or over the limit")
        }
        why = try container.decodeIfPresent(String.self, forKey: .why)
        if let why, why.count > GoalLimits.whyLength {
            throw DecodingError.dataCorruptedError(forKey: .why, in: container,
                                                   debugDescription: "goal reason over the limit")
        }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        state = try container.decode(GoalState.self, forKey: .state)
        checkIn = try container.decodeIfPresent(CheckInCadence.self, forKey: .checkIn) ?? .none
        steps = try container.decodeIfPresent([GoalStep].self, forKey: .steps) ?? []
        persona = try container.decodeIfPresent(String.self, forKey: .persona)
        source = try container.decode(GoalSource.self, forKey: .source)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(why, forKey: .why)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(dueAt, forKey: .dueAt)
        try container.encode(state, forKey: .state)
        try container.encode(checkIn, forKey: .checkIn)
        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(persona, forKey: .persona)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
    }
}
