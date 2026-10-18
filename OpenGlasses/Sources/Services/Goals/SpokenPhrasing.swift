import Foundation

/// Small, deterministic pieces of spoken English shared by the goal and activity phrasers
/// (Plan IW). Built by hand rather than with a date formatter so the exact strings are pinned by
/// tests and do not change with the device's formatting data (the system's short time style, for
/// one, puts a narrow no-break space before "PM").
enum SpokenPhrasing {
    private static let numberWords = ["zero", "one", "two", "three", "four", "five", "six",
                                      "seven", "eight", "nine", "ten", "eleven", "twelve"]

    /// "two", "eleven", "25".
    static func number(_ n: Int) -> String {
        (n >= 0 && n < numberWords.count) ? numberWords[n] : String(n)
    }

    /// "one thing", "three things"; pass `plural` for nouns that do not take an "s".
    static func count(_ n: Int, _ noun: String, plural: String? = nil) -> String {
        "\(number(n)) \(n == 1 ? noun : (plural ?? noun + "s"))"
    }

    static func capitalisedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// A title as it reads inside a list: "Book the skip" → "book the skip". Only a first word
    /// that is ordinary lower case after its capital is touched (and a lone "A"), so "TV", "I" and
    /// "MOT" keep their case. A name at the start ("Dave's bike") is lowered too; that only shows on a display,
    /// because speech has no case.
    static func listCased(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let firstWord = text.prefix { !$0.isWhitespace }
        let rest = firstWord.dropFirst()
        if rest.isEmpty { return first == "A" ? "a" + text.dropFirst() : text }
        guard rest.allSatisfy({ !$0.isUppercase }) else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// "a", "a and b", "a, b, and c".
    static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    /// Ends a clause as a sentence, without doubling punctuation the clause already has.
    static func sentence(_ clause: String) -> String {
        let trimmed = clause.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return trimmed }
        return ".?!…".contains(last) ? trimmed : trimmed + "."
    }

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday",
                                   "Friday", "Saturday"]
    private static let months = ["January", "February", "March", "April", "May", "June", "July",
                                 "August", "September", "October", "November", "December"]

    /// "today", "tomorrow", "Saturday" (within the coming week), else "20 October".
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...6:
            return weekdays[calendar.component(.weekday, from: date) - 1]
        default:
            let parts = calendar.dateComponents([.day, .month], from: date)
            return "\(parts.day ?? 1) \(months[(parts.month ?? 1) - 1])"
        }
    }

    /// "9 AM", "2:30 PM", "12 PM".
    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        let minutes = minute < 10 ? "0\(minute)" : "\(minute)"
        return minute == 0 ? "\(twelve) \(suffix)" : "\(twelve):\(minutes) \(suffix)"
    }

    /// "today at 4 PM", "tomorrow at 9 AM", "Saturday at 10:30 AM".
    static func dayAndTime(_ date: Date, now: Date, calendar: Calendar) -> String {
        "\(day(date, now: now, calendar: calendar)) at \(time(date, calendar: calendar))"
    }
}
