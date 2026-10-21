import Foundation

/// A table a question names, recognised so retrieval can take the table route ahead of the clause
/// route (Plan JJ P1), the way [[ClauseReference]] does for a clause number.
///
/// Recognised: "table 99", "Table 99", "tbl 99", "tbl. 99", "table no. 99", a number spoken as
/// words ("table ninety-nine", "table one hundred and two"), a letter beside the number (Plan JJ
/// P5: "table 95A", "table 95 B", "table five A", "table Q7", "table Q seven"), and — only when the
/// question says "table" — every word of one table's title ("the conductor ratings table" for a
/// table titled "Conductor ratings"). Not recognised: "table" with no number after it ("a table
/// saw"), a table word inside another word ("timetable 9"), or a model number that happens to
/// start with the letters ("TBL99X").
///
/// A lower-case "a" or "i" standing after the number is read as a word ("is table 5 a good
/// source"), not as the label's letter, unless the vault prints a table of that label
/// (`references(in:catalogue:)`, `labels(in:among:)`).
///
/// The label is spelled as the extractor writes a caption's (`TableExtractor.caption`):
/// "Table 99", "Table 95A", "Table Q7". Pure and deterministic.
enum TableReference {

    /// One table a vault holds, by label and title — what title words are matched against.
    struct Entry: Equatable, Hashable {
        let label: String
        let title: String

        init(label: String, title: String) {
            self.label = label
            self.title = title
        }
    }

    /// "Table 99".
    static func label(number: Int) -> String { "Table \(number)" }

    /// "Table 95A", "Table Q7": a number with the letters printed before or after it.
    static func label(number: Int, prefix: String, suffix: String) -> String {
        "Table \(prefix.uppercased())\(number)\(suffix.uppercased())"
    }

    // MARK: - By number

    /// The tables a question names by number, in order of first appearance, de-duplicated.
    static func labels(in text: String) -> [String] {
        labels(in: text, among: [])
    }

    /// The tables a question names by number, reading a lower-case "a" or "i" after the number as
    /// the label's letter only when `available` holds that label ("table five a" where the vault
    /// prints a Table 95A). Labels are compared without case.
    static func labels(in text: String, among available: [String]) -> [String] {
        var seen = Set<String>()
        return spans(in: text).map { span in
            if let lettered = span.lettered,
               available.contains(where: { $0.caseInsensitiveCompare(lettered) == .orderedSame }) {
                return lettered
            }
            return span.label
        }.filter { seen.insert($0.lowercased()).inserted }
    }

    /// The question with every numbered table reference blanked out, so the per-token boost does
    /// not also fire on the table's number — "99" is a cell on page after page of a book.
    static func removingReferences(from text: String) -> String {
        var out = text
        for span in spans(in: text).reversed() {
            out.replaceSubrange(span.range, with: " ")
        }
        return out
    }

    /// The tables a question names: by number when it gives one, else the one table whose title
    /// its words match closely (`titled(in:catalogue:)`), else none.
    static func references(in text: String, catalogue: [Entry]) -> [String] {
        let numbered = labels(in: text, among: catalogue.map(\.label))
        guard numbered.isEmpty else { return numbered }
        return titled(in: text, catalogue: catalogue).map { [$0] } ?? []
    }

    // MARK: - By title

    /// The label of the one table whose title the question's words match closely, or nil.
    ///
    /// The question must say "table" (or "tables"), so a question that merely uses a word some
    /// table's title uses ("what rating does this breaker need") is not sent to that table. Then a
    /// title matches when the question holds every one of the title's content words
    /// ([[LexicalSupport]] terms, so "ratings" is "rating"), and at least two; the best match must
    /// be the only one, because two tables whose titles match equally well are a question to ask,
    /// not one to route. Plan JJ P3 raised this from half the title and one word: a question that
    /// shared half a table's title ranked the table's rows above the clause that answered it,
    /// which cost the code book's answer key its one table-route question (measured privately:
    /// hit@1 / hit@4 0.38 / 0.55 → 0.39 / 0.56, nothing else lost). A table named by its number
    /// is unaffected.
    static func titled(in text: String, catalogue: [Entry]) -> String? {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        guard words.contains(where: { $0 == "table" || $0 == "tables" }) else { return nil }
        let asked = LexicalSupport.contentTerms(text).subtracting(LexicalSupport.contentTerms("table tables"))
        guard !asked.isEmpty else { return nil }
        var best: (score: Int, labels: Set<String>) = (0, [])
        for entry in catalogue {
            let title = LexicalSupport.contentTerms(entry.title)
            guard !title.isEmpty else { continue }
            let shared = asked.intersection(title).count
            guard shared >= 2, shared == title.count else { continue }
            if shared > best.score {
                best = (shared, [entry.label])
            } else if shared == best.score {
                best.labels.insert(entry.label)
            }
        }
        return best.labels.count == 1 ? best.labels.first : nil
    }

    // MARK: - Recognition

    private struct Span {
        let range: Range<String.Index>
        let label: String
        /// The label with a lower-case "a" or "i" after the number read as its letter, when one
        /// stands there: taken only where the vault prints that table.
        var lettered: String?
    }

