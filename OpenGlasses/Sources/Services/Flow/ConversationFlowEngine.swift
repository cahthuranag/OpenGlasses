import Foundation

/// Reserves the voice entry path before async command routing or the first-launch cue can
/// suspend. A replacement also owns the gap while the cancelled model task finishes cleanup.
/// Tokens keep a superseded routing continuation from releasing or dispatching its successor.
struct SpokenTurnGate {
    private var routingID: UUID?
    private var replacementID: UUID?
    private var interruptionFragment: (text: String, at: Date)?
    private(set) var reservedAt: Date?

    var isReserved: Bool { routingID != nil || replacementID != nil }
    var isReplacing: Bool { replacementID != nil }

    mutating func beginRouting(now: Date = Date()) -> UUID? {
        guard !isReserved else { return nil }
        let id = UUID()
        routingID = id
        reservedAt = now
        return id
    }

    func ownsRouting(_ id: UUID) -> Bool { routingID == id }

    mutating func endRouting(_ id: UUID) {
        guard ownsRouting(id) else { return }
        routingID = nil
        reservedAt = nil
    }

    mutating func beginReplacement(interruption: String? = nil, now: Date = Date()) -> UUID {
        let id = UUID()
        routingID = nil
        replacementID = id
        reservedAt = now
        interruptionFragment = interruption.map { ($0.trimmingCharacters(in: .whitespacesAndNewlines), now) }
        return id
    }

    /// The stop listener and dictation can deliver the same barge-in fragment. The replacement
    /// already owns those words; consume one matching dictation callback within the handoff.
    mutating func consumeRepeatedInterruption(_ text: String, now: Date = Date()) -> Bool {
        guard let fragment = interruptionFragment else { return false }
        guard (0...2).contains(now.timeIntervalSince(fragment.at)) else {
            interruptionFragment = nil
            return false
        }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines) == fragment.text else { return false }
        interruptionFragment = nil
        return true
    }

    mutating func endReplacement(_ id: UUID) -> Bool {
        guard replacementID == id else { return false }
        replacementID = nil
        reservedAt = nil
        return true
    }

    mutating func invalidate() {
        routingID = nil
        replacementID = nil
        reservedAt = nil
        interruptionFragment = nil
    }

    /// Dictation can deliver the beginning of a correction just before the stop listener hears
    /// its ending. Join adjacent fragments once; older held speech is superseded by barge-in.
    static func replacementText(held: String?, heldAt: Date?, interruption: String,
                                now: Date = Date()) -> String {
        let next = interruption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let heldAt, (0...2).contains(now.timeIntervalSince(heldAt)),
              let held = held?.trimmingCharacters(in: .whitespacesAndNewlines), !held.isEmpty else { return next }
        if next.hasPrefix(held) { return next }
        if held.hasSuffix(next) { return held }
        return held + " " + next
    }
}

/// One pre-LLM voice-command handler in the ordered chain (Plan BG P2).
///
/// A handler inspects the transcript and, if it applies, performs its side effect (drive the
/// teleprompter, a HUD card, the launcher, filter bystander speech, …) and reports that it consumed
/// the turn. Consuming the turn stops the flow before the LLM is ever called. Handlers capture the
/// live `AppState` in their closure, so the engine needs no wide protocol seam over it.
struct VoiceCommandHandler {
    /// Short identifier for logging / tests (e.g. "teleprompter", "intent-ignore").
    let label: String
    /// Inspect `text`; return `true` if this handler consumed the turn (flow stops), else `false`.
    let handle: (_ text: String) async -> Bool
}

/// Runs the ordered pre-LLM voice-command chain: the first handler that consumes the transcript
/// wins, and no later handler runs. If none consume it, the transcript falls through to the LLM.
///
/// This is the deterministic core of the conversation flow's routing decision — pure orchestration
/// over injected handlers, so it is unit-testable with mock handlers even though the real handlers
/// drive device-only services.
struct ConversationFlowEngine {
    let handlers: [VoiceCommandHandler]

    /// Route `text` through the chain. Returns the `label` of the handler that consumed the turn,
    /// or `nil` if none did (the caller then proceeds to the LLM path).
    func route(_ text: String) async -> String? {
        for handler in handlers {
            if await handler.handle(text) {
                return handler.label
            }
        }
        return nil
    }
}
