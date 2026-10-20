import Foundation

/// Token chunks in, complete sentences out (Plan HZ P0).
///
/// A streamed reply can only be spoken a sentence at a time if something can say where a sentence
/// ends while the rest of it is still arriving, and the obvious answer — cut at the last `.` — is
/// the one the old streamer used and the reason it was not reused: "2.5 mm", "e.g." and
/// "Dr. Patel" each split mid-phrase.
///
/// A boundary is a terminator (`.`, `!`, `?`, `…`, or a run of them, plus any closing quote or
/// bracket) followed by whitespace and then an upper-case letter, a digit or an opening quote — or
/// a blank line — or a newline that starts a list item. It is **not** a boundary when:
/// - the word before a lone `.` is an abbreviation (`abbreviations`) or a single capital initial;
/// - the `.` is followed by anything but whitespace, which covers "2.5", "3.14", versions and
///   IP-like tokens without a rule of their own;
/// - the text is inside an unclosed code span or fenced block.
///
/// A boundary is decided only once two characters past it are visible (or the stream has ended),
/// so a chunk that stops at "e." or at a list marker's digit never forces a guess. A sentence
/// shorter than `Limits.minimumLength` waits for the next boundary — "Sure." is not worth a
/// synthesis request of its own — and one that runs past `Limits.maximumLength` without a
/// boundary is cut at its last comma or semicolon, so a run-on paragraph cannot hold the first
/// audio hostage.
///
/// Pure and headless: it never sees a voice, a clock or a network, which is what lets every one of
/// those cases be pinned in a unit test.
struct SentenceStreamSplitter {

    struct Limits: Equatable {
        /// A sentence shorter than this merges into the next one.
        var minimumLength: Int = 20
        /// Past this, a sentence with no boundary is cut at its last comma or semicolon.
        var maximumLength: Int = 300

        static let `default` = Limits()
    }

