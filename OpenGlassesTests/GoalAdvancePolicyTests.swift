import XCTest
@testable import OpenGlasses

/// Plan IW P0 — what the assistant may offer for a goal, and when it may bring one up. Nothing
/// here changes a goal: the next step is chosen, evidence is *suggested*, and unprompted speech
/// is capped.
final class GoalAdvancePolicyTests: XCTestCase {
    private typealias F = GoalActivityFixture

    // MARK: - Next step: `next` → earliest due → first open

    func testNextStepSelectionTable() {
        let cases: [(name: String, steps: [GoalStep], state: GoalState, expected: Int?)] = [
            ("first open when nothing is dated or marked",
             [F.step(1, "A"), F.step(2, "B"), F.step(3, "C")], .active, 1),
            ("done and skipped steps are passed over",
             [F.step(1, "A", state: .done), F.step(2, "B", state: .skipped), F.step(3, "C")], .active, 3),
            ("an in-progress step counts as open",
             [F.step(1, "A", state: .done), F.step(2, "B", state: .inProgress), F.step(3, "C")], .active, 2),
            ("the earliest due date wins over order",
             [F.step(1, "A", dueAt: F.date(25, 9)), F.step(2, "B"), F.step(3, "C", dueAt: F.date(21, 9))], .active, 3),
            ("a step marked next wins over a due date",
             [F.step(1, "A", dueAt: F.date(20, 9)), F.step(2, "B", state: .next), F.step(3, "C")], .active, 2),
            ("a finished step's due date does not count",
             [F.step(1, "A", state: .done, dueAt: F.date(20, 9)), F.step(2, "B"), F.step(3, "C", dueAt: F.date(22, 9))], .active, 3),
            ("nothing left", [F.step(1, "A", state: .done), F.step(2, "B", state: .skipped)], .active, nil),
            ("no steps", [], .active, nil),
            ("a paused goal offers nothing", [F.step(1, "A")], .paused, nil),
            ("a done goal offers nothing", [F.step(1, "A")], .done, nil),
            ("an abandoned goal offers nothing", [F.step(1, "A")], .abandoned, nil),
        ]
        for row in cases {
            let goal = F.goal(row.steps, state: row.state)
            XCTAssertEqual(GoalAdvancePolicy.nextStep(in: goal)?.id, row.expected.map { F.uuid(100 + $0) }, row.name)
        }
    }

    func testTheOfferIsTheNextStepsAction() {
        let goal = F.goal([F.step(1, "Book the skip", state: .done, action: .search(query: "skip hire")),
                           F.step(2, "List the bike", action: .draft(kind: .listing, prompt: "Bike")),
                           F.step(3, "Sort the shelves")])
        XCTAssertEqual(GoalAdvancePolicy.offer(for: goal), .draft(kind: .listing, prompt: "Bike"))
        XCTAssertNil(GoalAdvancePolicy.offer(for: F.goal([F.step(1, "Sort the shelves")])))
    }

    // MARK: - Evidence: suggest only

    func testEvidenceSuggestionTable() {
        let goal = F.goal([F.step(1, "Book the skip", action: .search(query: "skip hire")),
                           F.step(2, "Hold Saturday", action: .calendarHold(title: "Garage", at: F.date(24, 9), minutes: 60)),
                           F.step(3, "Sort the shelves"),
                           F.step(4, "Done already", state: .done)])
        func entry(step: Int?, tool: String?, outcome: ActivityOutcome = .done, kind: ActivityKind = .action,
                   authorisation: ActivityAuthorisation = .asked, goal: UUID? = F.uuid(1)) -> ActivityEntry {
            F.entry(1, at: F.now, title: "Did a thing", kind: kind, tool: tool, outcome: outcome,
                    authorisation: authorisation, goalID: goal, stepID: step.map { F.uuid(100 + $0) })
        }
        let cases: [(name: String, entry: ActivityEntry, suggests: Bool)] = [
            ("a linked search from the step's own tool", entry(step: 1, tool: "web_search"), true),
            ("a linked calendar entry for the hold", entry(step: 2, tool: "calendar"), true),
            ("a step with no action accepts any linked tool", entry(step: 3, tool: "save_note"), true),
            ("a step under a standing grant", entry(step: 3, tool: "van_stock", authorisation: .standingGrant(scope: "van")), true),
            ("a linked scheduled run", entry(step: 3, tool: nil, kind: .scheduledRun, authorisation: .scheduled), true),
            ("the wrong tool for the step's action", entry(step: 2, tool: "reminder"), false),
            ("not linked to any step", entry(step: nil, tool: "web_search"), false),
            ("linked to another goal", entry(step: 1, tool: "web_search", goal: F.uuid(2)), false),
            ("failed", entry(step: 1, tool: "web_search", outcome: .failed), false),
            ("uncertain", entry(step: 1, tool: "web_search", outcome: .uncertain), false),
            ("still waiting on the wearer", entry(step: 1, tool: "web_search", outcome: .waitingOnYou), false),
            ("held", entry(step: 3, tool: "save_note", kind: .held, authorisation: .heldForYou), false),
            ("refused", entry(step: 3, tool: "save_note", kind: .refused, authorisation: .refused(reason: "restrictedTarget")), false),
            ("turned away as read-only", entry(step: 3, tool: "calendar", authorisation: .readOnly), false),
            ("the step is already done", entry(step: 4, tool: "save_note"), false),
            ("a step that does not exist", entry(step: 9, tool: "save_note"), false),
        ]
        for row in cases {
            let suggestion = GoalAdvancePolicy.evidenceSuggestion(for: row.entry, in: goal)
            XCTAssertEqual(suggestion != nil, row.suggests, row.name)
            if let suggestion {
                XCTAssertEqual(suggestion.goalID, goal.id, row.name)
                XCTAssertEqual(suggestion.stepID, row.entry.stepID, row.name)
                XCTAssertEqual(suggestion.entryID, row.entry.id, row.name)
            }
        }
        var paused = goal
        paused.state = .paused
        XCTAssertNil(GoalAdvancePolicy.evidenceSuggestion(for: entry(step: 1, tool: "web_search"), in: paused))
    }

