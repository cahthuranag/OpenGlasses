import XCTest
@testable import OpenGlasses

/// Plan HZ P0 — the order, prefetch and demotion rules of a streamed reply, driven event by event.
/// No audio, no clock: synthesis "completes" when a test says it does, in whatever order it likes.
final class StreamedReplyScheduleTests: XCTestCase {

    private let cloud: [TTSEngine] = [.elevenLabs, .kokoro, .system]

    private func plays(_ actions: [StreamedReplySchedule.Action]) -> [Int] {
        actions.compactMap { if case .play(let index, _) = $0 { return index } else { return nil } }
    }

    private func syntheses(_ actions: [StreamedReplySchedule.Action]) -> [StreamedReplySchedule.Action] {
        actions.filter { if case .synthesize = $0 { return true } else { return false } }
    }

    /// Sentences synthesising or synthesised and waiting — never more than the depth.
    private func prefetched(_ schedule: StreamedReplySchedule) -> Int {
        schedule.items.filter {
            switch $0.state {
            case .synthesizing, .ready: return true
            default: return false
            }
        }.count
    }

    // MARK: - Order

    func testPlaybackStaysInOrderWhenSynthesisCompletesOutOfOrder() {
        var schedule = StreamedReplySchedule(prefetchDepth: 3)
        var started: [StreamedReplySchedule.Action] = []
        for sentence in ["One sentence.", "Two sentence.", "Three sentence."] {
            started += schedule.enqueue(sentence, chain: cloud)
        }
        XCTAssertEqual(started, [.synthesize(index: 0, engine: .elevenLabs),
                                 .synthesize(index: 1, engine: .elevenLabs),
                                 .synthesize(index: 2, engine: .elevenLabs)])

        XCTAssertEqual(plays(schedule.synthesisSucceeded(index: 2, engine: .elevenLabs)), [],
                       "the third is ready first and still waits")
        XCTAssertEqual(plays(schedule.synthesisSucceeded(index: 1, engine: .elevenLabs)), [])
        XCTAssertEqual(plays(schedule.synthesisSucceeded(index: 0, engine: .elevenLabs)), [0])
        XCTAssertEqual(plays(schedule.playbackEnded(index: 0, completed: true)), [1])
        XCTAssertEqual(plays(schedule.playbackEnded(index: 1, completed: true)), [2])
        _ = schedule.playbackEnded(index: 2, completed: true)
        XCTAssertFalse(schedule.isComplete, "still open: more sentences may come")
        _ = schedule.close()
        XCTAssertTrue(schedule.isComplete)
        XCTAssertEqual(schedule.heardCount, 3)
    }

    func testOnlyOneSentencePlaysAtATime() {
        var schedule = StreamedReplySchedule()
        _ = schedule.enqueue("One sentence.", chain: [.system])
        _ = schedule.enqueue("Two sentence.", chain: [.system])
        XCTAssertEqual(plays(schedule.synthesisSucceeded(index: 0, engine: .system)), [0])
        XCTAssertEqual(plays(schedule.synthesisSucceeded(index: 1, engine: .system)), [],
                       "ready, but the first is still playing")
        XCTAssertEqual(schedule.playingIndex, 0)
    }

    // MARK: - Depth

    func testPrefetchNeverExceedsTheDepth() {
        var schedule = StreamedReplySchedule(prefetchDepth: 2)
        var actions: [StreamedReplySchedule.Action] = []
        for index in 0..<6 { actions += schedule.enqueue("Sentence number \(index).", chain: cloud) }
        XCTAssertEqual(syntheses(actions).count, 2)
        XCTAssertEqual(prefetched(schedule), 2)

        // The head plays: one slot frees, and exactly one more sentence starts.
        let next = schedule.synthesisSucceeded(index: 0, engine: .elevenLabs)
        XCTAssertEqual(next, [.play(index: 0, engine: .elevenLabs), .synthesize(index: 2, engine: .elevenLabs)])
        XCTAssertEqual(prefetched(schedule), 2, "two synthesising while one plays")

        _ = schedule.synthesisSucceeded(index: 1, engine: .elevenLabs)
        _ = schedule.synthesisSucceeded(index: 2, engine: .elevenLabs)
        XCTAssertLessThanOrEqual(prefetched(schedule), 2)
        XCTAssertEqual(schedule.items[3].state, .waiting, "nothing beyond the depth starts early")
    }

    func testTheDepthIsClampedToThree() {
        XCTAssertEqual(StreamedReplySchedule(prefetchDepth: 9).prefetchDepth, 3)
        XCTAssertEqual(StreamedReplySchedule(prefetchDepth: 0).prefetchDepth, 1)
        XCTAssertEqual(StreamedReplySchedule().prefetchDepth, 2)
    }

    // MARK: - Fallback and demotion

    func testAFailedEngineFallsToTheNextForThatSentence() {
        var schedule = StreamedReplySchedule()
        _ = schedule.enqueue("One sentence.", chain: cloud)
        XCTAssertEqual(schedule.synthesisFailed(index: 0, engine: .elevenLabs),
                       [.synthesize(index: 0, engine: .kokoro)])
        XCTAssertEqual(schedule.synthesisFailed(index: 0, engine: .kokoro),
                       [.synthesize(index: 0, engine: .system)])
        XCTAssertFalse(schedule.cloudDemoted, "one cloud failure is a sentence's problem, not the reply's")
    }

