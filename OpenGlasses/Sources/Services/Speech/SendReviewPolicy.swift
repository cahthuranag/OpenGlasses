import Foundation

/// Whether a finished transcript waits in the chat bar for a moment before it goes (Plan JM P1,
/// "Check what I said before sending").
///
/// The review is a short pause, not a gate: untouched, the transcript sends itself when the
/// countdown completes, exactly as the spoken turn it is. Touching it holds the countdown, and what
/// the wearer then sends is a typed turn, marked as an edited transcript in a job's record.
///
/// It only happens where somebody can read it: the option is on, the app is in the foreground with
/// the screen on, the mode is Direct and the turn belongs to the phone. A locked phone, CarPlay,
/// the Watch, a glasses-only turn and the Realtime modes send as they always have.
enum SendReviewPolicy {

    /// Where the turn is being watched from.
    enum Surface: Equatable, Sendable {
        case phone
        case carPlay
        case watch
        case glassesOnly
    }

    static func shouldReview(enabled: Bool, mode: AppMode, foreground: Bool, screenOn: Bool,
                             surface: Surface) -> Bool {
        enabled && mode == .direct && foreground && screenOn && surface == .phone
    }

    /// What happens to a review in progress when the app leaves the screen.
    enum BackgroundResolution: Equatable, Sendable {
        /// Still counting: there is nothing left to read it on, so it goes now as spoken.
        case sendAsSpoken
        /// The wearer had taken it over: their draft stays in the bar for when they come back,
        /// and the listener is handed back meanwhile.
        case keepDraft
    }

    static func resolutionOnBackground(edited: Bool) -> BackgroundResolution {
        edited ? .keepDraft : .sendAsSpoken
    }

    /// The auto-send countdown. Pure: the state is a function of the time elapsed and whether the
    /// wearer has touched the text.
    struct Countdown: Equatable, Sendable {
        static let defaultSeconds: TimeInterval = 3
        static let minimumSeconds: TimeInterval = 2
        static let maximumSeconds: TimeInterval = 10

        enum State: Equatable, Sendable {
            case counting(remaining: TimeInterval)
            case send
            /// Edited: the countdown stops and the wearer sends by hand.
            case held
        }

        let seconds: TimeInterval

        init(seconds: TimeInterval) {
            self.seconds = Self.clamp(seconds)
        }

        /// Bounded to 2…10 s; anything unusable (NaN, infinite) falls back to the default.
        static func clamp(_ seconds: TimeInterval) -> TimeInterval {
            guard seconds.isFinite else { return defaultSeconds }
            return min(max(seconds, minimumSeconds), maximumSeconds)
        }

        func state(at elapsed: TimeInterval, edited: Bool) -> State {
            if edited { return .held }
            let remaining = seconds - max(elapsed, 0)
            return remaining > 0 ? .counting(remaining: remaining) : .send
        }

        /// How far round the ring is, 0…1.
        func progress(at elapsed: TimeInterval) -> Double {
            min(max(elapsed / seconds, 0), 1)
        }
    }
}

/// A transcript waiting in the chat bar for its countdown (Plan JM P1).
struct PendingTranscript: Equatable, Identifiable, Sendable {
    let id: UUID
    /// What the recogniser heard — sent unchanged when the countdown completes.
    let text: String
    let startedAt: Date
    let countdown: SendReviewPolicy.Countdown
    /// The wearer touched the text; the countdown has stopped.
    var isHeld = false
    /// The listener was already handed back (the app went to the background holding a draft), so
    /// a later cancel or send does not hand it back twice.
    var listenerHandedBack = false

    init(text: String, startedAt: Date = Date(), seconds: TimeInterval, id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.startedAt = startedAt
        self.countdown = SendReviewPolicy.Countdown(seconds: seconds)
    }

    func state(at now: Date) -> SendReviewPolicy.Countdown.State {
        countdown.state(at: now.timeIntervalSince(startedAt), edited: isHeld)
    }
}
