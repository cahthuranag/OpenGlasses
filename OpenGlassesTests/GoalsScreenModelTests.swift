import XCTest
@testable import OpenGlasses

/// Plan IW P2 — the Goals screen's model, headless over a real `GoalStore` in a scratch folder.
/// Invented titles only.
@MainActor
final class GoalsScreenModelTests: XCTestCase {

    private typealias Fx = GoalActivityFixture
    private var directory: URL!
    private var store: GoalStore!
    private var toolCalls: [(name: String, arguments: [String: Any], step: GoalStepContext)] = []
    private var drafts: [String] = []
    private var agentMode = true
    private var goalsToolOpen = true

    override func setUp() {
        super.setUp()
        directory = Fx.workspace("GoalsScreen")
        store = GoalStore(directory: directory, clock: { Fx.now }, hipaaRetentionDays: { nil })
        toolCalls = []
        drafts = []
        agentMode = true
        goalsToolOpen = true
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func model() -> GoalsScreenModel {
        var environment = GoalsScreenModel.Environment()
        environment.now = { Fx.now }
        environment.calendar = { Fx.calendar() }
        environment.agentModeEnabled = { [unowned self] in agentMode }
        environment.goalsToolEnabled = { [unowned self] in goalsToolOpen }
        environment.enabledActionTools = { ["reminder", "calendar", "web_search", "manage_schedule"] }
        environment.runTool = { [unowned self] name, arguments, step in
            toolCalls.append((name, arguments, step))
            return "Added it."
        }
        environment.startDraft = { [unowned self] request in
            drafts.append(request)
            return "The draft is in your conversation."
        }
        return GoalsScreenModel(store: store, environment: environment)
    }

    private func seed(_ goal: Goal) { store.add(goal) }

    private var garage: Goal {
        Fx.goal([Fx.step(1, "Book the skip", state: .done),
                 Fx.step(2, "Sort the shelves", dueAt: Fx.date(20, 23, 59), action: .search(query: "shelf brackets")),
                 Fx.step(3, "List the bike for sale", action: .draft(kind: .listing, prompt: "A blue road bike.")),
                 Fx.step(4, "Check the skip came", action: .scheduledCheck(prompt: "Has it come?", every: .daily)),
                 Fx.step(5, "Ask about the paint", action: .ask(question: "Is the depot open Sundays?")),
                 Fx.step(6, "Recycle the boxes", state: .skipped)],
                dueAt: Fx.date(24, 23, 59), checkIn: .beforeDue(days: 2))
    }

    // MARK: - The list

    func testTheEmptyStateAndTheAddPathFollowTheGoalsTool() {
        let screen = model()
        XCTAssertTrue(screen.showsEmptyState)
        XCTAssertTrue(screen.canAdd)
        goalsToolOpen = false
        XCTAssertFalse(screen.canAdd, "an organisation that closes the goals tool hides adding")
        XCTAssertEqual(screen.add(.init(title: "Plan the trip", steps: ["Book flights"])), .unavailable)
        XCTAssertTrue(store.goals.isEmpty)

        seed(garage)
        XCTAssertFalse(screen.showsEmptyState)
        XCTAssertEqual(screen.openGoals.map(\.title), ["Clear the garage"],
                       "existing goals still show with the add path closed")
    }

    func testProgressCountsDoneOverStepsNotSkipped() {
        seed(garage)
        let summary = model().openGoals[0]
        XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(summary.total, 5, "the skipped step is not counted")
        XCTAssertEqual(summary.fraction, 0.2, accuracy: 0.0001)
        XCTAssertEqual(summary.status, "Due Saturday")
        XCTAssertEqual(summary.progressText, "1 of 5 steps done")
    }

    func testFinishedGoalsAreListedApartMostRecentFirst() {
        seed(garage)
        var older = Fx.goal([Fx.step(1, "Buy paint")], title: "Paint the fence")
        older = Goal(id: Fx.uuid(2), title: older.title, createdAt: Fx.date(10, 9), state: .done,
                     steps: older.steps, source: .wearer, finishedAt: Fx.date(12, 9))
        let newer = Goal(id: Fx.uuid(3), title: "Plan the trip", createdAt: Fx.date(11, 9), state: .abandoned,
                         steps: [], source: .wearer, finishedAt: Fx.date(15, 9))
        seed(older)
        seed(newer)
        let screen = model()
        XCTAssertEqual(screen.openGoals.map(\.title), ["Clear the garage"])
        XCTAssertEqual(screen.finishedGoals.map(\.title), ["Plan the trip", "Paint the fence"])
        XCTAssertEqual(screen.finishedGoals.map(\.status), ["Set aside", "Done"])
    }

    // MARK: - Steps and their offers

    func testEachStepSaysWhatItCanOffer() {
        seed(garage)
        agentMode = false
        let rows = model().steps(of: Fx.uuid(1))
        XCTAssertEqual(rows.map(\.title), ["Book the skip", "Sort the shelves", "List the bike for sale",
                                           "Check the skip came", "Ask about the paint", "Recycle the boxes"])
        XCTAssertEqual(rows[0].status, "Done")
        XCTAssertEqual(rows[0].offer, .none, "a done step offers nothing")
        XCTAssertTrue(rows[1].isNext, "the dated step is next")
        XCTAssertEqual(rows[1].status, "Due tomorrow")
        XCTAssertEqual(rows[1].offer, .runnable("Search for it"))
        XCTAssertEqual(rows[2].offer, .runnable("Draft it"))
        XCTAssertEqual(rows[3].offer, .blocked("Set up the check", reason: "Needs Agentic Features, which is off."))
        XCTAssertEqual(rows[4].offer, .none)
        XCTAssertEqual(rows[4].question, "Is the depot open Sundays?")
        XCTAssertEqual(rows[5].status, "Skipped")
    }

    func testDoneSkipAndReopen() {
        seed(garage)
        let screen = model()
        screen.setStep(Fx.uuid(102), of: Fx.uuid(1), to: .done)
        XCTAssertEqual(store.goal(id: Fx.uuid(1))?.steps[1].state, .done)
        XCTAssertEqual(store.goal(id: Fx.uuid(1))?.steps[1].doneAt, Fx.now)
        screen.setStep(Fx.uuid(102), of: Fx.uuid(1), to: .open)
        XCTAssertEqual(store.goal(id: Fx.uuid(1))?.steps[1].state, .open)
        XCTAssertNil(store.goal(id: Fx.uuid(1))?.steps[1].doneAt)
        screen.setStep(Fx.uuid(103), of: Fx.uuid(1), to: .skipped)
        XCTAssertEqual(screen.openGoals[0].total, 4)
    }

    // MARK: - "Do it"

    func testDoItRunsTheStepsToolWithItsArgumentsAndTheStepAttached() async {
        seed(garage)
        let screen = model()
        await screen.doIt(Fx.uuid(102), of: Fx.uuid(1))
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls[0].name, "web_search")
        XCTAssertEqual(toolCalls[0].arguments["query"] as? String, "shelf brackets")
        XCTAssertEqual(toolCalls[0].step, GoalStepContext(goalID: Fx.uuid(1), stepID: Fx.uuid(102)))
        XCTAssertEqual(screen.runResult, "Added it.")
        XCTAssertEqual(store.goal(id: Fx.uuid(1))?.steps[1].state, .open,
                       "running the offer does not mark the step done — the wearer does")
    }

