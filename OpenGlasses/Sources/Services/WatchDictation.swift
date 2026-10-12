import AVFoundation

/// A question dictated on the watch: spoken into the wrist, turned into text by the system's own
/// dictation there, and sent to the phone as that text.
///
/// The watch has no speech recogniser an app can run, so this is the one way the wrist's own
/// microphone reaches the assistant. What arrives is a typed turn in every respect — the same
/// path the composer and the "Ask Avenkin a Question" shortcut take — with one decision of its
/// own: whether the phone says the answer aloud.
enum WatchDictation {
    /// The watch protocol's name for it, and the key its text travels under.
    static let command = "askText"
    static let textKey = "text"

    /// A dictated question is a sentence or two. Anything longer is cut rather than refused.
    static let maxCharacters = 2_000

    /// The question a message carries, trimmed and bounded; nil when there is nothing to ask.
    static func question(from message: [String: Any]) -> String? {
        guard let raw = message[textKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxCharacters))
    }

    /// Whether the phone speaks the answer: only into something the wearer has on.
    ///
    /// Someone dictating to their wrist may have the phone in a pocket, a bag or another room. With
    /// glasses, earbuds or a car carrying the audio, the answer belongs in their ear. With nothing
    /// but the phone's own speaker or earpiece, reading it aloud would announce it to whoever is
    /// near the phone — so the watch shows it instead.
    static func speaksAnswer(outputs: [AVAudioSession.Port]) -> Bool {
        !outputs.isEmpty && !outputs.allSatisfy { $0 == .builtInSpeaker || $0 == .builtInReceiver }
    }

    static func speaksAnswerNow() -> Bool {
        speaksAnswer(outputs: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType))
    }
}
