import XCTest
@testable import OpenGlasses

/// Plan IN P3a — clause numbers in a code book are found by number, the clause's own text first.
@MainActor
final class ClauseReferenceTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClauseReferenceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - Recognition

    func testRecognisesTheShapesCodeBooksPrint() {
        XCTAssertEqual(ClauseReference.references(in: "what does clause 3.9.4.2 say"), ["3.9.4.2"])
        XCTAssertEqual(ClauseReference.references(in: "what does 3.9.4.2 say"), ["3.9.4.2"],
                       "two dots is never a reading, so no clause word is needed")
        XCTAssertEqual(ClauseReference.references(in: "rule 26-700 for grounding"), ["26-700"])
        XCTAssertEqual(ClauseReference.references(in: "what's in 26-700"), ["26-700"])
        XCTAssertEqual(ClauseReference.references(in: "Section 110.26 working space"), ["110.26"])
        XCTAssertEqual(ClauseReference.references(in: "§ 210.8 GFCI"), ["210.8"])
        XCTAssertEqual(ClauseReference.references(in: "does 210.8(A) cover garages"), ["210.8"])
        XCTAssertEqual(ClauseReference.references(in: "clauses 3.9.4 and 3.9.5, and clause 3.9.4 again"),
                       ["3.9.4", "3.9.5"])
        XCTAssertEqual(ClauseReference.references(in: "rule 26\u{2013}700"), ["26-700"], "an en dash is a hyphen")
    }

    func testSpokenSeparatorsAreJoined() {
        XCTAssertEqual(ClauseReference.references(in: "clause 3 point 9 point 4 point 2"), ["3.9.4.2"])
        XCTAssertEqual(ClauseReference.references(in: "rule 26 dash 700"), ["26-700"])
    }

    func testReadingsModelsRangesAndDatesAreNotClauses() {
        XCTAssertEqual(ClauseReference.references(in: "pressure reads 0.28"), [])
        XCTAssertEqual(ClauseReference.references(in: "it measured 110.26 volts"), [],
                       "one dot without a clause word is a measurement")
        XCTAssertEqual(ClauseReference.references(in: "208-230 volt units"), [])
        XCTAssertEqual(ClauseReference.references(in: "Model 30RB-060 Carrier fault E5"), [])
        XCTAssertEqual(ClauseReference.references(in: "installed 2026-10-17"), [])
        XCTAssertEqual(ClauseReference.references(in: "Table 3.4 and Figure 3.2"), [],
                       "tables and figures are found by caption")
    }

    func testClausePiecesStayOutOfTheTokenBoost() {
        let stripped = ClauseReference.removingReferences(from: "rule 26-700 and fault E5")
        XCTAssertEqual(CodeTokenizer.codeTokens(from: stripped), ["E5"])
        XCTAssertEqual(ClauseReference.removingReferences(from: "fault E5 on 30RB-060"), "fault E5 on 30RB-060")
    }

    // MARK: - Matching

    func testAHeadingStartsTheClause() {
        let text = "3.9.4.2 Protection against mechanical damage\nCables installed where exposed shall be enclosed."
        XCTAssertEqual(ClauseReference.match("3.9.4.2", in: text), .starts)
        XCTAssertEqual(ClauseReference.match("3.9.4.2", in: "## 3.9.4.2 Protection against mechanical damage"), .starts)
        XCTAssertEqual(ClauseReference.match("3.9.4.2",
                       in: "Earlier text ends here. 3.9.4.2 Protection against mechanical damage applies."),
                       .starts, "chunks join sentences with spaces, so a sentence boundary counts as a line start")
        XCTAssertEqual(ClauseReference.match("26-700", in: "26-700 General\n(1) This Subsection applies"), .starts)
        XCTAssertEqual(ClauseReference.match("3.9.4", in: text), .startsSubclause)
    }

    func testACitationOnlyCites() {
        XCTAssertEqual(ClauseReference.match("3.9.4.2", in: "Cables shall comply with Clause 3.9.4.2, and"), .cites)
        XCTAssertEqual(ClauseReference.match("26-700", in: "Rule 26-700 requires bonding"), .cites)
        XCTAssertEqual(ClauseReference.match("3.9.4.2", in: "Shall comply. 3.9.4.2 and 3.9.4.3 both apply."), .cites,
                       "a number at a sentence start followed by lower case is a reference, not a heading")
    }

    func testNumberBoundaries() {
        XCTAssertNil(ClauseReference.match("3.9.4.2", in: "see 13.9.4.2 Foo"))
        XCTAssertNil(ClauseReference.match("3.9.4.2", in: "see 2.3.9.4.2 Foo"))
        XCTAssertNil(ClauseReference.match("3.9.4", in: "see 3.9.40 Foo"))
        XCTAssertNil(ClauseReference.match("26-700", in: "see 126-700 and 26-7001"))
        XCTAssertEqual(ClauseReference.match("3.9.4", in: "see 3.9.4.2 for detail"), .cites,
                       "a subclause of it is still about it")
        XCTAssertEqual(ClauseReference.match("3.9.4.2", in: "Clause 3.9.4.2."), .cites)
    }

    func testContentsPagesCiteRatherThanStart() {
        let contents = "Contents 3.9.4.1 General 110 3.9.4.2 Protection against mechanical damage 112 "
            + "3.9.4.3 Enclosure 113 3.9.5 Wiring systems 114"
        XCTAssertEqual(ClauseReference.match("3.9.4.2", in: contents), .cites)
        let leaders = "3.9.4.2 Protection against mechanical damage ........ 112\n3.9.4.3 Enclosure ........ 113"
        XCTAssertEqual(ClauseReference.match("3.9.4.2", in: leaders), .cites)
    }

    func testAHeadingAtTheTopOutranksOneAtTheTail() {
        XCTAssertLessThan(ClauseReference.offset(of: ["3.9.4.2"], in: "3.9.4.2 Protection. Cables shall…"),
                          ClauseReference.offset(of: ["3.9.4.2"], in: "Earlier text. 3.9.4.2 Protection"))
        XCTAssertEqual(ClauseReference.offset(of: ["3.9.4.2"], in: "nothing here"), .max)
    }

    func testTheClauseSectionCarriesItsTextOn() {
        XCTAssertEqual(ClauseReference.match("3.9.4.2", in: "Heavy-duty conduit shall be used.",
                                             section: "3.9.4.2 Protection against mechanical damage"),
                       .continues)
        XCTAssertNil(ClauseReference.match("3.9.4.2", in: "Heavy-duty conduit shall be used.",
                                           section: "3.9.4.20 Something else"))
    }

    // MARK: - The store and the retriever

    /// A code book that cross-references clause 3.9.4.2 on thirty pages before the clause itself,
    /// with a contents page in front — the shape that hid the clause behind the token search's
    /// document-order limit.
    private static func codeBook() -> String {
        var pages = ["Contents\n3.9.4.1 General 110\n3.9.4.2 Protection against mechanical damage 112\n"
                     + "3.9.4.3 Enclosure 113\n3.9.5 Wiring systems 114"]
        for n in 1...30 {
            pages.append("Installation note \(n). Wiring in area \(n) shall be supported at suitable intervals "
                         + "and, where exposed, shall comply with Clause 3.9.4.2. Fixings shall suit the surface "
                         + "and the load, and the installer shall record the method used for area \(n).")
        }
        pages.append("3.9.4.2 Protection against mechanical damage\nCables installed in locations where they "
                     + "are exposed to mechanical damage shall be protected by an enclosure, by barriers, or by "
                     + "installation in a position that avoids the damage. "
                     + String(repeating: "The protection shall be suited to the severity of the damage expected in "
                              + "the location and shall remain effective for the life of the installation. ",
                              count: 6)
                     + "Protection shall extend at least 150 mm above the floor.")
        pages.append("Where heavy-duty conduit is used as the enclosure it shall be continuous over the exposed "
                     + "length.\n3.9.4.3 Enclosure\nAn enclosure shall be of a material suited to the location.")
        return pages.joined(separator: "\u{0C}")
    }

    private func makeStore() async -> (DocumentStore, String) {
        let dir = tempRoot.appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: dir)
        let namespace = DocumentStore.vaultNamespace("code_book")
        _ = await store.ingest(name: "Wiring Rules", text: Self.codeBook(), namespace: namespace)
        return (store, namespace)
    }

    private static let clauseText = "exposed to mechanical damage shall be protected"

    func testTheStorePutsTheClauseAheadOfItsCitations() async {
        let (store, namespace) = await makeStore()
        // The clause is cited on more chunks than any search limit, so document order alone never
        // reaches it.
        let byToken = store.passages(containingToken: "3.9.4.2", namespace: namespace, limit: 8)
        XCTAssertFalse(byToken.contains { $0.text.contains(Self.clauseText) },
                       "fixture must reproduce the bug it guards")

        let found = store.passages(clause: "3.9.4.2", namespace: namespace, limit: 8)
        XCTAssertEqual(found.first?.clauseMatch, .starts)
        XCTAssertTrue(found.first?.text.contains(Self.clauseText) == true)
        XCTAssertTrue(found.contains { $0.clauseMatch == .continues },
                      "the chunk after the heading carries the clause on")
        XCTAssertTrue(found.prefix(3).contains { $0.clauseMatch == .continues })
        XCTAssertFalse(found.prefix(2).contains { $0.text.contains("Contents") }, "the contents page is a citation")
    }

    func testTheRetrieverAnswersAClauseQuestionWithTheClause() async {
        let (store, namespace) = await makeStore()
        var tokensSearched: [String] = []
        let retriever = VaultRetriever(
            query: { _, _ in [] },
            tokenSearch: { token, limit in
                tokensSearched.append(token)
                return store.passages(containingToken: token, namespace: namespace, limit: limit)
            },
            clauseSearch: { clause, limit in store.passages(clause: clause, namespace: namespace, limit: limit) })

        let outcome = retriever.retrieve(.init(turn: "what does clause 3.9.4.2 say", limit: 4))
        XCTAssertTrue(outcome.answers)
        XCTAssertTrue(outcome.passages.first?.text.contains(Self.clauseText) == true)
        XCTAssertEqual(outcome.passages.first?.matchedTokens, ["3.9.4.2"])
        XCTAssertEqual(outcome.passages.first?.clauseMatch, .starts)
        XCTAssertTrue(outcome.passages.contains { $0.clauseMatch == .continues })
        XCTAssertFalse(outcome.passages.contains { $0.clauseMatch == .cites && $0.text.contains("Contents") })

        _ = retriever.retrieve(.init(turn: "rule 26-700 bonding", limit: 4))
        XCTAssertFalse(tokensSearched.contains("26") || tokensSearched.contains("700"),
                       "a rule number's pieces are not searched as codes")
    }

    func testWithoutAClauseTheOrderingIsUnchanged() {
        func raw(_ index: Int, _ text: String, _ similarity: Float) -> DocumentStore.Passage {
            DocumentStore.Passage(documentId: "d", documentName: "Manual", chunkIndex: index, text: text,
                                  similarity: similarity, page: index, section: nil)
        }
        let retriever = VaultRetriever(query: { _, _ in
            [raw(1, "The pressure switch opens on low suction.", 0.9), raw(2, "Fault E5 means low pressure.", 0.4)]
        })
        let outcome = retriever.retrieve(.init(turn: "fault E5 pressure switch", limit: 2))
        XCTAssertEqual(outcome.passages.map(\.chunkIndex), [2, 1], "an exact code hit still leads")
        XCTAssertNil(outcome.passages.first?.clauseMatch)
    }
}
