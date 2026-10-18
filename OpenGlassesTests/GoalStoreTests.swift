import XCTest
@testable import OpenGlasses

/// Plan IW P1 — the goal store: a round trip through the file, the 50-goal cap, finished goals
/// kept 90 days, an unreadable file never overwritten, and delete all.
@MainActor
final class GoalStoreTests: XCTestCase {
    private typealias F = GoalActivityFixture

    private var directory: URL!
    private var now = F.now

    override func setUp() {
        super.setUp()
        directory = F.workspace("GoalStoreTests")
        now = F.now
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func store(hipaaDays: Int? = nil) -> GoalStore {
        GoalStore(directory: directory, clock: { [unowned self] in self.now },
                  hipaaRetentionDays: { hipaaDays })
    }

    private func goal(_ n: Int, state: GoalState = .active, finishedAt: Date? = nil) -> Goal {
        Goal(id: F.uuid(n), title: "Goal \(n)", why: "Because", createdAt: F.date(1, 9),
             dueAt: F.date(30, 17), state: state, checkIn: .beforeDue(days: 2),
             steps: [F.step(1, "Book the skip", action: .search(query: "skip hire")),
                     F.step(2, "Sort the shelves", state: .done)],
             source: .wearer, finishedAt: finishedAt)
    }

    func testAGoalRoundTripsThroughTheFile() {
        XCTAssertEqual(store().add(goal(1)), .added)
        let reopened = store()
        XCTAssertEqual(reopened.goals, [goal(1)])
    }

    func testTheCapRefusesAFiftyFirstOpenGoal() {
        let goals = store()
        for n in 1...GoalStore.capacity { XCTAssertEqual(goals.add(goal(n)), .added) }
        XCTAssertEqual(goals.add(goal(99)), .full)
        XCTAssertEqual(goals.goals.count, GoalStore.capacity)
        XCTAssertNil(goals.goal(id: F.uuid(99)))
    }

    func testAtTheCapTheGoalThatFinishedLongestAgoMakesRoom() {
        let goals = store()
        for n in 1...(GoalStore.capacity - 2) { goals.add(goal(n)) }
        goals.add(goal(200, state: .done, finishedAt: F.date(10, 9)))
        goals.add(goal(201, state: .abandoned, finishedAt: F.date(5, 9)))
        XCTAssertEqual(goals.add(goal(99)), .added)
        XCTAssertNil(goals.goal(id: F.uuid(201)), "the oldest finished goal went")
        XCTAssertNotNil(goals.goal(id: F.uuid(200)))
    }

    func testFinishedGoalsAreKeptNinetyDaysThenGo() {
        let goals = store()
        goals.add(goal(1, state: .done, finishedAt: F.date(19, 9).addingTimeInterval(-89 * 86_400)))
        goals.add(goal(2, state: .abandoned, finishedAt: F.date(19, 9).addingTimeInterval(-91 * 86_400)))
        goals.add(goal(3, state: .paused))
        let reopened = store()
        XCTAssertEqual(reopened.goals.map(\.id), [F.uuid(1), F.uuid(3)],
                       "an open goal never expires; a finished one goes after ninety days")
    }

    func testAShorterHIPAARetentionAppliesToFinishedGoals() {
        store().add(goal(1, state: .done, finishedAt: F.date(9, 9)))
        XCTAssertTrue(store(hipaaDays: 7).goals.isEmpty)
    }

    func testFinishingStampsAndResumingClearsTheFinishTime() {
        let goals = store()
        goals.add(goal(1))
        now = F.date(20, 8)
        XCTAssertEqual(goals.update(F.uuid(1)) { $0.state = .done }?.finishedAt, F.date(20, 8))
        XCTAssertNil(goals.update(F.uuid(1)) { $0.state = .active }?.finishedAt)
    }

    func testAnUnreadableFileIsNeverOverwritten() throws {
        let url = directory.appendingPathComponent("goals.json")
        try Data("{ broken".utf8).write(to: url)
        let goals = store()
        XCTAssertTrue(goals.isUnreadable)
        XCTAssertEqual(goals.add(goal(1)), .unavailable)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ broken")
    }

    func testOneBadGoalCostsThatGoalOnly() throws {
        store().add(goal(1))
        let url = directory.appendingPathComponent("goals.json")
        var text = try String(contentsOf: url, encoding: .utf8)
        let long = String(repeating: "x", count: GoalLimits.titleLength + 1)
        text = text.replacingOccurrences(of: "\"goals\":[", with: "\"goals\":[{\"id\":\"\(F.uuid(9))\",\"title\":\"\(long)\"},")
        try text.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(store().goals.map(\.id), [F.uuid(1)])
    }

    func testDeleteAllLeavesNothing() {
        let goals = store()
        goals.add(goal(1))
        goals.deleteAll()
        XCTAssertTrue(goals.goals.isEmpty)
        XCTAssertTrue(store().goals.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("goals.json").path))
    }

    func testForgetRemovesGoalsThatNameTheSubjectAnywhere() {
        let goals = store()
        goals.add(Goal(id: F.uuid(1), title: "Plan Aroha's party", createdAt: F.now, source: .wearer))
        goals.add(Goal(id: F.uuid(2), title: "Clear the garage", createdAt: F.now,
                       steps: [F.step(1, "Ask Aroha for the trailer")], source: .wearer))
        goals.add(Goal(id: F.uuid(3), title: "Renew the passport", createdAt: F.now, source: .wearer))
        XCTAssertEqual(goals.forget(matching: "aroha"), 2)
        XCTAssertEqual(store().goals.map(\.id), [F.uuid(3)])
    }
}
