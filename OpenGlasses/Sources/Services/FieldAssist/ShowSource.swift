import Foundation
import UIKit
import UserNotifications

// "Show me the page", "show me the relevant pages" (Plan IN P2).
//
// The partner's electrician keeps the phone in a pocket: the spoken answer with its clause is
// usually enough, and when he wants to check he says "show me the page". Before this, the model
// could only reach a page through `manual_figure(page:)`, and a bare page number was looked up in
// every manual — with two code books loaded it opened the right page number in the wrong book.
// Here "show me" resolves against the citations of the answer he just heard, by document and page,
// and never searches for a page number at all (decision 2).

// MARK: - What the last answer cited

/// The sources the most recent answer cited, kept per session so "show me the second one" still
/// works after a follow-up that cited nothing.
///
/// Two inputs, because the modes differ. In Direct mode the answer's own text is parsed for its
/// `Source:` lines (`CitationLineParser`) and that is authoritative. The live modes (Gemini Live,
/// OpenAI Realtime) give the app no answer text with sources in it, so what `manual_lookup` returned
/// stands in for it — provisionally, until an answer that cites something replaces it. Pure.
struct AnswerSourceMemory: Equatable {

    /// A passage a retrieval returned this session, so a cited page can be marked with the passage
    /// that was actually given to the model.
    struct Retrieved: Equatable, Hashable {
        let documentId: String
        let documentName: String
        let chunkIndex: Int
        let page: Int?
        let section: String?
        let text: String
    }

    private(set) var sessionId: String?
    private(set) var confirmed: [Citation] = []
    private(set) var provisional: [Citation]?
    private(set) var retrieved: [Retrieved] = []

    /// How many retrieved passages are kept. A few turns' worth: enough to mark what was cited a
    /// question or two ago, not a record of the job.
    static let retainedPassages = 32

    /// The last answer's manual citations, in the order it gave them.
    var citations: [Citation] { provisional ?? confirmed }

    /// A retrieval ran (the per-turn block or `manual_lookup`). Remembers its passages; says
    /// nothing about what was cited.
    mutating func noteRetrieved(_ passages: [Retrieved], sessionId: String?) {
        adopt(sessionId)
        guard !passages.isEmpty else { return }
        var seen = Set<Retrieved>()
        retrieved = Array((passages + retrieved).filter { seen.insert($0).inserted }.prefix(Self.retainedPassages))
    }

    /// `manual_lookup` answered: its sources stand for the answer until one that cites replaces
    /// them. An empty lookup changes nothing.
    mutating func noteLookup(_ passages: [Retrieved], sessionId: String?) {
        noteRetrieved(passages, sessionId: sessionId)
        let cited = Self.citations(from: passages)
        if !cited.isEmpty { provisional = cited }
    }

    /// A Direct-mode answer finished. One that cites manuals becomes the answer "show me" refers
    /// to; one that cites nothing leaves the previous answer's sources where they were.
    mutating func noteAnswer(_ citations: [Citation], sessionId: String?) {
        adopt(sessionId)
        let manual = Self.unique(citations.filter { $0.kind == .manual && $0.page != nil })
        provisional = nil
        if !manual.isEmpty { confirmed = manual }
    }

    /// The passages behind a citation: same manual, on a page the citation names.
    func retrieved(for citation: Citation) -> [Retrieved] {
        guard let page = citation.page else { return [] }
        let last = citation.throughPage ?? page
        let title = citation.title.lowercased()
        return retrieved.filter {
            $0.documentName.lowercased() == title && ($0.page.map { (page...last).contains($0) } ?? false)
        }
        .sorted { ($0.page ?? 0, $0.chunkIndex) < ($1.page ?? 0, $1.chunkIndex) }
    }

    static func citations(from passages: [Retrieved]) -> [Citation] {
        unique(passages.compactMap { passage in
            passage.page.map { Citation(kind: .manual, title: passage.documentName, page: $0, section: passage.section) }
        })
    }

    /// One citation per manual page, first mention first.
    private static func unique(_ citations: [Citation]) -> [Citation] {
        var seen = Set<String>()
        return citations.filter { seen.insert("\($0.title.lowercased())#\($0.page ?? 0)").inserted }
    }