    /// "table", "tbl" or "tbl." standing as a word.
    private static let keyword = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(?:tables?|tbl\.?)(?![\p{L}\p{N}])"#, options: [.caseInsensitive])
    /// What may stand between the keyword and its number: "no.", "number", "#".
    private static let filler = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:no\.?|number|#)\s*)?"#, options: [.caseInsensitive])
    /// A printed number, whole, with the letters a label may carry against it ("95A", "Q7"): not
    /// followed by another letter, a digit or a decimal part.
    private static let digits = try! NSRegularExpression(
        pattern: #"^([A-Za-z]{1,2})?(\d{1,4})([A-Za-z])?(?![\p{L}\p{N}]|[.,]\d)"#)
    /// One letter standing as a word after the number ("95 B", "five A").
    private static let letterAfter = try! NSRegularExpression(pattern: #"^[ \t]+([A-Za-z])(?![\p{L}\p{N}])"#)
    /// One letter standing as a word before the number ("Q seven", "Q 7").
    private static let letterBefore = try! NSRegularExpression(pattern: #"^([A-Za-z])[ \t]+"#)

    private static func spans(in text: String) -> [Span] {
        let ns = text as NSString
        var found: [Span] = []
        func tail(_ from: Int) -> NSRange { NSRange(location: from, length: ns.length - from) }
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
            match.range(at: index).location == NSNotFound ? "" : ns.substring(with: match.range(at: index))
        }
        for match in keyword.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var cursor = NSMaxRange(match.range)
            if let gap = filler.firstMatch(in: text, range: tail(cursor)) { cursor += gap.range.length }
            var number: Int?
            var prefix = ""
            var suffix = ""
            var end = cursor
            if let printed = digits.firstMatch(in: text, options: [.anchored], range: tail(cursor)) {
                number = Int(group(printed, 2))
                prefix = group(printed, 1)
                suffix = group(printed, 3)
                end = NSMaxRange(printed.range)
            } else if let spoken = spokenNumber(in: ns, from: cursor) {
                number = spoken.value
                end = spoken.end
            } else if let letter = letterBefore.firstMatch(in: text, options: [.anchored], range: tail(cursor)),
                      isLabelLetter(group(letter, 1)) {
                // "Q seven", "Q 7": one letter, then the number.
                let after = NSMaxRange(letter.range)
                if let printed = digits.firstMatch(in: text, options: [.anchored], range: tail(after)),
                   group(printed, 1).isEmpty {
                    number = Int(group(printed, 2))
                    suffix = group(printed, 3)
                    end = NSMaxRange(printed.range)
                } else if let spoken = spokenNumber(in: ns, from: after) {
                    number = spoken.value
                    end = spoken.end
                }
                if number != nil { prefix = group(letter, 1) }
            }
            guard let number, number > 0 else { continue }
            // A letter standing after the number is the label's when it is a capital or any small
            // letter but "a" and "i", which are words; those only where the vault prints the table.
            var lettered: String?
            if suffix.isEmpty, let letter = letterAfter.firstMatch(in: text, options: [.anchored], range: tail(end)) {
                let word = group(letter, 1)
                if isLabelLetter(word) {
                    suffix = word
                    end = NSMaxRange(letter.range)
                } else {
                    lettered = label(number: number, prefix: prefix, suffix: word)
                }
            }
            guard let range = Range(NSRange(location: match.range.location, length: end - match.range.location), in: text)
            else { continue }
            found.append(Span(range: range, label: label(number: number, prefix: prefix, suffix: suffix),
                              lettered: lettered))
        }
        return found
    }

    /// A letter standing on its own that belongs to a label rather than the sentence: a capital,
    /// or a small letter other than the words "a" and "i".
    private static func isLabelLetter(_ letter: String) -> Bool {
        guard letter.count == 1, let first = letter.first else { return false }
        return first.isUppercase || !["a", "i"].contains(letter)
    }

    // MARK: - Spoken numbers

    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// The next word, after spaces or a hyphen.
    private static let spokenWord = try! NSRegularExpression(pattern: #"[\s\-]*(\p{L}+)"#)

    /// A number written as words starting at `start` ("ninety-nine", "one hundred and two"), and
    /// where it ends, or nil when the next word is not a number.
    private static func spokenNumber(in text: NSString, from start: Int) -> (value: Int, end: Int)? {
        // The words that follow, each with where it ends; a hyphen joins two as a space does.
        var words: [(word: String, end: Int)] = []
        var cursor = start
        while words.count < 6,
              let m = spokenWord.firstMatch(in: text as String, options: [.anchored],
                                            range: NSRange(location: cursor, length: text.length - cursor)) {
            words.append((text.substring(with: m.range(at: 1)).lowercased(), NSMaxRange(m.range)))
            cursor = NSMaxRange(m.range)
        }
        var index = 0
        var value = 0
        var end: Int?
        func word(_ i: Int) -> String? { i < words.count ? words[i].word : nil }

        // [one–nine] hundred [and]
        if let w = word(0), let u = units[w], u < 10, word(1) == "hundred" {
            value = u * 100
            end = words[1].end
            index = 2
            if word(index) == "and" { index += 1 }
        } else if word(0) == "hundred" || (word(0) == "a" && word(1) == "hundred") {
            value = 100
            index = word(0) == "a" ? 2 : 1
            end = words[index - 1].end
            if word(index) == "and" { index += 1 }
        }
        // twenty–ninety [one–nine] | one–nineteen
        if let w = word(index), let t = tens[w] {
            value += t
            end = words[index].end
            if let next = word(index + 1), let u = units[next], u < 10 {
                value += u
                end = words[index + 1].end
            }
        } else if let w = word(index), let u = units[w] {
            value += u
            end = words[index].end
        }
        return end.map { (value, $0) }
    }
}
