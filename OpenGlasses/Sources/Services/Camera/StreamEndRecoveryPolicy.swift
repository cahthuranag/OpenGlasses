import Foundation

/// Plan HJ P0 — what to do when a wanted glasses stream ends and does not come back by itself
/// (pure).
///
/// # The gaps this closes
///
/// The reconnect ladder (`StreamReconnectPolicy`) answered a drop from one place, with one input.
/// Three ways a stream ends never reached it, or reached it with too little to go on:
///
/// * **A stall recovery that fails.** The stall detector's rebuild threw, the stream was marked
///   not streaming, and nothing else happened: the `.stopped` the dying stream sent was ours, the
///   detector disarms on a stream that is not streaming, and the ladder was never asked. A camera
///   that was wanted stayed gone until the wearer stopped and started it by hand.
/// * **A session that ended for a reason.** The ladder read only the last *stream* error. A
///   device session that ended because the glasses were too hot or flat was retried for the full
///   minute and a half.
/// * **A session that keeps ending.** A successful reconnect zeroed every counter, so a stream
///   that came up, ran for a few seconds and died again looped for as long as the wearer let it.
///
/// And none of it knew whether the phone was in a pocket. A give-up there cleared the intent
/// where nobody could see the notice, and the wearer unlocked to a camera that had silently
/// stopped and needed a manual Start.
///
/// # The shape
///
/// One table, rows in order, the same discipline as `StreamReconnectPolicy` (which stays as the
/// foreground cadence and the `mayAct` gate). The SDK's errors are classified into a `Cause` at
/// the edge, so nothing here imports it. `StreamEndHistory` answers how many times the stream has
/// ended recently, and survives a successful reconnect on purpose.
enum StreamEndRecoveryPolicy {

    /// What ended the stream, classified at the edge.
    enum Cause: Equatable {
        /// The stream stopped and nothing said why.
        case streamStopped
        /// The last `StreamError`, classified by `CameraErrorPolicy`.
        case streamError(CameraErrorPolicy.RetryDisposition)
        /// The last `DeviceSessionError`, classified by `CameraErrorPolicy`.
        case sessionError(CameraErrorPolicy.RetryDisposition)
        /// The glasses refused the session for a compatibility reason (an update to the glasses'
        /// app, or to this build). Its own case because no unlock fixes it — see row 3a.
        case compatibilityRefusal(notice: String)
        /// The stall detector's own rebuild threw. Reported by the owner as it lets go.
        case stallRecoveryFailed
    }

    /// How the stream came to be asked about, before the errors are read.
    enum Trigger: Equatable {
        /// The stream reported `.stopped` while it was wanted, or a rung of the ladder failed.
        case streamStopped
        /// The stall detector's rebuild threw.
        case stallRecoveryFailed
    }

    /// What the device session last said, classified at the edge.
    enum SessionFailure: Equatable {
        case classified(CameraErrorPolicy.RetryDisposition)
        case compatibilityRefusal(notice: String)
    }

    /// Where the app is. The wearer can see a notice only in the foreground.
    enum Presence: String, Equatable {
        case foreground, background, locked
    }

    enum Decision: Equatable {
        /// Climb this rung after `after` seconds.
        case retry(after: TimeInterval, attempt: Int)
        /// A start or rebuild we own is in flight; look again without spending a rung.
        case deferToOwner(after: TimeInterval)
        /// Nobody wants the stream.
        case standDown
        /// Stop climbing, clear the intent, and say why. The wearer can see it.
        case giveUp(notice: String)
        /// Stop climbing but keep the intent; climb once more from rung 0 when the app is back in
        /// front, and show `notice` then — not into a pocket.
        case parkUntilForeground(notice: String)
    }

    // MARK: - Numbers (placeholders P2 replaces)

    /// Ends within `flapWindow` at which the ladder stops climbing.
    static let flapLimit = 3

    /// How far back an end still counts towards `flapLimit`.
    static let flapWindow: TimeInterval = 120

    /// The background/locked ladder: slower and shorter than the foreground one. The radio is
    /// shared with the voice link, nobody can see the preview, and every cold start costs the
    /// glasses battery. 3 s twice, then 10 s five times: about 56 s.
    static func backgroundReconnectDelay(attempt: Int) -> TimeInterval? {
        switch attempt {
        case ..<0: return nil
        case 0..<2: return 3
        case 2..<7: return 10
        default: return nil
        }
    }

    /// The cadence for `presence`. The foreground one is today's ladder, untouched.
    static func reconnectDelay(attempt: Int, presence: Presence) -> TimeInterval? {
        switch presence {
        case .foreground: return StreamRecoveryPolicy.reconnectDelay(attempt: attempt)
        case .background, .locked: return backgroundReconnectDelay(attempt: attempt)
        }
    }

    /// Total wall-clock a ladder may spend for `presence`, derived from the cadence.
    static func reconnectBudget(presence: Presence) -> TimeInterval {
        var total: TimeInterval = 0
        var attempt = 0
        while let delay = reconnectDelay(attempt: attempt, presence: presence) {
            total += delay
            attempt += 1
        }
        return total
    }

