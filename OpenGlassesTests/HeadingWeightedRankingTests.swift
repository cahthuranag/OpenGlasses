import XCTest
@testable import OpenGlasses

/// BM25F inside the ranking groups, a heading's words weighted three times a body word's (Plan IV
/// P7), and the term statistics the store derives for it. Every document, number and sentence here
/// is invented.
@MainActor
final class HeadingWeightedRankingTests: XCTestCase {

    private func raw(_ doc: String, _ index: Int, _ text: String, section: String? = nil,
                     similarity: Float = 0.5) -> DocumentStore.Passage {
        DocumentStore.Passage(documentId: doc, documentName: doc, chunkIndex: index, text: text,
                              similarity: similarity, page: index + 1, section: section)
    }

    private func statistics(_ chunks: [(String, String?)]) -> LexicalSupport.TermStatistics {
        chunks.reduce(into: LexicalSupport.TermStatistics()) { $0.add(text: $1.0, heading: $1.1) }
    }

    /// A corpus where "panel" and "cover" are on every page and "hinge" on two.
    private var corpus: LexicalSupport.TermStatistics {
        statistics((0..<20).map { i in
            ("Open the panel cover and read dial \(i).", i == 7 ? "Hinge care" : "Dial \(i)")
        } + [("Oil the hinge once a year.", nil)])
    }

    // MARK: - The statistics

    func testTermCountsKeepTheRepeatsContentTermsCollapses() {
        let text = "Check the hinges. The hinge pins and the hinge cover, then the latch."
        let counted = LexicalSupport.termCounts(text)
        XCTAssertEqual(Set(counted.counts.keys), LexicalSupport.contentTerms(text))
        XCTAssertEqual(counted.counts["hinge"], 3)
        XCTAssertEqual(counted.length, counted.counts.values.reduce(0, +))
    }

    func testStatisticsCountChunksNotOccurrencesAndAdd() {
        let a = statistics([("hinge hinge hinge", "Hinge care"), ("latch", nil)])
        XCTAssertEqual(a.chunkCount, 2)
        XCTAssertEqual(a.documentFrequency["hinge"], 1, "a chunk counts once, body and heading together")
        XCTAssertEqual(a.bodyLength, 4)
        XCTAssertEqual(a.headingLength, 2)
        let b = statistics([("hinge latch", "Latch care")])
        let both = statistics([("hinge hinge hinge", "Hinge care"), ("latch", nil), ("hinge latch", "Latch care")])
        XCTAssertEqual(a + b, both)
    }

    func testARareSharedWordOutweighsTwoWordsOnEveryPage() {
        let terms = LexicalSupport.contentTerms("panel cover hinge")
        let common = corpus.score(queryTerms: terms, text: "Lift the panel cover off.", heading: nil)
        let rare = corpus.score(queryTerms: terms, text: "Oil the hinge once a year.", heading: nil)
        XCTAssertGreaterThan(rare, common)
        XCTAssertEqual(corpus.score(queryTerms: [], text: "hinge", heading: "Hinge"), 0)
        XCTAssertEqual(corpus.score(queryTerms: terms, text: "Nothing shared here.", heading: nil), 0)
    }

    func testAHeadingWordCountsMoreThanTheSameWordInTheBody() {
        let terms: Set<String> = ["hinge"]
        let inHeading = corpus.score(queryTerms: terms, text: "Oil it once a year.", heading: "Hinge care")
        let inBody = corpus.score(queryTerms: terms, text: "Oil the hinge once a year.", heading: "Care")
        XCTAssertGreaterThan(inHeading, inBody)
        XCTAssertEqual(corpus.score(queryTerms: terms, text: "Oil it once a year.", heading: "Hinge care", headingWeight: 0), 0)
    }

    // MARK: - The order inside a group

    private func retriever(_ passages: [DocumentStore.Passage], statistics: LexicalSupport.TermStatistics?,
                           tokenHits: [DocumentStore.Passage] = []) -> VaultRetriever {
        VaultRetriever(query: { _, _ in passages },
                       tokenSearch: { token, _ in tokenHits.filter { CodeTokenizer.contains($0.text, token: token) } },
                       termStatistics: statistics == nil ? nil : { statistics },
                       policy: RetrievalEvidencePolicy(similarityFloor: 0))
    }

    func testTheHeadingThatNamesTheSubjectLeadsWhereACountTies() {
        // Both share the one content word; the count cannot tell them apart and the score puts the
        // passing mention first.
        let passing = raw("a-guide", 0, "Wipe the hinge when you clean the panel.", section: "Cleaning", similarity: 0.6)
        let named = raw("b-guide", 1, "Oil it once a year with light oil.", section: "Hinge care", similarity: 0.5)
        let request = VaultRetriever.Request(turn: "hinge", limit: 2)
        XCTAssertEqual(retriever([passing, named], statistics: nil).retrieve(request).passages.map(\.documentId),
                       ["a-guide", "b-guide"], "without statistics: shared words, then score, as before")
        XCTAssertEqual(retriever([passing, named], statistics: corpus).retrieve(request).passages.map(\.documentId),
                       ["b-guide", "a-guide"])
    }

