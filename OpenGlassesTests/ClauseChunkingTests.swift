import XCTest
@testable import OpenGlasses

/// Line breaks kept between sentences, and chunks that start at a clause heading in a document
/// detected as clause-numbered (Plan IV P3). Every number, heading and sentence here is invented.
final class ClauseChunkingTests: XCTestCase {

    /// A rule printed on its own line under a one-word group heading.
    private let groupedRule = """
        Page 1

        Fittings
        41-310 Blue cover plates
        Fit the blue cover before the first power-up. Keep the spare in the lid pocket.
        """

    func testALineBreakBetweenSentencesSurvivesIntoTheChunk() throws {
        let kept = try XCTUnwrap(DocumentChunker().chunk(groupedRule).first)
        XCTAssertTrue(kept.text.contains("\n41-310 Blue cover plates"), kept.text)
        XCTAssertEqual(ClauseReference.match("41-310", in: kept.text, section: kept.section), .starts,
                       "the rule starts a line, so it starts the clause")

        let joined = try XCTUnwrap(DocumentChunker(keepsLineBreaks: false, chunksAtClauseHeadings: false)
            .chunk(groupedRule).first)
        XCTAssertFalse(joined.text.contains("\n"))
        XCTAssertEqual(ClauseReference.match("41-310", in: joined.text, section: joined.section), .cites,
                       "joined by a space after its group heading, the rule only reads as cited")
    }

    func testSentencesOnOneLineStayJoinedByASpace() throws {
        let chunk = try XCTUnwrap(DocumentChunker().chunk("Turn the dial left. Then wait for the green lamp.").first)
        XCTAssertEqual(chunk.text, "Turn the dial left. Then wait for the green lamp.")
    }

    func testSentenceStartsStillPointAtTheirSentences() {
        for chunk in DocumentChunker().chunk(clauseNumberedBook(rules: 12)) {
            let characters = Array(chunk.text)
            for start in chunk.sentenceStarts {
                XCTAssertLessThan(start, characters.count, chunk.text)
                XCTAssertFalse(characters[start].isWhitespace, "a sentence start lands on its first character: \(chunk.text)")
                if start > 0 { XCTAssertTrue(characters[start - 1].isWhitespace, "and the separator before it is one character") }
            }
        }
    }

    // MARK: - Clause-numbered documents

    /// `rules` invented clauses, each a group heading, a numbered heading line and two sentences.
    private func clauseNumberedBook(rules: Int) -> String {
        (0..<rules).map { i in
            """
            Page \(i + 1)

            Group \(["Alpha", "Bravo", "Charlie", "Delta"][i % 4])
            \(40 + i / 10)-\(100 + i * 2) Example heading number \(i)
            The panel for case \(i) has a \(i % 2 == 0 ? "grey" : "white") lid. Mark it with tag \(i) before you leave the site.
            """
        }.joined(separator: "\n\n")
    }

    func testAClauseNumberedDocumentChunksAtEachClauseAndCitesIt() throws {
        let text = clauseNumberedBook(rules: 12)
        XCTAssertEqual(DocumentChunker.clauseHeadingLines(in: text).count, 12)
        let chunks = DocumentChunker().chunk(text)
        for i in 0..<12 {
            let number = "\(40 + i / 10)-\(100 + i * 2)"
            let own = chunks.filter { $0.section?.hasPrefix(number) == true }
            XCTAssertFalse(own.isEmpty, "rule \(number) has a chunk of its own")
            XCTAssertTrue(own.contains { ClauseReference.match(number, in: $0.text, section: $0.section) == .starts },
                          "and one of them starts it")
            for chunk in own {
                XCTAssertFalse(chunk.text.contains("tag \(i + 1) "), "no text from the next rule rides in: \(chunk.text)")
            }
        }
    }

    func testAProseManualIsNotClauseNumberedAndChunksExactlyAsBefore() {
        // Numbered procedure steps, a decimal reading and a few numbered sections: no clause shape.
        let manual = """
            Page 1

            1. Ignition check
            Hold the switch for five seconds. The lamp blinks twice.
            2. Sensor check
            Read the value on the display. A reading of 2.6 or more is good.
            3.1 Overview
            The cabinet has two doors and a filter rack.
            3.2 Cleaning
            Wipe the rack with a dry cloth.
            """
        XCTAssertTrue(DocumentChunker.clauseHeadingLines(in: manual).count < DocumentChunker.minimumClauseHeadings)
        XCTAssertEqual(DocumentChunker().chunk(manual).map(\.text),
                       DocumentChunker(chunksAtClauseHeadings: false).chunk(manual).map(\.text),
                       "a document that isn't clause-numbered is never split at its headings")
    }

    func testFewerClauseHeadingsThanTheThresholdLeaveTheDocumentAlone() {
        let text = clauseNumberedBook(rules: DocumentChunker.minimumClauseHeadings - 1)
        XCTAssertEqual(DocumentChunker().chunk(text).map(\.text),
                       DocumentChunker(chunksAtClauseHeadings: false).chunk(text).map(\.text))
    }

    func testARunningHeaderRepeatingOneClauseCountsOnce() {
        let text = (0..<12).map { _ in "41-310 Blue cover plates\nFit the cover." }.joined(separator: "\n")
        XCTAssertEqual(DocumentChunker.clauseHeadingLines(in: text).count, 1)
    }
}
