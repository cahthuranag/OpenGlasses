import Foundation

/// A clause, rule or section number in a code or standard — "3.9.4.2" (AS/NZS 3000), "26-700"
/// (CEC), "110.26" or "210.8(A)" (NEC) — recognised in a question and found by number in the
/// manuals (Plan IN P3a).
///
/// `CodeTokenizer` cannot carry these. It keeps a decimal whole and never boosts on one, because
/// "0.28" is a reading (Plan GB P1), so "what does 3.9.4.2 say" had no exact match at all; and it
/// splits "26-700" at the hyphen, so a rule number boosted every passage that printed a 26 or a
/// 700. A clause is matched here as its whole printed form, with number-aware boundaries — "3.9.4"
/// is not inside "13.9.4", "2.3.9.4" or "3.9.40" — and a passage that *starts* the clause ranks
/// ahead of one that merely cites it, because a code book cross-references its busiest clauses
/// dozens of times and the reader asked for the clause, not for the places that point at it.
///
/// Pure and deterministic: recognition is a few patterns over the question, matching is string
/// work over a passage. Nothing here needs the store or an embedder.
enum ClauseReference {

    /// How a passage relates to a clause it was searched for. A higher rank is shown first.
    enum Match: Int, Comparable {
        /// Mentions the clause, or a subclause of it, in running text: "in accordance with
        /// Clause 3.9.4", a contents line, an index entry.
        case cites = 1
        /// Carries on the clause's own text: a later chunk of the section the clause heads, or the
        /// chunk straight after the one that starts it.
        case continues = 2
        /// Starts a subclause of it — "3.9.4.2 Protection…" for a question about 3.9.4.
        case startsSubclause = 3
        /// Starts the clause itself: its number followed by its title.
        case starts = 4

        static func < (a: Match, b: Match) -> Bool { a.rawValue < b.rawValue }
    }

    // MARK: - Recognition

    /// The clause numbers a question names, in order of first appearance, de-duplicated.
    ///
    /// Recognised: a number with two or more dots ("3.9.4.2" — never a reading); any dotted or
    /// hyphenated number after a clause word ("clause 3.9", "rule 26-700", "section 110.26",
    /// "§ 210.8"); a one- or two-level dotted number with a lettered subdivision ("210.8(A)");
    /// and a bare `NN-NNN` rule number ("26-700"). A spoken "3 point 9 point 4" or "26 dash
    /// 700" is read the same as the printed form. A one-dot number on its own ("0.28",
    /// "110.26") is not recognised: without a clause word it is far more often a measurement.
    static func references(in text: String) -> [String] {
        var seen = Set<String>()
        return spans(in: normalized(text)).map(\.clause).filter { seen.insert($0).inserted }
    }

    /// The question with every recognised clause number blanked out, so the per-token boost does
    /// not also fire on its pieces — "26-700" boosting every passage that prints a 26.
    static func removingReferences(from text: String) -> String {
        let normal = normalized(text)
        var out = normal
        for span in spans(in: normal).reversed() {
            out.replaceSubrange(span.range, with: " ")
        }
        return out
    }

