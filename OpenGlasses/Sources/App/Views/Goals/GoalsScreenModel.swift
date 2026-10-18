import Combine
import Foundation

/// The Goals screen's presentation model (Plan IW P2): what is listed, how progress and state read,
/// and every change the screen can make — all over `GoalStore`, with the clock, the gates and the
/// two ways of acting on a step passed in, so the screen's behaviour is tested headless.
///
/// Goals are the wearer's own list: everything is readable, editable and deletable here, and none
/// of it needs Agent Mode. Only the check-ins (background work) do, and the screen says so rather
/// than hiding the picker. "Do it" never acts by itself: it hands the step's suggested action to the
/// router — the same authorization ladder a spoken request meets — or, for a draft, to a drafting
/// turn.
@MainActor
final class GoalsScreenModel: ObservableObject {

    /// What the model needs from the app. `live` wires the running app; tests pass fakes.
    @MainActor
    struct Environment {
        var now: () -> Date = Date.init
        var calendar: () -> Calendar = { Calendar.current }
        var agentModeEnabled: () -> Bool = { Config.agentModeEnabled }
        /// False when the `goals` tool is switched off — by the wearer, or closed by an
        /// organisation profile (`closedTools` reaches `Config.isToolEnabled`). The list still
        /// shows; only adding a goal is hidden.
        var goalsToolEnabled: () -> Bool = { Config.isToolEnabled("goals") }
        var enabledActionTools: () -> Set<String> = { GoalsTool.liveEnabledActionTools() }
        /// One tool call through the router, as the wearer's own request; returns what it said.
        var runTool: @MainActor (_ name: String, _ arguments: [String: Any],
                                 _ step: GoalStepContext) async -> String = { _, _, _ in "" }
        /// A drafting turn: the request goes to the assistant as the wearer's message.
        var startDraft: @MainActor (_ request: String) async -> String = { _ in "" }
    }

    /// One goal in the list.
    struct GoalSummary: Identifiable, Equatable {
        let id: UUID
        let title: String
        let done: Int
        let total: Int
        /// "Due Saturday", "Paused", "Done", "Set aside" — the line under the title.
        let status: String
        let state: GoalState

        /// 0…1 for the ring; an empty goal draws an empty ring.
        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
        /// "2 of 4 steps done" — the ring's words, for VoiceOver and the row.
        var progressText: String {
            total == 0 ? String(localized: "No steps yet", comment: "Goals screen: a goal with no steps.")
                : String(localized: "\(done) of \(total) steps done", comment: "Goals screen: a goal's progress.")
        }
    }

    /// What a step can offer to do.
    enum StepOffer: Equatable {
        case none
        /// The button's title.
        case runnable(String)
        /// The button's title and why it is off.
        case blocked(String, reason: String)
    }

    /// One step in a goal's page.
    struct StepRow: Identifiable, Equatable {
        let id: UUID
        let title: String
        let state: GoalStepState
        /// "Due tomorrow", "Done", "Skipped", or nil.
        let status: String?
        let isNext: Bool
        let offer: StepOffer
        /// The question a step asks the wearer, when its offer is a question rather than an action.
        let question: String?
    }

    enum AddOutcome: Equatable {
        case added(UUID)
        case invalid(String)
        case full
        case unavailable
    }

    /// What the wearer typed into the add sheet.
    struct NewGoal: Equatable {
        var title = ""
        var why = ""
        var dueAt: Date?
        var steps: [String] = [""]
    }

    static let maximumSteps = 20

    let store: GoalStore
    private let environment: Environment
    private var storeChanges: AnyCancellable?

    /// The last "Do it" result, shown until dismissed.
    @Published var runResult: String?
    /// The step whose "Do it" is in flight.
    @Published private(set) var runningStepID: UUID?

