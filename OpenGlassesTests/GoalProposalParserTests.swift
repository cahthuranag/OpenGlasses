import XCTest
@testable import OpenGlasses

/// Plan IW P0 — a model's goal proposal is checked before the wearer hears it. Problems with the
/// goal refuse it whole; a problem with one step's suggested action drops only that action.
final class GoalProposalParserTests: XCTestCase {
    private typealias F = GoalActivityFixture

    private func parser(permit: @escaping (StepAction) -> Bool = { _ in true }) -> GoalProposalParser {
        GoalProposalParser(now: F.now, calendar: F.calendar(), isPermitted: permit)
    }

    private let fourSteps = """
    [{"title": "Book the skip", "action": {"kind": "search", "query": "skip hire near me"}},
     {"title": "Sort the shelves"},
     {"title": "List the bike for sale", "action": {"kind": "draft", "draftKind": "listing", "prompt": "A listing for the bike"}},
     {"title": "Drop the paint at the depot", "action": {"kind": "reminder", "text": "Paint to the depot", "at": "2026-10-24T09:00:00+13:00"}}]
    """

    private func accepted(_ outcome: GoalProposalOutcome,
                          file: StaticString = #filePath, line: UInt = #line) -> (GoalProposal, [DroppedAction])? {
        guard case .accepted(let proposal, let dropped) = outcome else {
            XCTFail("expected acceptance, got \(outcome)", file: file, line: line)
            return nil
        }
        return (proposal, dropped)
    }

    private func problems(_ outcome: GoalProposalOutcome,
                          file: StaticString = #filePath, line: UInt = #line) -> [GoalProposalProblem] {
        guard case .rejected(let problems) = outcome else {
            XCTFail("expected rejection, got \(outcome)", file: file, line: line)
            return []
        }
        return problems
    }

    // MARK: - The happy path

    func testAWellFormedProposalIsAcceptedWithEveryAction() throws {
        let json = #"{"title": "Clear the garage", "why": "Before the move", "dueAt": "2026-10-30", "steps": \#(fourSteps)}"#
        let (proposal, dropped) = try XCTUnwrap(accepted(parser().parse(json)))
        XCTAssertTrue(dropped.isEmpty)
        XCTAssertEqual(proposal.title, "Clear the garage")
        XCTAssertEqual(proposal.why, "Before the move")
        XCTAssertEqual(proposal.steps.map(\.title),
                       ["Book the skip", "Sort the shelves", "List the bike for sale", "Drop the paint at the depot"])
        XCTAssertEqual(proposal.steps[0].action, .search(query: "skip hire near me"))
        XCTAssertNil(proposal.steps[1].action)
        XCTAssertEqual(proposal.steps[2].action, .draft(kind: .listing, prompt: "A listing for the bike"))
        XCTAssertEqual(proposal.steps[3].action, .reminder(text: "Paint to the depot", at: F.date(24, 9)))
    }

    /// "Before the thirtieth" is still open all of the thirtieth, in the wearer's own calendar.
    func testABareDateMeansTheEndOfThatDayInTheWearersCalendar() throws {
        let json = #"{"title": "Clear the garage", "dueAt": "2026-10-30", "steps": \#(fourSteps)}"#
        let (proposal, _) = try XCTUnwrap(accepted(parser().parse(json)))
        XCTAssertEqual(proposal.dueAt, F.date(31, 0).addingTimeInterval(-1))
    }

    func testAnAcceptedProposalBecomesAProposedGoalOnlyWhenAsked() throws {
        let json = #"{"title": "Clear the garage", "steps": \#(fourSteps)}"#
        let (proposal, _) = try XCTUnwrap(accepted(parser().parse(json)))
        var next = 200
        let goal = proposal.makeGoal(id: F.uuid(9), createdAt: F.now, checkIn: .weekly) {
            next += 1
            return F.uuid(next)
        }
        XCTAssertEqual(goal.source, .proposed)
        XCTAssertEqual(goal.state, .active)
        XCTAssertEqual(goal.checkIn, .weekly)
        XCTAssertEqual(goal.steps.map(\.id), [F.uuid(201), F.uuid(202), F.uuid(203), F.uuid(204)])
        XCTAssertTrue(goal.steps.allSatisfy { $0.state == .open && $0.evidence.isEmpty })
    }

    // MARK: - Lengths

