import XCTest
@testable import OpenGlasses

/// Plan JM P3 — the pure scoring behind the recogniser comparison: normalisation, the word
/// alignment and its substitution/insertion/deletion counts, and the session table.
final class RecognizerComparisonTests: XCTestCase {

    // MARK: - Normalisation

    func testNormalisationIgnoresCaseAndPunctuation() {
        XCTAssertEqual(RecognizerComparison.normalize("Check the Filter, please!"), "check the filter please")
        XCTAssertEqual(RecognizerComparison.normalize("What's the \"pressure\"?"), "whats the pressure")
    }

    func testNormalisationKeepsHyphenatedTokensAndDigits() {
        XCTAssertEqual(RecognizerComparison.normalize("Charge it with R-410A."), "charge it with r-410a")
        XCTAssertEqual(RecognizerComparison.normalize("Part number 7X-4420-B"), "part number 7x-4420-b")
        XCTAssertEqual(RecognizerComparison.normalize("3.5 kW at 1,200 rpm"), "3.5 kw at 1200 rpm")
        XCTAssertEqual(RecognizerComparison.normalize("a dash - between"), "a dash between",
                       "a hyphen standing alone is a space, not a token")
        XCTAssertEqual(RecognizerComparison.normalize("-leading and trailing-"), "leading and trailing")
    }

    func testNormalisationCollapsesWhitespace() {
        XCTAssertEqual(RecognizerComparison.normalize("  two\t\tspaces \n and  lines  "), "two spaces and lines")
        XCTAssertEqual(RecognizerComparison.normalize(" ... "), "")
    }

    // MARK: - Word error rate

    func testIdenticalScoresZero() {
        let score = RecognizerComparison.wordErrorRate(reference: "what is the superheat",
                                                       hypothesis: "what is the superheat")
        XCTAssertEqual(score.rate, 0)
        XCTAssertEqual(score.errors, 0)
        XCTAssertEqual(score.referenceWords, 4)
    }

    func testCaseAndPunctuationDifferencesScoreAsEqual() {
        let score = RecognizerComparison.wordErrorRate(reference: "What is the superheat on R-410A?",
                                                       hypothesis: "what is the Superheat on r-410a")
        XCTAssertEqual(score.rate, 0)
    }

    func testEmptyHypothesisScoresOne() {
        let score = RecognizerComparison.wordErrorRate(reference: "check the capacitor", hypothesis: "")
        XCTAssertEqual(score.rate, 1)
        XCTAssertEqual(score.deletions, 3)
        XCTAssertEqual(score.substitutions, 0)
        XCTAssertEqual(score.insertions, 0)
    }

    func testBothEmptyScoresZero() {
        let score = RecognizerComparison.wordErrorRate(reference: "", hypothesis: "  ")
        XCTAssertEqual(score.rate, 0)
        XCTAssertEqual(score.referenceWords, 0)
    }

    func testAHypothesisAgainstAnEmptyReferenceIsAllInsertions() {
        let score = RecognizerComparison.wordErrorRate(reference: "", hypothesis: "two words")
        XCTAssertEqual(score.insertions, 2)
        XCTAssertEqual(score.rate, 1)
    }

    func testKnownSubstitutionInsertionDeletionCounts() {
        // ref:  order part number 7X-4420-B for the  unit
        // hyp:  order part      7X-4420-D for the  new unit
        //       (deleted "number", substituted the part, inserted "new")
        let score = RecognizerComparison.wordErrorRate(
            reference: "Order part number 7X-4420-B for the unit",
            hypothesis: "order part 7X-4420-D for the new unit")
        XCTAssertEqual(score.referenceWords, 7)
        XCTAssertEqual(score.substitutions, 1)
        XCTAssertEqual(score.insertions, 1)
        XCTAssertEqual(score.deletions, 1)
        XCTAssertEqual(score.rate, 3.0 / 7.0, accuracy: 1e-9)
    }

    func testAllSubstitutions() {
        let score = RecognizerComparison.wordErrorRate(reference: "one two", hypothesis: "three four")
        XCTAssertEqual(score.substitutions, 2)
        XCTAssertEqual(score.insertions + score.deletions, 0)
        XCTAssertEqual(score.rate, 1)
    }

