import Foundation

/// Joining the pieces a model's reply arrives in, without gluing sentences together.
///
/// A reply can come back in several pieces: Gemini's text parts, the Responses API's message items
/// and their `output_text` blocks. Concatenated as they are, a piece that ends a sentence runs
/// straight into the next one — "…hora exata.Tens razão" — which reads as one word on screen and
/// is spoken as one. Pure, so it is tested without a model.
enum TextSegmentJoiner {

    /// The segments in order, with a single space between two that meet with no whitespace on
    /// either side. Whitespace already at a boundary (a newline, a paragraph break) is kept as it
    /// is; empty segments add nothing.
    static func join<S: Sequence>(_ segments: S) -> String where S.Element == String {
        var result = ""
        for segment in segments where !segment.isEmpty {
            if let last = result.last, let first = segment.first,
               !last.isWhitespace, !first.isWhitespace {
                result += " "
            }
            result += segment
        }
        return result
    }

    /// Put back the space a model left out between two sentences: a lowercase letter, the
    /// sentence's closing mark, and the next sentence's capital with no gap — "exata.Tens",
    /// "Papa.O Papa". Only where the capital starts a word (it is followed by a lowercase letter,
    /// whitespace or the end), so "ASP.NET", "3.5" and "U.S." are left alone. Code spans in
    /// backticks and anything shaped like an address (`://`, `www.`, an `@`) are never touched.
    static func repairingGluedSentences(_ text: String) -> String {
        guard text.contains(where: { $0 == "." || $0 == "!" || $0 == "?" }) else { return text }
        // Even-indexed pieces are outside backticks; odd ones are code and stay as they are.
        let pieces = text.components(separatedBy: "`")
        return pieces.enumerated().map { index, piece in
            index.isMultiple(of: 2) ? repairedProse(piece) : piece
        }.joined(separator: "`")
    }

    private static let token = try! NSRegularExpression(pattern: #"\S+"#)
    private static let gluedBoundary = try! NSRegularExpression(
        pattern: #"(?<=\p{Ll}[.!?])(?=\p{Lu}(?:\p{Ll}|$))"#)

    private static func repairedProse(_ text: String) -> String {
        let source = text as NSString
        var result = text
        // From the end, so earlier ranges still refer to the original string.
        for match in token.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let word = source.substring(with: match.range)
            guard !word.contains("://"), !word.lowercased().hasPrefix("www."), !word.contains("@"),
                  let range = Range(match.range, in: result) else { continue }
            let whole = NSRange(location: 0, length: (word as NSString).length)
            let repaired = gluedBoundary.stringByReplacingMatches(in: word, range: whole, withTemplate: " ")
            if repaired != word { result.replaceSubrange(range, with: repaired) }
        }
        return result
    }
}
