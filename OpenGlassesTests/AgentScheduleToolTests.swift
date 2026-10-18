import XCTest
@testable import OpenGlasses

@MainActor
final class AgentScheduleToolTests: XCTestCase {
    private var savedTasks: Data?

    override func setUp() {
        super.setUp()
        savedTasks = UserDefaults.standard.data(forKey: "agentScheduledTasks")
        AgentScheduler.saveTasks([])
    }

    override func tearDown() {
        UserDefaults.standard.set(savedTasks, forKey: "agentScheduledTasks")
        super.tearDown()
    }

    private func create(_ interval: Any? = nil, name: String = "Check prices") async throws -> String {
        var args: [String: Any] = ["action": "create", "task_name": name, "task_prompt": "Look up the current price"]
        args["interval_minutes"] = interval
        return try await AgentScheduleTool().execute(args: args)
    }

    func testNumericInputsAreRoundedAndReportedAsStored() async throws {
        for (input, expected) in [(15.0 as Any, 15), ("20" as Any, 20), (12 as Any, 12), (15.6 as Any, 16)] {
            let reply = try await create(input)
            XCTAssertEqual(AgentScheduler.savedTasks().last?.intervalMinutes, expected)
            XCTAssertTrue(reply.contains("every \(expected) min"))
        }
    }

    func testMissingIntervalDefaultsAndZeroSaysOnceDaily() async throws {
        let defaultReply = try await create()
        XCTAssertEqual(AgentScheduler.savedTasks().last?.intervalMinutes, 30)
        XCTAssertTrue(defaultReply.contains("every 30 min"))
        let dailyReply = try await create(0)
        XCTAssertEqual(AgentScheduler.savedTasks().last?.intervalMinutes, 0)
        XCTAssertTrue(dailyReply.contains("once daily"))
        XCTAssertFalse(dailyReply.contains("every 0 min"))
    }

    func testJSONNumbersKeepTheirRequestedCadence() async throws {
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data("[15.0, 15.6]".utf8)) as? [Any])
        for value in values {
            _ = try await create(value)
        }
        XCTAssertEqual(AgentScheduler.savedTasks().map(\.intervalMinutes), [15, 16])
    }

    func testInvalidIntervalsNeverCreateATask() async throws {
        let invalid: [Any] = ["soon", "", -1, -0.1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude, true, NSNull()]
        for input in invalid {
            let reply = try await create(input)
            XCTAssertTrue(reply.contains("non-negative number"))
            XCTAssertTrue(AgentScheduler.savedTasks().isEmpty)
        }
    }

    func testDuplicateNamesGetDistinctIDsAndPreserveTheFirstTask() async throws {
        let firstReply = try await create(15)
        let secondReply = try await create(20)
        let thirdReply = try await create(25)
        XCTAssertEqual(AgentScheduler.savedTasks().map(\.id), ["check-prices", "check-prices-2", "check-prices-3"])
        XCTAssertEqual(AgentScheduler.savedTasks().map(\.intervalMinutes), [15, 20, 25])
        XCTAssertTrue(firstReply.contains("ID: check-prices,"))
        XCTAssertTrue(secondReply.contains("ID: check-prices-2,"))
        XCTAssertTrue(thirdReply.contains("ID: check-prices-3,"))
    }

    func testEmptySlugAndReservedLegacyNameAreStillSaved() async throws {
        _ = try await create(15, name: "!!!")
        _ = try await create(15, name: "Morning briefing")
        XCTAssertEqual(AgentScheduler.savedTasks().map(\.id), ["task", "morning-briefing-2"])
    }

    func testConcurrentCreatesCannotOverwriteEachOther() async throws {
        async let first = create(15)
        async let second = create(20)
        _ = try await (first, second)
        XCTAssertEqual(Set(AgentScheduler.savedTasks().map(\.id)), ["check-prices", "check-prices-2"])
    }
}
