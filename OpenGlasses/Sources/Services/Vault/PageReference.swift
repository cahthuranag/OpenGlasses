import Foundation

/// A page a technician names out loud — "page 34", "pages 34 and 35", "p. 12" — recognised in a
/// turn so the number is read as a place in the manual rather than as a code.
///
/// Field report, build 497: "check page 34 of the service manual, item number two" handed `34` to
/// the exact-token search, which ranks a verbatim hit ahead of everything else. The vent-length
/// tables on pages 17 and 18 of the installation instructions print a 34 in a cell, so they filled
/// all four passage slots and the next turn put Table 8 on the phone — a page nobody named, in a
/// manual nobody asked for. A page number says where to look; it is not something to look for.
///
/// Pure and deterministic, the sibling of [[ClauseReference]] and of the job references
/// `ManualTurnScope` takes out of a turn.
enum PageReference {

    /// The pages the text names, in ascending order. A short range ("pages 34 to 36") names every
    /// page in it; a long one names its two ends, because a technician reading out a range that
    /// wide is not pointing at one place.
    static func pages(in text: String) -> Set<Int> {
        var pages = Set<Int>()
        for match in matches(in: text) {
            pages.insert(match.first)
            guard let last = match.last else { continue }
            if match.isRange, last > match.first, last - match.first <= maximumFilledRange {
                pages.formUnion(match.first...last)
            } else {
                pages.insert(last)
            }
        }
        return pages
    }

    /// The text with every named page number blanked out. The page word stays — it is ordinary
    /// language — and only the number that would otherwise be searched as a code goes.
    static func removingReferences(from text: String) -> String {
        let ns = NSMutableString(string: text)
        for match in matches(in: text).reversed() {
            for range in match.numberRanges.reversed() {
                ns.replaceCharacters(in: range, with: " ")
            }
        }
        return ns as String
    }

    // MARK: - Recognition

    private struct Match {
        let first: Int
        let last: Int?
        let isRange: Bool
        let numberRanges: [NSRange]
    }

    private static let maximumFilledRange = 5

    /// "page 34", "page number 34", "pages 34 and 35", "pages 34-36", "pg 12", "p. 12". A bare
    /// "p" needs its full stop: "p 12" is as likely the end of a part number as a page.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![\p{L}\p{N}])(?:pages?|pgs?\.?|pp?\.)\s*(?:(?:number|no\.?|num|#)\s*)?(\d{1,4})(?:\s*(-|–|to|through|and|&|,)\s*(\d{1,4}))?(?![\p{L}\p{N}])"#)

    private static func matches(in text: String) -> [Match] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { result in
            guard let first = Int(ns.substring(with: result.range(at: 1))) else { return nil }
            var ranges = [result.range(at: 1)]
            var last: Int?
            var isRange = false
            if result.range(at: 3).location != NSNotFound, let second = Int(ns.substring(with: result.range(at: 3))) {
                last = second
                ranges.append(result.range(at: 3))
                let joiner = ns.substring(with: result.range(at: 2)).lowercased()
                isRange = ["-", "–", "to", "through"].contains(joiner)
            }
            return Match(first: first, last: last, isRange: isRange, numberRanges: ranges)
        }
    }
}