    /// `environment` nil takes the defaults — the app's own gates, and nothing to run a step with.
    init(store: GoalStore, environment: Environment? = nil) {
        self.store = store
        self.environment = environment ?? Environment()
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - The list

    var isUnreadable: Bool { store.isUnreadable }
    var showsEmptyState: Bool { store.goals.isEmpty && !store.isUnreadable }
    var canAdd: Bool { environment.goalsToolEnabled() }
    var agentModeEnabled: Bool { environment.agentModeEnabled() }

    /// Active and paused goals, in the order they were added.
    var openGoals: [GoalSummary] {
        store.goals.filter { $0.state == .active || $0.state == .paused }.map(summary)
    }

    /// Done and set-aside goals, most recently finished first.
    var finishedGoals: [GoalSummary] {
        store.goals.filter { $0.state == .done || $0.state == .abandoned }
            .sorted { ($0.finishedAt ?? $0.createdAt) > ($1.finishedAt ?? $1.createdAt) }
            .map(summary)
    }

    func goal(_ id: UUID) -> Goal? { store.goal(id: id) }

    func summary(_ goal: Goal) -> GoalSummary {
        let status: String
        switch goal.state {
        case .paused: status = String(localized: "Paused", comment: "Goals screen: a paused goal.")
        case .done: status = String(localized: "Done", comment: "Goals screen: a finished goal.")
        case .abandoned: status = String(localized: "Set aside", comment: "Goals screen: an abandoned goal.")
        case .active:
            if let due = goal.dueAt {
                status = String(localized: "Due \(dayWords(due))", comment: "Goals screen: when a goal is due.")
            } else {
                status = String(localized: "No due date", comment: "Goals screen: a goal with no due date.")
            }
        }
        return GoalSummary(id: goal.id, title: goal.title, done: goal.doneStepCount,
                           total: goal.countedSteps.count, status: status, state: goal.state)
    }

    // MARK: - One goal's steps

    func steps(of goalID: UUID) -> [StepRow] {
        guard let goal = store.goal(id: goalID) else { return [] }
        let next = GoalAdvancePolicy.nextStep(in: goal)?.id
        let permitted = StepActionPermission.predicate(enabledTools: environment.enabledActionTools(),
                                                       agentModeEnabled: environment.agentModeEnabled())
        return goal.steps.map { step in
            let status: String?
            switch step.state {
            case .done: status = String(localized: "Done", comment: "Goals screen: a step that is done.")
            case .skipped: status = String(localized: "Skipped", comment: "Goals screen: a step that was skipped.")
            case .open, .next, .inProgress:
                status = step.dueAt.map {
                    String(localized: "Due \(dayWords($0))", comment: "Goals screen: when a step is due.")
                }
            }
            var offer = StepOffer.none
            var question: String?
            if step.state.isActionable, goal.state == .active, let action = step.suggestedAction {
                if case .ask(let asked) = action {
                    question = asked
                } else {
                    let title = StepActionRun.buttonTitle(for: action)
                    offer = permitted(action)
                        ? .runnable(title)
                        : .blocked(title, reason: Self.blockedReason(action, agentModeEnabled: environment.agentModeEnabled()))
                }
            }
            return StepRow(id: step.id, title: step.title, state: step.state, status: status,
                           isNext: step.id == next, offer: offer, question: question)
        }
    }

    static func blockedReason(_ action: StepAction, agentModeEnabled: Bool) -> String {
        if action.needsAgentMode && !agentModeEnabled {
            return String(localized: "Needs Agentic Features, which is off.",
                          comment: "Goals screen: why a step's scheduled check cannot be set up.")
        }
        return String(localized: "The tool this needs is switched off.",
                      comment: "Goals screen: why a step's suggested action cannot run.")
    }

    /// Shown under the check-in picker while check-ins cannot run.
    func checkInNote(for goalID: UUID) -> String? {
        guard let goal = store.goal(id: goalID), goal.checkIn != .none else { return nil }
        if !environment.agentModeEnabled() {
            return String(localized: "Check-ins are paused while Agentic Features is off. Your goal stays as it is.",
                          comment: "Goals screen: check-ins need Agent Mode.")
        }
        if goal.state == .paused {
            return String(localized: "No check-ins while the goal is paused.",
                          comment: "Goals screen: a paused goal is not checked in on.")
        }
        if case .beforeDue = goal.checkIn, goal.dueAt == nil, !goal.steps.contains(where: { $0.dueAt != nil }) {
            return String(localized: "There's no due date to count back from, so there's nothing to check in on yet.",
                          comment: "Goals screen: a before-due check-in on an undated goal.")
        }
        return nil
    }

    // MARK: - Check-in cadence

    /// The choices the picker offers. "Before it's due" only when there is a date to count from,
    /// and always the goal's current cadence, so the picker never shows a value it cannot select.
    func cadenceChoices(for goalID: UUID) -> [CheckInCadence] {
        guard let goal = store.goal(id: goalID) else { return [.none] }
        var choices: [CheckInCadence] = [.none, .daily, .weekly]
        if goal.dueAt != nil || goal.steps.contains(where: { $0.dueAt != nil }) {
            choices += [1, 2, 3, 7].map { .beforeDue(days: $0) }
        }
        if !choices.contains(goal.checkIn) { choices.append(goal.checkIn) }
        return choices
    }

    static func cadenceLabel(_ cadence: CheckInCadence) -> String {
        switch cadence {
        case .none: return String(localized: "Off", comment: "Goals screen: no check-ins.")
        case .daily: return String(localized: "Once a day", comment: "Goals screen: a daily check-in.")
        case .weekly: return String(localized: "Once a week", comment: "Goals screen: a weekly check-in.")
        case .beforeDue(let days):
            return days == 1
                ? String(localized: "The day before it's due", comment: "Goals screen: a check-in one day before.")
                : String(localized: "\(days) days before it's due", comment: "Goals screen: a check-in some days before.")
        }
    }

    func setCadence(_ cadence: CheckInCadence, for goalID: UUID) {
        store.update(goalID) { $0.checkIn = cadence }
    }

    // MARK: - Changing a goal

    func setStep(_ stepID: UUID, of goalID: UUID, to state: GoalStepState) {
        let now = environment.now()
        store.update(goalID) { goal in
            guard let index = goal.steps.firstIndex(where: { $0.id == stepID }) else { return }
            goal.steps[index].state = state
            goal.steps[index].doneAt = state == .done ? now : nil
        }
    }

    func setState(_ state: GoalState, for goalID: UUID) {
        store.update(goalID) { $0.state = state }
    }

    func delete(_ goalID: UUID) {
        store.remove(goalID)
    }

    @discardableResult
    func rename(_ goalID: UUID, to title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= GoalLimits.titleLength else { return false }
        store.update(goalID) { $0.title = trimmed }
        return true
    }

    @discardableResult
    func setWhy(_ goalID: UUID, to why: String) -> Bool {
        let trimmed = why.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= GoalLimits.whyLength else { return false }
        store.update(goalID) { $0.why = trimmed.isEmpty ? nil : trimmed }
        return true
    }

    /// A picked day means the end of that day, as a spoken date does. Nil clears it.
    func setDue(_ goalID: UUID, to day: Date?) {
        let due = day.map { Self.endOfDay($0, calendar: environment.calendar()) }
        store.update(goalID) { $0.dueAt = due }
    }

    @discardableResult
    func addStep(_ title: String, to goalID: UUID) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= GoalLimits.stepTitleLength,
              let goal = store.goal(id: goalID), goal.steps.count < Self.maximumSteps else { return false }
        store.update(goalID) { $0.steps.append(GoalStep(id: UUID(), title: trimmed)) }
        return true
    }

