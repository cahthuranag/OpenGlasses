import XCTest
@testable import OpenGlasses

/// Plan IW P1 — the `activity` tool: "what have you done today / this morning / since …" and
/// "what's next", read from the trail, the goals and the scheduled tasks. Reads only.
@MainActor
final class ActivityToolTests: XCTestCase {
    private typealias F = GoalActivityFixture

    private var directory: URL!
    private var trail: ActivityStore!
    private var goals: GoalStore!
    private var tasks: [AgentScheduler.ScheduledTask] = []
    private var agentMode = true

    override func setUp() {
        super.setUp()
        directory = F.workspace("ActivityToolTests")
        trail = ActivityStore(directory: directory, clock: { F.now }, hipaaMode: { false },
                              hipaaRetentionDays: { nil })
        goals = GoalStore(directory: directory, clock: { F.now }, hipaaRetentionDays: { nil })
        tasks = []
        agentMode = true
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func tool() -> ActivityTool {
        let trail = trail!
        let goals = goals!
        let tool = ActivityTool(activity: { trail }, goals: { goals })
        tool.scheduledTasks = { [unowned self] in self.tasks }
        tool.agentModeEnabled = { [unowned self] in self.agentMode }
        tool.clock = { F.now }
        tool.timeZone = { F.auckland }
        return tool
    }

    private func seedMorning() {
        trail.append(F.entry(1, at: F.date(19, 8), title: "Added the dentist to your calendar", tool: "calendar"))
        trail.append(F.entry(2, at: F.date(19, 9), title: "Saved a note for you", tool: "save_note"))
        trail.append(F.entry(3, at: F.date(18, 15), title: "Set a reminder for you", tool: "reminder"))
    }

    func testTodayCountsAndReadsTodaysEntriesOnly() async throws {
        seedMorning()
        let said = try await tool().execute(args: ["action": "today"])
        XCTAssertEqual(said, "Today I did two things. Added the dentist to your calendar. Saved a note for you. "
                       + "Nothing is waiting on you.")
    }

    func testSinceATimeToday() async throws {
        seedMorning()
        let said = try await tool().execute(args: ["action": "since", "time": "08:30"])
        XCTAssertEqual(said, "Since 8:30 AM, I did one thing. Saved a note for you. Nothing is waiting on you.")
        let missing = try await tool().execute(args: ["action": "since"])
        XCTAssertEqual(missing, "Since when? Give me a time, like 09:30.")
    }

    func testAnHourNotYetReachedMeansYesterday() {
        let start = ActivityTool.start("14:00", now: F.now, calendar: F.calendar())
        XCTAssertEqual(start, F.date(18, 14))
        XCTAssertEqual(ActivityTool.start("2026-10-19T07:00:00+13:00", now: F.now, calendar: F.calendar()),
                       F.date(19, 7))
        XCTAssertNil(ActivityTool.start("teatime", now: F.now, calendar: F.calendar()))
    }

    func testAnEmptyDay() async throws {
        let said = try await tool().execute(args: ["action": "today"])
        XCTAssertEqual(said, "I haven't done anything today, and nothing is waiting on you.")
    }

    func testNextMergesGoalStepsScheduledTasksAndWaitingItems() async throws {
        goals.add(F.goal([F.step(1, "Book the skip", dueAt: F.date(20, 12))]))
        tasks = [AgentScheduler.ScheduledTask(id: "t", name: "Upcoming Events", prompt: "p", intervalMinutes: 60,
                                              enabled: true, lastRun: F.date(19, 9, 30), speakResult: true)]
        trail.append(F.entry(4, at: F.date(19, 9), title: "Your OK to use the send message tool",
                             kind: .held, outcome: .waitingOnYou, authorisation: .heldForYou))
        let said = try await tool().execute(args: ["action": "next"])
        XCTAssertTrue(said.hasPrefix("Here's what's next."), said)
        XCTAssertTrue(said.contains("I'll run Upcoming Events"), said)
        XCTAssertTrue(said.contains("Clear the garage: book the skip, due tomorrow."), said)
        XCTAssertTrue(said.hasSuffix("One thing is waiting on you: your OK to use the send message tool."), said)
    }

    func testScheduledTasksAreNotPromisedWithAgentModeOff() async throws {
        agentMode = false
        tasks = [AgentScheduler.ScheduledTask(id: "t", name: "Upcoming Events", prompt: "p", intervalMinutes: 60,
                                              enabled: true, speakResult: true)]
        let said = try await tool().execute(args: ["action": "next"])
        XCTAssertEqual(said, "Nothing's coming up, and nothing is waiting on you.")
    }

    func testTheToolIsARegisteredLocalRead() {
        let registry = NativeToolRegistry(locationService: LocationService())
        let tool = registry.tool(named: "activity")
        XCTAssertTrue(tool is ActivityTool)
        XCTAssertEqual(tool?.executionSemantics.effect, .readOnly)
        XCTAssertEqual(OfflineToolPolicy.availability(of: "activity"), .local)
        XCTAssertTrue(LLMService.localSafeTools.contains("activity"))
    }

    func testNextDueFollowsTheSchedulersOwnRule() {
        let calendar = F.calendar()
        var task = AgentScheduler.ScheduledTask(id: "t", name: "n", prompt: "p", intervalMinutes: 30,
                                                enabled: true, lastRun: F.date(19, 9, 50), speakResult: true)
        XCTAssertEqual(ScheduleDuePolicy.nextDue(task: task, now: F.now, calendar: calendar), F.date(19, 10, 20))
        task.lastRun = F.date(19, 9)
        XCTAssertEqual(ScheduleDuePolicy.nextDue(task: task, now: F.now, calendar: calendar), F.now, "already due")
        task.intervalMinutes = 0
        XCTAssertEqual(ScheduleDuePolicy.nextDue(task: task, now: F.now, calendar: calendar), F.date(20, 0))
        task.enabled = false
        XCTAssertNil(ScheduleDuePolicy.nextDue(task: task, now: F.now, calendar: calendar))
    }
}