    // MARK: - Copy

    /// The ladder stopped because the stream kept ending, in the foreground.
    static var flapNotice: String {
        String(localized: "The glasses camera keeps dropping out, so it has stopped trying. Start the camera again when you're ready.")
    }

    /// Shown when the app comes back to the front after a park that happened while locked.
    static var parkedWhileLockedNotice: String {
        String(localized: "The glasses camera stopped while your phone was locked. It will try again when you open Avenkin.")
    }

    /// The same, for a park that happened while the app was in the background but the phone was
    /// not locked.
    static var parkedInBackgroundNotice: String {
        String(localized: "The glasses camera stopped while Avenkin was in the background. It will try again when you open Avenkin.")
    }

    /// What a park says on the way back to the front. A reason the wearer can act on (glasses too
    /// hot, folded) follows the opening sentence; a flap or a spent budget has none to add, and
    /// the foreground give-up copy for those ("start the camera again") would be untrue here,
    /// because the camera is about to try again by itself.
    static func parkedNotice(presence: Presence, reason: String? = nil) -> String {
        let opening = presence == .locked ? parkedWhileLockedNotice : parkedInBackgroundNotice
        guard let reason else { return opening }
        return opening + " " + reason
    }

    // MARK: - The cause

    /// Build the cause from what the backend saw. A session that cannot be retried outranks
    /// anything the stream said, and a stream that cannot be retried outranks the trigger; after
    /// that the trigger decides, because a failed stall recovery must reach the ladder whatever
    /// transient error the dying stream threw on the way out.
    static func cause(trigger: Trigger,
                      streamFailure: CameraErrorPolicy.RetryDisposition?,
                      sessionFailure: SessionFailure?) -> Cause {
        if case .compatibilityRefusal(let notice)? = sessionFailure {
            return .compatibilityRefusal(notice: notice)
        }
        if case .classified(let disposition)? = sessionFailure, case .stopRetrying = disposition {
            return .sessionError(disposition)
        }
        if let streamFailure, case .stopRetrying = streamFailure {
            return .streamError(streamFailure)
        }
        if trigger == .stallRecoveryFailed { return .stallRecoveryFailed }
        if case .classified(let disposition)? = sessionFailure { return .sessionError(disposition) }
        if let streamFailure { return .streamError(streamFailure) }
        return .streamStopped
    }

    // MARK: - The table

    /// - Parameters:
    ///   - transitionIsOurs: a warm-up, a stall recovery or a capture owns the stream.
    ///   - attempt: which rung is next (0-based).
    ///   - recentEnds: `StreamEndHistory.count(within: flapWindow)`, this end included.
    static func decide(cause: Cause, presence: Presence, streamingIntended: Bool,
                       transitionIsOurs: Bool, attempt: Int, recentEnds: Int) -> Decision {
        // 1. Intent first: a stream nobody wants gets no retry and no notice, whatever went wrong.
        guard streamingIntended else { return .standDown }

        // 2. Ownership defers every cause but one. A failed stall recovery is reported *by* the
        //    owner as it lets go, so deferring it to the owner is the dead end this plan closes.
        //    The caller clears its flag before asking; this row says so too, so a reorder cannot
        //    bring the dead end back.
        if transitionIsOurs && cause != .stallRecoveryFailed {
            return .deferToOwner(after: StreamReconnectPolicy.deferToOwnerDelay)
        }

        // 3a. A compatibility refusal gives up wherever the phone is: no unlock updates anything.
        if case .compatibilityRefusal(let notice) = cause { return .giveUp(notice: notice) }

        // 3. A device condition or a fold. In the foreground, say so and stop; out of it, glasses
        //    that were hot or flat may well be fine by the time the phone is unlocked.
        switch cause {
        case .streamError(.stopRetrying(let notice)), .sessionError(.stopRetrying(let notice)):
            return presence == .foreground
                ? .giveUp(notice: notice)
                : .parkUntilForeground(notice: parkedNotice(presence: presence, reason: notice))
        default:
            break
        }

        // 4. The stream keeps ending. A successful reconnect does not reset this count.
        if recentEnds >= flapLimit {
            return presence == .foreground
                ? .giveUp(notice: flapNotice)
                : .parkUntilForeground(notice: parkedNotice(presence: presence))
        }

        // 5–6. The cadence. In front it is today's ladder, asked of the gate that has always run
        //      it; rows 1–3 above have already answered everything else that gate asks.
        if presence == .foreground {
            switch StreamReconnectPolicy.next(attempt: attempt, streamingIntended: true,
                                              transitionIsOurs: false, lastFailure: nil) {
            case .retry(let delay, let attempt): return .retry(after: delay, attempt: attempt)
            case .giveUp(let notice): return .giveUp(notice: notice)
            // Unreachable with the intent set and no owner; spelled out so the table stays whole.
            case .standDown: return .standDown
            case .deferToOwner(let delay): return .deferToOwner(after: delay)
            }
        }
        guard let delay = backgroundReconnectDelay(attempt: attempt) else {
            return .parkUntilForeground(notice: parkedNotice(presence: presence))
        }
        return .retry(after: delay, attempt: attempt)
    }