    @discardableResult
    func renameStep(_ stepID: UUID, of goalID: UUID, to title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= GoalLimits.stepTitleLength else { return false }
        store.update(goalID) { goal in
            guard let index = goal.steps.firstIndex(where: { $0.id == stepID }) else { return }
            goal.steps[index].title = trimmed
        }
        return true
    }

    func removeStep(_ stepID: UUID, from goalID: UUID) {
        store.update(goalID) { $0.steps.removeAll { $0.id == stepID } }
    }

    // MARK: - Adding a goal

    /// Keep a goal the wearer typed. Not offered when the `goals` tool is off or closed.
    func add(_ draft: NewGoal) -> AddOutcome {
        guard canAdd else { return .unavailable }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = draft.why.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = draft.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !title.isEmpty else {
            return .invalid(String(localized: "Give the goal a name.", comment: "Goals screen: add without a title."))
        }
        guard title.count <= GoalLimits.titleLength else {
            return .invalid(String(localized: "That name is a bit long. Try saying it more briefly.",
                                   comment: "Goals screen: an over-long goal title."))
        }
        guard why.count <= GoalLimits.whyLength else {
            return .invalid(String(localized: "That reason is a bit long.", comment: "Goals screen: an over-long reason."))
        }
        guard !steps.isEmpty else {
            return .invalid(String(localized: "Add at least one step.", comment: "Goals screen: add without steps."))
        }
        guard steps.count <= Self.maximumSteps, steps.allSatisfy({ $0.count <= GoalLimits.stepTitleLength }) else {
            return .invalid(String(localized: "One of the steps is a bit long.", comment: "Goals screen: an over-long step."))
        }
        let now = environment.now()
        let calendar = environment.calendar()
        let due = draft.dueAt.map { Self.endOfDay($0, calendar: calendar) }
        if let due, due <= now {
            return .invalid(String(localized: "That date has already gone.", comment: "Goals screen: a past due date."))
        }
        let goal = Goal(id: UUID(), title: title, why: why.isEmpty ? nil : why, createdAt: now, dueAt: due,
                        checkIn: CheckInCadence.defaultCadence(dueAt: due),
                        steps: steps.map { GoalStep(id: UUID(), title: $0) }, source: .wearer)
        switch store.add(goal) {
        case .added: return .added(goal.id)
        case .full: return .full
        case .unavailable: return .unavailable
        }
    }