    func testRateCanExceedOneWithInsertions() {
        let score = RecognizerComparison.wordErrorRate(reference: "yes", hypothesis: "yes yes yes")
        XCTAssertEqual(score.insertions, 2)
        XCTAssertEqual(score.rate, 2)
    }

    // MARK: - Rows and the session

    private func row(_ engine: RecognizerComparison.Engine, _ text: String,
                     outcome: RecognizerComparison.Outcome = .transcribed,
                     seconds: TimeInterval = 1.25) -> RecognizerComparison.Row {
        .init(engine: engine, transcript: text, elapsed: seconds, outcome: outcome)
    }

    func testARowIsScoredOnlyWhenItTranscribedAndThereIsAReference() {
        XCTAssertNotNil(row(.appleSpeech, "hello there").score(against: "hello there"))
        XCTAssertNil(row(.appleSpeech, "hello there").score(against: "  "))
        XCTAssertNil(row(.deepgram, "", outcome: .notConfigured).score(against: "hello"))
        XCTAssertNil(row(.openAI, "", outcome: .failed("http500")).score(against: "hello"))
    }

    func testSessionTableShape() {
        var session = RecognizerComparison.Session()
        session.add(rows: [
            row(.appleSpeech, "check the filter"),
            row(.deepgram, "", outcome: .notConfigured, seconds: 0),
            row(.openAI, "", outcome: .failed("http500"), seconds: 0.5),
        ], reference: "Check the filters", hints: true)
        session.add(rows: [row(.appleSpeech, "a | pipe\nand a line")], reference: "a pipe and a line", hints: true)
        session.add(rows: [row(.appleSpeech, "check filter")], reference: "check the filter", hints: false)

        let lines = session.table().components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "| # | Engine | Hints | WER % | S/I/D | Seconds | Transcript |")
        XCTAssertEqual(lines[1], "|---|---|---|---|---|---|---|")
        XCTAssertEqual(lines[2], "| 1 | Apple Speech | on | 33.3 | 1/0/0 | 1.25 | check the filter |")
        XCTAssertEqual(lines[3], "| 1 | Deepgram | on | — | — | 0.00 | (not configured) |")
        XCTAssertEqual(lines[4], "| 1 | OpenAI | on | — | — | 0.50 | (failed: http500) |")
        XCTAssertEqual(lines[5], "| 2 | Apple Speech | on | 0.0 | 0/0/0 | 1.25 | a / pipe and a line |",
                       "a pipe or a line break in a transcript never breaks the table")
        XCTAssertEqual(lines[6], "| 3 | Apple Speech | off | 33.3 | 0/0/1 | 1.25 | check filter |")
        // The per-engine summary, hints on and off apart: corpus WER, 1 error over 3 + 5 words.
        XCTAssertEqual(lines[7], "")
        XCTAssertEqual(lines[8], "| Engine | Hints | Utterances | WER % |")
        XCTAssertEqual(lines[10], "| Apple Speech | on | 2 | 12.5 |")
        XCTAssertEqual(lines[11], "| Apple Speech | off | 1 | 33.3 |")
        XCTAssertEqual(lines.count, 12, "engines that never scored have no summary line")
    }

    func testSessionKeepsTheNewestFiftyRows() {
        var session = RecognizerComparison.Session()
        for i in 0..<30 {
            session.add(rows: [row(.appleSpeech, "a \(i)"), row(.onDevice, "b \(i)")], reference: "a \(i)", hints: true)
        }
        XCTAssertEqual(session.entries.count, RecognizerComparison.Session.capacity)
        XCTAssertEqual(session.utteranceCount, 30)
        XCTAssertEqual(session.entries.first?.utterance, 6, "the oldest rows went first")
        XCTAssertEqual(session.entries.last?.utterance, 30)
        session.clear()
        XCTAssertTrue(session.isEmpty)
        XCTAssertEqual(session.utteranceCount, 0)
    }

    func testAddingNoRowsIsNotAnUtterance() {
        var session = RecognizerComparison.Session()
        session.add(rows: [], reference: "anything", hints: true)
        XCTAssertEqual(session.utteranceCount, 0)
        XCTAssertTrue(session.isEmpty)
    }
}