    private mutating func adopt(_ id: String?) {
        guard id != sessionId else { return }
        self = AnswerSourceMemory()
        sessionId = id
    }
}

// MARK: - Which source "show me" means

/// Turns `which` and `document` into the cited sources to open. Pure.
enum ShowSourceResolver {

    struct Source: Equatable {
        /// The citation's place in the answer, 1-based — the number its mark carries.
        let number: Int
        let citation: Citation
    }

    enum Outcome: Equatable {
        case sources([Source])
        /// What to tell the model instead. Nothing opens.
        case problem(String)
    }

    /// The most pages "all" opens in one sheet.
    static let maximumPages = 6

    private static let ordinals: [String: Int] = [
        "first": 1, "one": 1, "1": 1, "1st": 1,
        "second": 2, "two": 2, "2": 2, "2nd": 2,
        "third": 3, "three": 3, "3": 3, "3rd": 3,
        "fourth": 4, "four": 4, "4": 4, "4th": 4,
        "fifth": 5, "five": 5, "5": 5, "5th": 5,
        "sixth": 6, "six": 6, "6": 6, "6th": 6,
    ]
    private static let allWords: Set<String> = ["all", "every", "relevant", "both", "them", "pages", "sources"]

    static func resolve(which rawWhich: String?, document: String?, memory: AnswerSourceMemory) -> Outcome {
        let all = memory.citations.enumerated().map { Source(number: $0.offset + 1, citation: $0.element) }
        guard !all.isEmpty else {
            return .problem("No answer in this job has cited a manual page yet, so there is no page to show. "
                + "Search with manual_lookup first. Nothing was opened.")
        }
        var pool = all
        if let document = document?.trimmingCharacters(in: .whitespacesAndNewlines), !document.isEmpty {
            // A title that holds the words as written wins over a looser match: "book a" is in
            // "Code Book A", and every word but "a" is in "Code Book B" as well.
            let exact = all.filter { $0.citation.title.localizedCaseInsensitiveContains(document) }
            pool = exact.isEmpty ? all.filter { ManualDocumentChoice.matches($0.citation.title, requested: document) } : exact
            guard !pool.isEmpty else {
                return .problem("The last answer did not cite a manual called \"\(document)\". It cited "
                    + titles(all) + ". Nothing was opened.")
            }
        }
        let which = (rawWhich ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = which.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)

        // A clause number: the cited source that holds it.
        if let clause = ClauseReference.references(in: which).first {
            let holding = pool.filter { source in
                if let section = source.citation.section,
                   (ClauseReference.match(clause, in: section, section: section) ?? .cites) >= .startsSubclause {
                    return true
                }
                return memory.retrieved(for: source.citation).contains {
                    (ClauseReference.match(clause, in: $0.text, section: $0.section) ?? .cites) >= .continues
                }
            }
            guard !holding.isEmpty else {
                return .problem("The last answer did not cite clause \(clause). It cited "
                    + labels(pool) + ". Nothing was opened.")
            }
            return .sources(Array(holding.prefix(maximumPages)))
        }
        if words.contains(where: allWords.contains) {
            return .sources(Array(pool.prefix(maximumPages)))
        }
        if words.contains("last") || words.contains("latest") {
            return .sources([pool[pool.count - 1]])
        }
        if let ordinal = words.lazy.compactMap({ ordinals[$0] }).first {
            // With a manual named, "the second one" counts within that manual's sources.
            let numbered = pool
            guard ordinal <= numbered.count else {
                return .problem("The last answer cited \(numbered.count) source\(numbered.count == 1 ? "" : "s"): "
                    + labels(numbered) + ". Nothing was opened.")
            }
            return .sources([numbered[ordinal - 1]])
        }
        // "The page", "it", "that", or nothing: the first source the answer cited.
        return .sources([pool[0]])
    }

    private static func titles(_ sources: [Source]) -> String {
        var seen = Set<String>()
        return sources.map(\.citation.title).filter { seen.insert($0).inserted }.joined(separator: "; ")
    }

