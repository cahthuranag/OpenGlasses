import XCTest
@testable import OpenGlasses

/// Plan IW P1 — "make a goal …": one structured call, the parser, a read-back, and nothing stored
/// until the wearer says yes. Edit drops or renames a step; no keeps nothing.
@MainActor
final class GoalDrafterTests: XCTestCase {
    private typealias F = GoalActivityFixture

    private var directory: URL!
    private var store: GoalStore!
    private var model: FakeGoalDraftModel!

    private let garage = #"""
    {"title": "Clear the garage", "dueAt": "2026-10-24",
     "steps": [{"title": "Book the skip", "action": {"kind": "search", "query": "skip hire"}},
               {"title": "Sort the shelves"},
               {"title": "List the bike for sale", "action": {"kind": "draft", "draftKind": "listing", "prompt": "the bike"}},
               {"title": "Drop the paint at the depot", "action": {"kind": "scheduled_check", "prompt": "is it open", "every": "weekly"}}]}
    """#

    override func setUp() {
        super.setUp()
        directory = F.workspace("GoalDrafterTests")
        store = GoalStore(directory: directory, clock: { F.now }, hipaaRetentionDays: { nil })
        model = FakeGoalDraftModel()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func parser(agentMode: Bool = false, enabled: Set<String> = ["web_search", "reminder", "calendar"])
        -> GoalProposalParser {
        GoalProposalParser(now: F.now, calendar: F.calendar(),
                           isPermitted: StepActionPermission.predicate(enabledTools: enabled,
                                                                       agentModeEnabled: agentMode))
    }

    private var phraser: GoalPhraser { GoalPhraser(now: F.now, calendar: F.calendar()) }

    private func drafter() -> GoalDrafter {
        let model = model!
        return GoalDrafter(model: { model })
    }

    func testAProposalIsReadBackAndStoredOnYes() async throws {
        model.answer = garage
        let drafter = drafter()
        let said = await drafter.propose(request: "clear the garage before the 24th", parser: parser(),
                                         phraser: phraser, agentModeEnabled: false)
        XCTAssertEqual(said, "Okay, by Saturday. I'd break that into: book the skip, sort the shelves, list the "
                       + "bike for sale, and drop the paint at the depot. Want me to keep an eye on it? "
                       + "I left out one thing I'd have offered, because I can't do it here.")
        XCTAssertTrue(store.goals.isEmpty, "nothing is stored before yes")
        XCTAssertNotNil(drafter.pending(at: F.now))

        var ids = (10...20).map(F.uuid).makeIterator()
        guard case .stored(let goal) = drafter.accept(checkIn: nil, persona: "p1", store: store, now: F.now,
                                                      makeID: { ids.next()! }) else {
            return XCTFail("yes stores the goal")
        }
        XCTAssertEqual(store.goals, [goal])
        XCTAssertEqual(goal.title, "Clear the garage")
        XCTAssertEqual(goal.source, .proposed)
        XCTAssertEqual(goal.persona, "p1")
        XCTAssertEqual(goal.checkIn, .beforeDue(days: 2), "keep an eye on it: two days before it's due")
        XCTAssertEqual(goal.steps.map(\.suggestedAction), [.search(query: "skip hire"),
                                                          nil,
                                                          .draft(kind: .listing, prompt: "the bike"),
                                                          nil])
        XCTAssertNil(drafter.pending(at: F.now), "a stored proposal is no longer pending")
    }

    func testEditDropsAStepBeforeYes() async throws {
        model.answer = garage
        let drafter = drafter()
        _ = await drafter.propose(request: "clear the garage", parser: parser(), phraser: phraser,
                                  agentModeEnabled: false)
        guard case .revised(let proposal) = drafter.revise(step: "paint", renameTo: nil, now: F.now) else {
            return XCTFail("the paint step can be dropped")
        }
        XCTAssertEqual(proposal.steps.map(\.title), ["Book the skip", "Sort the shelves", "List the bike for sale"])
        XCTAssertEqual(drafter.revise(step: "2", renameTo: "Sort the top shelves", now: F.now),
                       .revised(GoalProposal(title: "Clear the garage", why: nil, dueAt: proposal.dueAt, steps: [
                           proposal.steps[0], .init(title: "Sort the top shelves", action: nil), proposal.steps[2],
                       ])))
        XCTAssertEqual(drafter.revise(step: "boat", renameTo: nil, now: F.now), .noSuchStep)

        guard case .stored(let goal) = drafter.accept(checkIn: CheckInCadence.none, persona: nil, store: store,
                                                      now: F.now) else { return XCTFail("yes stores it") }
        XCTAssertEqual(goal.steps.map(\.title), ["Book the skip", "Sort the top shelves", "List the bike for sale"])
        XCTAssertEqual(goal.checkIn, CheckInCadence.none)
    }

    func testNoStoresNothing() async {
        model.answer = garage
        let drafter = drafter()
        _ = await drafter.propose(request: "clear the garage", parser: parser(), phraser: phraser,
                                  agentModeEnabled: false)
        XCTAssertTrue(drafter.decline())
        XCTAssertEqual(drafter.accept(checkIn: nil, persona: nil, store: store, now: F.now), .nothingPending)
        XCTAssertTrue(store.goals.isEmpty)
    }

    func testAnUnansweredProposalLapses() async {
        model.answer = garage
        let drafter = drafter()
        _ = await drafter.propose(request: "clear the garage", parser: parser(), phraser: phraser,
                                  agentModeEnabled: false)
        let later = F.now.addingTimeInterval(GoalDrafter.pendingLifetime + 1)
        XCTAssertNil(drafter.pending(at: later))
        XCTAssertEqual(drafter.accept(checkIn: nil, persona: nil, store: store, now: later), .nothingPending)
    }

    func testTheScheduledCheckSurvivesWithAgentModeOn() async {
        model.answer = garage
        let drafter = drafter()
        let said = await drafter.propose(request: "clear the garage", parser: parser(agentMode: true, enabled: [
            "web_search", "manage_schedule"]), phraser: phraser, agentModeEnabled: true)
        XCTAssertFalse(said.contains("I left out"), said)
        XCTAssertEqual(drafter.pending(at: F.now)?.proposal.steps.last?.action,
                       .scheduledCheck(prompt: "is it open", every: .weekly))
        XCTAssertTrue(model.systems.first?.contains("scheduled_check") ?? false)
    }

    func testThePromptLeavesScheduledChecksOutWithAgentModeOff() async {
        model.answer = garage
        _ = await drafter().propose(request: "clear the garage", parser: parser(), phraser: phraser,
                                    agentModeEnabled: false)
        XCTAssertFalse(model.systems.first?.contains("scheduled_check") ?? true)
        XCTAssertTrue(model.systems.first?.contains("2026-10-19") ?? false, "the model is told today's date")
    }

    func testNoAnswerOrABadAnswerHoldsNothing() async {
        let drafter = drafter()
        model.answer = nil
        let silent = await drafter.propose(request: "x", parser: parser(), phraser: phraser, agentModeEnabled: false)
        XCTAssertEqual(silent, "I couldn't work out steps for that just now. Tell me the steps, or try again in a moment.")
        model.answer = #"{"title": "Clear the garage", "steps": [{"title": "Book the skip"}]}"#
        let short = await drafter.propose(request: "x", parser: parser(), phraser: phraser, agentModeEnabled: false)
        XCTAssertEqual(short, "I couldn't break that into a sensible number of steps. Tell me the steps, or say it another way.")
        XCTAssertNil(drafter.pending(at: F.now))
    }

    func testTheProductionModelNeedsAnLLM() async {
        let model = LLMGoalDraftModel(llm: nil)
        let data = await model.draftGoal(system: "s", request: "r", schema: GoalDrafter.schema)
        XCTAssertNil(data)
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: GoalDrafter.schema),
                        "the schema is plain JSON a provider can carry")
    }
}