    // MARK: - "Do it"

    /// Run a step's suggested action through the normal tool path. The router decides — it may ask
    /// the wearer, hold the call, or refuse it — and whatever it says is shown.
    func doIt(_ stepID: UUID, of goalID: UUID) async {
        guard runningStepID == nil, let goal = store.goal(id: goalID), goal.state == .active,
              let step = goal.steps.first(where: { $0.id == stepID }), step.state.isActionable,
              let action = step.suggestedAction else { return }
        let permitted = StepActionPermission.predicate(enabledTools: environment.enabledActionTools(),
                                                       agentModeEnabled: environment.agentModeEnabled())
        guard permitted(action) else {
            runResult = Self.blockedReason(action, agentModeEnabled: environment.agentModeEnabled())
            return
        }
        runningStepID = stepID
        defer { runningStepID = nil }
        switch StepActionRun.run(for: action, step: step, goal: goal, calendar: environment.calendar()) {
        case .tool(let name, let arguments):
            let said = await environment.runTool(name, arguments.rawValues,
                                                 GoalStepContext(goalID: goalID, stepID: stepID))
            runResult = said.isEmpty ? nil : said
        case .draft(let request):
            let said = await environment.startDraft(request)
            runResult = said.isEmpty ? nil : said
        case .nothing:
            break
        }
    }

    // MARK: - Pieces

    private func dayWords(_ date: Date) -> String {
        SpokenPhrasing.day(date, now: environment.now(), calendar: environment.calendar())
    }

    static func endOfDay(_ day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return (calendar.date(byAdding: .day, value: 1, to: start) ?? start).addingTimeInterval(-1)
    }
}

extension GoalsScreenModel.Environment {
    /// The running app: the router for a tool, the conversation for a draft. The router is asked
    /// with the wearer as the origin — a press of "Do it" is the wearer's own request — inside the
    /// step's activity scope, so the trail row it writes links back to this goal.
    @MainActor
    static var live: Self {
        var environment = Self()
        environment.runTool = { name, arguments, step in
            guard let appState = AppStateProvider.shared,
                  let router = appState.llmService.nativeToolRouter else {
                return String(localized: "The assistant isn't ready yet. Try again in a moment.",
                              comment: "Goals screen: Do it before the app is ready.")
            }
            let outcome = await ActivityScope.$goalStep.withValue(step) {
                await router.execute(.root(name: name, arguments: ToolArguments(arguments), origin: .user))
            }
            return outcome.text
        }
        environment.startDraft = { request in
            guard let appState = AppStateProvider.shared else { return "" }
            guard !appState.isProcessing else {
                return String(localized: "The assistant is busy. Try again when it has finished.",
                              comment: "Goals screen: a draft while a turn is running.")
            }
            await appState.sendTextMessage(request)
            return String(localized: "The draft is in your conversation.",
                          comment: "Goals screen: where a step's draft went.")
        }
        return environment
    }
}
