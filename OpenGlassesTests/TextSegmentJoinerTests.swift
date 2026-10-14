import XCTest
@testable import OpenGlasses

/// A tester's replies that used a tool ran sentences together — "…hora exata.Tens razão",
/// "…sobre o Papa.O Papa…" — on screen and out loud.
final class TextSegmentJoinerTests: XCTestCase {

    // MARK: - Joining pieces

    func testPiecesThatMeetWithoutWhitespaceGetOneSpace() {
        XCTAssertEqual(TextSegmentJoiner.join(["Não sei a hora exata.", "Tens razão, desculpa."]),
                       "Não sei a hora exata. Tens razão, desculpa.")
        XCTAssertEqual(TextSegmentJoiner.join(["Li uma notícia sobre o Papa.", "O Papa visitou Lisboa."]),
                       "Li uma notícia sobre o Papa. O Papa visitou Lisboa.")
    }

    func testWhitespaceAlreadyAtABoundaryIsKeptAsItIs() {
        XCTAssertEqual(TextSegmentJoiner.join(["First paragraph.\n\n", "Second."]), "First paragraph.\n\nSecond.")
        XCTAssertEqual(TextSegmentJoiner.join(["One.", "\nTwo."]), "One.\nTwo.")
        XCTAssertEqual(TextSegmentJoiner.join(["One. ", "Two."]), "One. Two.")
    }

    func testEmptyPiecesAddNothing() {
        XCTAssertEqual(TextSegmentJoiner.join(["", "Only.", ""]), "Only.")
        XCTAssertEqual(TextSegmentJoiner.join([String]()), "")
        XCTAssertEqual(TextSegmentJoiner.join(["Hello"]), "Hello")
    }

    // MARK: - A space the model left out

    func testTheTestersSentencesAreSeparated() {
        XCTAssertEqual(TextSegmentJoiner.repairingGluedSentences("Não sei a hora exata.Tens razão, desculpa."),
                       "Não sei a hora exata. Tens razão, desculpa.")
        XCTAssertEqual(TextSegmentJoiner.repairingGluedSentences("Li uma notícia sobre o Papa.O Papa visitou Lisboa."),
                       "Li uma notícia sobre o Papa. O Papa visitou Lisboa.")
        XCTAssertEqual(TextSegmentJoiner.repairingGluedSentences("Done!Next step?Yes."),
                       "Done! Next step? Yes.")
    }

    func testAbbreviationsNumbersCodeAndAddressesAreLeftAlone() {
        for text in [
            "Built on ASP.NET today.",
            "Versão 3.5 do modelo.",
            "The U.S. Army replied.",
            "e.g. this one",
            "Open www.Example.com now.",
            "See https://site.com/Path.Html for more.",
            "Call `self.View` here.",
            "Write to a.B@x.com.",
            "No glue here. None at all.",
        ] {
            XCTAssertEqual(TextSegmentJoiner.repairingGluedSentences(text), text, text)
        }
    }

    // MARK: - The Responses parser

    func testResponsesReplyInTwoMessagesIsNotGlued() {
        let response: [String: Any] = ["output": [
            ["type": "message", "phase": "commentary",
             "content": [["type": "output_text", "text": "Vou procurar a hora exata."]]],
            ["type": "message", "content": [["type": "output_text", "text": "Tens razão, são três horas."]]],
        ]]
        XCTAssertEqual(ResponsesTranslator.parseOutput(response).text,
                       "Vou procurar a hora exata. Tens razão, são três horas.")
    }
}
