import XCTest
@testable import OpenGlasses

/// A session rebuilt after a full window replays the turn's tool results instead of running the
/// tools again, and a brand-new conversation does not "shorten" a history it never had.
@MainActor
final class AppleToolResultCacheTests: XCTestCase {

    /// Stands in for `field_session`: each execution opens (or reports) the job.
    private final class FakeJobTool {
        private(set) var executions = 0
        func run() -> String {
            executions += 1
            return executions == 1 ? "Job opened." : "A job is already open."
        }
    }

    func testARetriedSessionReplaysTheFirstResultInsteadOfRunningTheToolAgain() async {
        let cache = AppleToolResultCache()
        let tool = FakeJobTool()

        // Attempt 1: the model calls the tool, then the window overflows.
        let first = await cache.resolve(name: "field_session", argumentsJSON: #"{"action":"start","reference":"108"}"#) {
            tool.run()
        }
        // Attempts 2 and 3: rebuilt sessions ask again, once with the keys in another order.
        let second = await cache.resolve(name: "field_session", argumentsJSON: #"{"action":"start","reference":"108"}"#) {
            tool.run()
        }
        let third = await cache.resolve(name: "field_session", argumentsJSON: #"{ "reference": "108", "action": "start" }"#) {
            tool.run()
        }

        XCTAssertEqual(tool.executions, 1, "the job is opened once, however many sessions the turn takes")
        XCTAssertEqual([first, second, third], ["Job opened.", "Job opened.", "Job opened."])
        XCTAssertEqual(cache.replays, 2)
    }

    func testDifferentArgumentsOrADifferentToolAreDifferentCalls() async {
        let cache = AppleToolResultCache()
        let tool = FakeJobTool()
        _ = await cache.resolve(name: "field_session", argumentsJSON: #"{"action":"start"}"#) { tool.run() }
        _ = await cache.resolve(name: "field_session", argumentsJSON: #"{"action":"pause"}"#) { tool.run() }
        _ = await cache.resolve(name: "reading", argumentsJSON: #"{"action":"start"}"#) { tool.run() }
        XCTAssertEqual(tool.executions, 3)
        XCTAssertEqual(cache.replays, 0)
    }

    func testTheCacheEndsWithTheTurn() async {
        let cache = AppleToolResultCache()
        let tool = FakeJobTool()
        _ = await cache.resolve(name: "field_session", argumentsJSON: "{}") { tool.run() }
        XCTAssertFalse(cache.isEmpty)
        cache.clear()
        XCTAssertTrue(cache.isEmpty)
        XCTAssertEqual(cache.replays, 0)
        let next = await cache.resolve(name: "field_session", argumentsJSON: "{}") { tool.run() }
        XCTAssertEqual(tool.executions, 2, "the next turn's call runs")
        XCTAssertEqual(next, "A job is already open.")
    }

    func testCanonicalArgumentsSortKeysAndLeaveNonJSONAlone() {
        XCTAssertEqual(AppleToolResultCache.canonicalJSON(#"{"b":1,"a":{"d":2,"c":3}}"#),
                       #"{"a":{"c":3,"d":2},"b":1}"#)
        XCTAssertEqual(AppleToolResultCache.canonicalJSON("  not json "), "not json")
        XCTAssertNotEqual(AppleToolResultCache.key(name: "a", argumentsJSON: "{}"),
                          AppleToolResultCache.key(name: "b", argumentsJSON: "{}"))
    }

    // MARK: - Carry

    func testANewConversationStartsWithNothingCarriedSoAFullWindowFailsAtOnce() {
        let start = AppleSessionPolicy.initialCarry(requested: AppleSessionPolicy.carriedEntryLimit, available: 0)
        XCTAssertEqual(start, 0)
        XCTAssertNil(AppleSessionPolicy.carryAfterOverflow(start, available: 0),
                     "no history to drop: no retry, no second run of the tools")
    }

    func testTheCarryNeverClaimsMoreThanTheHistoryHolds() {
        XCTAssertEqual(AppleSessionPolicy.initialCarry(requested: 12, available: 3), 3)
        XCTAssertEqual(AppleSessionPolicy.initialCarry(requested: 12, available: 40), 12)
        XCTAssertEqual(AppleSessionPolicy.initialCarry(requested: 0, available: 40), 0)
        // 3 entries: one retry, with none, then stop.
        XCTAssertEqual(AppleSessionPolicy.carryAfterOverflow(3, available: 3), 0)
        XCTAssertNil(AppleSessionPolicy.carryAfterOverflow(0, available: 3))
        // A long history still steps 12 → 4 → 0.
        XCTAssertEqual(AppleSessionPolicy.carryAfterOverflow(12, available: 30), 4)
        XCTAssertEqual(AppleSessionPolicy.carryAfterOverflow(4, available: 30), 0)
        // A carry asked to shrink past a short history is read at the history's size.
        XCTAssertEqual(AppleSessionPolicy.carryAfterOverflow(12, available: 2), 0)
    }
}
