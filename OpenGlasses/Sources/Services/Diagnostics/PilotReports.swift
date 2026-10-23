import Foundation

enum PilotReportRecipients {
    /// Refuse the whole list rather than silently sending to only some of the intended people.
    static func validated(_ raw: [String]) -> [String]? {
        let values = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (1...3).contains(values.count), values.allSatisfy(SupportReportRecipient.isPlausible) else { return nil }
        var seen: Set<String> = []
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}

/// Calendar arithmetic matters: a working day can be 23 or 25 hours long.
enum PilotReportPromptPolicy {
    static let horizonDays = 7
    static func daysToOffer(now: Date, activityDays: [Date], sentDays: Set<String>,
                            lastPromptDay: String?, enabled: Bool, jobOpen: Bool,
                            live: Bool, carPlay: Bool, calendar: Calendar) -> [Date] {
        guard enabled, !jobOpen, !live, !carPlay,
              lastPromptDay != dayKey(now, calendar: calendar) else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let oldest = calendar.date(byAdding: .day, value: -horizonDays, to: today) else { return [] }
        return Set(activityDays.map { calendar.startOfDay(for: $0) })
            .filter { $0 >= oldest && $0 < today && !sentDays.contains(dayKey($0, calendar: calendar)) }
            .sorted(by: >)
    }
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(c.era ?? 1)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// Only recipient addresses and calendar dates live here; no report or transcript is copied.
/// A profile may seed these settings, but can never lock them on.
@MainActor
struct PilotReportStore {
    static let shared = PilotReportStore(defaults: .standard)
    let defaults: UserDefaults
    static let enabledKey = "pilotReportsEnabled"
    static let recipientsKey = "pilotReportRecipients"
    static let sentDaysKey = "pilotReportSentDays"
    static let lastPromptKey = "pilotReportLastPromptDay"
    static let keys = [enabledKey, recipientsKey, sentDaysKey, lastPromptKey]
    var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var recipients: [String]? { PilotReportRecipients.validated(defaults.stringArray(forKey: Self.recipientsKey) ?? []) }
    var sentDays: Set<String> { Set(defaults.stringArray(forKey: Self.sentDaysKey) ?? []) }
    var lastPromptDay: String? { defaults.string(forKey: Self.lastPromptKey) }
    func prompted(at now: Date, calendar: Calendar) {
        defaults.set(PilotReportPromptPolicy.dayKey(now, calendar: calendar), forKey: Self.lastPromptKey)
    }
    func sent(day: Date, now: Date = Date(), calendar: Calendar = .current) {
        // Bound metadata too: older days are never automatically offered again.
        let oldest = calendar.date(byAdding: .day, value: -PilotReportPromptPolicy.horizonDays,
                                   to: calendar.startOfDay(for: now)) ?? now
        let relevant = Set((0...PilotReportPromptPolicy.horizonDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: oldest).map {
                PilotReportPromptPolicy.dayKey($0, calendar: calendar)
            }
        })
        var sent = sentDays.intersection(relevant)
        sent.insert(PilotReportPromptPolicy.dayKey(day, calendar: calendar))
        defaults.set(sent.intersection(relevant).sorted(), forKey: Self.sentDaysKey)
    }
    func clear() { for key in Self.keys { defaults.removeObject(forKey: key) } }
}
