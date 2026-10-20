import XCTest
@testable import OpenGlasses

/// Plan HZ P0 — what may be said before the reply is final. The gate's one job is to make sure
/// streaming changes when words are said and never which words: anything later processing could
/// still rewrite is held, and spoken whole at the end as it is today.
final class StreamSpeechGateTests: XCTestCase {

    private func feed(_ gate: StreamSpeechGate, _ chunks: [String]) -> [String] {
        chunks.flatMap { gate.ingest($0) }
    }

    // MARK: - Think blocks

    func testAThinkBlockIsHeldUntilItCloses() {
        let gate = StreamSpeechGate()
        XCTAssertEqual(gate.ingest("<think>The user wants the forecast. Some reasoning here. "), [])
        XCTAssertEqual(gate.ingest("More reasoning. Still thinking. </th"), [],
                       "a close tag split across chunks is still a close tag")
        let released = feed(gate, ["ink>The forecast for today is sunny and warm. ",
                                   "Take a hat with you."])
        XCTAssertEqual(released, ["The forecast for today is sunny and warm."])
        XCTAssertFalse(gate.text.contains("reasoning"), "the reasoning never reaches speech")
    }

    func testNothingAfterAnOpenThinkIsReleased() {
        let gate = StreamSpeechGate()
        let released = feed(gate, ["The answer is coming right up now. ",
                                   "<think>Let me reconsider this. Maybe not. Another sentence here. "])
        XCTAssertEqual(released, [], "the opener waits on what follows it, and what follows is a think block")
        XCTAssertEqual(feed(gate, ["Even more thinking. Yes."]), [])
    }

    // MARK: - Choice lists

    func testAChoiceListOpeningIsHeldToTheEnd() {
        let gate = StreamSpeechGate()
        let released = feed(gate, ["Which would you like for dinner tonight?", "\n1",
                                   ". Pizza from the corner place\n2. Pasta at home\n3. Something else"])
        XCTAssertEqual(released, [])
        XCTAssertEqual(gate.holdReason, .choiceList)
        XCTAssertEqual(feed(gate, [" entirely. That is all I have for you."]), [], "held for the rest of the reply")
    }

    func testALetteredListIsAChoiceListWithoutACue() {
        let gate = StreamSpeechGate()
        _ = feed(gate, ["Here are the routes you could take.\nA) The early train at six\nB) The bus"])
        XCTAssertEqual(gate.holdReason, .choiceList)
    }

    func testNumberedStepsWithoutAChoiceCueStreamLikeProse() {
        let gate = StreamSpeechGate()
        let released = feed(gate, ["Do it in this order.\n1. Turn off the breaker at the panel\n",
                                   "2. Remove the cover plate screws\n3. Test the wires"])
        XCTAssertNil(gate.holdReason)
        XCTAssertEqual(released, ["Do it in this order.",
                                  "1. Turn off the breaker at the panel",
                                  "2. Remove the cover plate screws"])
    }

    func testTheChoiceRuleIsInjected() {
        let gate = StreamSpeechGate(rules: .init(looksLikeChoiceList: { _ in false }))
        let released = feed(gate, ["Which would you like for dinner tonight?\n1. Pizza from the corner place\n2. Pasta"])
        XCTAssertNil(gate.holdReason, "with the buttons off the list streams")
        XCTAssertEqual(released.first, "Which would you like for dinner tonight?")
    }

    // MARK: - Rewritable replies

    func testAMemoryCommandShapeHoldsTheReply() {
        let gate = StreamSpeechGate()
        let released = feed(gate, ["Got it, I will remember that your van is the white one. ",
                                   "[REMEMBER: van = white]"])
        XCTAssertEqual(released, [])
        XCTAssertEqual(gate.holdReason, .rewrite)
    }

