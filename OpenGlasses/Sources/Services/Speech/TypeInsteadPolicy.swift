import Foundation

/// When the Voice tab offers a "Type instead" chip (Plan JM P1).
///
/// The dock's Type button already runs the full agent turn; the chip only puts it in reach at the
/// moment speech is failing. A wearer who is heard first time never sees it.
///
/// A small ledger, pure, so "two misses in a row" and "one good turn clears it" are tested rather
/// than hoped:
///
/// - two consecutive failures — a turn the wearer opened that ended on the no-speech timeout, or a
///   transcript with no word in it — show the chip;
/// - one reply in which the assistant said it did not understand shows it at once;
/// - one good spoken turn, or one typed turn, clears it and resets the count.
///
/// Direct mode only. The Realtime modes and Gemini Live hide the chat bar and do not dictate, so
/// nothing is counted there and the chip never shows.
struct TypeInsteadPolicy: Equatable, Sendable {

    enum Event: Equatable, Sendable {
        /// A turn the wearer opened (wake word or tap) ended on the no-speech timeout. A follow-up
        /// window that heard nothing is the ordinary end of a conversation and is not reported.
        case noSpeech
        /// The recogniser delivered something with no word in it.
        case shortTranscript
        /// The recogniser delivered words.
        case recognised
        /// The wearer sent a typed turn.
        case typedTurn
        /// The assistant's reply was that it did not understand.
        case notUnderstood
    }

    /// How many failures in a row show the chip.
    static let failuresToShow = 2

    private(set) var consecutiveFailures = 0
    private(set) var isShowing = false

    init() {}

    /// Feed one event; returns whether the chip should now show.
    @discardableResult
    mutating func note(_ event: Event, mode: AppMode) -> Bool {
        guard mode == .direct else {
            clear()
            return false
        }
        switch event {
        case .noSpeech, .shortTranscript:
            consecutiveFailures += 1
            if consecutiveFailures >= Self.failuresToShow { isShowing = true }
        case .notUnderstood:
            isShowing = true
        case .recognised, .typedTurn:
            clear()
        }
        return isShowing
    }

    /// Hide the chip and forget the count.
    mutating func clear() {
        consecutiveFailures = 0
        isShowing = false
    }

    /// Whether a transcript has no word in it: nothing left once whitespace, punctuation and
    /// symbols are taken away. A single letter or digit is a word ("a", "I", "5").
    static func isShorterThanAWord(_ text: String) -> Bool {
        !text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    /// The event a finished transcript reports.
    static func event(forTranscript text: String) -> Event {
        isShorterThanAWord(text) ? .shortTranscript : .recognised
    }
}