    // MARK: - Back in front

    enum ForegroundAction: Equatable {
        /// Climb the ladder again from rung 0, with a fresh history.
        case resumeLadder
        /// Nothing parked, or nobody wants the stream any more.
        case nothing
        /// The SDK is holding or moving the stream itself. A start here would be a competing
        /// one (`StreamPausePolicy`, `LiveRecoveryCameraPolicy`): lift the park and let the
        /// state listener's rows act on what the SDK does next.
        case awaitSDKResume
    }

    /// What the app coming back to the front does for a parked camera. `cameraPhase` is the
    /// stream's own state, or nil when there is no stream.
    static func onForeground(parked: Bool, streamingIntended: Bool,
                             cameraPhase: CameraStreamStatePolicy.StreamState?) -> ForegroundAction {
        guard parked, streamingIntended else { return .nothing }
        switch cameraPhase {
        case nil, .stopped?, .stopping?:
            return .resumeLadder
        case .paused?, .starting?, .waitingForDevice?, .streaming?:
            return .awaitSDKResume
        }
    }

    // MARK: - The stall detector's handoff

    /// How the shared rebuild under a stall recovery ended.
    enum RebuildOutcome: Equatable {
        /// A fresh picture arrived from the rebuilt stream.
        case recovered
        /// The rebuilt stream reached `.streaming` and sent nothing. The stream is still claimed,
        /// so the stall detector sees it again and `StallRecoveryBackoff` paces it.
        case noFrame
        /// The rebuild threw. The stream is no longer claimed and the detector is disarmed.
        case failed
    }

    /// Whether the stall detector hands a stream end to the ladder. Only a rebuild that threw
    /// leaves nothing armed; nil is a recovery that never rebuilt (backed off, gave up, or the
    /// stream came back by itself).
    static func handsOffToLadder(after outcome: RebuildOutcome?, streamingIntended: Bool) -> Bool {
        outcome == .failed && streamingIntended
    }

    // MARK: - Presence from the app's signals

    /// The presence the scene phase and the lock state describe. `.inactive` is a transition
    /// (the lock screen sliding, the app switcher) and leaves the presence where it was, except
    /// that a phone whose protected data is back is no longer locked.
    static func presence(scenePhase: PrivacyFilterAvailability.Phase,
                         protectedDataAvailable: Bool,
                         previous: Presence) -> Presence {
        guard protectedDataAvailable else { return .locked }
        switch scenePhase {
        case .active: return .foreground
        case .background: return .background
        case .inactive: return previous == .locked ? .background : previous
        }
    }
}

/// Plan HJ P0 — how many times a wanted stream has ended recently (pure, injected clock).
///
/// Lives with the backend for one streaming session. A successful reconnect does **not** clear it:
/// that was the loop (a stream that comes back and dies again a few seconds later looked new every
/// time). A wearer's Stop or Start does, and ends older than `retention` age out.
struct StreamEndHistory {

    /// Seconds on a clock that keeps running while the phone sleeps, so a window measured across
    /// a locked stretch is not shortened by it.
    typealias Clock = () -> TimeInterval

    private let clock: Clock
    private let retention: TimeInterval
    private(set) var ends: [TimeInterval] = []
    private(set) var lastRecoveryAt: TimeInterval?

    init(retention: TimeInterval = StreamEndRecoveryPolicy.flapWindow,
         clock: @escaping Clock = StreamEndHistory.continuousSeconds) {
        self.retention = retention
        self.clock = clock
    }

    /// A wanted stream ended.
    mutating func recordEnd() {
        let now = clock()
        ends.removeAll { now - $0 > retention }
        ends.append(now)
    }

    /// The stream came back. Kept for the log (how long it ran before the next end), and
    /// deliberately not a reset.
    mutating func recordRecovery() {
        lastRecoveryAt = clock()
    }

    /// Ends within the last `window` seconds.
    func count(within window: TimeInterval) -> Int {
        let now = clock()
        return ends.filter { now - $0 <= window }.count
    }

    /// Seconds since the stream last came back, or nil when it has not in this history.
    var secondsSinceRecovery: TimeInterval? {
        lastRecoveryAt.map { clock() - $0 }
    }

    /// The wearer started or stopped the camera, or a parked ladder is resuming.
    mutating func reset() {
        ends.removeAll()
        lastRecoveryAt = nil
    }

    private static let origin = ContinuousClock.now

    /// `ContinuousClock` keeps counting while the system sleeps, unlike `systemUptime`.
    static func continuousSeconds() -> TimeInterval {
        let elapsed = ContinuousClock.now - origin
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}
