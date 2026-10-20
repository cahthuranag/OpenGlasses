import Foundation

/// Whether a dictation turn asks the input node for Apple's voice processing (noise suppression
/// and echo cancellation) — the front end the Realtime engine already uses and dictation did not.
///
/// Pure, so the table is tested without an audio session. Shipped behind a developer switch and
/// measured on the device before it defaults on: turning voice processing on reformats the input
/// node and can add latency, and the turn ledger is where that would show.
enum DictationCapturePolicy {

    /// Who owns the engine the dictation tap sits on.
    enum EngineOwnership: Equatable, Sendable {
        /// The wake-word listener's engine, borrowed so dictation keeps working in the background.
        /// Never reformatted from here: the listener's tap and its format belong to it.
        case sharedWithWakeWord
        /// An engine dictation built for itself (foreground only), which it may configure freely.
        case dedicated
    }

    /// True only on the phone's own mic, on an engine dictation owns, with the developer switch on.
    ///
    /// - A Bluetooth route never: the glasses and a headset do their own processing on the far
    ///   side of a hands-free link that cannot carry the processed format.
    /// - The shared engine never: voice processing reformats the input node out from under the
    ///   wake-word listener's tap.
    static func voiceProcessing(route: MicRoute, engine: EngineOwnership, developerSwitch: Bool) -> Bool {
        guard developerSwitch else { return false }
        guard route == .phone else { return false }
        return engine == .dedicated
    }
}
