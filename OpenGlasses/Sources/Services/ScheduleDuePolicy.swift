import Foundation

enum ScheduleDuePolicy {
    static func isDue(task: AgentScheduler.ScheduledTask, now: Date, calendar: Calendar) -> Bool {
        guard task.enabled, task.intervalMinutes >= 0 else { return false }
        guard let lastRun = task.lastRun else { return true }
        if task.intervalMinutes == 0 {
            return calendar.startOfDay(for: lastRun) < calendar.startOfDay(for: now)
        }
        return now.timeIntervalSince(lastRun) >= TimeInterval(task.intervalMinutes) * 60
    }

    /// When the task next falls due, by the same rule as `isDue`: now when it is already due, else
    /// its interval after the last run (the start of the next day for a once-daily task). Nil for a
    /// task that is switched off. Plan IW P1 — "what's next" names the tasks due within a day; the
    /// scheduler's own check cycle may run a due task a few minutes after this.
    static func nextDue(task: AgentScheduler.ScheduledTask, now: Date, calendar: Calendar) -> Date? {
        guard task.enabled, task.intervalMinutes >= 0 else { return nil }
        if isDue(task: task, now: now, calendar: calendar) { return now }
        guard let lastRun = task.lastRun else { return now }
        if task.intervalMinutes == 0 {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastRun))
        }
        return lastRun.addingTimeInterval(TimeInterval(task.intervalMinutes) * 60)
    }
}