    func testAMemoryCommandLaterInTheReplyHoldsOnlyWhatFollows() {
        let gate = StreamSpeechGate()
        let released = feed(gate, ["Your next job is at ten in Riverside. It is a",
                                   " boiler service. [REM", "EMBER: next = ten]"])
        XCTAssertEqual(released, ["Your next job is at ten in Riverside."],
                       "a sentence followed by a tag is never released by its boundary")
        XCTAssertEqual(gate.holdReason, .rewrite)

        // Post-processing strips the tag; what is left to say is exactly what was held.
        let final = "Your next job is at ten in Riverside. It is a boiler service."
        let reconciliation = StreamSpeechGate.reconcile(reply: final, spoken: released)
        XCTAssertEqual(reconciliation.remainder, "It is a boiler service.")
        XCTAssertTrue(reconciliation.spokenIsPartOfReply)
    }

    func testPlainProseIsReleasedASentenceAtATime() {
        let gate = StreamSpeechGate()
        XCTAssertEqual(gate.ingest("The forecast for Auckland is sunny today."), [])
        XCTAssertEqual(gate.ingest(" Expect light winds after three."), ["The forecast for Auckland is sunny today."])
        XCTAssertEqual(gate.ingest(" Take a hat with you."), ["Expect light winds after three."])
        XCTAssertEqual(gate.released, ["The forecast for Auckland is sunny today.",
                                       "Expect light winds after three."])
    }

    // MARK: - Iterations

    func testAToolPreambleIsReleasedAtTheResetAndTheNextIterationStartsClean() {
        let gate = StreamSpeechGate()
        XCTAssertEqual(gate.ingest("Let me check the forecast for you."), [])
        XCTAssertEqual(gate.endIteration(), ["Let me check the forecast for you."])
        XCTAssertEqual(gate.text, "")
        XCTAssertEqual(gate.released, [])
    }

    func testAFragmentAtTheResetIsDropped() {
        let gate = StreamSpeechGate()
        _ = gate.ingest("The weather in Auck")
        XCTAssertEqual(gate.endIteration(), [], "a model cut off mid-clause is not spoken")
    }

    func testAHoldDoesNotOutliveItsIteration() {
        let gate = StreamSpeechGate()
        _ = gate.ingest("Noted for later. [REMEMBER: gate = code 1234]")
        XCTAssertTrue(gate.isHolding)
        XCTAssertEqual(gate.endIteration(), [])
        XCTAssertFalse(gate.isHolding)
        XCTAssertEqual(feed(gate, ["The forecast for Auckland is sunny today. Take a hat."]),
                       ["The forecast for Auckland is sunny today."])
    }

    // MARK: - Reconciling with the final reply

    func testTheRemainderIsWhatFollowsTheSpokenText() {
        let spoken = ["The forecast for Auckland is sunny today."]
        let reply = "The forecast for Auckland is sunny today.\n\nTake a hat with you."
        let reconciliation = StreamSpeechGate.reconcile(reply: reply, spoken: spoken)
        XCTAssertEqual(reconciliation.remainder, "Take a hat with you.")
        XCTAssertTrue(reconciliation.spokenIsPartOfReply)
    }

    func testANoticeTheStreamNeverCarriedIsStillSaid() {
        let reconciliation = StreamSpeechGate.reconcile(
            reply: "From your team: The torque spec is 25 newton metres. Check it twice.",
            spoken: ["The torque spec is 25 newton metres."])
        XCTAssertEqual(reconciliation.remainder, "From your team: Check it twice.")
        XCTAssertTrue(reconciliation.spokenIsPartOfReply)
    }

    func testAReplyThatIsNotTheStreamIsSaidInFull() {
        let reconciliation = StreamSpeechGate.reconcile(
            reply: "I need you to confirm that before I send it.",
            spoken: ["Let me send that order now."])
        XCTAssertEqual(reconciliation.remainder, "I need you to confirm that before I send it.")
        XCTAssertFalse(reconciliation.spokenIsPartOfReply)
    }

    func testNothingSpokenMeansTheWholeReplyRemains() {
        let reconciliation = StreamSpeechGate.reconcile(reply: "  It is sunny.  ", spoken: [])
        XCTAssertEqual(reconciliation.remainder, "It is sunny.")
    }
}
