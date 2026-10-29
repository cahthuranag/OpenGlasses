import Foundation

/// Undoes "fake bold" in a PDF's text layer (Plan JY P4).
///
/// A Chinese or Japanese PDF often sets a heading in bold by printing every glyph twice, a hair
/// apart, instead of using a bold font. The text layer then reads each character twice — a heading
/// meaning "temperature" comes out as 温温度度 — which breaks every bigram the term search cuts from
/// it, and the font says nothing about weight, so the type rules never see a heading either.
///
/// The doubling is collapsed only where the evidence is unambiguous, because Chinese and Japanese
/// repeat characters on purpose (常常, 看看, 高高兴兴): a run of consecutive doubled pairs whose
/// letters are all Han, kana or Hangul, and either
/// - at least `minimumPairs` pairs over at least `minimumDistinct` different characters — legitimate
///   reduplication repeats one or two characters, never three different ones in a row; or
/// - a doubled CJK punctuation mark beside a doubled letter (注注：：) — no text doubles a full-width
///   colon or comma on purpose.
///
/// Latin, Cyrillic and Arabic text is never touched ("ll", "ee", "XXIII"), nor is a run of one
/// repeated character (a dot leader, an underscore rule) or a mathematical letter a text layer
/// repeats for a subscript. Pure, and deterministic over its input.
enum OverprintedText {

    /// Pairs a run needs, with `minimumDistinct` different characters, to be collapsed on its own.
    static let minimumPairs = 3
    static let minimumDistinct = 3

    /// A doubled pair whose second copy starts less than this many ems after the first is one
    /// glyph printed twice (Plan JY P5a). Measured on a regulation's Chinese edition: the copies
    /// of every overprinted pair sit 0.4–0.6 em apart (PDFKit splits the glyph's box between
    /// them), and a CJK character's advance to the next is 0.7–1.3 em (0.9–1.1 for all but 0.6%).
    static let overprintAdvance = 0.7

    /// The line with its overprinted runs collapsed, and how many characters were overprinted (as
    /// read once). Zero when nothing qualified, and then `text` is `line` unchanged.
    ///
    /// **By the type, where it is known (Plan JY P5a).** `advance` gives, for the character at an
    /// index of `line`, how far the next character starts after it, in ems (nil when the page
    /// doesn't say). Text alone cannot tell a two-character heading printed twice (温温度度) from a
    /// reduplicated word (高高兴兴), so a run the text rule leaves is decided pair by pair from the
    /// glyphs: a CJK pair whose copies are less than `overprintAdvance` apart is one glyph printed
    /// twice and collapses, one drawn a full glyph apart is two characters and stays. A run whose
    /// geometry isn't known for every pair keeps the text rule. A run the text rule collapses is
    /// collapsed as before.
    static func collapsed(_ line: String, advance: ((Int) -> Double?)? = nil) -> (text: String, overprinted: Int) {
        let characters = Array(line)
        guard characters.count >= 4 else { return (line, 0) }
        var out: [Character] = []
        out.reserveCapacity(characters.count)
        var overprinted = 0
        var index = 0
        while index < characters.count {
            var end = index
            while end + 1 < characters.count, characters[end] == characters[end + 1], !characters[end].isWhitespace {
                end += 2
            }
            if end > index, qualifies(characters[index..<end]) {
                for pair in stride(from: index, to: end, by: 2) { out.append(characters[pair]) }
                overprinted += (end - index) / 2
                index = end
            } else if end > index, let advance, let printedTwice = printedTwice(characters, index..<end, advance: advance) {
                for (offset, pair) in stride(from: index, to: end, by: 2).enumerated() {
                    out.append(characters[pair])
                    if printedTwice[offset] { overprinted += 1 } else { out.append(characters[pair + 1]) }
                }
                index = end
            } else if end > index {
                out.append(contentsOf: characters[index..<end])
                index = end
            } else {
                out.append(characters[index])
                index += 1
            }
        }
        return overprinted == 0 ? (line, 0) : (String(out), overprinted)
    }

    /// Whether most of a line's letters were overprinted: the line was set in (fake) bold.
    static func isMostlyOverprinted(_ line: String, collapsed: (text: String, overprinted: Int)) -> Bool {
        guard collapsed.overprinted > 0 else { return false }
        let letters = collapsed.text.filter(\.isLetter).count
        return letters > 0 && collapsed.overprinted * 2 >= letters
    }

    /// Every line of `text` collapsed. A page's text layer read without type goes through this.
    static func collapsedLines(_ text: String) -> String {
        guard text.contains(where: { TextScript.of($0)?.isCJK == true }) else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { collapsed(String($0)).text }
            .joined(separator: "\n")
    }

    /// For each doubled pair in `range` (both copies of each), whether its glyph was printed twice,
    /// read off `advance`; nil when a CJK pair's geometry is unknown. A pair of any other character
    /// is never collapsed.
    private static func printedTwice(_ characters: [Character], _ range: Range<Int>,
                                     advance: (Int) -> Double?) -> [Bool]? {
        var verdicts: [Bool] = []
        for pair in stride(from: range.lowerBound, to: range.upperBound, by: 2) {
            let character = characters[pair]
            let isCJK = TextScript.of(character)?.isCJK == true || isCJKPunctuation(character)
            guard isCJK else { verdicts.append(false); continue }
            guard let em = advance(pair) else { return nil }
            verdicts.append(em < overprintAdvance)
        }
        return verdicts.isEmpty ? nil : verdicts
    }

    /// A run of doubled pairs (`run` holds both copies of each) that is overprinting, not text.
    private static func qualifies(_ run: ArraySlice<Character>) -> Bool {
        let pairs = stride(from: run.startIndex, to: run.endIndex, by: 2).map { run[$0] }
        guard pairs.count >= 2 else { return false }
        var letters = 0
        for character in pairs where character.isLetter {
            guard TextScript.of(character)?.isCJK == true else { return false }
            letters += 1
        }
        guard letters > 0 else { return false }
        let distinct = Set(pairs).count
        if pairs.count >= minimumPairs, distinct >= minimumDistinct { return true }
        return distinct >= 2 && pairs.contains(where: isCJKPunctuation)
    }

    /// Ideographic and full-width punctuation: 、。「」，：；！？ and their kin.
    private static func isCJKPunctuation(_ character: Character) -> Bool {
        guard !character.isLetter, !character.isNumber, let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3001...0x303F, 0xFF01...0xFF0F, 0xFF1A...0xFF20, 0xFF3B...0xFF40, 0xFF5B...0xFF65: return true
        default: return false
        }
    }
}
