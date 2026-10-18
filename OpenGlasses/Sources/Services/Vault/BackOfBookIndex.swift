import Foundation

/// A document's own subject index — the alphabetical list at the back that points from a term to
/// the clauses or tables that cover it (Plan IV P5).
///
/// The index was written by someone who knew which clause answers which everyday word, which is
/// exactly what a question in a technician's words lacks. Detected and parsed from the document's
/// text, it turns the question's words into clause references `manual_lookup` offers the model to
/// look up by number. (As extra candidates in the per-turn ranking they were measured and moved
/// nothing, so they stay a hint.)
///
/// **Detection does nothing for a document without one.** An index is a line reading "Index" in
/// the last part of the document, followed by enough lines that end in references — clause numbers
/// with two or more parts ("41-310", "3.9.4"), or "Table Q3" / "Section Q4" — to be a list rather
/// than a stray heading. A prose manual, which has no such list, gets none.
///
/// Pure over text: what a document's entries say is read at search time from the stored text and
/// never written anywhere else.
struct BackOfBookIndex: Equatable {

    struct Entry: Equatable {
        /// The entry's content terms ([[LexicalSupport]]), its heading's included for a sub-entry.
        let terms: Set<String>
        /// What it points at, in the order printed: clause numbers and "Table Q3"-style labels.
        let references: [String]
    }

    let entries: [Entry]
    /// How many entries each term appears in.
    private let frequency: [String: Int]

    init(entries: [Entry]) {
        self.entries = entries
        var df: [String: Int] = [:]
        for entry in entries { for term in entry.terms { df[term, default: 0] += 1 } }
        frequency = df
    }

    /// How many referencing entries make a list an index.
    static let minimumEntries = 30

    /// The index in `text`, or nil when the document has none.
    static func parse(_ text: String) -> BackOfBookIndex? {
        let lines = text.components(separatedBy: "\n")
        // The heading is in the last part of the document; the contents page's "Index" line, at
        // the front, is not where the index starts.
        let tail = Int(Double(lines.count) * 0.6)
        guard let start = lines.indices.last(where: { $0 >= tail && isIndexHeading(lines[$0]) }) else { return nil }

        var entries: [Entry] = []
        var heading: Set<String> = []
        var previous: Set<String> = []
        for raw in lines[(start + 1)...] {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count > 1 else { continue }
            let found = references(in: line)
            let label = found.first.map { String(line[..<$0.range.lowerBound]) } ?? line
            let terms = LexicalSupport.contentTerms(label)
            if found.isEmpty {
                // A heading line for the sub-entries under it ("Fittings" before "covers 41-310").
                if !terms.isEmpty, line.rangeOfCharacter(from: .decimalDigits) == nil { heading = terms }
                continue
            }
            let refs = found.map(\.reference)
            if terms.isEmpty {
                // References carried onto the next line belong to the entry above.
                if !previous.isEmpty { entries.append(Entry(terms: previous, references: refs)) }
                continue
            }
            let subEntry = label.first.map(\.isLowercase) ?? false
            let entryTerms = subEntry ? terms.union(heading) : terms
            if !subEntry { heading = terms }
            previous = entryTerms
            entries.append(Entry(terms: entryTerms, references: refs))
        }
        return entries.count >= minimumEntries ? BackOfBookIndex(entries: entries) : nil
    }

    /// The references for a question's words, best first: entries scored by how much of the
    /// question's weight they carry (rarer index words weigh more), less what they add beyond it.
    func references(for question: String, limit: Int = 3) -> [String] {
        let asked = LexicalSupport.contentTerms(question)
        guard !asked.isEmpty else { return [] }
        let scored = entries.compactMap { entry -> (Entry, Double)? in
            let shared = entry.terms.intersection(asked)
            guard !shared.isEmpty else { return nil }
            let covered = shared.reduce(0) { $0 + weight($1) }
            let total = entry.terms.reduce(0) { $0 + weight($1) }
            return (entry, covered * covered / max(total, 0.001))
        }.sorted { $0.1 > $1.1 }
        var seen = Set<String>()
        var out: [String] = []
        for (entry, _) in scored {
            for reference in entry.references where seen.insert(reference).inserted {
                out.append(reference)
                if out.count == limit { return out }
            }
        }
        return out
    }

    // MARK: - Reading lines

    private static func isIndexHeading(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#: "))
        return t.caseInsensitiveCompare("Index") == .orderedSame || t.caseInsensitiveCompare("Subject index") == .orderedSame
    }

    private static let referencePattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}.\-])(\d{1,3}(?:[.\-]\d{1,4}){1,4})(?![\p{N}])|\b((?:Table|Section)\s+[A-Z]?\d{1,3}[A-Z]?)\b"#)

    private static func references(in line: String) -> [(range: Range<String.Index>, reference: String)] {
        let ns = line as NSString
        return referencePattern.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let group = match.range(at: 1).location != NSNotFound ? 1 : 2
            guard let range = Range(match.range(at: group), in: line),
                  let whole = Range(match.range, in: line) else { return nil }
            return (whole, String(line[range]))
        }
    }

    private func weight(_ term: String) -> Double {
        log(Double(entries.count + 1) / Double((frequency[term] ?? 0) + 1))
    }
}
