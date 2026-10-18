import XCTest
@testable import OpenGlasses

/// Plan IW P2 — goal check-ins: one typed scheduler task per goal that wants one, `beforeDue`
/// firing once, at most two goal sentences a day, nothing at all with Agent Mode off, and a
/// finished goal losing its task. Invented ids and titles only.
@MainActor
final class GoalCheckInTests: XCTestCase {

    private typealias Fx = GoalActivityFixture
    private let calendar = GoalActivityFixture.calendar()

    private func goal(_ n: Int, checkIn: CheckInCadence, state: GoalState = .active,
                      dueAt: Date? = nil, title: String = "Clear the garage") -> Goal {
        Goal(id: Fx.uuid(n), title: title, createdAt: Fx.date(18, 9), dueAt: dueAt, state: state,
             checkIn: checkIn,
             steps: [Fx.step(1, "Book the skip", state: .done), Fx.step(2, "Sort the shelves"),
                     Fx.step(3, "List the bike for sale")],
             source: .wearer)
    }

    private var promptTask: AgentScheduler.ScheduledTask {
        AgentScheduler.ScheduledTask(id: "calendar-check", name: "Upcoming Events", prompt: "Check.",
                                     intervalMinutes: 15, enabled: true, speakResult: true)
    }

    // MARK: - Cadence → task

