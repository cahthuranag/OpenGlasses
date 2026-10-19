import Foundation

/// Plan HY P2 — a rolling-window cap on how many cloud calls a loop may make.
///
/// Live Coach clamps its interval to 1–10 s and its duration to two hours, which allowed up to
/// 7,200 vision calls in one session. This is the ceiling on that: at most ``limit`` calls in any
/// ``window`` (by default 240 an hour, about one every 15 s on average). A call is counted for one
/// window from the moment it was admitted, then rolls off and frees its slot.
///
/// Pure value type with time passed in — no `Date()` inside — so the window is testable to the
/// second.
///
/// **Not for safety loops.** Navigation's hazard loop and first aid never take one: a budget that
/// silenced a hazard callout to save a cloud call would be the wrong trade every time. A test
/// scans those files to keep it that way.
struct CallBudget: Equatable {

    /// Calls allowed per window.
    let limit: Int
    /// The rolling window, in seconds.
    let window: TimeInterval
    /// When each call still inside the window was admitted, oldest first.
    private(set) var admitted: [Date] = []

    /// Live Coach's proposed default; the cost tracker can show whether it bites.
    static let defaultLimit = 240
    static let defaultWindow: TimeInterval = 3600

    init(limit: Int = CallBudget.defaultLimit, window: TimeInterval = CallBudget.defaultWindow) {
        self.limit = max(0, limit)
        self.window = max(0, window)
    }

    /// Spend one call if the window has room. Returns whether it was admitted.
    mutating func admit(now: Date) -> Bool {
        rollOff(now: now)
        guard admitted.count < limit else { return false }
        admitted.append(now)
        return true
    }

    /// How many calls the window still has room for at `now`.
    func remaining(now: Date) -> Int {
        max(0, limit - admitted.filter { isInsideWindow($0, now: now) }.count)
    }

    /// When the next call will be admitted: `now` while there is room, otherwise the moment the
    /// oldest counted call rolls off.
    func nextAvailable(now: Date) -> Date {
        guard remaining(now: now) == 0 else { return now }
        let oldest = admitted.first { isInsideWindow($0, now: now) } ?? now
        return oldest.addingTimeInterval(window)
    }

    /// A call admitted at `stamp` is counted while less than one window has passed; at exactly one
    /// window it has rolled off.
    private func isInsideWindow(_ stamp: Date, now: Date) -> Bool {
        now.timeIntervalSince(stamp) < window
    }

    private mutating func rollOff(now: Date) {
        // `isInsideWindow`'s rule, spelled inline: calling a method on `self` from inside a
        // mutation of `self.admitted` is an exclusivity violation.
        let window = window
        admitted.removeAll { now.timeIntervalSince($0) >= window }
    }
}
