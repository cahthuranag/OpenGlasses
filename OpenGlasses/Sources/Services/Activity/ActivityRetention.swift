import Foundation

/// How long the trail keeps entries (Plan IW): 14 days and at most 1000 entries, the same horizon
/// as turn traces. Pure — the store calls `prune` before every write.
enum ActivityRetention {
    static let horizonDays = 14
    static let maximumEntries = 1000

    /// The horizon actually applied: the trail's own, or a shorter retention the wearer's HIPAA
    /// setting asks for. A longer setting never extends the trail.
    static func effectiveHorizonDays(hipaaRetentionDays: Int? = nil) -> Int {
        guard let hipaaRetentionDays, hipaaRetentionDays > 0 else { return horizonDays }
        return min(horizonDays, hipaaRetentionDays)
    }

    /// Entries older than the horizon are dropped, then the oldest beyond the cap. What survives
    /// is returned oldest first. An entry stamped in the future (a clock change) is kept: dropping
    /// it would hide an action.
    static func prune(_ entries: [ActivityEntry], now: Date,
                      horizonDays: Int = horizonDays) -> [ActivityEntry] {
        let cutoff = now.addingTimeInterval(-TimeInterval(horizonDays) * 24 * 60 * 60)
        let kept = entries.filter { $0.at >= cutoff }.sorted { $0.at < $1.at }
        guard kept.count > maximumEntries else { return kept }
        return Array(kept.suffix(maximumEntries))
    }
}
