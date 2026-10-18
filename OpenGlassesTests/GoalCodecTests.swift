import XCTest
@testable import OpenGlasses

/// Plan IW P0 — a goal written by this build reads in the next. The fixture is the on-disk format;
/// if it stops decoding, a stored goal would be lost on update.
final class GoalCodecTests: XCTestCase {
    private typealias F = GoalActivityFixture

    static let fixture = #"""
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "title": "Clear the garage",
      "why": "Before the move",
      "createdAt": "2026-10-18T20:00:00Z",
      "dueAt": "2026-10-30T10:59:59.000Z",
      "state": "active",
      "checkIn": "before_due:2",
      "persona": "Weekend",
      "source": "proposed",
      "steps": [
        {"id": "00000000-0000-0000-0000-000000000101", "title": "Book the skip", "state": "done",
         "doneAt": "2026-10-19T01:00:00Z", "suggestedAction": {"kind": "search", "query": "skip hire"},
         "evidence": ["operation:op-1", "trace:tr-1", "thread:th-1", "goal:g-1"]},
        {"id": "00000000-0000-0000-0000-000000000102", "title": "Hold Saturday", "state": "in_progress",
         "suggestedAction": {"kind": "calendar_hold", "title": "Garage", "at": "2026-10-23T21:00:00Z", "minutes": 120}},
        {"id": "00000000-0000-0000-0000-000000000103", "title": "List the bike", "state": "next",
         "dueAt": "2026-10-24T00:00:00.500Z",
         "suggestedAction": {"kind": "draft", "draftKind": "listing", "prompt": "A listing for the bike"}},
        {"id": "00000000-0000-0000-0000-000000000104", "title": "Paint to the depot", "state": "open",
         "suggestedAction": {"kind": "reminder", "text": "Paint", "at": "2026-10-22T20:00:00Z"}},
        {"id": "00000000-0000-0000-0000-000000000105", "title": "Check delivery", "state": "skipped",
         "suggestedAction": {"kind": "scheduled_check", "prompt": "Delivered yet?", "every": "weekly"}},
        {"id": "00000000-0000-0000-0000-000000000106", "title": "Ask about the depot", "state": "open",
         "suggestedAction": {"kind": "ask", "question": "Which depot?"}},
        {"id": "00000000-0000-0000-0000-000000000107", "title": "From a newer build", "state": "open",
         "suggestedAction": {"kind": "teleport", "where": "moon"}}
      ]
    }
    """#

    private func decode(_ json: String) throws -> Goal {
        try RecordJSONCodec.decoder().decode(Goal.self, from: Data(json.utf8))
    }

    func testTheFixtureDecodes() throws {
        let goal = try decode(Self.fixture)
        XCTAssertEqual(goal.id, F.uuid(1))
        XCTAssertEqual(goal.title, "Clear the garage")
        XCTAssertEqual(goal.why, "Before the move")
        XCTAssertEqual(goal.createdAt, F.date(19, 9))
        XCTAssertEqual(goal.dueAt, F.date(30, 23, 59).addingTimeInterval(59))
        XCTAssertEqual(goal.state, .active)
        XCTAssertEqual(goal.checkIn, .beforeDue(days: 2))
        XCTAssertEqual(goal.persona, "Weekend")
        XCTAssertEqual(goal.source, .proposed)
        XCTAssertEqual(goal.steps.map(\.state), [.done, .inProgress, .next, .open, .skipped, .open, .open])
        XCTAssertEqual(goal.steps[0].doneAt, F.date(19, 14))
        XCTAssertEqual(goal.steps[0].evidence, [.operation("op-1"), .trace("tr-1"), .thread("th-1"), .goal("g-1")])
        XCTAssertEqual(goal.steps.map(\.suggestedAction), [
            .search(query: "skip hire"),
            .calendarHold(title: "Garage", at: F.date(24, 10), minutes: 120),
            .draft(kind: .listing, prompt: "A listing for the bike"),
            .reminder(text: "Paint", at: F.date(23, 9)),
            .scheduledCheck(prompt: "Delivered yet?", every: .weekly),
            .ask(question: "Which depot?"),
            nil,
        ])
        XCTAssertEqual(goal.steps[2].dueAt, F.date(24, 13).addingTimeInterval(0.5), "fractional seconds survive")
        XCTAssertEqual(goal.steps[6].title, "From a newer build", "an unknown action loses the offer, not the step")
    }

    func testEncodeThenDecodeIsIdentity() throws {
        let goal = try decode(Self.fixture)
        let data = try RecordJSONCodec.encoder().encode(goal)
        XCTAssertEqual(try RecordJSONCodec.decoder().decode(Goal.self, from: data), goal)

        let json = String(decoding: data, as: UTF8.self)
        for token in [#""checkIn":"before_due:2""#, #""state":"in_progress""#, #""kind":"calendar_hold""#,
                      #""source":"proposed""#, #""2026-10-23T21:00:00.000Z""#, #""operation:op-1""#] {
            XCTAssertTrue(json.contains(token), token)
        }
    }

    func testEveryCadenceRoundTrips() throws {
        for cadence in [CheckInCadence.none, .daily, .weekly, .beforeDue(days: 1), .beforeDue(days: 30)] {
            let data = try RecordJSONCodec.encoder().encode([cadence])
            XCTAssertEqual(try RecordJSONCodec.decoder().decode([CheckInCadence].self, from: data), [cadence])
        }
        for bad in ["before_due:0", "before_due:31", "before_due:", "hourly"] {
            XCTAssertNil(CheckInCadence(codeValue: bad), bad)
        }
    }

    func testOptionalFieldsDefault() throws {
        let minimal = #"""
        {"id": "00000000-0000-0000-0000-000000000002", "title": "Sort the lounge",
         "createdAt": "2026-10-18T20:00:00Z", "state": "paused", "source": "wearer"}
        """#
        let goal = try decode(minimal)
        XCTAssertEqual(goal.checkIn, CheckInCadence.none)
        XCTAssertEqual(goal.steps, [])
        XCTAssertNil(goal.dueAt)
        XCTAssertNil(goal.why)
    }

    func testLimitsAreEnforcedWhenAStoredGoalIsRead() {
        let longTitle = String(repeating: "t", count: GoalLimits.titleLength + 1)
        let longStep = String(repeating: "s", count: GoalLimits.stepTitleLength + 1)
        let longWhy = String(repeating: "w", count: GoalLimits.whyLength + 1)
        let base = #"{"id": "00000000-0000-0000-0000-000000000002", "createdAt": "2026-10-18T20:00:00Z", "state": "active", "source": "wearer""#
        XCTAssertThrowsError(try decode(base + #", "title": "\#(longTitle)"}"#))
        XCTAssertThrowsError(try decode(base + #", "title": ""}"#))
        XCTAssertThrowsError(try decode(base + #", "title": "T", "why": "\#(longWhy)"}"#))
        XCTAssertThrowsError(try decode(base + #", "title": "T", "steps": [{"id": "00000000-0000-0000-0000-000000000101", "title": "\#(longStep)", "state": "open"}]}"#))
        XCTAssertThrowsError(try decode(base.replacingOccurrences(of: "active", with: "archived") + #", "title": "T"}"#),
                             "an unknown state is not guessed")
        XCTAssertNoThrow(try decode(base + #", "title": "T"}"#))
    }
}
