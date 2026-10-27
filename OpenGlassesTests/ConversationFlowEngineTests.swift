import XCTest
@testable import OpenGlasses

/// Plan BG P2 — the pure routing core of the conversation flow: an ordered `VoiceCommandHandler`
/// chain where the first handler to consume the transcript wins and short-circuits the rest.
final class ConversationFlowEngineTests: XCTestCase {

    @MainActor
    func testReservationBlocksAnotherTranscriptWhileAsyncRoutingIsSuspended() async {
        let gate = Box(SpokenTurnGate())
        var resume: CheckedContinuation<Void, Never>?
        let dispatched = Box(0)
        var first: Task<Void, Never>?
        await withCheckedContinuation { entered in
            first = Task { @MainActor in
                guard let id = gate.value.beginRouting() else { return }
                defer { gate.value.endRouting(id) }
                _ = await ConversationFlowEngine(handlers: [
                    VoiceCommandHandler(label: "suspending-command-or-cue") { _ in
                        await withCheckedContinuation { continuation in
                            resume = continuation
                            entered.resume()
                        }
                        return false
                    }
                ]).route("first fragment")
                if gate.value.ownsRouting(id) { dispatched.value += 1 }
            }
        }
        XCTAssertNil(gate.value.beginRouting(), "a second fragment must not pass admission across an await")
        resume?.resume()
        await first?.value
        XCTAssertEqual(dispatched.value, 1)
        XCTAssertFalse(gate.value.isReserved)
        XCTAssertNotNil(gate.value.beginRouting(), "the next turn is allowed after routing finishes")
    }

    func testReplacementOwnsCleanupAndInvalidatesOlderRoutingAndWaiters() {
        var gate = SpokenTurnGate()
        let original = gate.beginRouting()!
        let firstReplacement = gate.beginReplacement()
        XCTAssertFalse(gate.ownsRouting(original))
        gate.endRouting(original)
        XCTAssertTrue(gate.isReplacing)
        XCTAssertNil(gate.beginRouting())
        let newerReplacement = gate.beginReplacement()
        XCTAssertFalse(gate.endReplacement(firstReplacement))
        XCTAssertTrue(gate.isReplacing)
        XCTAssertTrue(gate.endReplacement(newerReplacement))
        XCTAssertNotNil(gate.beginRouting())
        gate.invalidate()
        XCTAssertFalse(gate.isReserved)
    }

    func testAdjacentCorrectionFragmentsJoinOnceAndStaleSpeechIsSuperseded() {
        let now = Date()
        XCTAssertEqual(SpokenTurnGate.replacementText(held: "Verifica melhor porque", heldAt: now,
                                                     interruption: "é hoje", now: now), "Verifica melhor porque é hoje")
        XCTAssertEqual(SpokenTurnGate.replacementText(held: "é hoje", heldAt: now,
                                                     interruption: "é hoje", now: now), "é hoje")
        XCTAssertEqual(SpokenTurnGate.replacementText(held: "old question", heldAt: now.addingTimeInterval(-3),
                                                     interruption: "new correction", now: now), "new correction")
    }

    func testDuplicateDictationOfBargeInIsConsumedOnceWithinTheHandoff() {
        let now = Date()
        var gate = SpokenTurnGate()
        let id = gate.beginReplacement(interruption: "é hoje", now: now)
        XCTAssertTrue(gate.endReplacement(id))
        XCTAssertFalse(gate.consumeRepeatedInterruption("another correction", now: now))
        XCTAssertTrue(gate.consumeRepeatedInterruption(" é hoje ", now: now.addingTimeInterval(1)))
        XCTAssertFalse(gate.consumeRepeatedInterruption("é hoje", now: now.addingTimeInterval(1)))
        _ = gate.beginReplacement(interruption: "é hoje", now: now)
        XCTAssertFalse(gate.consumeRepeatedInterruption("é hoje", now: now.addingTimeInterval(3)))
    }

    /// Records which handlers ran, in order, so we can assert short-circuiting.
    private func recordingHandler(_ label: String, consumes: Bool, into log: Box<[String]>) -> VoiceCommandHandler {
        VoiceCommandHandler(label: label) { _ in
            log.value.append(label)
            return consumes
        }
    }

    func testFirstConsumingHandlerWinsAndShortCircuits() async {
        let ran = Box<[String]>([])
        let engine = ConversationFlowEngine(handlers: [
            recordingHandler("a", consumes: false, into: ran),
            recordingHandler("b", consumes: true, into: ran),
            recordingHandler("c", consumes: true, into: ran),   // must never run
        ])
        let consumed = await engine.route("hello")
        XCTAssertEqual(consumed, "b")
        XCTAssertEqual(ran.value, ["a", "b"], "handlers run in order; nothing after the winner runs")
    }

    func testNoHandlerConsumesReturnsNil() async {
        let ran = Box<[String]>([])
        let engine = ConversationFlowEngine(handlers: [
            recordingHandler("a", consumes: false, into: ran),
            recordingHandler("b", consumes: false, into: ran),
        ])
        let consumed = await engine.route("weather?")
        XCTAssertNil(consumed, "nothing consumed → caller proceeds to the LLM")
        XCTAssertEqual(ran.value, ["a", "b"], "every handler is offered the transcript")
    }

    func testEmptyChainReturnsNil() async {
        let consumed = await ConversationFlowEngine(handlers: []).route("anything")
        XCTAssertNil(consumed)
    }

    func testFirstHandlerCanWinImmediately() async {
        let ran = Box<[String]>([])
        let engine = ConversationFlowEngine(handlers: [
            recordingHandler("first", consumes: true, into: ran),
            recordingHandler("second", consumes: true, into: ran),
        ])
        let consumed = await engine.route("next")
        XCTAssertEqual(consumed, "first")
        XCTAssertEqual(ran.value, ["first"], "the rest of the chain is skipped")
    }

    func testHandlerReceivesTheTranscript() async {
        var seen: String?
        let engine = ConversationFlowEngine(handlers: [
            VoiceCommandHandler(label: "capture") { text in seen = text; return true }
        ])
        _ = await engine.route("open the menu")
        XCTAssertEqual(seen, "open the menu")
    }
}