    func testACadenceMakesOneTypedTaskAndLeavesPromptTasksAlone() {
        let goals = [goal(1, checkIn: .daily), goal(2, checkIn: .none, title: "Paint the fence")]
        let tasks = GoalCheckInSchedule.reconciled([promptTask], goals: goals, now: Fx.now)

        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0], promptTask, "a prompt task is untouched and keeps its place")
        let checkIn = tasks[1]
        XCTAssertEqual(checkIn.kind, .goalCheckIn(goalID: Fx.uuid(1)))
        XCTAssertEqual(checkIn.goalCheckInID, Fx.uuid(1))
        XCTAssertTrue(checkIn.enabled)
        XCTAssertEqual(checkIn.prompt, "", "a check-in is typed, never a prompt for the model")
        XCTAssertEqual(checkIn.name, GoalCheckInSchedule.taskName,
                       "the goal's title is not copied into the scheduled-task list")
        XCTAssertEqual(checkIn.lastRun, Fx.now, "a daily check-in counts from when it was set")

        XCTAssertEqual(GoalCheckInSchedule.reconciled(tasks, goals: goals, now: Fx.date(20, 9)), tasks,
                       "reconciling again changes nothing")
    }

    func testABeforeDueCheckInStartsWithNoRunAndAPausedGoalsTaskIsOff() {
        let due = Fx.date(25, 18)
        let tasks = GoalCheckInSchedule.reconciled(
            [], goals: [goal(1, checkIn: .beforeDue(days: 3), dueAt: due),
                        goal(2, checkIn: .weekly, state: .paused)], now: Fx.now)
        XCTAssertEqual(tasks.map(\.goalCheckInID), [Fx.uuid(1), Fx.uuid(2)])
        XCTAssertNil(tasks[0].lastRun, "a before-due check-in has its own window")
        XCTAssertTrue(tasks[0].enabled)
        XCTAssertFalse(tasks[1].enabled, "a paused goal is not checked in on, and keeps its task")
    }

    func testFinishingSettingAsideOrDeletingAGoalRemovesItsTask() {
        let start = GoalCheckInSchedule.reconciled([promptTask], goals: [goal(1, checkIn: .daily)], now: Fx.now)
        XCTAssertEqual(start.count, 2)
        for finished in [goal(1, checkIn: .daily, state: .done), goal(1, checkIn: .daily, state: .abandoned),
                         goal(1, checkIn: .none)] {
            XCTAssertEqual(GoalCheckInSchedule.reconciled(start, goals: [finished], now: Fx.now), [promptTask],
                           "\(finished.state) / \(finished.checkIn.codeValue) keeps a check-in task")
        }
        XCTAssertEqual(GoalCheckInSchedule.reconciled(start, goals: [], now: Fx.now), [promptTask],
                       "a deleted goal keeps a check-in task")
    }

    func testAnExistingTaskKeepsItsRunHistoryThroughAPause() {
        var tasks = GoalCheckInSchedule.reconciled([], goals: [goal(1, checkIn: .daily)], now: Fx.now)
        tasks[0].lastRun = Fx.date(19, 12)
        tasks[0].lastSpokenAt = Fx.date(19, 12)
        let paused = GoalCheckInSchedule.reconciled(tasks, goals: [goal(1, checkIn: .daily, state: .paused)],
                                                    now: Fx.date(19, 13))
        let resumed = GoalCheckInSchedule.reconciled(paused, goals: [goal(1, checkIn: .daily)],
                                                     now: Fx.date(20, 9))
        XCTAssertEqual(resumed[0].lastRun, Fx.date(19, 12))
        XCTAssertEqual(resumed[0].lastSpokenAt, Fx.date(19, 12))
        XCTAssertTrue(resumed[0].enabled)
    }

    func testTheScreensSaveKeepsTheStoredCheckIns() {
        let stored = GoalCheckInSchedule.reconciled([promptTask], goals: [goal(1, checkIn: .daily)], now: Fx.now)
        var stale = [promptTask]   // opened before the goal had a cadence
        stale[0].enabled = false
        let saved = GoalCheckInSchedule.mergingEdits(stale, into: stored)
        XCTAssertEqual(saved.count, 2)
        XCTAssertFalse(saved[0].enabled, "the screen's own edit is kept")
        XCTAssertEqual(saved[1].goalCheckInID, Fx.uuid(1), "the stored check-in is not lost")
    }

    // MARK: - beforeDue(3) fires once

    func testBeforeDueThreeFiresOnceInItsWindow() {
        let due = Fx.date(25, 18)
        let goals = [goal(1, checkIn: .beforeDue(days: 3), dueAt: due)]
        var tasks = GoalCheckInSchedule.reconciled([], goals: goals, now: Fx.date(19, 9))

        func run(_ at: Date) -> [GoalCheckInOutput] {
            let result = GoalCheckInPolicy.run(tasks: tasks, goals: goals, agentModeEnabled: true,
                                               wearerPresent: true, now: at, calendar: calendar)
            tasks = result.tasks
            return result.outputs
        }

        XCTAssertTrue(run(Fx.date(21, 20)).isEmpty, "before the window opens (the 22nd)")
        let first = run(Fx.date(22, 9))
        XCTAssertEqual(first.map(\.goalID), [Fx.uuid(1)], "the window opens three days before")
        XCTAssertNotNil(first.first?.spokenLine)
        XCTAssertTrue(run(Fx.date(22, 15)).isEmpty, "not twice the same day")
        XCTAssertTrue(run(Fx.date(24, 9)).isEmpty, "and not again before it is due")
        XCTAssertTrue(run(Fx.date(26, 9)).isEmpty, "nor after")
    }

    // MARK: - At most two goal sentences a day

    func testOnlyTwoCheckInsAreSaidADayAndEveryOneIsFiled() {
        let goals = [goal(1, checkIn: .daily, title: "Clear the garage"),
                     goal(2, checkIn: .daily, title: "Paint the fence"),
                     goal(3, checkIn: .daily, title: "Plan the trip")]
        var tasks = GoalCheckInSchedule.reconciled([], goals: goals, now: Fx.date(18, 9))

        let result = GoalCheckInPolicy.run(tasks: tasks, goals: goals, agentModeEnabled: true,
                                           wearerPresent: true, now: Fx.date(19, 9), calendar: calendar)
        XCTAssertEqual(result.outputs.count, 3, "every due check-in reaches the digest")
        XCTAssertEqual(result.outputs.compactMap(\.spokenLine).count, 2, "but only two are said")
        XCTAssertNil(result.outputs[2].spokenLine)
        XCTAssertEqual(Set(result.outputs.map(\.digestID)).count, 3, "one digest item per goal")
        tasks = result.tasks
        XCTAssertEqual(tasks.compactMap(\.lastSpokenAt).count, 2)
        XCTAssertTrue(tasks.allSatisfy { $0.lastRun == Fx.date(19, 9) })

        // A fourth goal falls due later the same day: the day's two are used up.
        let fourth = goal(4, checkIn: .beforeDue(days: 2), dueAt: Fx.date(20, 18), title: "Return the drill")
        tasks = GoalCheckInSchedule.reconciled(tasks, goals: goals + [fourth], now: Fx.date(19, 14))
        let later = GoalCheckInPolicy.run(tasks: tasks, goals: goals + [fourth], agentModeEnabled: true,
                                          wearerPresent: true, now: Fx.date(19, 15), calendar: calendar)
        XCTAssertEqual(later.outputs.map(\.goalID), [Fx.uuid(4)])
        XCTAssertNil(later.outputs[0].spokenLine, "the cap is a day's, across goals")

        // The next morning the allowance is back.
        let nextDay = GoalCheckInPolicy.run(tasks: later.tasks, goals: goals, agentModeEnabled: true,
                                            wearerPresent: true, now: Fx.date(20, 9), calendar: calendar)
        XCTAssertEqual(nextDay.outputs.compactMap(\.spokenLine).count, 2)
    }

    func testAWearerWhoIsNotThereGetsTheDigestOnly() {
        let goals = [goal(1, checkIn: .daily)]
        let tasks = GoalCheckInSchedule.reconciled([], goals: goals, now: Fx.date(18, 9))
        let result = GoalCheckInPolicy.run(tasks: tasks, goals: goals, agentModeEnabled: true,
                                           wearerPresent: false, now: Fx.date(19, 9), calendar: calendar)
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertNil(result.outputs[0].spokenLine)
        XCTAssertNil(result.tasks[0].lastSpokenAt, "nothing said, nothing counted")
        XCTAssertEqual(result.tasks[0].lastRun, Fx.date(19, 9))
    }

    // MARK: - Agent Mode

    func testAgentModeOffPausesCheckInsAndLeavesGoalsAlone() {
        let goals = [goal(1, checkIn: .daily)]
        let tasks = GoalCheckInSchedule.reconciled([], goals: goals, now: Fx.date(18, 9))
        let result = GoalCheckInPolicy.run(tasks: tasks, goals: goals, agentModeEnabled: false,
                                           wearerPresent: true, now: Fx.date(19, 9), calendar: calendar)
        XCTAssertTrue(result.outputs.isEmpty)
        XCTAssertEqual(result.tasks, tasks, "a paused check-in does not use up its run")
        XCTAssertTrue(GoalCheckInPolicy.due(tasks: tasks, goals: goals, agentModeEnabled: false,
                                            now: Fx.date(19, 9), calendar: calendar).isEmpty)
    }

    func testTheSchedulerRunsCheckInsOnlyWithAgentModeAndFilesThem() {
        let key = "agentScheduledTasks"
        let saved = UserDefaults.standard.data(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let goals = [goal(1, checkIn: .beforeDue(days: 2), dueAt: Date().addingTimeInterval(36 * 3600))]
        AgentScheduler.saveTasks([promptTask])
        let scheduler = AgentScheduler()
        let recorder = FakeActivityRecorder()
        var filed: [GoalCheckInOutput] = []
        scheduler.goals = { goals }
        scheduler.activityRecorder = recorder
        scheduler.fileGoalCheckIn = { filed.append($0) }

        scheduler.agentModeEnabled = { false }
        scheduler.runGoalCheckIns(now: Date(), wearerPresent: false)
        XCTAssertTrue(filed.isEmpty, "Agent Mode off: no check-in runs")
        XCTAssertTrue(recorder.entries.isEmpty)

        scheduler.agentModeEnabled = { true }
        scheduler.runGoalCheckIns(now: Date(), wearerPresent: false)
        XCTAssertEqual(filed.map(\.goalID), [Fx.uuid(1)])
        XCTAssertEqual(recorder.entries.map(\.title), ["Checked in on a goal"])
        XCTAssertEqual(recorder.entries.first?.goalID, Fx.uuid(1))
        XCTAssertEqual(recorder.entries.first?.refs, [.goal(Fx.uuid(1).uuidString.lowercased())])
        XCTAssertNotNil(AgentScheduler.savedTasks().first { $0.goalCheckInID == Fx.uuid(1) }?.lastRun)

        scheduler.runGoalCheckIns(now: Date(), wearerPresent: false)
        XCTAssertEqual(filed.count, 1, "before-due fires once")

        scheduler.goals = { nil }
        AgentScheduler.reconcileGoalCheckIns(goals: [])
        XCTAssertEqual(AgentScheduler.savedTasks().map(\.id), [promptTask.id],
                       "with the goal gone, so is its task")
    }

    // MARK: - The prompt path never sees a check-in

    func testACheckInIsNeverDueAsAPromptTask() {
        var task = GoalCheckInSchedule.reconciled([], goals: [goal(1, checkIn: .daily)], now: Fx.now)[0]
        task.lastRun = nil
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: task, now: Fx.now, calendar: calendar))
        XCTAssertNil(ScheduleDuePolicy.nextDue(task: task, now: Fx.now, calendar: calendar))
        XCTAssertTrue(ScheduleDuePolicy.isDue(task: promptTask, now: Fx.now, calendar: calendar))
    }

    func testTheKindIsStoredAsAStringAndAnUnknownKindKeepsTheList() throws {
        let tasks = GoalCheckInSchedule.reconciled([promptTask], goals: [goal(1, checkIn: .daily)], now: Fx.now)
        let data = try JSONEncoder().encode(tasks)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"goal_check_in:00000000-0000-0000-0000-000000000001\""), json)
        XCTAssertEqual(try JSONDecoder().decode([AgentScheduler.ScheduledTask].self, from: data), tasks)

        let newer = json.replacingOccurrences(of: "goal_check_in:00000000-0000-0000-0000-000000000001",
                                              with: "weather_watch:7")
        let decoded = try JSONDecoder().decode([AgentScheduler.ScheduledTask].self, from: Data(newer.utf8))
        XCTAssertEqual(decoded.count, 2, "a kind from a newer build does not lose the list")
        XCTAssertEqual(decoded[1].kind, .unrecognised("weather_watch:7"))
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: decoded[1], now: Fx.now, calendar: calendar))

        let old = #"[{"id":"x","name":"X","prompt":"P","intervalMinutes":5,"enabled":true,"speakResult":false}]"#
        let legacy = try JSONDecoder().decode([AgentScheduler.ScheduledTask].self, from: Data(old.utf8))
        XCTAssertNil(legacy[0].kind, "a task saved before kinds existed is a prompt task")
    }

    // MARK: - What is said

    func testTheCheckInSentence() {
        let phraser = GoalPhraser(now: Fx.now, calendar: calendar)
        XCTAssertEqual(phraser.checkIn(for: goal(1, checkIn: .daily)),
                       "A check-in on Clear the garage: one of three done, and next is sort the shelves.")
        let dated = Goal(id: Fx.uuid(2), title: "Paint the fence", createdAt: Fx.date(18, 9), checkIn: .daily,
                         steps: [Fx.step(1, "Buy the paint", dueAt: Fx.date(20, 23, 59)), Fx.step(2, "Paint it")],
                         source: .wearer)
        XCTAssertEqual(phraser.checkIn(for: dated),
                       "A check-in on Paint the fence: none of two done yet, and next is buy the paint, due tomorrow.")
    }
}
