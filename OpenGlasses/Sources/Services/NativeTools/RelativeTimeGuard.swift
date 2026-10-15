import Foundation

/// The wearer's own words for the Direct-mode turn in flight, bound by `ConversationTurnRunner`
/// around the model call.
///
/// A task-local rather than `AppState.currentTranscription`, because that property outlives its
/// turn: it still holds the last spoken question while a live session, a scheduled agent task or
/// an MCP client calls a tool minutes later. Bound only where the turn started from something the
/// wearer said or typed, and inherited by every tool call the model makes inside that turn; nil
/// everywhere else, which keeps every guard that reads it out of the way.
enum TurnUtteranceScope {
    @TaskLocal static var current: String?
}

/// Decides whether a relative time the wearer said ("in 15 minutes") overrides the value the model
/// computed for a timer or reminder.
///
/// The authoritative input is the wearer's utterance for this turn (`TurnUtteranceScope`), read
/// only for a call the model made (`ToolInvocationOrigin.model`). A tapped control, a skill pack
/// or Siri Action binding, a live session and an agent task all pass the tool exactly what they
/// meant, so they are never second-guessed. When the sentence reads with certainty
/// (`RelativeTimeParser`) and the model's value is more than a small tolerance away from it — or
/// is not a value at all — the sentence wins. When the model gave no value, nothing is filled in:
/// the override corrects arithmetic, it does not invent a due time the model chose to leave out.
enum RelativeTimeGuard {

    /// What the model passed, as an offset from now.
    enum ModelValue: Equatable {
        /// The argument was not given.
        case absent
        /// Given, but not a number or date the tool can read.
        case unreadable
        /// Given and readable: this many seconds from now. Negative when it is in the past.
        case offset(TimeInterval)
    }

    /// How far apart the model and the sentence were. Logged in place of either value: the size
    /// of the error is the useful signal, and the times themselves describe the wearer's day.
    enum Disagreement: String, Equatable {
        case unreadable, underAMinute, minutes, hours, days
    }

    enum Decision: Equatable {
        case keepModel
        case useParsed(seconds: TimeInterval, disagreement: Disagreement)
    }

    /// A timer's seconds are a straight conversion with no clock in it: anything but the same
    /// number is the model's mistake.
    static let timerTolerance: TimeInterval = 1
    /// A reminder's due time is computed against a clock the model read from its prompt some
    /// seconds before the call, and models round to the minute. Two minutes clears both; the
    /// mistakes this exists for are an hour or a time zone out.
    static let reminderTolerance: TimeInterval = 120

    static func decide(parsed: TimeInterval?, model: ModelValue,
                       tolerance: TimeInterval) -> Decision {
        guard let parsed, parsed > 0 else { return .keepModel }
        switch model {
        case .absent:
            return .keepModel
        case .unreadable:
            return .useParsed(seconds: parsed, disagreement: .unreadable)
        case .offset(let offset):
            let difference = abs(offset - parsed)
            guard difference > tolerance else { return .keepModel }
            return .useParsed(seconds: parsed, disagreement: disagreement(of: difference))
        }
    }

    static func disagreement(of difference: TimeInterval) -> Disagreement {
        switch difference {
        case ..<60: return .underAMinute
        case ..<3600: return .minutes
        case ..<86_400: return .hours
        default: return .days
        }
    }

    /// The utterance to check this call against, or nil when there is none to trust.
    static func utteranceForCurrentCall() -> String? {
        guard ToolInvocationScope.current?.context.origin == .model else { return nil }
        guard let text = TurnUtteranceScope.current?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Records that an override happened. No utterance, no times: the tool and how far out the
    /// model was.
    static func logOverride(tool: String, _ disagreement: Disagreement) {
        PrivacyLog.toolRun(.relativeTimeOverridden, tool: tool,
                           detail: PrivacyToken(disagreement.rawValue))
    }
}

// MARK: - Timer

/// The seconds `set_timer` runs for, after the guard has had its say.
struct TimerDurationResolution: Equatable {
    /// Nil when there is no usable duration ("Missing timer duration.").
    let seconds: Int?
    /// Set when the wearer's words replaced the model's number.
    let overridden: RelativeTimeGuard.Disagreement?

    static func resolve(modelArgument: Any?, utterance: String?) -> TimerDurationResolution {
        let modelSeconds: Int?
        let model: RelativeTimeGuard.ModelValue
        if modelArgument == nil {
            modelSeconds = nil; model = .absent
        } else if let value = modelArgument as? Int {
            modelSeconds = value; model = .offset(TimeInterval(value))
        } else if let value = modelArgument as? Double, value.isFinite,
                  abs(value) < Double(Int32.max) {
            modelSeconds = Int(value); model = .offset(value)
        } else {
            modelSeconds = nil; model = .unreadable
        }
        let parsed = utterance.flatMap {
            RelativeTimeParser.duration(in: $0, anchors: .timer)
        }
        switch RelativeTimeGuard.decide(parsed: parsed, model: model,
                                        tolerance: RelativeTimeGuard.timerTolerance) {
        case .keepModel:
            return TimerDurationResolution(seconds: modelSeconds, overridden: nil)
        case .useParsed(let seconds, let disagreement):
            return TimerDurationResolution(seconds: Int(seconds.rounded()), overridden: disagreement)
        }
    }
}

// MARK: - Reminder

/// The `due_at` a reminder is created with, after the guard has had its say.
enum ReminderDueResolution: Equatable {
    /// The model's value stands; validate it as before.
    case model(String?)
    /// The wearer's words replaced it.
    case parsed(Date, RelativeTimeGuard.Disagreement)

    static func resolve(modelDueAt: String?, utterance: String?, now: Date) -> ReminderDueResolution {
        let trimmed = modelDueAt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model: RelativeTimeGuard.ModelValue
        if let trimmed, !trimmed.isEmpty {
            model = ReminderDuePolicy.parse(trimmed)
                .map { .offset($0.timeIntervalSince(now)) } ?? .unreadable
        } else {
            model = .absent
        }
        let parsed = utterance.flatMap {
            RelativeTimeParser.duration(in: $0, anchors: .reminder)
        }
        switch RelativeTimeGuard.decide(parsed: parsed, model: model,
                                        tolerance: RelativeTimeGuard.reminderTolerance) {
        case .keepModel:
            return .model(modelDueAt)
        case .useParsed(let seconds, let disagreement):
            return .parsed(now.addingTimeInterval(seconds), disagreement)
        }
    }
}