    /// Words that end in a `.` without ending the sentence, lower-cased and without the final dot.
    /// Single capital initials ("J. R. R. Tolkien") are handled by rule, not by this list.
    static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "e.g", "i.e", "etc", "vs", "approx", "no", "fig"
    ]

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]"]
    private static let openingQuotes: Set<Character> = ["\"", "“", "‘", "'", "("]

    let limits: Limits
    /// Text received and not yet emitted.
    private var buffer: [Character] = []

    init(limits: Limits = .default) {
        self.limits = limits
    }

    /// Whether anything is waiting to be emitted.
    var isEmpty: Bool { buffer.allSatisfy(\.isWhitespace) }

    /// The text received and not yet emitted.
    var pending: String { String(buffer) }

    /// Feed one chunk; returns the sentences it completed, in order.
    mutating func ingest(_ chunk: String) -> [String] {
        buffer.append(contentsOf: chunk)
        return drain(endOfStream: false)
    }

    /// End of stream: every sentence still waiting, the last one however short.
    mutating func flush() -> [String] {
        var sentences = drain(endOfStream: true)
        let rest = Self.trimmed(buffer[...])
        buffer.removeAll()
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }

    /// Flush only if what is waiting already ends a sentence — a stream that has gone quiet after
    /// a full stop is done with that sentence, while one that stopped mid-clause may still be
    /// typing it. Used where a producer has no end-of-stream signal of its own.
    mutating func flushIfComplete() -> [String] {
        guard endsAtTerminator else { return drain(endOfStream: false) }
        return flush()
    }

    /// Drop everything waiting.
    mutating func reset() {
        buffer.removeAll()
    }

    /// Whether the waiting text, trailing whitespace and closers aside, ends in a terminator and
    /// is not inside code.
    var endsAtTerminator: Bool {
        var i = buffer.count - 1
        while i >= 0, buffer[i].isWhitespace || Self.closers.contains(buffer[i]) { i -= 1 }
        guard i >= 0, Self.terminators.contains(buffer[i]) else { return false }
        return !Self.isInsideCode(buffer[...])
    }

    // MARK: - Scanning

    private mutating func drain(endOfStream: Bool) -> [String] {
        var sentences: [String] = []
        while let cut = nextCut(endOfStream: endOfStream) {
            let sentence = Self.trimmed(buffer[..<cut])
            buffer.removeFirst(cut)
            if let firstText = buffer.firstIndex(where: { !$0.isWhitespace }) {
                buffer.removeFirst(firstText)
            } else {
                buffer.removeAll()
            }
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        return sentences
    }

    /// The end (exclusive) of the next emittable sentence, or nil to wait for more text.
    private func nextCut(endOfStream: Bool) -> Int? {
        let count = buffer.count
        var inFence = false
        var inSpan = false
        var lastSoftBreak: Int?   // just past the last comma/semicolon outside code
        var i = 0
        while i < count {
            // The sentence has run long with no boundary: cut at its last comma or semicolon.
            if i >= limits.maximumLength, let soft = lastSoftBreak {
                return soft
            }
            let c = buffer[i]
            if c == "`" {
                if i + 2 < count, buffer[i + 1] == "`", buffer[i + 2] == "`" {
                    inFence.toggle()
                    i += 3
                    continue
                }
                // A lone backtick at the very end may still grow into a fence: wait for it.
                if !endOfStream, !inFence, i + 2 >= count,
                   buffer[i...].allSatisfy({ $0 == "`" }) {
                    return nil
                }
                if !inFence { inSpan.toggle() }
                i += 1
                continue
            }
            if inFence || inSpan {
                i += 1
                continue
            }
            if c == "," || c == ";" {
                if i + 1 >= limits.minimumLength { lastSoftBreak = i + 1 }
                i += 1
                continue
            }
            if Self.terminators.contains(c) {
                switch terminatorBoundary(at: i, endOfStream: endOfStream) {
                case .wait:
                    return nil
                case .skip(let next):
                    i = next
                    continue
                case .cut(let end):
                    if Self.trimmed(buffer[..<end]).count >= limits.minimumLength { return end }
                    i = end
                    continue
                }
            }
            if c == "\n" {
                switch newlineBoundary(at: i, endOfStream: endOfStream) {
                case .wait:
                    return nil
                case .skip(let next):
                    i = next
                    continue
                case .cut(let end):
                    if Self.trimmed(buffer[..<end]).count >= limits.minimumLength { return end }
                    i += 1
                    continue
                }
            }
            i += 1
        }
        return nil
    }

    private enum Candidate {
        /// Not decidable until more text arrives.
        case wait
        /// Not a boundary; resume scanning here.
        case skip(next: Int)
        /// A boundary; the sentence ends here (exclusive).
        case cut(end: Int)
    }

    /// A terminator at `index`: is the sentence over?
    private func terminatorBoundary(at index: Int, endOfStream: Bool) -> Candidate {
        let count = buffer.count
        var end = index
        while end < count, Self.terminators.contains(buffer[end]) { end += 1 }
        let run = end - index
        while end < count, Self.closers.contains(buffer[end]) { end += 1 }
        guard end < count else { return endOfStream ? .skip(next: end) : .wait }
        // "2.5", "e.g.x", "v1.2.3": no whitespace, no boundary.
        guard buffer[end].isWhitespace else { return .skip(next: end) }

        // A lone full stop after an abbreviation or an initial does not end the sentence.
        if run == 1, buffer[index] == ".", isAbbreviation(endingBefore: index) {
            return .skip(next: end)
        }

        var next = end
        while next < count, buffer[next].isWhitespace { next += 1 }
        guard next < count else { return endOfStream ? .skip(next: next) : .wait }
        // Two characters of the next sentence, so a list marker or an initial is visible.
        guard next + 1 < count || endOfStream else { return .wait }

        let start = buffer[next]
        if start.isUppercase || start.isNumber || Self.openingQuotes.contains(start) {
            return .cut(end: end)
        }
        // A newline before a list marker ends the sentence whatever its case.
        if buffer[end..<next].contains("\n"), listMarkerLength(at: next) != nil {
            return .cut(end: end)
        }
        return .skip(next: end)
    }

    /// A newline at `index`: a blank line, or a list item starting, ends what came before.
    private func newlineBoundary(at index: Int, endOfStream: Bool) -> Candidate {
        let count = buffer.count
        var next = index
        var newlines = 0
        while next < count, buffer[next].isWhitespace {
            if buffer[next] == "\n" { newlines += 1 }
            next += 1
        }
        guard next < count else { return endOfStream ? .skip(next: next) : .wait }
        if newlines >= 2 { return .cut(end: index) }
        // Enough of the line to tell a marker from a word.
        guard next + 3 < count || endOfStream else { return .wait }
        return listMarkerLength(at: next) != nil ? .cut(end: index) : .skip(next: index + 1)
    }

    /// The length of a list marker ("- ", "* ", "• ", "1. ", "12) ") at `index`, or nil.
    private func listMarkerLength(at index: Int) -> Int? {
        let count = buffer.count
        guard index < count else { return nil }
        let c = buffer[index]
        if c == "-" || c == "*" || c == "•" {
            return index + 1 < count && buffer[index + 1] == " " ? 2 : nil
        }
        var j = index
        while j < count, j - index < 3, buffer[j].isASCII, buffer[j].isNumber { j += 1 }
        guard j > index, j + 1 < count, buffer[j] == "." || buffer[j] == ")",
              buffer[j + 1] == " " else { return nil }
        return j + 2 - index
    }

    /// Whether the word ending just before `index` (a full stop) is an abbreviation or an initial.
    private func isAbbreviation(endingBefore index: Int) -> Bool {
        var start = index
        while start > 0, buffer[start - 1].isLetter || buffer[start - 1] == "." { start -= 1 }
        let word = String(buffer[start..<index])
        guard !word.isEmpty else { return false }
        if word.count == 1, let only = word.first, only.isUppercase { return true }
        return Self.abbreviations.contains(word.lowercased())
    }

    // MARK: - Helpers

    private static func trimmed(_ slice: ArraySlice<Character>) -> String {
        String(slice).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a fence or a code span is still open at the end of `slice`.
    private static func isInsideCode(_ slice: ArraySlice<Character>) -> Bool {
        var inFence = false
        var inSpan = false
        var i = slice.startIndex
        while i < slice.endIndex {
            if slice[i] == "`" {
                if i + 2 < slice.endIndex, slice[i + 1] == "`", slice[i + 2] == "`" {
                    inFence.toggle()
                    i += 3
                    continue
                }
                if !inFence { inSpan.toggle() }
            }
            i += 1
        }
        return inFence || inSpan
    }
}