    private static func labels(_ sources: [Source]) -> String {
        sources.map { "\($0.number). \($0.citation.label)" }.joined(separator: "; ")
    }
}

// MARK: - Putting the pages on the phone

/// A set of cited pages for the sheet.
struct SourcePagesRequest: Equatable, Identifiable {
    let id = UUID()
    let pages: [FieldSessionService.StagedFigure]
}

/// Holds the answer's sources for the session and puts the pages `show_source` resolved in front of
/// the technician — now when the app is in front, or as soon as it is when the phone is locked or
/// the app is in the background, with a notification saying where the page is. Nothing here claims
/// a page is on screen when it is not.
@MainActor
final class ShowSourceCenter: ObservableObject {

    static let shared = ShowSourceCenter()

    private(set) var memory = AnswerSourceMemory()
    /// The request the app should present now.
    @Published private(set) var presented: SourcePagesRequest?
    /// A request made while the app could not show it.
    private(set) var waiting: SourcePagesRequest?

    /// Seams for the tests: whether the app is in front, and how a waiting page is announced.
    var isAppActive: () -> Bool = { UIApplication.shared.applicationState == .active }
    var announce: (String) -> Void = ShowSourceCenter.postNotification

    private var activeObserver: NSObjectProtocol?

    init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appBecameActive() }
        }
    }

    // MARK: Memory

    func noteRetrieved(_ passages: [VaultRetriever.Passage], sessionId: String?) {
        memory.noteRetrieved(passages.compactMap(Self.retrieved), sessionId: sessionId)
    }

    func noteLookup(_ passages: [VaultRetriever.Passage], sessionId: String?) {
        memory.noteLookup(passages.compactMap(Self.retrieved), sessionId: sessionId)
    }

    func noteAnswer(_ text: String, sessionId: String?) {
        memory.noteAnswer(CitationLineParser.parse(text), sessionId: sessionId)
    }

    /// The cited passages to mark for a citation opened in `documentId`, numbered as the answer
    /// numbered the citation (or 1 when it is not in the last answer — a chip on an older answer).
    func citedPassages(for citation: Citation, documentId: String, store: DocumentStore?,
                       number: Int? = nil) -> [CitedPassage] {
        guard let store else { return [] }
        let position = number ?? (memory.citations.firstIndex {
            $0.title.lowercased() == citation.title.lowercased() && $0.page == citation.page
        }.map { $0 + 1 } ?? 1)
        return memory.retrieved(for: citation)
            .filter { $0.documentId == documentId }
            .compactMap { store.anchor(documentId: $0.documentId, chunkIndex: $0.chunkIndex) }
            .map { CitedPassage(number: position, anchor: $0) }
    }

    // MARK: Presenting

    /// Put `pages` on the phone. Returns true when they are on screen now; false when they are
    /// waiting for the app to come to the front, in which case `notice` has been announced.
    @discardableResult
    func present(_ pages: [FieldSessionService.StagedFigure], notice: String) -> Bool {
        guard !pages.isEmpty else { return false }
        let request = SourcePagesRequest(pages: pages)
        if isAppActive() {
            waiting = nil
            presented = request
            return true
        }
        waiting = request
        announce(notice)
        return false
    }

    /// The app came to the front — by the notification's tap or any other way. A waiting page opens.
    func appBecameActive() {
        guard let waiting else { return }
        self.waiting = nil
        presented = waiting
    }

    // MARK: Helpers

    private static func retrieved(_ passage: VaultRetriever.Passage) -> AnswerSourceMemory.Retrieved? {
        guard passage.source == .manual || passage.source == .capturedManual else { return nil }
        return .init(documentId: passage.documentId, documentName: passage.documentName,
                     chunkIndex: passage.chunkIndex, page: passage.page, section: passage.section,
                     text: passage.text)
    }

    /// "AS/NZS 3000, page 112, §3.9.4.2 — tap to open". The citation is the vault's own label; no
    /// passage text goes on the lock screen.
    static func noticeText(for citation: Citation) -> String {
        "\(citation.label) — tap to open"
    }

    private static func postNotification(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Manual page ready"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "show-source-page", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
