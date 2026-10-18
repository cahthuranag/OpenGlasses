import XCTest
@testable import OpenGlasses

/// Six passages where a passage is one clause, four everywhere else (Plan IV P6). Every document,
/// number and sentence here is invented.
@MainActor
final class ManualPassageLimitTests: XCTestCase {

    private let limit = ManualPassageLimit()

    private func passage(_ doc: String, _ index: Int, source: RetrievalSource = .manual,
                         text: String = "x", section: String? = nil) -> VaultRetriever.Passage {
        VaultRetriever.Passage(documentId: doc, documentName: doc, chunkIndex: index, text: text, page: index + 1,
                               section: section, similarity: 0.9, score: 0.9, matchedTokens: [], source: source)
    }

    private func six(from doc: String) -> [VaultRetriever.Passage] { (0..<6).map { passage(doc, $0) } }

    func testTheRetrieverIsAskedForSixOnlyWhenAClauseNumberedManualCanBeSearched() {
        XCTAssertEqual(limit.requestLimit(searchesClauseNumbered: false), 4)
        XCTAssertEqual(limit.requestLimit(searchesClauseNumbered: true), 6)
    }

    func testSixAreKeptWhenTheBestPassageIsFromAClauseNumberedDocument() {
        let outcome = RetrievalOutcome.sufficient(six(from: "rules"))
        XCTAssertEqual(limit.shaped(outcome, isClauseNumbered: { $0 == "rules" }).passages.count, 6)
    }

    func testAProsePassageFirstCutsToFour() {
        let mixed = [passage("guide", 0)] + six(from: "rules").prefix(5)
        let shaped = limit.shaped(.sufficient(mixed), isClauseNumbered: { $0 == "rules" })
        XCTAssertEqual(shaped.passages.map(\.documentId), ["guide", "rules", "rules", "rules"])
        XCTAssertTrue(shaped.isSufficient)
    }

    func testTheBestManualPassageDecidesWhenALearningLeads() {
        let learning = passage("crew", 0, source: .teamLearning)
        let shaped = limit.shaped(.sufficient([learning] + six(from: "rules").prefix(5)), isClauseNumbered: { $0 == "rules" })
        XCTAssertEqual(shaped.passages.count, 6)
    }

    func testACutStillCarriesAManualPassage() {
        let learnings = (0..<4).map { passage("crew\($0)", 0, source: .teamLearning) }
        let shaped = limit.shaped(.sufficient(learnings + [passage("guide", 0), passage("guide", 1)]),
                                  isClauseNumbered: { _ in false })
        XCTAssertEqual(shaped.passages.count, 4)
        XCTAssertEqual(shaped.passages.last?.documentId, "guide", "the last kept slot gives way to the best manual passage")
        XCTAssertTrue(shaped.isSufficient)
    }

    func testFewPassagesAndRefusalsAreUntouched() {
        let three = RetrievalOutcome.sufficient(Array(six(from: "guide").prefix(3)))
        XCTAssertEqual(limit.shaped(three, isClauseNumbered: { _ in false }), three)
        let refused = RetrievalOutcome.insufficient(reason: RetrievalEvidencePolicy.insufficientSentence)
        XCTAssertEqual(limit.shaped(refused, isClauseNumbered: { _ in false }), refused)
    }

    /// Six of the longest chunks the chunker makes, with long citations, fit the passage budget the
    /// turn block and the lookup result share — nothing is dropped and no omission notice appears.
    func testSixOfTheLongestPassagesFitTheBudget() {
        let longest = String(repeating: "Keep the grey lid closed. ", count: 40).prefix(DocumentChunker().maxChars)
        let passages = (0..<6).map { i in
            passage("A very long invented rule book title for the budget check, part \(i)", i,
                    text: String(longest), section: "\(40 + i)-\(100 + i) Example heading for budget case \(i)")
        }
        let bounded = VaultRetriever.boundedOutcome(.sufficient(passages), characterLimit: 12_000)
        XCTAssertEqual(bounded.outcome.passages.count, 6)
        XCTAssertEqual(bounded.notice, "")
        XCTAssertFalse(VaultRetriever.promptBlock(.sufficient(passages)).contains("omitted by the context budget"))
        XCTAssertFalse(VaultRetriever.toolResult(.sufficient(passages), query: "lid").contains("omitted by the context budget"))
    }

    // MARK: - Reading a stored document's shape

    private func makeStore() -> (DocumentStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ManualPassageLimitTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (DocumentStore(directory: dir), dir)
    }

    /// `rules` invented clauses, each a group heading, a numbered heading line and two sentences.
    static func clauseNumberedBook(rules: Int = 14) -> String {
        (0..<rules).map { i in
            """
            Page \(i + 1)

            Group \(["Alpha", "Bravo", "Charlie", "Delta"][i % 4])
            \(40 + i / 10)-\(100 + i * 2) Example heading number \(i)
            The panel for case \(i) has a \(i % 2 == 0 ? "grey" : "white") lid. Mark it with tag \(i) before you leave the site.
            """
        }.joined(separator: "\n\n")
    }

    /// A prose manual: numbered steps and readings, no clause headings.
    static func proseManual(pages: Int = 24) -> String {
        (1...pages).map { n in
            """
            Page \(n)

            Step \(n). Turn the blue dial to \(n).5 and wait two minutes for the green lamp. \
            If the lamp stays dark, open the side cover and check the small fuse marked F\(n). \
            Write the reading on the job card before you close the cover again.
            """
        }.joined(separator: "\n\n")
    }

    func testTheStoreReadsTheShapeFromStoredText() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ingestedRules = await store.ingest(name: "Rules", text: Self.clauseNumberedBook())
        let ingestedGuide = await store.ingest(name: "Guide", text: Self.proseManual())
        let rules = try XCTUnwrap(ingestedRules), guide = try XCTUnwrap(ingestedGuide)
        XCTAssertTrue(store.isClauseNumbered(documentId: rules.id))
        XCTAssertFalse(store.isClauseNumbered(documentId: guide.id))
        XCTAssertFalse(store.isClauseNumbered(documentId: "missing"))
        XCTAssertFalse(DocumentChunker.isClauseNumbered(Self.clauseNumberedBook(rules: DocumentChunker.minimumClauseHeadings - 1)))
    }
}