    /// The suggestion is a value; asking for it leaves the goal exactly as it was.
    func testEvidenceIsNeverApplied() {
        let goal = F.goal([F.step(1, "Book the skip"), F.step(2, "B"), F.step(3, "C")])
        let before = goal
        let entry = F.entry(1, at: F.now, title: "Searched", tool: "web_search",
                            goalID: goal.id, stepID: F.uuid(101))
        XCTAssertNotNil(GoalAdvancePolicy.evidenceSuggestion(for: entry, in: goal))
        XCTAssertEqual(goal, before)
        XCTAssertEqual(goal.steps[0].state, .open)
    }

    // MARK: - Daily cap

    func testTwoUnpromptedGoalSentencesADayInTheWearersCalendar() {
        let calendar = F.calendar()
        let cases: [(name: String, spoken: [Date], now: Date, allowed: Bool)] = [
            ("none yet", [], F.date(19, 9), true),
            ("one today", [F.date(19, 8)], F.date(19, 9), true),
            ("two today", [F.date(19, 8), F.date(19, 8, 30)], F.date(19, 9), false),
            ("two yesterday", [F.date(18, 20), F.date(18, 23, 59)], F.date(19, 0, 1), true),
            ("one yesterday, one today", [F.date(18, 23), F.date(19, 7)], F.date(19, 9), true),
        ]
        XCTAssertEqual(GoalAdvancePolicy.dailySentenceCap, 2)
        for row in cases {
            XCTAssertEqual(GoalAdvancePolicy.maySpeakGoalSentence(spokenAt: row.spoken, now: row.now,
                                                                  calendar: calendar),
                           row.allowed, row.name)
        }
    }

    // MARK: - Check-in cadence

    func testCheckInCadenceTable() {
        let calendar = F.calendar()
        let open = [F.step(1, "A"), F.step(2, "B")]
        let due = F.date(24, 17) // Saturday, 5 PM
        let cases: [(name: String, goal: Goal, last: Date?, now: Date, due: Bool)] = [
            ("no cadence", F.goal(open, checkIn: .none), nil, F.now, false),
            ("daily, never checked", F.goal(open, checkIn: .daily), nil, F.now, true),
            ("daily, checked earlier today", F.goal(open, checkIn: .daily), F.date(19, 7), F.now, false),
            ("daily, checked yesterday", F.goal(open, checkIn: .daily), F.date(18, 23), F.now, true),
            ("weekly, six days on", F.goal(open, checkIn: .weekly), F.date(13, 10), F.now, false),
            ("weekly, seven days on", F.goal(open, checkIn: .weekly), F.date(12, 22), F.now, true),
            ("before due 3: window not open yet", F.goal(open, dueAt: due, checkIn: .beforeDue(days: 3)), nil, F.date(20, 23, 59), false),
            ("before due 3: window opens at midnight", F.goal(open, dueAt: due, checkIn: .beforeDue(days: 3)), nil, F.date(21, 0), true),
            ("before due 3: already checked in the window", F.goal(open, dueAt: due, checkIn: .beforeDue(days: 3)), F.date(21, 8), F.date(23, 9), false),
            ("before due 3: checked before the window opened", F.goal(open, dueAt: due, checkIn: .beforeDue(days: 3)), F.date(19, 8), F.date(22, 9), true),
            ("before due 3: past due", F.goal(open, dueAt: due, checkIn: .beforeDue(days: 3)), nil, F.date(24, 17), false),
            ("before due falls back to the next step's date",
             F.goal([F.step(1, "A", dueAt: due)], checkIn: .beforeDue(days: 1)), nil, F.date(23, 6), true),
            ("before due with no date anywhere", F.goal(open, checkIn: .beforeDue(days: 2)), nil, F.now, false),
            ("nothing left to do", F.goal([F.step(1, "A", state: .done)], checkIn: .daily), nil, F.now, false),
            ("paused", F.goal(open, state: .paused, checkIn: .daily), nil, F.now, false),
        ]
        for row in cases {
            XCTAssertEqual(GoalAdvancePolicy.isCheckInDue(goal: row.goal, lastCheckIn: row.last,
                                                          now: row.now, calendar: calendar),
                           row.due, row.name)
        }
    }

    /// `.beforeDue(3)` speaks once over the whole run-up, not once a day.
    func testBeforeDueFiresOnceAcrossTheWindow() {
        let calendar = F.calendar()
        let goal = F.goal([F.step(1, "A")], dueAt: F.date(24, 17), checkIn: .beforeDue(days: 3))
        var last: Date?
        var fired: [Date] = []
        var hour = F.date(19, 0)
        while hour < F.date(26, 0) {
            if GoalAdvancePolicy.isCheckInDue(goal: goal, lastCheckIn: last, now: hour, calendar: calendar) {
                fired.append(hour)
                last = hour
            }
            hour = hour.addingTimeInterval(3600)
        }
        XCTAssertEqual(fired, [F.date(21, 0)])
    }

    func testTheDefaultCadenceIsTheQuietOne() {
        XCTAssertEqual(CheckInCadence.defaultCadence(dueAt: F.date(24, 17)), .beforeDue(days: 2))
        XCTAssertEqual(CheckInCadence.defaultCadence(dueAt: nil), CheckInCadence.none)
    }
}