    func testOverLongTitlesAndReasonsAreRefusedNotTrimmed() {
        let longTitle = String(repeating: "a", count: GoalLimits.titleLength + 1)
        let longWhy = String(repeating: "b", count: GoalLimits.whyLength + 1)
        let json = #"{"title": "\#(longTitle)", "why": "\#(longWhy)", "steps": \#(fourSteps)}"#
        XCTAssertEqual(problems(parser().parse(json)),
                       [.titleTooLong(count: 81), .whyTooLong(count: 141)])

        let exact = String(repeating: "a", count: GoalLimits.titleLength)
        XCTAssertNotNil(accepted(parser().parse(#"{"title": "\#(exact)", "steps": \#(fourSteps)}"#)))
    }

    func testAnOverLongOrMissingStepTitleIsNamedByIndex() {
        let longStep = String(repeating: "s", count: GoalLimits.stepTitleLength + 1)
        let json = """
        {"title": "Clear the garage", "steps": [{"title": "One"}, {"title": "  "}, {"title": "\(longStep)"}]}
        """
        XCTAssertEqual(problems(parser().parse(json)),
                       [.missingStepTitle(index: 1), .stepTitleTooLong(index: 2, count: 81)])
    }

    func testMissingTitleAndUnreadableInputAreRefused() {
        XCTAssertEqual(problems(parser().parse(#"{"steps": \#(fourSteps)}"#)), [.missingTitle])
        XCTAssertEqual(problems(parser().parse("not json")), [.unreadable])
        XCTAssertEqual(problems(parser().parse("[1, 2, 3]")), [.unreadable])
    }

    // MARK: - Step count

    func testBetweenThreeAndSevenSteps() {
        func steps(_ n: Int) -> String {
            "[" + (1...n).map { #"{"title": "Step \#($0)"}"# }.joined(separator: ",") + "]"
        }
        for n in [3, 7] {
            XCTAssertNotNil(accepted(parser().parse(#"{"title": "T", "steps": \#(steps(n))}"#)), "\(n) steps")
        }
        XCTAssertEqual(problems(parser().parse(#"{"title": "T", "steps": \#(steps(2))}"#)), [.tooFewSteps(count: 2)])
        XCTAssertEqual(problems(parser().parse(#"{"title": "T", "steps": \#(steps(8))}"#)), [.tooManySteps(count: 8)])
        XCTAssertEqual(problems(parser().parse(#"{"title": "T"}"#)), [.tooFewSteps(count: 0)])
    }

    // MARK: - Dates

    func testADueDateInThePastIsRefused() {
        for due in ["2026-10-18", "2026-10-19T09:59:00+13:00", "2026-10-19T10:00:00+13:00"] {
            XCTAssertEqual(problems(parser().parse(#"{"title": "T", "dueAt": "\#(due)", "steps": \#(fourSteps)}"#)),
                           [.dueDateInPast], due)
        }
        XCTAssertEqual(problems(parser().parse(#"{"title": "T", "dueAt": "next week", "steps": \#(fourSteps)}"#)),
                       [.dueDateUnreadable])
        XCTAssertEqual(problems(parser().parse(#"{"title": "T", "dueAt": "2026-02-30", "steps": \#(fourSteps)}"#)),
                       [.dueDateUnreadable], "a day that does not exist is not quietly rolled over")
        // Today, as a bare date, is still ahead: it means the end of today.
        XCTAssertNotNil(accepted(parser().parse(#"{"title": "T", "dueAt": "2026-10-19", "steps": \#(fourSteps)}"#)))
    }

    func testAnActionTimedInThePastIsDroppedAndTheStepKept() throws {
        let json = """
        {"title": "T", "steps": [
          {"title": "Ring the depot", "action": {"kind": "reminder", "text": "Ring the depot", "at": "2026-10-19T08:00:00+13:00"}},
          {"title": "Hold time", "action": {"kind": "calendar_hold", "title": "Garage", "at": "2026-10-18T10:00:00+13:00", "minutes": 60}},
          {"title": "Three"}]}
        """
        let (proposal, dropped) = try XCTUnwrap(accepted(parser().parse(json)))
        XCTAssertEqual(proposal.steps.count, 3)
        XCTAssertNil(proposal.steps[0].action)
        XCTAssertNil(proposal.steps[1].action)
        XCTAssertEqual(dropped, [DroppedAction(stepIndex: 0, reason: .dateInPast),
                                 DroppedAction(stepIndex: 1, reason: .dateInPast)])
    }

    // MARK: - Action kinds

    func testUnknownActionKindsAreDroppedByName() throws {
        let json = """
        {"title": "T", "steps": [
          {"title": "Pay the deposit", "action": {"kind": "payment", "amount": 50}},
          {"title": "Run something", "action": {"kind": "run_tool", "tool": "send_message"}},
          {"title": "Ask", "action": {"kind": "ask", "question": "Which depot do you use?"}}]}
        """
        let (proposal, dropped) = try XCTUnwrap(accepted(parser().parse(json)))
        XCTAssertEqual(dropped, [DroppedAction(stepIndex: 0, reason: .unknownKind("payment")),
                                 DroppedAction(stepIndex: 1, reason: .unknownKind("run_tool"))])
        XCTAssertEqual(proposal.steps.map(\.title), ["Pay the deposit", "Run something", "Ask"])
        XCTAssertEqual(proposal.steps[2].action, .ask(question: "Which depot do you use?"))
    }

    func testEveryKindInTheClosedSetParses() throws {
        let json = """
        {"title": "T", "steps": [
          {"title": "A", "action": {"kind": "reminder", "text": "Skip"}},
          {"title": "B", "action": {"kind": "calendar_hold", "title": "Garage", "at": "2026-10-24T10:00:00+13:00", "minutes": 120}},
          {"title": "C", "action": {"kind": "search", "query": "paint depot hours"}},
          {"title": "D", "action": {"kind": "draft", "draftKind": "message", "prompt": "Ask about the skip"}},
          {"title": "E", "action": {"kind": "scheduled_check", "prompt": "Has the skip been delivered?", "every": "daily"}},
          {"title": "F", "action": {"kind": "ask", "question": "Keep the bike?"}}]}
        """
        let (proposal, dropped) = try XCTUnwrap(accepted(parser().parse(json)))
        XCTAssertEqual(dropped, [])
        XCTAssertEqual(proposal.steps.compactMap(\.action?.kind), StepAction.Kind.allCases)
    }

    func testActionFieldsOutOfBoundsDropTheActionWithTheField() throws {
        let longQuery = String(repeating: "q", count: GoalLimits.actionTextLength + 1)
        let json = """
        {"title": "T", "steps": [
          {"title": "A", "action": {"kind": "calendar_hold", "title": "Garage", "at": "2026-10-24T10:00:00+13:00", "minutes": 4}},
          {"title": "B", "action": {"kind": "search", "query": "\(longQuery)"}},
          {"title": "C", "action": {"kind": "draft", "draftKind": "poem", "prompt": "x"}},
          {"title": "D", "action": {"kind": "scheduled_check", "prompt": "x", "every": "hourly"}},
          {"title": "E", "action": {"note": "no kind"}}]}
        """
        let (_, dropped) = try XCTUnwrap(accepted(parser().parse(json)))
        XCTAssertEqual(dropped.map(\.reason), [.invalid(field: "minutes"), .invalid(field: "query"),
                                               .invalid(field: "draftKind"), .invalid(field: "every"),
                                               .invalid(field: "kind")])
    }

    // MARK: - Permission

    /// An action whose tool the wearer has switched off, or whose integration is read-only, is
    /// never offered — the step stays, the offer goes.
    func testActionsOnDisabledOrReadOnlyToolsAreDropped() throws {
        let json = """
        {"title": "T", "steps": [
          {"title": "Book the skip", "action": {"kind": "search", "query": "skip hire"}},
          {"title": "Hold Saturday", "action": {"kind": "calendar_hold", "title": "Garage", "at": "2026-10-24T10:00:00+13:00", "minutes": 60}},
          {"title": "Remind me", "action": {"kind": "reminder", "text": "Paint"}},
          {"title": "Draft it", "action": {"kind": "draft", "draftKind": "listing", "prompt": "Bike"}}]}
        """
        let permit = StepActionPermission.predicate(enabledTools: ["calendar", "reminder"],
                                                    readOnlyTools: ["calendar"],
                                                    agentModeEnabled: false)
        let (proposal, dropped) = try XCTUnwrap(accepted(parser(permit: permit).parse(json)))
        XCTAssertEqual(dropped, [DroppedAction(stepIndex: 0, reason: .notPermitted),
                                 DroppedAction(stepIndex: 1, reason: .notPermitted)])
        XCTAssertEqual(proposal.steps.map { $0.action?.kind }, [nil, nil, .reminder, .draft],
                       "a draft runs through no tool, so it is always offerable")
    }

    /// Goals work without Agent Mode; only a background check needs it.
    func testAScheduledCheckNeedsAgentModeAndNothingElseDoes() throws {
        let json = """
        {"title": "T", "steps": [
          {"title": "Check", "action": {"kind": "scheduled_check", "prompt": "Delivered yet?", "every": "weekly"}},
          {"title": "Search", "action": {"kind": "search", "query": "skip hire"}},
          {"title": "Three"}]}
        """
        let tools: Set<String> = ["manage_schedule", "web_search"]
        let off = StepActionPermission.predicate(enabledTools: tools, agentModeEnabled: false)
        let on = StepActionPermission.predicate(enabledTools: tools, agentModeEnabled: true)

        let (withoutAgent, dropped) = try XCTUnwrap(accepted(parser(permit: off).parse(json)))
        XCTAssertEqual(dropped, [DroppedAction(stepIndex: 0, reason: .notPermitted)])
        XCTAssertEqual(withoutAgent.steps[1].action, .search(query: "skip hire"))

        let (withAgent, none) = try XCTUnwrap(accepted(parser(permit: on).parse(json)))
        XCTAssertEqual(none, [])
        XCTAssertEqual(withAgent.steps[0].action, .scheduledCheck(prompt: "Delivered yet?", every: .weekly))
    }

    /// The predicate sees the resolved action, so a later rule can judge more than the tool name.
    func testThePredicateIsGivenTheResolvedAction() throws {
        var seen: [StepAction] = []
        let json = #"{"title": "T", "steps": [{"title": "A", "action": {"kind": "search", "query": "q"}}, {"title": "B"}, {"title": "C"}]}"#
        _ = parser(permit: { seen.append($0); return true }).parse(json)
        XCTAssertEqual(seen, [.search(query: "q")])
    }
}
