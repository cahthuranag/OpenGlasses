import Foundation

/// The support report's one line about goals and the trail (Plan IW P2): counts only — never a
/// goal's title, a step, or an entry's words. "Goals: 2 active; activity entries (14 d): 37".
enum GoalActivityReportLine {
    static func line(goals: [Goal], entries: [ActivityEntry], now: Date) -> String {
        let active = goals.filter { $0.state == .active }.count
        let cutoff = now.addingTimeInterval(-TimeInterval(ActivityRetention.horizonDays) * 86_400)
        let recent = entries.filter { $0.at >= cutoff }.count
        return "Goals: \(active) active; activity entries (\(ActivityRetention.horizonDays) d): \(recent)"
    }
}