    func testADraftGoesToTheConversationNotToATool() async {
        seed(garage)
        let screen = model()
        await screen.doIt(Fx.uuid(103), of: Fx.uuid(1))
        XCTAssertTrue(toolCalls.isEmpty)
        XCTAssertEqual(drafts, ["Draft a listing for my goal \u{201C}Clear the garage\u{201D}, for the step "
                                + "\u{201C}List the bike for sale\u{201D}: A blue road bike."])
    }

    func testAScheduledCheckIsRefusedWithAgentModeOffAndRunsWithItOn() async {
        seed(garage)
        agentMode = false
        let screen = model()
        await screen.doIt(Fx.uuid(104), of: Fx.uuid(1))
        XCTAssertTrue(toolCalls.isEmpty)
        XCTAssertEqual(screen.runResult, "Needs Agentic Features, which is off.")

        agentMode = true
        await screen.doIt(Fx.uuid(104), of: Fx.uuid(1))
        XCTAssertEqual(toolCalls.map(\.name), ["manage_schedule"])
        XCTAssertEqual(toolCalls[0].arguments["interval_minutes"] as? Int, 0)
        XCTAssertEqual(toolCalls[0].arguments["task_name"] as? String, "Check the skip came")
    }

    func testNothingRunsOnAPausedGoalOrADoneStep() async {
        var paused = garage
        paused.state = .paused
        seed(paused)
        let screen = model()
        await screen.doIt(Fx.uuid(102), of: Fx.uuid(1))
        XCTAssertTrue(toolCalls.isEmpty)
        XCTAssertEqual(screen.steps(of: Fx.uuid(1))[1].offer, .none)
    }

    func testEveryStepActionMapsToTheToolItNames() {
        let goal = garage
        let step = goal.steps[1]
        let calendar = Fx.calendar()
        let at = Fx.date(21, 9, 30)
        let cases: [(StepAction, String?)] = [
            (.reminder(text: "Call the skip firm", at: at), "reminder"),
            (.calendarHold(title: "Sort shelves", at: at, minutes: 90), "calendar"),
            (.search(query: "skip hire"), "web_search"),
            (.scheduledCheck(prompt: "Is it here?", every: .weekly), "manage_schedule"),
        ]
        for (action, tool) in cases {
            guard case .tool(let name, let arguments) = StepActionRun.run(for: action, step: step, goal: goal,
                                                                       calendar: calendar) else {
                return XCTFail("\(action) should run a tool")
            }
            XCTAssertEqual(name, tool)
            XCTAssertEqual(name, action.toolName, "the run uses the tool the action already names")
            switch action {
            case .reminder:
                XCTAssertEqual(arguments["due_at"], .text("2026-10-21T09:30:00+13:00"))
            case .calendarHold:
                XCTAssertEqual(arguments["date"], .text("2026-10-21"))
                XCTAssertEqual(arguments["start_time"], .text("09:30"))
                XCTAssertEqual(arguments["duration_minutes"], .number(90))
            case .scheduledCheck:
                XCTAssertEqual(arguments["interval_minutes"], .number(10_080))
            default:
                break
            }
        }
        XCTAssertEqual(StepActionRun.run(for: .ask(question: "When?"), step: step, goal: goal, calendar: calendar),
                       .nothing)
    }