    /// Printed and spoken variants brought to one form: an en dash or a non-breaking hyphen is a
    /// hyphen, and "3 point 9" or "26 dash 700" are joined.
    static func normalized(_ text: String) -> String {
        var out = text
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2010}", with: "-")
        // A spoken separator joins two digits; repeated because each pass consumes the digit it
        // ends on, so "3 point 9 point 4" needs two.
        for _ in 0..<6 {
            let joined = joinSpoken(out)
            if joined == out { break }
            out = joined
        }
        return out
    }

    private static func joinSpoken(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in spokenSeparator.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let word = ns.substring(with: m.range(at: 2)).lowercased()
            let mark = (word == "dash" || word == "hyphen") ? "-" : "."
            out += ns.substring(with: m.range(at: 1)) + mark + ns.substring(with: m.range(at: 3))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static let spokenSeparator = try! NSRegularExpression(
        pattern: #"(\d)\s*\b(point|dot|dash|hyphen)\b\s*(\d)"#, options: [.caseInsensitive])

    private struct Span {
        let range: Range<String.Index>
        let clause: String
    }

    /// Every recognised clause in already-normalised text, by position, first spelling kept.
    private static func spans(in text: String) -> [Span] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var found: [(NSRange, String)] = []
        for (pattern, group) in recognisers {
            for m in pattern.matches(in: text, range: whole) {
                let r = m.range(at: group)
                guard r.location != NSNotFound else { continue }
                // A span already claimed (the keyword form also matches the bare one) is skipped.
                if found.contains(where: { NSIntersectionRange($0.0, r).length > 0 }) { continue }
                found.append((r, ns.substring(with: r)))
            }
        }
        return found.sorted { $0.0.location < $1.0.location }.compactMap { r, clause in
            Range(r, in: text).map { Span(range: $0, clause: clause) }
        }
    }

    /// The clause words a number may follow. "Table" and "Figure" are left out on purpose: those
    /// are found by caption (Plan EK), and a reading may follow them.
    private static let keyword = #"(?:\b(?:rules?|clauses?|sections?|sec\.|articles?|art\.|regulations?|reg\.|paragraphs?|para\.)|§)"#
    /// No letter, digit, or number-joining mark before; none after unless it starts a subdivision.
    private static let leftEdge = #"(?<![\p{L}\p{N}.\-])"#
    private static let rightEdge = #"(?![\p{L}\p{N}]|[.\-]\d)"#

    private static let recognisers: [(NSRegularExpression, Int)] = [
        (#"\#(keyword)\s*(\d{1,4}(?:[.\-]\d{1,4}){1,5})\#(rightEdge)"#, 1),
        (#"\#(leftEdge)(\d{1,3}(?:\.\d{1,3}){2,5})\#(rightEdge)"#, 1),
        (#"\#(leftEdge)(\d{1,4}(?:\.\d{1,3}){1,2})(?=\([A-Za-z0-9]{1,3}\))"#, 1),
        (#"\#(leftEdge)(\d{1,2}-\d{3,4})\#(rightEdge)"#, 1),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.caseInsensitive]), $0.1) }

    // MARK: - Matching

    /// How `text` (with its chunk's `section`, when it has one) relates to `clause`, or nil when it
    /// does not carry it.
    static func match(_ clause: String, in text: String, section: String? = nil) -> Match? {
        guard !clause.isEmpty else { return nil }
        var best: Match?
        func consider(_ m: Match) { if best.map({ m > $0 }) ?? true { best = m } }

        if let section, headingMatch(clause, in: section) != nil {
            // The chunk sits inside the clause's section; it starts the clause only if the heading
            // itself is in this chunk's text, which the text scan below decides.
            consider(.continues)
        }

        let contents = looksLikeContents(text)
        var searchStart = text.startIndex
        while let r = text.range(of: clause, range: searchStart..<text.endIndex) {
            searchStart = r.upperBound
            guard let occurrence = occurrence(of: r, in: text) else { continue }
            let starting = !contents && startsHere(r, in: text, subclause: occurrence == .subclause)
            switch (occurrence, starting) {
            case (.exact, true): consider(.starts)
            case (.subclause, true): consider(.startsSubclause)
            default: consider(.cites)
            }
            if best == .starts { break }
        }
        return best
    }

    /// How far into `text` the first of `clauses` appears, for ordering passages that hold a
    /// clause equally well: a chunk that opens on the heading carries the clause's body, while one
    /// that ends on it — the chunker's overlap repeats a heading into the next chunk — carries
    /// little more than its title. `Int.max` when none appears.
    static func offset(of clauses: [String], in text: String) -> Int {
        clauses.compactMap { text.range(of: $0) }
            .map { text.distance(from: text.startIndex, to: $0.lowerBound) }
            .min() ?? .max
    }

    private enum Occurrence { case exact, subclause }

    /// Whether the characters around `r` make it this clause (or a subclause of it) rather than
    /// part of a longer number.
    private static func occurrence(of r: Range<String.Index>, in text: String) -> Occurrence? {
        if r.lowerBound > text.startIndex {
            let before = text.index(before: r.lowerBound)
            let p = text[before]
            if p.isLetter || p.isNumber { return nil }
            if p == "." || p == "-", before > text.startIndex, text[text.index(before: before)].isNumber {
                return nil
            }
        }
        guard r.upperBound < text.endIndex else { return .exact }
        let n = text[r.upperBound]
        if n.isLetter || n.isNumber { return nil }
        if n == "." || n == "-" {
            let after = text.index(after: r.upperBound)
            if after < text.endIndex, text[after].isNumber { return .subclause }
        }
        return .exact
    }

    /// Whether the clause at `r` is printed as a heading: at the start of a line or straight after
    /// a sentence boundary (chunks join sentences with spaces), optionally after a `##` marker or
    /// a clause word on its own line, and followed by a capitalised title or nothing at all.
    private static func startsHere(_ r: Range<String.Index>, in text: String, subclause: Bool) -> Bool {
        var before = String(text[text.startIndex..<r.lowerBound])
        while let last = before.last, last == " " || last == "\t" || last == "#" { before.removeLast() }
        var atBoundary = before.isEmpty || before.last == "\n"
        if !atBoundary, let k = before.range(of: #"(?:^|\n)[ \t#]*(?:rule|clause|section|article|regulation|§)$"#,
                                             options: [.regularExpression, .caseInsensitive]) {
            atBoundary = !k.isEmpty
        }
        if !atBoundary, let last = before.last, ".:;".contains(last) { atBoundary = true }
        guard atBoundary else { return false }

        var after = text[r.upperBound...]
        if subclause, let tail = after.range(of: #"^(?:[.\-]\d+)+"#, options: .regularExpression) {
            after = after[tail.upperBound...]
        }
        if after.isEmpty || after.range(of: #"^[ \t]*(\n|$)"#, options: .regularExpression) != nil { return true }
        guard after.range(of: #"^[ \t]+\p{Lu}"#, options: .regularExpression) != nil else { return false }
        // A contents line names the clause and its page with leaders between: a pointer, not text.
        let line = after.prefix { $0 != "\n" }.prefix(200)
        return line.range(of: #"\.{4,}|(?:\.\s){3,}|…{2,}"#, options: .regularExpression) == nil
    }

    /// A chunk that is a table of contents: entries run together as "…title 112 3.9.4.3 Title…",
    /// or dot leaders between titles and pages. Every clause in it is cited, none started.
    static func looksLikeContents(_ text: String) -> Bool {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        return contentsEntry.numberOfMatches(in: text, range: whole) >= 3
            || leaders.numberOfMatches(in: text, range: whole) >= 2
    }

    private static let contentsEntry = try! NSRegularExpression(
        pattern: #"(?<![\p{N}.\-])\d{1,4}\s+\d{1,3}(?:[.\-]\d{1,4})+\s+\p{Lu}"#)
    private static let leaders = try! NSRegularExpression(pattern: #"\.{4,}|(?:\.\s){4,}|…{2,}"#)

    /// How a section heading relates to `clause`: it starts with it (`starts`), with a subclause of
    /// it (`startsSubclause`), or not at all.
    private static func headingMatch(_ clause: String, in section: String) -> Match? {
        var heading = section.trimmingCharacters(in: .whitespaces)
        if let k = heading.range(of: #"^(?:#+\s*)?(?:(?:rule|clause|section|article|regulation)\s+|§\s*)?"#,
                                 options: [.regularExpression, .caseInsensitive]) {
            heading.removeSubrange(k)
        }
        guard heading.hasPrefix(clause) else { return nil }
        let rest = heading.dropFirst(clause.count)
        guard let n = rest.first else { return .starts }
        if n.isLetter || n.isNumber { return nil }
        if n == "." || n == "-", rest.dropFirst().first?.isNumber == true { return .startsSubclause }
        return .starts
    }
}
