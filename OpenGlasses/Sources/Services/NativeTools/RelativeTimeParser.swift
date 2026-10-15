import Foundation

/// Reads a relative duration — "in 15 minutes", "in an hour and a half", "a ten minute timer" —
/// out of what the wearer said, so the timer and reminder tools can check the number the model
/// worked out against the one in the sentence.
///
/// Small and on-device models get now-plus-N arithmetic wrong often enough to matter: a reminder
/// lands an hour late because the model added in the wrong time zone, or a timer runs fifteen
/// seconds because the model forgot to multiply. The sentence itself is unambiguous, so this reads
/// it deterministically and the tools let it win when the two disagree (`RelativeTimeGuard`).
///
/// Pure and conservative. A wrong override is worse than none, so anything short of a certain
/// reading returns nil and the tool keeps today's behaviour:
///
/// - **English only.** The app's other utterance parsers (`ParkingUtteranceParser`,
///   `ConversationClassifier`) are English-only with no locale table, and this follows them. A
///   sentence in another language matches none of the vocabulary and comes back nil.
/// - **Vague amounts are nil**: "in a bit", "in a few minutes", "in a couple of minutes", "in a
///   minute or two", "in a second". "In a minute" reads as sixty seconds; "in a second" does not
///   read as one second, because nobody sets a one-second timer.
/// - **A number without a unit is nil** ("in 15"), and so is a unit this does not handle: days,
///   weeks and months cross daylight-saving changes, where "in two days" means the same clock time
///   rather than 48 hours, and that calendar arithmetic is the model's to do.
/// - **Two different durations are nil** ("set a timer for 10 minutes and remind me in an hour"):
///   which one belongs to this call is a reading of intent, not of numbers.
/// - **Absolute times are out of scope**, and a sentence that names one beside a relative phrase
///   ("tomorrow", "at 3pm", "on Friday") is nil rather than half-read.
/// - **A phrase anchored somewhere other than now is nil**: "in 15 minutes before the meeting",
///   "for an hour after lunch".
///
/// No clock: this returns a duration. The caller adds it to a `now` it was handed.
enum RelativeTimeParser {

    /// Which phrasings count as "from now". "From now" itself ("15 minutes from now") always counts.
    struct Anchors: OptionSet, Sendable {
        let rawValue: Int
        /// "in 15 minutes", "in about an hour".
        static let inPhrase = Anchors(rawValue: 1 << 0)
        /// "for 15 minutes" — a timer's own phrasing ("set a timer for 15 minutes").
        static let forPhrase = Anchors(rawValue: 1 << 1)
        /// "a 15 minute timer".
        static let timerNoun = Anchors(rawValue: 1 << 2)

        /// A reminder is due *in* a duration; "remind me for an hour" is not a reminder.
        static let reminder: Anchors = [.inPhrase]
        /// A timer runs *for* a duration, goes off *in* one, or is a "10 minute timer".
        static let timer: Anchors = [.inPhrase, .forPhrase, .timerNoun]
    }

    /// The one relative duration `utterance` states, in seconds, or nil when there is none or it
    /// cannot be read with certainty.
    static func duration(in utterance: String, anchors: Anchors) -> TimeInterval? {
        let words = tokens(utterance)
        guard !words.isEmpty else { return nil }

        var found: [TimeInterval] = []
        var i = 0
        while i < words.count {
            let anchored = isAnchored(words, at: i, anchors: anchors)
            switch parseDuration(words, at: i) {
            case .none:
                i += 1
            case .uncertain:
                // An anchored phrase that does not read cleanly ("in 15", "in a few minutes", "in
                // 2 days") is a relative time this cannot pin down. Reading some *other* phrase in
                // the same sentence instead would be guessing which one the wearer meant.
                if anchored { return nil }
                i += 1
            case .parsed(let seconds, let end):
                let tail = following(words, end)
                if tail == .disqualified {
                    if anchored { return nil }
                    i += 1
                    continue
                }
                let timerNoun = anchors.contains(.timerNoun) && end < words.count
                    && ["timer", "timers"].contains(words[end])
                if anchored || tail == .fromNow || timerNoun {
                    found.append(seconds)
                    i = end
                } else {
                    i += 1
                }
            }
        }

        guard let first = found.first,
              found.allSatisfy({ abs($0 - first) < 0.5 }),
              !namesAnAbsoluteTime(utterance, words) else { return nil }
        return first
    }

    // MARK: - Tokens

