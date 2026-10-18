import XCTest
@testable import OpenGlasses

/// Plan IW P0 — a plan step can be written down without its arguments.
final class PlannedStepRecordTests: XCTestCase {

    func testTheRecordKeepsToolActionAndRationaleButNoArguments() throws {
        let step = AgentStep(tool: "calendar",
                             args: ["action": " Create ", "title": "Dentist", "notes": "the wearer's words"],
                             rationale: "Put the appointment in the calendar")
        let record = step.record
        XCTAssertEqual(record, PlannedStepRecord(tool: "calendar", actionKey: "create",
                                                 rationale: "Put the appointment in the calendar"))

        let json = String(decoding: try RecordJSONCodec.encoder().encode(record), as: UTF8.self)
        XCTAssertEqual(json, #"{"actionKey":"create","rationale":"Put the appointment in the calendar","tool":"calendar"}"#)
        XCTAssertFalse(json.contains("Dentist"))
        XCTAssertFalse(json.contains("words"))
    }

    func testAStepWithNoActionRecordsNone() {
        XCTAssertNil(AgentStep(tool: "web_search", args: ["query": "skip hire"]).record.actionKey)
        XCTAssertNil(AgentStep(tool: "web_search", args: ["action": 3]).record.actionKey)
        XCTAssertNil(AgentStep(tool: "web_search", args: ["action": "  "]).record.actionKey)
    }

    func testRoundTripAndFixture() throws {
        let fixture = #"{"tool":"reminder","actionKey":"create","rationale":"Remind you about the paint"}"#
        let decoded = try RecordJSONCodec.decoder().decode(PlannedStepRecord.self, from: Data(fixture.utf8))
        XCTAssertEqual(decoded, PlannedStepRecord(tool: "reminder", actionKey: "create",
                                                  rationale: "Remind you about the paint"))
        let again = try RecordJSONCodec.decoder().decode(
            PlannedStepRecord.self, from: try RecordJSONCodec.encoder().encode(decoded))
        XCTAssertEqual(again, decoded)

        let noAction = #"{"tool":"web_search","rationale":"Look it up"}"#
        XCTAssertNil(try RecordJSONCodec.decoder().decode(PlannedStepRecord.self, from: Data(noAction.utf8)).actionKey)
    }

    func testALongRationaleIsShortened() {
        let record = PlannedStepRecord(tool: "t", actionKey: nil, rationale: String(repeating: "r", count: 300))
        XCTAssertEqual(record.rationale.count, PlannedStepRecord.rationaleLength)
        XCTAssertTrue(record.rationale.hasSuffix("…"))
    }
}
