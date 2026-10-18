import XCTest
@testable import OpenGlasses

/// Plan IW P0 — the exact words. Monday 19 October 2026, 10 AM in Auckland throughout.
final class GoalPhraserTests: XCTestCase {
    private typealias F = GoalActivityFixture
    private let phraser = GoalPhraser(now: F.now, calendar: F.calendar())

    private var garage: Goal {
        F.goal([F.step(1, "Book the skip", state: .done),
                F.step(2, "Sort the shelves", state: .done),
                F.step(3, "List the bike for sale", dueAt: F.date(24, 12), action: .draft(kind: .listing, prompt: "Bike")),
                F.step(4, "Drop the paint at the depot")])
    }

    // MARK: - Status

    func testStatusSaysProgressThenTheNextStepThenOffersItsAction() {
        XCTAssertEqual(phraser.status(of: garage),
                       "Two of four done. Next: List the bike for sale, due Saturday. Want me to draft the listing?")
    }

    func testStatusProgressTable() {
        let cases: [(Goal, String)] = [
            (F.goal([F.step(1, "A"), F.step(2, "B"), F.step(3, "C")], dueAt: F.date(20, 17)),
             "None of three done yet, due tomorrow. Next: A."),
            (F.goal([F.step(1, "A", state: .done), F.step(2, "B", state: .done), F.step(3, "C", state: .done)]),
             "All three done. Want me to mark the goal done?"),
            (F.goal([F.step(1, "A", state: .done)]),
             "The one step is done. Want me to mark the goal done?"),
            (F.goal([F.step(1, "A")]), "Not started yet. Next: A."),
            (F.goal([F.step(1, "A", state: .done), F.step(2, "B", state: .skipped), F.step(3, "C")]),
             "One of two done. Next: C."),
            (F.goal([]), "There are no steps on it yet."),
            (F.goal([F.step(1, "A", state: .done), F.step(2, "B")], state: .paused),
             "That goal's paused. One of two done."),
            (F.goal([F.step(1, "A", state: .done)], state: .done), "That goal's done."),
            (F.goal([F.step(1, "A")], state: .abandoned), "You set that goal aside."),
        ]
        for (goal, expected) in cases {
            XCTAssertEqual(phraser.status(of: goal), expected)
        }
    }

    // MARK: - Next

    func testNextNamesTheGoalAndOffersTheAction() {
        let goal = F.goal([F.step(1, "Book the skip", dueAt: F.date(20, 9), action: .search(query: "skip hire")),
                           F.step(2, "Sort the shelves"), F.step(3, "Sell the bike")])
        XCTAssertEqual(phraser.next(for: goal),
                       "Next on Clear the garage: Book the skip, due tomorrow. Want me to search for skip hire?")
        XCTAssertEqual(phraser.next(for: F.goal([F.step(1, "A", state: .done)])),
                       "Nothing's left to do on Clear the garage.")
        XCTAssertEqual(phraser.next(for: F.goal([F.step(1, "A")], state: .paused)),
                       "That goal's paused. Not started yet.")
    }

    // MARK: - Read-back

    func testReadBackListsTheStepsAndAsksBeforeAnythingIsKept() {
        let proposal = GoalProposal(title: "Clear the garage", why: nil, dueAt: nil, steps: [
            .init(title: "Book the skip", action: nil), .init(title: "Sort the shelves", action: nil),
            .init(title: "List the bike for sale", action: nil), .init(title: "Drop the paint at the depot", action: nil),
        ])
        XCTAssertEqual(phraser.readBack(proposal),
                       "Okay. I'd break that into: book the skip, sort the shelves, list the bike for sale, "
                           + "and drop the paint at the depot. Want me to keep an eye on it?")
    }

    func testReadBackSaysTheDueDateAndKeepsCapitalisedWords() {
        let proposal = GoalProposal(title: "Sort the lounge", why: nil, dueAt: F.date(30, 23, 59), steps: [
            .init(title: "TV wall mount", action: nil), .init(title: "Order the rug", action: nil),
            .init(title: "I need a drill", action: nil),
        ])
        XCTAssertEqual(phraser.readBack(proposal),
                       "Okay, by 30 October. I'd break that into: TV wall mount, order the rug, and I need a drill. "
                           + "Want me to keep an eye on it?")
    }

    // MARK: - Offers

    func testOfferTable() {
        let cases: [(StepAction, String)] = [
            (.reminder(text: "Paint", at: nil), "Want me to set a reminder?"),
            (.reminder(text: "Paint", at: F.date(24, 9)), "Want me to remind you Saturday at 9 AM?"),
            (.reminder(text: "Paint", at: F.date(19, 16)), "Want me to remind you today at 4 PM?"),
            (.reminder(text: "Paint", at: F.date(2, 12, month: 11)), "Want me to remind you 2 November at 12 PM?"),
            (.calendarHold(title: "Garage", at: F.date(24, 10, 30), minutes: 60),
             "Want me to hold an hour in your calendar Saturday at 10:30 AM?"),
            (.calendarHold(title: "Garage", at: F.date(20, 8, 5), minutes: 120),
             "Want me to hold two hours in your calendar tomorrow at 8:05 AM?"),
            (.calendarHold(title: "Garage", at: F.date(20, 0), minutes: 30),
             "Want me to hold 30 minutes in your calendar tomorrow at 12 AM?"),
            (.calendarHold(title: "Garage", at: F.date(20, 13), minutes: 90),
             "Want me to hold 90 minutes in your calendar tomorrow at 1 PM?"),
            (.search(query: "skip hire"), "Want me to search for skip hire?"),
            (.draft(kind: .message, prompt: "x"), "Want me to draft the message?"),
            (.draft(kind: .email, prompt: "x"), "Want me to draft the email?"),
            (.scheduledCheck(prompt: "x", every: .daily), "Want me to check on it every day?"),
            (.scheduledCheck(prompt: "x", every: .weekly), "Want me to check on it every week?"),
            (.ask(question: "Which depot do you use?"), "Which depot do you use?"),
            (.ask(question: "Tell me which depot"), "Tell me which depot."),
        ]
        for (action, expected) in cases {
            XCTAssertEqual(phraser.offer(action), expected)
        }
    }

    func testEvidenceIsOfferedAsAQuestion() {
        XCTAssertEqual(phraser.evidenceSuggestion(for: F.step(1, "Book the skip")),
                       "Looks like this one's done: Book the skip. Want me to mark it done?")
    }

    /// Spoken copy never names a plan.
    func testNoStringNamesAPlan() throws {
        let pattern = try NSRegularExpression(pattern: #"\bPlan [A-Z]{1,2}\b"#)
        let spoken = [phraser.status(of: garage), phraser.next(for: garage),
                      phraser.evidenceSuggestion(for: garage.steps[0])]
            + [StepAction.reminder(text: "x", at: nil), .search(query: "q"), .draft(kind: .note, prompt: "x"),
               .scheduledCheck(prompt: "x", every: .daily)].map(phraser.offer)
            + [phraser.readBack(GoalProposal(title: "T", why: nil, dueAt: nil,
                                             steps: [.init(title: "A", action: nil)]))]
        for line in spoken {
            XCTAssertNil(pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), line)
        }
    }
}