    // MARK: - Editing

    func testAddValidatesAndTakesTheQuietestCheckIn() throws {
        let screen = model()
        XCTAssertEqual(screen.add(.init(title: "  ", steps: ["Book flights"])),
                       .invalid("Give the goal a name."))
        XCTAssertEqual(screen.add(.init(title: "Plan the trip", steps: ["", " "])),
                       .invalid("Add at least one step."))
        XCTAssertEqual(screen.add(.init(title: "Plan the trip", dueAt: Fx.date(18, 12), steps: ["Book flights"])),
                       .invalid("That date has already gone."))

        guard case .added(let id) = screen.add(.init(title: "Plan the trip", why: "Summer",
                                                       dueAt: Fx.date(30, 8), steps: ["Book flights", ""])) else {
            return XCTFail("not added")
        }
        let goal = try XCTUnwrap(store.goal(id: id))
        XCTAssertEqual(goal.steps.map(\.title), ["Book flights"])
        XCTAssertEqual(goal.why, "Summer")
        XCTAssertEqual(goal.dueAt, Fx.date(30, 23, 59).addingTimeInterval(59), "a picked day means its end")
        XCTAssertEqual(goal.checkIn, .beforeDue(days: 2))
        XCTAssertEqual(goal.source, .wearer)

        guard case .added(let undated) = screen.add(.init(title: "Learn the guitar", steps: ["Buy strings"])) else {
            return XCTFail("not added")
        }
        XCTAssertEqual(store.goal(id: undated)?.checkIn, CheckInCadence.none)
    }

    func testRenameStepsCadenceStateAndDelete() {
        seed(garage)
        let screen = model()
        XCTAssertFalse(screen.rename(Fx.uuid(1), to: String(repeating: "x", count: 81)))
        XCTAssertTrue(screen.rename(Fx.uuid(1), to: "Empty the garage"))
        XCTAssertTrue(screen.addStep("Sweep the floor", to: Fx.uuid(1)))
        XCTAssertTrue(screen.renameStep(Fx.uuid(101), of: Fx.uuid(1), to: "Book a bigger skip"))
        screen.removeStep(Fx.uuid(106), from: Fx.uuid(1))
        screen.setCadence(.daily, for: Fx.uuid(1))
        var goal = store.goal(id: Fx.uuid(1))
        XCTAssertEqual(goal?.title, "Empty the garage")
        XCTAssertEqual(goal?.steps.first?.title, "Book a bigger skip")
        XCTAssertEqual(goal?.steps.last?.title, "Sweep the floor")
        XCTAssertFalse(goal?.steps.contains { $0.title == "Recycle the boxes" } ?? true)
        XCTAssertEqual(goal?.checkIn, .daily)

        screen.setState(.paused, for: Fx.uuid(1))
        XCTAssertEqual(screen.openGoals.first?.status, "Paused")
        screen.setState(.done, for: Fx.uuid(1))
        goal = store.goal(id: Fx.uuid(1))
        XCTAssertNotNil(goal?.finishedAt)
        XCTAssertEqual(screen.finishedGoals.map(\.id), [Fx.uuid(1)])

        screen.delete(Fx.uuid(1))
        XCTAssertNil(store.goal(id: Fx.uuid(1)))
        XCTAssertTrue(screen.showsEmptyState)
    }

    func testCheckInChoicesAndNotes() {
        seed(garage)
        let screen = model()
        XCTAssertEqual(screen.cadenceChoices(for: Fx.uuid(1)),
                       [.none, .daily, .weekly, .beforeDue(days: 1), .beforeDue(days: 2),
                        .beforeDue(days: 3), .beforeDue(days: 7)])
        XCTAssertNil(screen.checkInNote(for: Fx.uuid(1)))
        agentMode = false
        XCTAssertEqual(screen.checkInNote(for: Fx.uuid(1)),
                       "Check-ins are paused while Agentic Features is off. Your goal stays as it is.")
        XCTAssertEqual(GoalsScreenModel.cadenceLabel(.beforeDue(days: 1)), "The day before it's due")
        XCTAssertEqual(GoalsScreenModel.cadenceLabel(.beforeDue(days: 3)), "3 days before it's due")

        let undated = Goal(id: Fx.uuid(2), title: "Learn the guitar", createdAt: Fx.now, checkIn: .weekly,
                           steps: [Fx.step(1, "Buy strings")], source: .wearer)
        seed(undated)
        XCTAssertEqual(screen.cadenceChoices(for: Fx.uuid(2)), [.none, .daily, .weekly],
                       "no date, so nothing to count back from")
    }
}
