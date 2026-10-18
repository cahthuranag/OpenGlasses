import XCTest
@testable import OpenGlasses

@MainActor
final class ScheduleDuePolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        return calendar
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func task(interval: Int = 0, lastRun: Date? = nil, enabled: Bool = true) -> AgentScheduler.ScheduledTask {
        .init(id: "test", name: "Test", prompt: "Check", intervalMinutes: interval,
              enabled: enabled, lastRun: lastRun, speakResult: false)
    }

    func testDailyTaskRunsInitiallyAndOnlyOnAnEarlierCalendarDay() {
        let now = date(27, hour: 0, minute: 5)
        XCTAssertTrue(ScheduleDuePolicy.isDue(task: task(), now: now, calendar: calendar))
        XCTAssertTrue(ScheduleDuePolicy.isDue(task: task(lastRun: date(26, hour: 23, minute: 55)), now: now, calendar: calendar))
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: task(lastRun: date(27, hour: 0)), now: now, calendar: calendar))
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: task(lastRun: date(28, hour: 0)), now: now, calendar: calendar))
    }

    func testDailyTaskUsesLocalDaysAcrossDaylightSavingTransition() {
        let lastRun = date(27, hour: 0, minute: 5)
        let nextDay = date(28, hour: 0, minute: 5)
        XCTAssertEqual(nextDay.timeIntervalSince(lastRun), 23 * 3600)
        XCTAssertTrue(ScheduleDuePolicy.isDue(task: task(lastRun: lastRun), now: nextDay, calendar: calendar))
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: task(lastRun: lastRun), now: date(27, hour: 23, minute: 55), calendar: calendar))
    }

    func testIntervalTasksKeepTheirElapsedTimeBoundary() {
        let lastRun = date(27, hour: 10)
        let scheduled = task(interval: 15, lastRun: lastRun)
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: scheduled, now: lastRun.addingTimeInterval(899), calendar: calendar))
        XCTAssertTrue(ScheduleDuePolicy.isDue(task: scheduled, now: lastRun.addingTimeInterval(900), calendar: calendar))
        XCTAssertTrue(ScheduleDuePolicy.isDue(task: task(interval: 15), now: lastRun, calendar: calendar))
    }

    func testDisabledAndInvalidIntervalsAreNeverDue() {
        let now = date(27, hour: 10)
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: task(enabled: false), now: now, calendar: calendar))
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: task(interval: -1), now: now, calendar: calendar))
        XCTAssertFalse(ScheduleDuePolicy.isDue(task: task(interval: Int.max, lastRun: now.addingTimeInterval(-10)), now: now, calendar: calendar))
    }
}