    func testTheRareWordBeatsTheCountOfCommonOnes() {
        let common = raw("a-guide", 0, "Lift the panel cover and set it down.", similarity: 0.5)
        let rare = raw("b-guide", 1, "Oil the hinge once a year.", similarity: 0.5)
        let request = VaultRetriever.Request(turn: "panel cover hinge", limit: 2)
        XCTAssertEqual(retriever([common, rare], statistics: nil).retrieve(request).passages.first?.documentId, "a-guide")
        XCTAssertEqual(retriever([common, rare], statistics: corpus).retrieve(request).passages.first?.documentId, "b-guide")
    }

    func testASpokenCodeStillLeadsWhateverTheWordsWeigh() {
        let row = raw("a-codes", 0, "QXRT 4 flashes", section: "Codes", similarity: 0.2)
        let prose = raw("b-guide", 1, "Hinge care: oil the hinge once a year.", section: "Hinge care", similarity: 0.9)
        let outcome = retriever([prose], statistics: corpus, tokenHits: [row])
            .retrieve(.init(turn: "QXRT hinge", limit: 2))
        XCTAssertEqual(outcome.passages.map(\.documentId), ["a-codes", "b-guide"])
    }

    // MARK: - The store's statistics

    private func makeStore() -> (DocumentStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HeadingWeightedRankingTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (DocumentStore(directory: dir), dir)
    }

    /// Twelve invented clauses with distinct headings; 99-212's heading names the latch, and two
    /// other clauses mention one in passing.
    private static let ruleBook: String = {
        let headings = ["Grey lids", "White lids", "Blue dials", "Green lamps", "Side covers", "Job cards",
                        "Latches", "Small fuses", "Tags", "Site exits", "Spare keys", "Labels"]
        return headings.enumerated().map { i, heading in
            let body = i == 6
                ? "Close it firmly by hand and test it twice."
                : "Keep the \(heading.lowercased()) clean and dry" + (i == 2 || i == 9 ? " and check the latch." : ".")
            return "Page \(i + 1)\n\n99-\(200 + i * 2) \(heading)\n\(body) Note it on the card for case \(i)."
        }.joined(separator: "\n\n")
    }()

    func testTheStoreDerivesStatisticsPerNamespaceAndCachesThem() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rulesNamespace = DocumentStore.vaultNamespace("rules"), guideNamespace = DocumentStore.vaultNamespace("guide")
        let ingestedRules = await store.ingest(name: "Rules", text: Self.ruleBook, namespace: rulesNamespace)
        let ingestedGuide = await store.ingest(name: "Guide", text: ManualPassageLimitTests.proseManual(),
                                               namespace: guideNamespace)
        let rules = try XCTUnwrap(ingestedRules), guide = try XCTUnwrap(ingestedGuide)
        XCTAssertTrue(store.isClauseNumbered(documentId: rules.id))
        XCTAssertFalse(store.isClauseNumbered(documentId: guide.id))

        let ruleStats = store.termStatistics(namespaces: [rulesNamespace])
        XCTAssertEqual(ruleStats.chunkCount, store.chunkCount(documentId: rules.id))
        XCTAssertGreaterThan(ruleStats.headingLength, 0, "clause headings are the heading field")
        XCTAssertEqual(store.termStatistics(namespaces: [rulesNamespace]), ruleStats, "read again from the cache")

        let guideStats = store.termStatistics(namespaces: [guideNamespace])
        XCTAssertEqual(guideStats.chunkCount, store.chunkCount(documentId: guide.id))
        XCTAssertEqual(store.termStatistics(namespaces: [rulesNamespace, guideNamespace]), ruleStats + guideStats)
        XCTAssertEqual(store.termStatistics(namespaces: nil), ruleStats + guideStats, "nil reads the whole store")

        // A manual added to the namespace moves the statistics; the other namespace's stay put.
        let ingestedMore = await store.ingest(name: "More rules", text: Self.ruleBook, namespace: rulesNamespace)
        let more = try XCTUnwrap(ingestedMore)
        let grown = store.termStatistics(namespaces: [rulesNamespace])
        XCTAssertEqual(grown.chunkCount, ruleStats.chunkCount + store.chunkCount(documentId: more.id))
        XCTAssertEqual(store.termStatistics(namespaces: [guideNamespace]), guideStats)
    }

    func testTheClauseWhoseHeadingNamesTheSubjectLeadsAClauseNumberedBook() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let namespace = DocumentStore.vaultNamespace("rules")
        let ingested = await store.ingest(name: "Rules", text: Self.ruleBook, namespace: namespace)
        _ = try XCTUnwrap(ingested)
        // The lexical route alone, so the embedder's similarities cannot decide the order.
        let retriever = VaultRetriever(
            query: { _, _ in [] },
            termSearch: { query, limit in store.passages(sharingTermsWith: query, limit: limit, namespace: namespace) },
            termStatistics: { store.termStatistics(namespaces: [namespace]) },
            policy: RetrievalEvidencePolicy(similarityFloor: 0))
        let passages = retriever.retrieve(.init(turn: "latch", limit: 3)).passages
        XCTAssertEqual(passages.count, 3, "the heading's clause and the two that mention a latch in passing")
        XCTAssertEqual(passages.first?.section?.hasPrefix("99-212"), true, "\(passages.map(\.section))")
    }
}
