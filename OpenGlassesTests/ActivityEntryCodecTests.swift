import XCTest
@testable import OpenGlasses

/// Plan IW P0 — trail entries on disk must survive app updates. The fixture pins every enum's
/// persisted string; renaming a Swift case must not change any of them.
final class ActivityEntryCodecTests: XCTestCase {
    private typealias F = GoalActivityFixture

    static let fixture = #"""
    [
      {"id": "00000000-0000-0000-0000-000000000501", "at": "2026-10-18T19:10:00Z", "kind": "action",
       "title": "Added the dentist to your calendar", "tool": "calendar", "authorisation": "asked",
       "origin": "wearer", "outcome": "done", "refs": ["operation:op-7"]},
      {"id": "00000000-0000-0000-0000-000000000502", "at": "2026-10-18T20:30:00.250Z", "kind": "planned_step",
       "title": "Recorded four parts on job 1017", "detail": "Finish the job record", "tool": "van_stock",
       "goalID": "00000000-0000-0000-0000-000000000001", "stepID": "00000000-0000-0000-0000-000000000101",
       "authorisation": "standing_grant:van-stock", "origin": "agent", "outcome": "uncertain",
       "refs": ["trace:tr-2", "goal:00000000-0000-0000-0000-000000000001"]},
      {"id": "00000000-0000-0000-0000-000000000503", "at": "2026-10-18T21:00:00Z", "kind": "scheduled_run",
       "title": "Ran your morning check", "authorisation": "scheduled", "origin": "scheduled",
       "outcome": "failed"},
      {"id": "00000000-0000-0000-0000-000000000504", "at": "2026-10-18T21:05:00Z", "kind": "told_you",
       "title": "Told you the parcel arrived", "authorisation": "asked", "origin": "remote:watch",
       "outcome": "done", "refs": ["thread:th-3"]},
      {"id": "00000000-0000-0000-0000-000000000505", "at": "2026-10-18T21:10:00Z", "kind": "held",
       "title": "A message to the office", "tool": "send_message", "authorisation": "held_for_you",
       "origin": "agent", "outcome": "waiting_on_you"},
      {"id": "00000000-0000-0000-0000-000000000506", "at": "2026-10-18T21:15:00Z", "kind": "refused",
       "title": "Stopped a skill from unlocking the door", "tool": "smart_home",
       "authorisation": "refused:restrictedTarget", "origin": "wearer", "outcome": "failed"},
      {"id": "00000000-0000-0000-0000-000000000507", "at": "2026-10-18T21:20:00Z", "kind": "refused",
       "title": "Didn't add to your read-only calendar", "tool": "calendar",
       "authorisation": "read_only", "origin": "wearer", "outcome": "failed"}
    ]
    """#

    private func decode(_ json: String) throws -> [ActivityEntry] {
        try RecordJSONCodec.decoder().decode([ActivityEntry].self, from: Data(json.utf8))
    }

    func testTheFixtureDecodes() throws {
        let entries = try decode(Self.fixture)
        XCTAssertEqual(entries.map(\.kind), [.action, .plannedStep, .scheduledRun, .toldYou, .held, .refused, .refused])
        XCTAssertEqual(entries.map(\.authorisation), [
            .asked, .standingGrant(scope: "van-stock"), .scheduled, .asked, .heldForYou,
            .refused(reason: ToolRefusalReason.restrictedTarget.rawValue), .readOnly,
        ])
        XCTAssertEqual(entries.map(\.origin), [.wearer, .agent, .scheduled, .remote(source: "watch"), .agent, .wearer, .wearer])
        XCTAssertEqual(entries.map(\.outcome), [.done, .uncertain, .failed, .done, .waitingOnYou, .failed, .failed])
        XCTAssertEqual(entries[0].at, F.date(19, 8, 10))
        XCTAssertEqual(entries[1].at, F.date(19, 9, 30).addingTimeInterval(0.25))
        XCTAssertEqual(entries[1].goalID, F.uuid(1))
        XCTAssertEqual(entries[1].stepID, F.uuid(101))
        XCTAssertEqual(entries[1].detail, "Finish the job record")
        XCTAssertEqual(entries[1].refs, [.trace("tr-2"), .goal(F.uuid(1).uuidString)])
        XCTAssertEqual(entries[2].refs, [], "missing refs read as none")
        XCTAssertEqual(entries[3].refs, [.thread("th-3")])
    }

    func testEncodeThenDecodeIsIdentity() throws {
        let entries = try decode(Self.fixture)
        let data = try RecordJSONCodec.encoder().encode(entries)
        XCTAssertEqual(try RecordJSONCodec.decoder().decode([ActivityEntry].self, from: data), entries)

        let json = String(decoding: data, as: UTF8.self)
        for token in [#""kind":"planned_step""#, #""authorisation":"standing_grant:van-stock""#,
                      #""origin":"remote:watch""#, #""outcome":"waiting_on_you""#,
                      #""authorisation":"refused:restrictedTarget""#, #""at":"2026-10-18T20:30:00.250Z""#] {
            XCTAssertTrue(json.contains(token), token)
        }
    }

    func testEveryEnumHasAStableCode() {
        XCTAssertEqual(ActivityKind.allCases.map(\.rawValue),
                       ["action", "planned_step", "scheduled_run", "told_you", "held", "refused"])
        XCTAssertEqual(ActivityOutcome.allCases.map(\.rawValue), ["done", "failed", "uncertain", "waiting_on_you"])
        let authorisations: [ActivityAuthorisation] = [.asked, .standingGrant(scope: "s"), .readOnly, .heldForYou,
                                                       .refused(reason: "r"), .scheduled]
        for value in authorisations {
            XCTAssertEqual(ActivityAuthorisation(codeValue: value.codeValue), value, value.codeValue)
        }
        for value in [ActivityOrigin.wearer, .scheduled, .agent, .remote(source: "x")] {
            XCTAssertEqual(ActivityOrigin(codeValue: value.codeValue), value, value.codeValue)
        }
        for value in [ActivityRef.operation("a"), .trace("b"), .thread("c"), .goal("d")] {
            XCTAssertEqual(ActivityRef(codeValue: value.codeValue), value, value.codeValue)
        }
        XCTAssertEqual(ActivityAuthorisation(refusal: .featureDisabled), .refused(reason: "featureDisabled"))
    }

    func testUnknownCodesAreRefusedNotGuessed() {
        for bad in ["", "standing_grant:", "refused:", "approved"] {
            XCTAssertNil(ActivityAuthorisation(codeValue: bad), bad)
        }
        XCTAssertNil(ActivityOrigin(codeValue: "remote:"))
        XCTAssertNil(ActivityRef(codeValue: "file:abc"))
        XCTAssertNil(ActivityRef(codeValue: "goal:"))
        let bad = Self.fixture.replacingOccurrences(of: #""kind": "action""#, with: #""kind": "teleport""#)
        XCTAssertThrowsError(try decode(bad))
    }

    func testOverLongTextIsShortenedNotLost() throws {
        let entry = ActivityEntry(id: F.uuid(9), at: F.now, kind: .action,
                                  title: String(repeating: "t", count: 150), detail: String(repeating: "d", count: 250),
                                  authorisation: .asked, origin: .wearer, outcome: .done)
        XCTAssertEqual(entry.title.count, ActivityEntry.titleLength)
        XCTAssertEqual(entry.detail?.count, ActivityEntry.detailLength)
        XCTAssertTrue(entry.title.hasSuffix("…"))

        let longOnDisk = #"[{"id": "00000000-0000-0000-0000-000000000509", "at": "2026-10-18T21:20:00Z", "kind": "action", "title": "\#(String(repeating: "x", count: 120))", "authorisation": "asked", "origin": "wearer", "outcome": "done"}]"#
        XCTAssertEqual(try decode(longOnDisk).first?.title.count, ActivityEntry.titleLength)

        let blankDetail = ActivityEntry(id: F.uuid(9), at: F.now, kind: .action, title: "T", detail: "  ",
                                        authorisation: .asked, origin: .wearer, outcome: .done)
        XCTAssertNil(blankDetail.detail)
    }
}
