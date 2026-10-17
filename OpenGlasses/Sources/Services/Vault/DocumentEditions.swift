import Foundation

/// The editions in a vault: documents that are revisions of one work (Plan IV P2).
///
/// A vault that loads a code book's current edition beside the previous one has two copies of most
/// rules. Searched together, the older copy takes slots before the model sees anything. Measured on
/// a code book loaded in two editions, hit@4 drops by a few points, and the older edition's copies
/// take a quarter of the slots that outrank the right passage. So the newest edition answers, and
/// an older one answers only when the turn asks for it (`EditionRequest`).
///
/// **Detection is deliberately small.** Documents are editions of one work when they share a
/// `kind` and their titles are the same once the edition label is taken out. The label is the
/// manifest's `edition`, or a year in the title ("2021 Code Book", "Code Book 2024"). Each
/// edition needs an order (a year, or a number in the label). A group with no order isn't treated
/// as editions, and a vault with one document per work is untouched. HK's `revision` and
/// `supersedes`, when they land, can feed the same type.
///
/// Pure over the manifest's documents.
struct DocumentEditions: Equatable {

    struct Edition: Equatable {
        let title: String
        /// What the technician would say: "2021", "Rev C".
        let label: String
        /// Higher is newer.
        let order: Int
    }

    /// Each work loaded in more than one edition, newest first.
    let works: [[Edition]]

    static let none = DocumentEditions(works: [])

    init(works: [[Edition]]) { self.works = works }

    /// From each document's title, kind and edition label. `init(documents:)` (beside
    /// `VaultDocument`) reads them off a manifest; a reader that doesn't decode a whole manifest
    /// passes them directly.
    init(entries: [(title: String, kind: String?, edition: String?)]) {
        var groups: [String: [Edition]] = [:]
        var keyOrder: [String] = []
        for document in entries {
            guard let edition = Self.edition(title: document.title, label: document.edition) else { continue }
            let key = (document.kind ?? "").lowercased() + "|" + Self.workKey(document.title, label: edition.label)
            if groups[key] == nil { keyOrder.append(key) }
            groups[key, default: []].append(edition)
        }
        works = keyOrder.compactMap { key in
            guard let group = groups[key], group.count > 1,
                  Set(group.map(\.order)).count == group.count else { return nil }
            return group.sorted { $0.order > $1.order }
        }
    }

    var isEmpty: Bool { works.isEmpty }

    /// The work a title belongs to, newest first, when it is one of several editions.
    func work(of title: String) -> [Edition]? { works.first { $0.contains { $0.title == title } } }

    func edition(of title: String) -> Edition? { work(of: title)?.first { $0.title == title } }

    /// The titles a request may search, or nil when nothing is filtered (no editions). A document
    /// that isn't an edition of anything is always searched.
    func searchableTitles(for request: EditionRequest, among titles: [String]) -> Set<String>? {
        guard !isEmpty else { return nil }
        var allowed = Set(titles.filter { work(of: $0) == nil })
        for work in works {
            switch request {
            case .newest:
                allowed.insert(work[0].title)
            case .compare:
                allowed.formUnion(work.map(\.title))
            case .previous:
                allowed.insert(work.count > 1 ? work[1].title : work[0].title)
            case .named(let labels):
                let named = work.filter { edition in labels.contains { Self.sameLabel($0, edition.label) } }
                allowed.formUnion(named.isEmpty ? [work[0].title] : named.map(\.title))
            }
        }
        return allowed
    }

    // MARK: - Recognition

    private static func edition(title: String, label explicit: String?) -> Edition? {
        if let label = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            guard let order = order(of: label) else { return nil }
            return Edition(title: title, label: label, order: order)
        }
        guard let year = years(in: title).last else { return nil }
        return Edition(title: title, label: String(year), order: year)
    }

    /// A year in the label, else its first number ("3rd edition" → 3, "Rev 2" → 2), else a
    /// revision letter ("Rev C" → 3).
    private static func order(of label: String) -> Int? {
        if let year = years(in: label).last { return year }
        if let r = label.range(of: #"\d+"#, options: .regularExpression) { return Int(label[r]) }
        if let r = label.range(of: #"(?i)\brev(?:ision)?\.?\s*([A-Z])\b"#, options: .regularExpression),
           let letter = label[r].last, letter.isLetter {
            return Int(letter.uppercased().unicodeScalars.first!.value) - 64
        }
        return nil
    }

    private static func years(in text: String) -> [Int] {
        let ns = text as NSString
        let rx = try! NSRegularExpression(pattern: #"(?<![\p{N}])(19|20)\d{2}(?![\p{N}])"#)
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range)) }
    }

    /// The title with its edition label and edition words taken out, lowercased.
    private static func workKey(_ title: String, label: String) -> String {
        var t = title.lowercased()
        t = t.replacingOccurrences(of: label.lowercased(), with: " ")
        t = t.replacingOccurrences(of: #"(?<![\p{N}])(19|20)\d{2}(?![\p{N}])"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\b(\d+(st|nd|rd|th)\s+)?(edition|ed\.|revision|rev\.?|version)\b"#,
                                   with: " ", options: .regularExpression)
        return t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    static func sameLabel(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }
}

/// Which edition a turn asks for (Plan IV P2, decided with the partner who supplied the code
/// books): the newest by default; an older one only when the turn names it by year or label, or
/// says "the previous edition", "the old code" or "the last code"; every edition when it asks what
/// changed or to compare. Plan IN P4's edition compare builds on `.compare`.
enum EditionRequest: Equatable {
    case newest
    case named(Set<String>)
    case previous
    case compare

    /// Read off what was said (the technician's turn, a lookup's query, or both). `editions` gives
    /// the labels a turn can name; without editions every turn is `.newest`.
    static func parse(_ text: String?, editions: DocumentEditions) -> EditionRequest {
        guard !editions.isEmpty, let text, !text.isEmpty else { return .newest }
        let said = " " + text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "'", with: "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ") + " "

        let labels = Set(editions.works.flatMap { $0.map(\.label) })
        let spoken = labels.filter { said.contains(" " + $0.lowercased() + " ") }

        if changePhrases.contains(where: { said.contains(" \($0) ") }) { return .compare }
        if comparePhrases.contains(where: { said.contains(" \($0) ") }),
           !spoken.isEmpty || editionWords.contains(where: { said.contains(" \($0) ") }) {
            return .compare
        }
        if spoken.count > 1 { return .named(spoken) }
        if previousPhrases.contains(where: { said.contains(" \($0) ") }) { return .previous }
        // Naming the newest edition asks for nothing the default doesn't give.
        let newest = Set(editions.works.map { $0[0].label.lowercased() })
        let older = spoken.filter { !newest.contains($0.lowercased()) }
        return older.isEmpty ? .newest : .named(older)
    }

    /// Whether the turn reaches past the default, so passages are labelled with their edition.
    var reachesOlderEditions: Bool { self != .newest }

    private static let changePhrases = [
        "what changed", "whats changed", "what has changed", "what have they changed", "whats different",
        "what is different", "difference between", "differences between", "changes between", "changed between",
        "changed since", "changed from", "change from the", "changes from the",
    ]
    private static let comparePhrases = ["compare", "comparison", "versus", "vs", "against the"]
    private static let editionWords = ["edition", "editions", "code", "codes", "version", "versions", "revision", "revisions"]
    private static let previousPhrases = [
        "previous edition", "previous code", "previous version", "previous revision", "older edition",
        "old edition", "old code", "older code", "last code", "last edition", "earlier edition", "prior edition",
        "former edition", "superseded edition", "superseded code", "the old one", "older version", "old version",
    ]
}
