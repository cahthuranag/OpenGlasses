import Foundation

/// The last question's audio, kept for the recogniser comparison (Plan JM P3).
struct KeptUtterance: Equatable, Sendable {
    /// Mono float samples at `sampleRate`, as the dictation tap delivered them.
    let samples: [Float]
    let sampleRate: Double
    let capturedAt: Date

    var duration: TimeInterval { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }
}

/// When the last question's audio is kept, and for how long (Plan JM P3).
///
/// Pure, so the rule is tested without an audio session: `TranscriptionService` owns one and feeds
/// it every captured buffer of a turn **only while the developer switch is on**. Memory only —
/// nothing here is written anywhere. What was kept is replaced by the next question that heard
/// speech, and forgotten when the switch goes off (the next turn starts with it off, or
/// `clear()`), or when the app leaves the screen (`clear()`, and `allowed` is false while it is in
/// the background, so a turn that ends there keeps nothing).
struct UtteranceRetention {
    /// The longest stretch kept: the first two minutes of a question. More is dropped, not kept.
    static let maxSeconds: TimeInterval = 120

    private(set) var kept: KeptUtterance?
    /// Whether this turn's buffers are being collected.
    private(set) var isCollecting = false
    /// Increments every turn, so a buffer that arrives late from an earlier turn is never mixed in.
    private(set) var turn = 0

    private var pending: [Float] = []
    private var pendingRate: Double = 0

    /// A turn starts. Collects only when keeping is allowed; a turn that starts with it not allowed
    /// forgets what was kept.
    mutating func beginTurn(allowed: Bool) {
        turn &+= 1
        pending = []
        pendingRate = 0
        isCollecting = allowed
        if !allowed { kept = nil }
    }

    /// One buffer of the current turn. The first buffer's rate is the turn's; a buffer at another
    /// rate (a route change mid-question) is skipped rather than mixed in. Capped at `maxSeconds`.
    mutating func append(_ samples: [Float], sampleRate: Double, turn: Int) {
        guard isCollecting, turn == self.turn, sampleRate > 0, !samples.isEmpty else { return }
        if pendingRate == 0 { pendingRate = sampleRate }
        guard sampleRate == pendingRate else { return }
        let room = Int(Self.maxSeconds * sampleRate) - pending.count
        guard room > 0 else { return }
        pending.append(contentsOf: samples.prefix(room))
    }

    /// The turn ended. A turn that heard speech, while keeping is still allowed, replaces what was
    /// kept; returns the number of samples kept, or nil when nothing was replaced. Keeping no longer
    /// allowed forgets what was kept.
    @discardableResult
    mutating func endTurn(heardSpeech: Bool, allowed: Bool, at date: Date) -> Int? {
        let collected = pending
        let rate = pendingRate
        let wasCollecting = isCollecting
        pending = []
        pendingRate = 0
        isCollecting = false
        guard allowed else {
            kept = nil
            return nil
        }
        guard wasCollecting, heardSpeech, !collected.isEmpty else { return nil }
        kept = KeptUtterance(samples: collected, sampleRate: rate, capturedAt: date)
        return collected.count
    }

    /// Forget everything, including a turn in progress.
    mutating func clear() {
        kept = nil
        pending = []
        pendingRate = 0
        isCollecting = false
    }
}