    func testTwoConsecutiveCloudFailuresDemoteTheRestOfTheReply() {
        var schedule = StreamedReplySchedule(prefetchDepth: 2)
        _ = schedule.enqueue("First sentence here.", chain: cloud)
        _ = schedule.enqueue("Second sentence here.", chain: cloud)
        _ = schedule.enqueue("Third sentence here.", chain: cloud)
        _ = schedule.synthesisFailed(index: 0, engine: .elevenLabs)
        _ = schedule.synthesisFailed(index: 1, engine: .elevenLabs)
        XCTAssertTrue(schedule.cloudDemoted)

        // The head comes back from Kokoro and plays; the third starts — on Kokoro, not the cloud.
        let actions = schedule.synthesisSucceeded(index: 0, engine: .kokoro)
        XCTAssertTrue(actions.contains(.synthesize(index: 2, engine: .kokoro)), "\(actions)")
        XCTAssertFalse(actions.contains(.synthesize(index: 2, engine: .elevenLabs)))

        // A sentence enqueued later in the same reply never tries the cloud either.
        let later = schedule.enqueue("Fourth sentence here.", chain: cloud)
        XCTAssertFalse(later.contains(.synthesize(index: 3, engine: .elevenLabs)))
    }

    func testDemotionLastsOnlyForTheReply() {
        var first = StreamedReplySchedule()
        _ = first.enqueue("First sentence here.", chain: cloud)
        _ = first.enqueue("Second sentence here.", chain: cloud)
        _ = first.synthesisFailed(index: 0, engine: .elevenLabs)
        _ = first.synthesisFailed(index: 1, engine: .elevenLabs)
        XCTAssertTrue(first.cloudDemoted)

        var next = StreamedReplySchedule()
        XCTAssertEqual(next.enqueue("The next reply.", chain: cloud),
                       [.synthesize(index: 0, engine: .elevenLabs)], "the next reply tries the cloud again")
    }

    func testACloudSuccessBetweenFailuresDoesNotDemote() {
        var schedule = StreamedReplySchedule(prefetchDepth: 3)
        for index in 0..<3 { _ = schedule.enqueue("Sentence number \(index).", chain: cloud) }
        _ = schedule.synthesisFailed(index: 0, engine: .elevenLabs)
        _ = schedule.synthesisSucceeded(index: 1, engine: .elevenLabs)
        _ = schedule.synthesisFailed(index: 2, engine: .elevenLabs)
        XCTAssertFalse(schedule.cloudDemoted, "two failures, but not consecutive")
    }

    func testARejectionLineRidesOnTheSentenceTheNextEngineSays() {
        var schedule = StreamedReplySchedule()
        _ = schedule.enqueue("It is sunny.", chain: cloud)
        _ = schedule.synthesisFailed(index: 0, engine: .elevenLabs, appendingText: "Your cloud voice is out of credit.")
        XCTAssertEqual(schedule.items[0].text, "It is sunny. Your cloud voice is out of credit.")
    }

    func testASentenceNoEngineCouldSayIsSkippedAndTheReplyGoesOn() {
        var schedule = StreamedReplySchedule()
        _ = schedule.enqueue("One sentence.", chain: [.kokoro])
        _ = schedule.enqueue("Two sentence.", chain: [.system])
        _ = schedule.synthesisSucceeded(index: 1, engine: .system)
        let actions = schedule.synthesisFailed(index: 0, engine: .kokoro)
        XCTAssertEqual(schedule.items[0].state, .unheard)
        XCTAssertEqual(plays(actions), [1], "the next sentence is no longer blocked")
    }

    // MARK: - Cancellation

    func testAResetDropsTheRemainder() {
        var schedule = StreamedReplySchedule()
        for index in 0..<4 { _ = schedule.enqueue("Sentence number \(index).", chain: [.system]) }
        _ = schedule.synthesisSucceeded(index: 0, engine: .system)
        _ = schedule.playbackEnded(index: 0, completed: true)
        _ = schedule.synthesisSucceeded(index: 1, engine: .system)   // now playing; 2 and 3 synthesising

        let inFlight = schedule.cancel()
        XCTAssertEqual(Set(inFlight), [1, 2, 3], "the playing sentence and the two synthesising")
        XCTAssertTrue(schedule.isComplete)
        XCTAssertEqual(schedule.heardCount, 1)
        XCTAssertEqual(schedule.items.map(\.state), [.heard, .dropped, .dropped, .dropped])
        XCTAssertEqual(schedule.unheardTexts, ["Sentence number 1.", "Sentence number 2.", "Sentence number 3."],
                       "a replay starts at the first unheard sentence")

        XCTAssertEqual(schedule.synthesisSucceeded(index: 2, engine: .system), [], "late results play nothing")
        XCTAssertEqual(schedule.playbackEnded(index: 1, completed: true), [])
        XCTAssertEqual(schedule.enqueue("More text.", chain: [.system]), [])
        XCTAssertEqual(schedule.heardCount, 1, "a sentence cut off mid-play was not heard")
    }
}
