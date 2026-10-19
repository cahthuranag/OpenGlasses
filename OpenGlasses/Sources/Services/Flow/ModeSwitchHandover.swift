import Foundation

/// Plan HY P0 — the conversation a mode switch carries into the next live session.
///
/// Plan CF's redial hangs up one brain and dials another, and it used to carry exactly one thing
/// across: the held frame pin. The words did not survive, so the new session opened with no idea
/// what had just been said and "and the other one?" had no referent. The machinery to fix that
/// already existed — ``LiveContextHandover`` builds a bounded block from the phone's own record of
/// a live session's turns, and both session managers open with `pendingResumeContext` — it was
/// only ever written by the offline handoff.
///
/// | Switch | Source | When |
/// |---|---|---|
/// | live → live with `.startSession` (the CF redial) | the old session's recorder | always |
/// | Direct → live (no redial: the policy never starts a session from Direct) | the Direct thread's last six turns | only if the newest is under ``directFreshness`` old |
/// | anything → Direct | none | Direct keeps its own thread (open question 1, decided no) |
///
/// Three rules the wiring in `performModeSwitch` keeps, stated here so they are read beside the
/// table rather than inferred from it:
///
/// * **Read before the teardown.** `stopSession()` resets the recorder, so the old session's turns
///   are read while it is still up.
/// * **A later switch clears a pending seed.** A Direct → live seed waits on the next start; a
///   second switch before that start drops it (``clearsPendingSeed(pending:seededBySwitch:)``), so
///   a stale block cannot ride into an unrelated session.
/// * **In memory only.** Nothing here is written anywhere; the block lives on the target manager
///   until a start consumes it, exactly as the offline handoff's does.
///
/// Pure: no store, no clock, no session. The caller hands in the turns and the time.
enum ModeSwitchHandover {

    /// One turn of the Direct thread, as the handover needs it: who, what, and when.
    struct DirectTurn: Equatable {
        let speaker: LiveTurnRecord.Speaker
        let text: String
        let at: Date
    }

    /// How old the newest Direct turn may be and still be "the conversation the wearer is having".
    ///
    /// Ten minutes: long enough for a pause to look something up, short enough that a thread from
    /// this morning is not presented to a new brain as what was just being talked about.
    static let directFreshness: TimeInterval = 10 * 60

    /// The block to set on the target manager's `pendingResumeContext`, or `nil` for none.
    ///
    /// - Parameters:
    ///   - from: the mode being left.
    ///   - to: the mode being entered.
    ///   - actions: `ModeSwitchPolicy`'s sequence for this switch. A live → live seed is only built
    ///     when it contains the redial; without one there is no session to open with it.
    ///   - oldRecorderTurns: the old live session's recorder, read before the teardown.
    ///   - directTurns: the Direct thread, oldest → newest.
    ///   - now: the moment of the switch.
    static func seed(from: AppMode, to: AppMode, actions: [ModeSwitchAction],
                     oldRecorderTurns: [LiveTurnRecord], directTurns: [DirectTurn],
                     now: Date) -> String? {
        guard to.isRealtime else { return nil }
        if from.isRealtime {
            guard actions.contains(.startSession(to)) else { return nil }
            return LiveContextHandover.build(turns: oldRecorderTurns, cause: .modeSwitch)
        }
        // Direct → live.
        let spoken = directTurns.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let newest = spoken.last, now.timeIntervalSince(newest.at) < directFreshness else {
            return nil
        }
        let records = spoken.map { LiveTurnRecord(speaker: $0.speaker, text: $0.text) }
        return LiveContextHandover.build(turns: records, cause: .modeSwitch)
    }

    /// Whether a new switch should drop the block that is pending on a manager.
    ///
    /// Only the block an earlier *switch* left there, and only while it is still unconsumed — the
    /// offline handoff writes the same slot just before it asks for the live mode back, and that
    /// block is meant for exactly the switch it precedes.
    static func clearsPendingSeed(pending: String?, seededBySwitch: String?) -> Bool {
        guard let pending, let seededBySwitch else { return false }
        return pending == seededBySwitch
    }

    /// The Direct thread's messages as handover turns: the wearer's and the assistant's, nothing
    /// the app wrote to itself.
    static func directTurns(from messages: [ConversationMessage]) -> [DirectTurn] {
        messages.compactMap { message in
            switch message.role {
            case "user": return DirectTurn(speaker: .wearer, text: message.content, at: message.timestamp)
            case "assistant": return DirectTurn(speaker: .assistant, text: message.content, at: message.timestamp)
            default: return nil
            }
        }
    }
}
