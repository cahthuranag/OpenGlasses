import XCTest
@testable import OpenGlasses

/// Plan IW P1 — the `goals` tool, every action, against a store over a temporary directory and a
/// fake drafting model. Goals work without Agent Mode; only a step's scheduled check needs it.
@MainActor
final class GoalsToolTests: XCTestCase {
    private typealias F = GoalActivityFixture

    private var directory: URL!
    private var store: GoalStore!
    private var model: FakeGoalDraftModel!
    private var agentMode = false

    override func setUp() {
        super.setUp()
        directory = F.workspace("GoalsToolTests")
        store = GoalStore(directory: directory, clock: { F.now }, hipaaRetentionDays: { nil })
        model = FakeGoalDraftModel()
        agentMode = false
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func tool() -> GoalsTool {
        let store = store!
        let model = model!
        let tool = GoalsTool(store: { store }, drafter: GoalDrafter(model: { model }))
        tool.agentModeEnabled = { [unowned self] in self.agentMode }
        tool.enabledActionTools = { ["reminder", "calendar", "web_search", "manage_schedule"] }
        tool.persona = { nil }
        tool.clock = { F.now }
        tool.calendar = { F.calendar() }
        return tool
    }

    private func run(_ tool: GoalsTool, _ args: [String: Any]) async throws -> String {
        try await tool.execute(args: args)
    }

    /// Clear the garage, four steps, the second already done, due Saturday 24 October.
    private func seedGarage() {
        store.add(Goal(id: F.uuid(1), title: "Clear the garage", createdAt: F.date(18, 9),
                       dueAt: F.date(24, 23, 59), state: .active, checkIn: .beforeDue(days: 2),
                       steps: [F.step(1, "Book the skip", action: .search(query: "skip hire")),
                               F.step(2, "Sort the shelves", state: .done),
                               F.step(3, "List the bike for sale", action: .draft(kind: .listing, prompt: "the bike")),
                               F.step(4, "Drop the paint at the depot")],
                       source: .wearer))
    }

    private var garage: Goal? { store.goal(id: F.uuid(1)) }

    // MARK: - Reading

    func testListWithNoGoals() async throws {
        let said = try await run(tool(), ["action": "list"])
        XCTAssertEqual(said, "You don't have any goals on the go. Say \"make a goal\" to start one.")
    }

    func testListNamesEachOpenGoalWithItsProgress() async throws {
        seedGarage()
        store.add(Goal(id: F.uuid(2), title: "Renew the passport", createdAt: F.now, state: .paused,
                       steps: [F.step(5, "Fill in the form")], source: .wearer))
        store.add(Goal(id: F.uuid(3), title: "Old goal", createdAt: F.now, state: .done, source: .wearer))
        let said = try await run(tool(), ["action": "list"])
        XCTAssertEqual(said, "You have two goals. Clear the garage: one of four done, due Saturday. "
                       + "Renew the passport: paused.")
    }

    func testStatusAndNextForOneGoal() async throws {
        seedGarage()
        let status = try await run(tool(), ["action": "status", "goal": "garage"])
        XCTAssertTrue(status.hasPrefix("One of four done, due Saturday."), status)
        XCTAssertTrue(status.contains("Want me to search for skip hire?"), status)
        let next = try await run(tool(), ["action": "next", "goal": "garage"])
        XCTAssertEqual(next, "Next on Clear the garage: Book the skip. Want me to search for skip hire?")
    }

    func testNextAcrossGoals() async throws {
        let none = try await run(tool(), ["action": "next"])
        XCTAssertEqual(none, "Nothing's next on your goals.")
        seedGarage()
        let said = try await run(tool(), ["action": "next"])
        XCTAssertTrue(said.contains("Clear the garage: book the skip"), said)
    }

    func testAnUnknownGoalNamesTheOpenOnes() async throws {
        seedGarage()
        let said = try await run(tool(), ["action": "status", "goal": "boat"])
        XCTAssertEqual(said, "I couldn't tell which goal you meant. Your goals are: Clear the garage.")
    }

    // MARK: - Adding

    func testAddWithTheWearersStepsIsReadBackAndStoredOnlyOnAccept() async throws {
        let goals = tool()
        let readBack = try await run(goals, ["action": "add", "title": "Clear the garage", "due": "2026-10-24",
                                             "steps": ["Book the skip", "Sort the shelves", "List the bike"]])
        XCTAssertEqual(readBack, "Okay, by Saturday. I'd break that into: book the skip, sort the shelves, "
                       + "and list the bike. Want me to keep an eye on it?")
        XCTAssertTrue(store.goals.isEmpty, "nothing is stored before the wearer says yes")

        let saved = try await run(goals, ["action": "accept"])
        XCTAssertEqual(saved, "Saved: Clear the garage, with three steps. I'll check in two days before it's due.")
        let goal = try XCTUnwrap(store.goals.first)
        XCTAssertEqual(goal.source, .wearer)
        XCTAssertEqual(goal.checkIn, .beforeDue(days: 2))
        XCTAssertEqual(goal.steps.map(\.title), ["Book the skip", "Sort the shelves", "List the bike"])
        XCTAssertTrue(model.requests.isEmpty, "the wearer's own steps need no model call")
    }

    func testAddWithOnlyATitleAsksTheModelForSteps() async throws {
        model.answer = #"{"title":"Clear the garage","steps":[{"title":"Book the skip","action":{"kind":"search","query":"skip hire"}},{"title":"Sort the shelves"},{"title":"Drop the paint at the depot"}]}"#
        let goals = tool()
        let readBack = try await run(goals, ["action": "add", "title": "clear the garage"])
        XCTAssertEqual(readBack, "Okay. I'd break that into: book the skip, sort the shelves, and drop the "
                       + "paint at the depot. Want me to keep an eye on it?")
        XCTAssertEqual(model.requests, ["clear the garage"])
        _ = try await run(goals, ["action": "accept", "check_in": "none"])
        XCTAssertEqual(store.goals.first?.source, .proposed)
        XCTAssertEqual(store.goals.first?.checkIn, CheckInCadence.none)
        XCTAssertEqual(store.goals.first?.steps.first?.suggestedAction, .search(query: "skip hire"))
    }

    func testTooFewStepsFromTheWearerAreRefusedWithAWayForward() async throws {
        let said = try await run(tool(), ["action": "add", "title": "Renew the passport", "steps": ["Fill in the form"]])
        XCTAssertEqual(said, "A goal needs three to seven steps. Tell me the steps again, or ask me to suggest them.")
    }

    func testReviseAndDecline() async throws {
        let goals = tool()
        _ = try await run(goals, ["action": "add", "title": "Clear the garage",
                                  "steps": ["Book the skip", "Sort the shelves", "Drop the paint"]])
        let revised = try await run(goals, ["action": "revise", "step": "paint"])
        XCTAssertEqual(revised, "Okay. I'd break that into: book the skip and sort the shelves. "
                       + "Want me to keep an eye on it?")
        let declined = try await run(goals, ["action": "decline"])
        XCTAssertEqual(declined, "Okay, I won't keep that one.")
        let accept = try await run(goals, ["action": "accept"])
        XCTAssertEqual(accept, "There's no goal waiting for a yes. Tell me the goal and I'll suggest steps.")
        XCTAssertTrue(store.goals.isEmpty)
    }

    // MARK: - Agent Mode and scheduled checks

    func testAScheduledCheckIsRefusedWithAgentModeOff() async throws {
        let goals = tool()
        let said = try await run(goals, ["action": "add", "title": "Clear the garage", "steps": [
            ["title": "Book the skip", "action": ["kind": "scheduled_check", "prompt": "is the skip booked", "every": "daily"]],
            ["title": "Sort the shelves"], ["title": "Drop the paint"],
        ]])
        XCTAssertTrue(said.hasSuffix(GoalsTool.agentModeRefusal), said)
        _ = try await run(goals, ["action": "accept"])
        XCTAssertNil(store.goals.first?.steps.first?.suggestedAction, "the check was left off")

        let edit = try await run(goals, ["action": "edit", "goal": "garage", "step": "1",
                                         "step_action": ["kind": "scheduled_check", "prompt": "is it booked", "every": "weekly"]])
        XCTAssertEqual(edit, GoalsTool.agentModeRefusal + " I left Clear the garage as it was.")
        XCTAssertNil(store.goals.first?.steps.first?.suggestedAction)
    }

    func testAScheduledCheckIsKeptWithAgentModeOn() async throws {
        agentMode = true
        seedGarage()
        let said = try await run(tool(), ["action": "edit", "goal": "garage", "step": "Drop the paint",
                                          "step_action": ["kind": "scheduled_check", "prompt": "is the depot open", "every": "weekly"]])
        XCTAssertTrue(said.hasPrefix("Done: I changed what I'll offer for that step."), said)
        XCTAssertEqual(garage?.steps[3].suggestedAction, .scheduledCheck(prompt: "is the depot open", every: .weekly))
    }

    func testGoalsWorkWithAgentModeOff() async throws {
        agentMode = false
        seedGarage()
        let said = try await run(tool(), ["action": "step_done", "goal": "garage", "step": "skip"])
        XCTAssertTrue(said.hasPrefix("Marked done: Book the skip."), said)
    }

    // MARK: - Steps and states

    func testStepDoneAndSkip() async throws {
        seedGarage()
        let goals = tool()
        let done = try await run(goals, ["action": "step_done", "goal": "garage", "step": "1"])
        XCTAssertEqual(done, "Marked done: Book the skip. Two of four done, due Saturday. "
                       + "Next: List the bike for sale. Want me to draft the listing?")
        XCTAssertEqual(garage?.steps[0].state, .done)
        XCTAssertEqual(garage?.steps[0].doneAt, F.now)

        let skipped = try await run(goals, ["action": "skip", "goal": "garage", "step": "bike"])
        XCTAssertTrue(skipped.hasPrefix("Skipped: List the bike for sale. Two of three done"), skipped)
        let last = try await run(goals, ["action": "step_done", "goal": "garage"])
        XCTAssertEqual(last, "Marked done: Drop the paint at the depot. That was the last step. "
                       + "Want me to mark the goal done?")
    }

    func testCompletePauseResumeAbandon() async throws {
        seedGarage()
        let goals = tool()
        let paused = try await run(goals, ["action": "pause", "goal": "garage"])
        XCTAssertEqual(paused, "Paused: Clear the garage. I won't bring it up until you pick it back up.")
        XCTAssertEqual(garage?.state, .paused)
        let again = try await run(goals, ["action": "pause", "goal": "garage"])
        XCTAssertEqual(again, "Clear the garage is already paused.")
        let resumed = try await run(goals, ["action": "resume", "goal": "garage"])
        XCTAssertEqual(resumed, "Back on: Clear the garage. One of four done, due Saturday.")
        let abandoned = try await run(goals, ["action": "abandon", "goal": "garage"])
        XCTAssertEqual(abandoned, "Set aside: Clear the garage.")
        XCTAssertEqual(garage?.finishedAt, F.now)
        _ = try await run(goals, ["action": "resume", "goal": "garage"])
        let completed = try await run(goals, ["action": "complete", "goal": "garage"])
        XCTAssertEqual(completed, "Marked done: Clear the garage.")
        XCTAssertEqual(garage?.state, .done)
    }

    func testEditChangesWhatItIsAskedTo() async throws {
        seedGarage()
        let said = try await run(tool(), ["action": "edit", "goal": "garage", "new_title": "Empty the garage",
                                          "due": "2026-10-31", "add_step": "Sweep the floor",
                                          "remove_step": "paint", "check_in": "weekly"])
        XCTAssertEqual(said, "Done: I renamed it, set it for 31 October, added a step, removed a step, "
                       + "and changed the check-ins. One of four done, due 31 October.")
        XCTAssertEqual(garage?.title, "Empty the garage")
        XCTAssertEqual(garage?.steps.map(\.title), ["Book the skip", "Sort the shelves", "List the bike for sale",
                                                    "Sweep the floor"])
        XCTAssertEqual(garage?.checkIn, .weekly)
        let nothing = try await run(tool(), ["action": "edit", "goal": "garage"])
        XCTAssertEqual(nothing, "What should I change about Empty the garage?")
    }

    func testAPastDueDateIsRefused() async throws {
        seedGarage()
        let said = try await run(tool(), ["action": "edit", "goal": "garage", "due": "2026-10-01"])
        XCTAssertEqual(said, "That date has already gone.")
    }

    // MARK: - Registration and closing

    func testTheToolIsRegisteredAndClassified() {
        let registry = NativeToolRegistry(locationService: LocationService())
        let tool = registry.tool(named: "goals")
        XCTAssertTrue(tool is GoalsTool)
        XCTAssertEqual(tool?.executionSemantics.effect, .localMutation)
        XCTAssertNil(ActivityTitler.title(tool: "goals", actionKey: "list", effectClass: .write))
        XCTAssertNil(ActivityTitler.title(tool: "goals", actionKey: "add", effectClass: .write),
                     "a proposal stores nothing, so it is not an action")
        XCTAssertEqual(ActivityTitler.title(tool: "goals", actionKey: "accept", effectClass: .write)?.title,
                       "Added a goal for you")
        XCTAssertEqual(OfflineToolPolicy.availability(of: "goals"), .degraded)
    }

    /// An organisation profile closes a tool by adding it to the disabled set every reader sees;
    /// `goals` needs nothing of its own for that to apply.
    func testAProfileCanCloseTheGoalsTool() {
        let (lockdown, drops) = ManagedLockdown.resolve(.init(closedTools: ["goals"]))
        XCTAssertTrue(drops.isEmpty)
        XCTAssertTrue(SettingsLockPolicy.isToolClosed("goals", lockdown: lockdown))
        XCTAssertTrue(SettingsLockPolicy.effectiveDisabledTools(stored: [], lockdown: lockdown).contains("goals"))

        // The disabled set is what the registry reads, so a closed `goals` is neither offered nor run.
        let wasEnabled = Config.isToolEnabled("goals")
        Config.setToolEnabled("goals", enabled: false)
        defer { Config.setToolEnabled("goals", enabled: wasEnabled) }
        let registry = NativeToolRegistry(locationService: LocationService())
        XCTAssertNil(registry.tool(named: "goals"))
        XCTAssertFalse(registry.toolNames.contains("goals"))
    }
}

/// A drafting model that answers with a fixed string and remembers what it was asked.
@MainActor
final class FakeGoalDraftModel: GoalDraftModel {
    var answer: String?
    private(set) var requests: [String] = []
    private(set) var systems: [String] = []

    func draftGoal(system: String, request: String, schema: [String: Any]) async -> Data? {
        requests.append(request)
        systems.append(system)
        return answer.map { Data($0.utf8) }
    }
}