    /// Lowercased words with sentence punctuation dropped, hyphenated numbers split ("twenty-five",
    /// "15-minute") and possessives of a unit folded ("an hour's time", "15 minutes' time").
    static func tokens(_ utterance: String) -> [String] {
        let spaced = utterance.lowercased()
            .replacingOccurrences(of: #"(?<=\d)-(?=[a-z])"#, with: " ", options: .regularExpression)
        return ParkingUtteranceParser.tokenize(spaced).map(\.lower)
    }

    // MARK: - Durations

    private enum Unit: Int, Comparable {
        case second = 1, minute = 60, hour = 3600

        var seconds: Double { Double(rawValue) }

        static func < (lhs: Unit, rhs: Unit) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static func unit(_ word: String) -> Unit? {
        var word = word
        if word.hasSuffix("'s") { word.removeLast(2) }
        if word.hasSuffix("'") { word.removeLast() }
        switch word {
        case "second", "seconds", "sec", "secs": return .second
        case "minute", "minutes", "min", "mins": return .minute
        case "hour", "hours", "hr", "hrs": return .hour
        default: return nil
        }
    }

    /// Words that, after "a"/"an", make an amount vague rather than absent: "in a few minutes",
    /// "in a bit". A plain noun ("in a meeting") is not a duration at all and is skipped instead.
    private static let vagueAmounts: Set<String> = [
        "few", "couple", "bit", "while", "moment", "little", "jiffy", "tick", "sec", "second", "mo",
    ]

    private enum Attempt: Equatable {
        /// Nothing here starts a duration.
        case none
        /// Something here starts one but does not read cleanly.
        case uncertain
        /// A duration, and the index just past it.
        case parsed(seconds: TimeInterval, end: Int)
    }

    private enum Component: Equatable {
        case none
        case uncertain
        case parsed(seconds: TimeInterval, unit: Unit, end: Int)
    }

    /// One or more components, largest unit first, optionally joined by "and": "2 hours and 30
    /// minutes", "an hour 15 minutes".
    private static func parseDuration(_ words: [String], at start: Int) -> Attempt {
        var total = 0.0
        var lastUnit: Unit?
        var index = start
        while true {
            var next = index
            if lastUnit != nil, next < words.count, words[next] == "and" { next += 1 }
            switch component(words, at: next) {
            case .none:
                if lastUnit == nil { return .none }
                // "in 2 hours and then …" — the duration ended before the "and".
                return total > 0 ? .parsed(seconds: total, end: index) : .uncertain
            case .uncertain:
                return .uncertain
            case .parsed(let seconds, let unit, let end):
                // "2 minutes and 3 hours" is not how a duration is said; don't add it up.
                if let lastUnit, unit >= lastUnit { return .uncertain }
                total += seconds
                lastUnit = unit
                index = end
            }
        }
    }

    private static func component(_ words: [String], at k: Int) -> Component {
        guard k < words.count else { return .none }
        let n = words.count

        // "half an hour", "half a minute", "half hour"
        if words[k] == "half" {
            var m = k + 1
            if m < n, ["a", "an"].contains(words[m]) { m += 1 }
            guard m < n, let u = unit(words[m]), u != .second else { return .uncertain }
            return .parsed(seconds: 0.5 * u.seconds, unit: u, end: m + 1)
        }

        // "a quarter of an hour", "quarter of an hour", "a quarter hour", "three quarters of an hour"
        var m = k
        var quarters = 0
        if words[m] == "a", m + 1 < n, words[m + 1] == "quarter" {
            quarters = 1; m += 2
        } else if words[m] == "quarter" {
            quarters = 1; m += 1
        } else if ["three", "3"].contains(words[m]), m + 1 < n, words[m + 1] == "quarters" {
            quarters = 3; m += 2
        }
        if quarters > 0 {
            if m < n, words[m] == "of" { m += 1 }
            if m < n, ["a", "an"].contains(words[m]) { m += 1 }
            guard m < n, unit(words[m]) == .hour else { return .uncertain }
            return .parsed(seconds: Double(quarters) * 900, unit: .hour, end: m + 1)
        }

        guard let (amount, length, isArticle) = quantity(words, at: k) else { return .none }
        m = k + length
        var value = amount

        if isArticle {
            guard m < n else { return .none }
            if vagueAmounts.contains(words[m]) { return .uncertain }
            // "in a meeting", "in an email": not an amount of time.
            guard unit(words[m]) != nil || unsupportedUnits.contains(words[m]) else { return .none }
        }

        // "one and a half hours", "2 and a half minutes"
        var halved = false
        if !isArticle, m + 2 < n, words[m] == "and", words[m + 1] == "a", words[m + 2] == "half" {
            value += 0.5; m += 3; halved = true
        }

        guard m < n, let u = unit(words[m]) else { return .uncertain }
        // "in a second" is a figure of speech, not a one-second duration.
        if isArticle && u == .second { return .uncertain }
        m += 1

        // "an hour and a half", "two hours and a half"
        if !halved, value == value.rounded(), m + 2 < n,
           words[m] == "and", words[m + 1] == "a", words[m + 2] == "half" {
            value += 0.5; m += 3
        }
        // A range after the unit ("in a minute or two") is caught by `following`.
        return .parsed(seconds: value * u.seconds, unit: u, end: m)
    }

    /// Units this does not convert. Seen after an amount they make the phrase uncertain rather
    /// than absent, so "in 2 days" can never be skipped past to a smaller phrase elsewhere.
    private static let unsupportedUnits: Set<String> = [
        "day", "days", "week", "weeks", "fortnight", "fortnights", "month", "months", "year",
        "years", "night", "nights",
    ]

    /// Largest amount accepted as a number; above it the reading is not trusted.
    private static let maximumQuantity = 10_000.0

    /// An amount at `index`: digits ("15", "1.5"), a spelled number ("twenty five", "a hundred"),
    /// or the article "a"/"an" meaning one. Returns the value, the words used and whether it was
    /// the article.
    private static func quantity(_ words: [String], at index: Int) -> (Double, Int, Bool)? {
        let word = words[index]
        if word.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
           let value = Double(word) {
            return value <= maximumQuantity ? (value, 1, false) : nil
        }
        if let (value, length) = ParkingUtteranceParser.spelledNumber(words, at: index) {
            return (Double(value), length, false)
        }
        if word == "a" || word == "an" { return (1, 1, true) }
        return nil
    }

    // MARK: - Anchors

    private static let hedges: Set<String> = [
        "about", "around", "roughly", "approximately", "exactly", "precisely", "just", "another",
    ]

    private static func isAnchored(_ words: [String], at index: Int, anchors: Anchors) -> Bool {
        var j = index - 1
        if j >= 0, hedges.contains(words[j]) { j -= 1 }
        guard j >= 0 else { return false }
        switch words[j] {
        case "in": return anchors.contains(.inPhrase)
        case "for": return anchors.contains(.forPhrase)
        default: return false
        }
    }

    private enum Tail { case plain, fromNow, disqualified }

    /// What comes straight after a duration. "In 15 minutes before the meeting" is anchored to the
    /// meeting, and "in a minute or two" is a range.
    private static func following(_ words: [String], _ end: Int) -> Tail {
        guard end < words.count else { return .plain }
        let next = words[end]
        if next == "from" {
            return end + 1 < words.count && words[end + 1] == "now" ? .fromNow : .disqualified
        }
        if ["before", "after", "past", "earlier", "later", "ago", "or", "to"]
            .contains(next), !(next == "to" && isActionTo(words, end)) {
            return .disqualified
        }
        return .plain
    }

    /// "Remind me in 10 minutes to call Mum" — the usual "to" introduces the reminder, not a
    /// clock time. Only "to" followed by a number ("10 minutes to 3") is a time of day.
    private static func isActionTo(_ words: [String], _ index: Int) -> Bool {
        guard index + 1 < words.count else { return true }
        let after = words[index + 1]
        if Double(after) != nil { return false }
        if ParkingUtteranceParser.spelledNumber(words, at: index + 1) != nil { return false }
        return true
    }

    // MARK: - Absolute times

    private static let absoluteWords: Set<String> = [
        "today", "tonight", "tomorrow", "tomorrow's", "yesterday", "tonight's", "today's",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "weekend", "noon", "midday", "midnight", "o'clock", "morning", "afternoon", "evening",
    ]

    /// Whether the sentence also names a clock time or a day, which makes the relative phrase a
    /// second, competing statement of when.
    private static func namesAnAbsoluteTime(_ utterance: String, _ words: [String]) -> Bool {
        if words.contains(where: absoluteWords.contains) { return true }
        // "3:30", "15:00"
        if utterance.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return true }
        // "3pm", "3 pm", "3 p.m."
        let lowered = utterance.lowercased()
        if lowered.range(of: #"\d\s*(a\.?m\.?|p\.?m\.?)(?![a-z])"#,
                         options: .regularExpression) != nil { return true }
        return false
    }
}
