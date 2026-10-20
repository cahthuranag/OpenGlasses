import XCTest
@testable import OpenGlasses

/// Plan HZ P0 — where a streamed reply's sentences end. Every case here is one the old streamer
/// (cut at the last `.`, `!`, `?` or newline) got wrong, or one the new rules could plausibly get
/// wrong the other way.
final class SentenceStreamSplitterTests: XCTestCase {

    /// Feed `chunks` in order, then end the stream.
    private func split(_ chunks: [String],
                       limits: SentenceStreamSplitter.Limits = .default) -> [String] {
        var splitter = SentenceStreamSplitter(limits: limits)
        var sentences: [String] = []
        for chunk in chunks { sentences += splitter.ingest(chunk) }
        return sentences + splitter.flush()
    }

    /// The same text one character at a time — the worst chunking a stream can do.
    private func splitByCharacter(_ text: String) -> [String] {
        split(text.map { String($0) })
    }

    // MARK: - Abbreviations and initials

    func testAbbreviationsDoNotEndASentence() {
        let text = "Dr. Patel will see you at three today. Please bring your card."
        XCTAssertEqual(split([text]), ["Dr. Patel will see you at three today.",
                                       "Please bring your card."])
    }

    func testEgBeforeACapitalDoesNotEndASentence() {
        let text = "Use a flexible sealant, e.g. Silicone works well here. Then let it dry for a day."
        XCTAssertEqual(split([text]), ["Use a flexible sealant, e.g. Silicone works well here.",
                                       "Then let it dry for a day."])
    }

    func testSingleCapitalInitialsDoNotEndASentence() {
        let text = "Ask J. Smith about the order today. He has the paperwork."
        XCTAssertEqual(split([text]), ["Ask J. Smith about the order today.",
                                       "He has the paperwork."])
    }

    // MARK: - Numbers

    func testDecimalsVersionsAndAddressesAreNotBoundaries() {
        let text = "Set the gap to 3.14 mm and the address to 192.168.1.20 on firmware 2.4.1 first. Then restart it."
        XCTAssertEqual(split([text]), [
            "Set the gap to 3.14 mm and the address to 192.168.1.20 on firmware 2.4.1 first.",
            "Then restart it."
        ])
    }

    /// The old streamer's headline failure: a chunk ending at "2." was spoken as a sentence.
    func testTwoPointFiveMillimetresContinuesAcrossAChunkBoundary() {
        let sentences = split(["The gap should be 2.", "5 mm on each side. Ch", "eck it twice before closing."])
        XCTAssertEqual(sentences, ["The gap should be 2.5 mm on each side.",
                                   "Check it twice before closing."])
    }

    func testASentenceEndingInANumberStillEnds() {
        XCTAssertEqual(split(["The reading on the gauge is 2.5. That is within the range."]),
                       ["The reading on the gauge is 2.5.", "That is within the range."])
    }

    // MARK: - Lists

    func testEachListItemIsASentenceOfItsOwn() {
        let text = """
        Here is the order to do it in:
        - Turn off the breaker at the panel
        - Remove the four cover plate screws
        - Test both wires with a meter
        """
        XCTAssertEqual(split([text]), [
            "Here is the order to do it in:",
            "- Turn off the breaker at the panel",
            "- Remove the four cover plate screws",
            "- Test both wires with a meter"
        ])
    }

    func testNumberedItemsAreSentencesAndTheirMarkersAreNotBoundaries() {
        let text = "1. Turn off the breaker at the panel\n2. Remove the cover plate screws\n3. Test the wires"
        XCTAssertEqual(splitByCharacter(text), [
            "1. Turn off the breaker at the panel",
            "2. Remove the cover plate screws",
            "3. Test the wires"
        ])
    }

    func testABlankLineEndsAParagraph() {
        let text = "The unit is a heat pump with no model plate\n\nCheck the label inside the door panel instead"
        XCTAssertEqual(split([text]), ["The unit is a heat pump with no model plate",
                                       "Check the label inside the door panel instead"])
    }

    // MARK: - Code

