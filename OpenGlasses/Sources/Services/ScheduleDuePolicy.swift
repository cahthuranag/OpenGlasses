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
}