    func testAFenceIsNeverCutOpen() {
        let text = "Type the following command into the console.\n```\necho Done. Next step\n```\nThat is all you need. Then restart the unit."
        for sentences in [split([text]), splitByCharacter(text)] {
            XCTAssertEqual(sentences.count, 2, "\(sentences)")
            for sentence in sentences {
                XCTAssertEqual(sentence.components(separatedBy: "```").count % 2, 1,
                               "an emitted sentence opened a fence it did not close: \(sentence)")
            }
            XCTAssertEqual(sentences.last, "Then restart the unit.")
        }
    }

    func testAnInlineCodeSpanIsNotSplit() {
        let text = "Set `max. Value` to ten in the settings file. Then save it and reboot."
        XCTAssertEqual(split([text]), ["Set `max. Value` to ten in the settings file.",
                                       "Then save it and reboot."])
    }

    // MARK: - Length limits

    func testAShortOpenerMergesIntoTheNextSentence() {
        XCTAssertEqual(split(["Sure. The forecast for today is sunny. Take a hat."]),
                       ["Sure. The forecast for today is sunny.", "Take a hat."])
    }

    func testARunOnIsCutAtItsLastCommaBeforeTheMaximum() {
        let opening = String(repeating: "the long run on clause ", count: 9)
            .trimmingCharacters(in: .whitespaces)
        let text = opening + ", and it keeps going " + String(repeating: "and going ", count: 12)
        var splitter = SentenceStreamSplitter()
        let early = splitter.ingest(text)
        XCTAssertEqual(early, [opening + ","], "cut before the stream ends, at the comma")
        XCTAssertLessThanOrEqual(early.first?.count ?? .max, SentenceStreamSplitter.Limits.default.maximumLength)
        XCTAssertEqual(splitter.flush().count, 1)
    }

    // MARK: - Chunk boundaries

    func testAChunkBoundaryInsideAWordChangesNothing() {
        let sentences = split(["The weather in Auck", "land is sunny today. Tom", "orrow it rains a lot."])
        XCTAssertEqual(sentences, ["The weather in Auckland is sunny today.", "Tomorrow it rains a lot."])
    }

    func testAChunkBoundaryInsideEgChangesNothing() {
        let sentences = split(["Bring a tool for it, e.", "g. a spanner, and a torch. Then start."])
        XCTAssertEqual(sentences, ["Bring a tool for it, e.g. a spanner, and a torch.", "Then start."])
    }

    func testCharacterByCharacterMatchesWholeText() {
        let replies = [
            "Dr. Patel will see you at three today. Please bring your card.",
            "The gap should be 2.5 mm on each side. Check it twice before closing!",
            "Is the breaker off? Good. Now remove the cover plate and test the wires.",
            "Here is the order:\n- Turn off the breaker at the panel\n- Remove the four cover plate screws"
        ]
        for reply in replies {
            XCTAssertEqual(splitByCharacter(reply), split([reply]), reply)
        }
    }

    func testASentenceWaitsUntilWhatFollowsItIsVisible() {
        var splitter = SentenceStreamSplitter()
        XCTAssertEqual(splitter.ingest("The forecast for Auckland is sunny today."), [],
                       "the next sentence has not started: it may still be an abbreviation")
        XCTAssertEqual(splitter.ingest(" T"), [], "one character is not enough to tell")
        XCTAssertEqual(splitter.ingest("ake a hat."), ["The forecast for Auckland is sunny today."])
        XCTAssertEqual(splitter.flush(), ["Take a hat."])
    }

    func testFlushIfCompleteReleasesOnlyAFinishedSentence() {
        var splitter = SentenceStreamSplitter()
        _ = splitter.ingest("The weather in Auck")
        XCTAssertEqual(splitter.flushIfComplete(), [], "a fragment stays")
        _ = splitter.ingest("land is sunny today.")
        XCTAssertEqual(splitter.flushIfComplete(), ["The weather in Auckland is sunny today."])
        XCTAssertTrue(splitter.isEmpty)
    }

    func testTheSentencesAreTheReply() {
        let reply = "Sure. The forecast for Auckland is sunny today with a high of 22 degrees. Expect light winds after 3 pm, e.g. around 10 km/h. Take a hat!"
        let joined = split([reply]).joined(separator: " ")
        XCTAssertEqual(joined, reply)
    }
}
