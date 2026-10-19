import XCTest
@testable import OpenGlasses

/// Plan HY P0 — what a mode switch carries into the next live session: each row of the handover
/// table, the Direct freshness rule, the pending-seed clearing rule, and that the block is
/// `LiveContextHandover`'s own.
final class ModeSwitchHandoverTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func redial(from old: AppMode, to new: AppMode) -> [ModeSwitchAction] {
        ModeSwitchPolicy.actions(from: old, to: new, wasSessionActive: true, autoRedial: true)
    }

    private let liveTurns = [
        LiveTurnRecord(speaker: .wearer, text: "Which of these two fuses is blown?"),
        LiveTurnRecord(speaker: .assistant, text: "The left one has a broken filament."),
    ]

    private func directTurn(_ speaker: LiveTurnRecord.Speaker, _ text: String,
                            ago seconds: TimeInterval) -> ModeSwitchHandover.DirectTurn {
        .init(speaker: speaker, text: text, at: now.addingTimeInterval(-seconds))
    }

    // MARK: - live → live (the CF redial)

    func testRedialCarriesTheOldSessionsTurns() throws {
        let block = try XCTUnwrap(ModeSwitchHandover.seed(
            from: .geminiLive, to: .openaiRealtime, actions: redial(from: .geminiLive, to: .openaiRealtime),
            oldRecorderTurns: liveTurns, directTurns: [], now: now))
        XCTAssertTrue(block.hasPrefix(LiveContextHandover.blockHeading),
                      "the block is LiveContextHandover's, heading and all")
        XCTAssertTrue(block.contains("Which of these two fuses is blown?"))
        XCTAssertTrue(block.contains("The left one has a broken filament."))
        XCTAssertEqual(block, LiveContextHandover.build(turns: liveTurns, cause: .modeSwitch))
    }

    func testRedialSaysItWasASwitchNotADroppedConnection() throws {
        let block = try XCTUnwrap(ModeSwitchHandover.seed(
            from: .openaiRealtime, to: .geminiLive, actions: redial(from: .openaiRealtime, to: .geminiLive),
            oldRecorderTurns: liveTurns, directTurns: [], now: now))
        XCTAssertTrue(block.contains("switched assistants"))
        XCTAssertFalse(block.contains("connection dropped and the previous session"),
                       "nothing failed, and the model must not be told it did")
    }

    func testRedialIgnoresTheDirectThread() throws {
        let block = try XCTUnwrap(ModeSwitchHandover.seed(
            from: .geminiLive, to: .openaiRealtime, actions: redial(from: .geminiLive, to: .openaiRealtime),
            oldRecorderTurns: liveTurns,
            directTurns: [directTurn(.wearer, "An old typed question", ago: 30)], now: now))
        XCTAssertFalse(block.contains("An old typed question"))
    }

    func testLiveSwitchWithoutARedialSeedsNothing() {
        let actions = ModeSwitchPolicy.actions(from: .geminiLive, to: .openaiRealtime,
                                               wasSessionActive: false, autoRedial: true)
        XCTAssertNil(ModeSwitchHandover.seed(from: .geminiLive, to: .openaiRealtime, actions: actions,
                                             oldRecorderTurns: liveTurns, directTurns: [], now: now))
        let killSwitch = ModeSwitchPolicy.actions(from: .geminiLive, to: .openaiRealtime,
                                                  wasSessionActive: true, autoRedial: false)
        XCTAssertNil(ModeSwitchHandover.seed(from: .geminiLive, to: .openaiRealtime, actions: killSwitch,
                                             oldRecorderTurns: liveTurns, directTurns: [], now: now))
    }

    func testRedialWithNothingSaidSeedsNothing() {
        XCTAssertNil(ModeSwitchHandover.seed(
            from: .geminiLive, to: .openaiRealtime, actions: redial(from: .geminiLive, to: .openaiRealtime),
            oldRecorderTurns: [], directTurns: [], now: now))
    }

    func testRedialKeepsAnInterruptedAnswerMarked() throws {
        let turns = [LiveTurnRecord(speaker: .wearer, text: "Read me the label"),
                     LiveTurnRecord(speaker: .assistant, text: "It says three", wasInterrupted: true)]
        let block = try XCTUnwrap(ModeSwitchHandover.seed(
            from: .geminiLive, to: .openaiCompatibleRealtime,
            actions: redial(from: .geminiLive, to: .openaiCompatibleRealtime),
            oldRecorderTurns: turns, directTurns: [], now: now))
        XCTAssertTrue(block.contains("Do not treat this answer as delivered"))
    }

    // MARK: - Direct → live

    func testDirectToLiveCarriesTheLastSixTurnsWhenFresh() throws {
        let turns = (0..<8).map { index in
            directTurn(index.isMultiple(of: 2) ? .wearer : .assistant, "turn \(index)",
                       ago: TimeInterval(600 - index * 60))
        }
        let actions = ModeSwitchPolicy.actions(from: .direct, to: .geminiLive,
                                               wasSessionActive: false, autoRedial: true)
        XCTAssertFalse(actions.contains(.startSession(.geminiLive)), "Direct never redials")
        let block = try XCTUnwrap(ModeSwitchHandover.seed(
            from: .direct, to: .geminiLive, actions: actions, oldRecorderTurns: [],
            directTurns: turns, now: now))
        XCTAssertFalse(block.contains("\"turn 0\""))
        XCTAssertFalse(block.contains("\"turn 1\""))
        for index in 2..<8 { XCTAssertTrue(block.contains("\"turn \(index)\""), "turn \(index)") }
        XCTAssertTrue(block.contains("- They said: \"turn 2\""))
        XCTAssertTrue(block.contains("- You answered: \"turn 3\""))
    }

    func testDirectSeedOlderThanTenMinutesIsDropped() {
        let stale = [directTurn(.wearer, "What's the torque spec?", ago: 11 * 60),
                     directTurn(.assistant, "Twenty-five newton metres.", ago: 11 * 60 - 5)]
        XCTAssertNil(ModeSwitchHandover.seed(from: .direct, to: .openaiRealtime, actions: [],
                                             oldRecorderTurns: [], directTurns: stale, now: now))
    }

    func testDirectFreshnessIsStrictlyUnderTenMinutes() {
        let atLimit = [directTurn(.wearer, "On the line", ago: ModeSwitchHandover.directFreshness)]
        XCTAssertNil(ModeSwitchHandover.seed(from: .direct, to: .geminiLive, actions: [],
                                             oldRecorderTurns: [], directTurns: atLimit, now: now))
        let justInside = [directTurn(.wearer, "Just inside", ago: ModeSwitchHandover.directFreshness - 1)]
        XCTAssertNotNil(ModeSwitchHandover.seed(from: .direct, to: .geminiLive, actions: [],
                                                oldRecorderTurns: [], directTurns: justInside, now: now))
    }

    func testFreshnessIsJudgedByTheNewestTurn() {
        let turns = [directTurn(.wearer, "Long ago", ago: 3600),
                     directTurn(.assistant, "Moments ago", ago: 20)]
        XCTAssertNotNil(ModeSwitchHandover.seed(from: .direct, to: .geminiLive, actions: [],
                                                oldRecorderTurns: [], directTurns: turns, now: now))
    }

    func testEmptyDirectThreadSeedsNothing() {
        XCTAssertNil(ModeSwitchHandover.seed(from: .direct, to: .geminiLive, actions: [],
                                             oldRecorderTurns: [], directTurns: [], now: now))
        XCTAssertNil(ModeSwitchHandover.seed(from: .direct, to: .geminiLive, actions: [],
                                             oldRecorderTurns: [],
                                             directTurns: [directTurn(.wearer, "   ", ago: 5)], now: now))
    }

    // MARK: - anything → Direct

    func testSwitchingToDirectSeedsNothing() {
        let actions = ModeSwitchPolicy.actions(from: .geminiLive, to: .direct,
                                               wasSessionActive: true, autoRedial: true)
        XCTAssertNil(ModeSwitchHandover.seed(from: .geminiLive, to: .direct, actions: actions,
                                             oldRecorderTurns: liveTurns,
                                             directTurns: [directTurn(.wearer, "x", ago: 5)], now: now))
    }

    // MARK: - A later switch clears a pending seed

    func testALaterSwitchClearsTheSeedAnEarlierSwitchLeft() {
        let block = "RECOVERED CONVERSATION CONTEXT:\n…"
        XCTAssertTrue(ModeSwitchHandover.clearsPendingSeed(pending: block, seededBySwitch: block))
    }

    func testALaterSwitchLeavesTheOfflineHandoffsBlockAlone() {
        XCTAssertFalse(ModeSwitchHandover.clearsPendingSeed(pending: "the phone's answers",
                                                            seededBySwitch: "an older switch seed"))
        XCTAssertFalse(ModeSwitchHandover.clearsPendingSeed(pending: "the phone's answers",
                                                            seededBySwitch: nil))
    }

    func testNothingPendingIsNothingToClear() {
        XCTAssertFalse(ModeSwitchHandover.clearsPendingSeed(pending: nil, seededBySwitch: "consumed"))
    }

    // MARK: - Reading the Direct thread

    func testDirectTurnsKeepOnlyTheWearerAndTheAssistant() {
        let messages = [ConversationMessage(role: "system", content: "Job context"),
                        ConversationMessage(role: "user", content: "Is it live?"),
                        ConversationMessage(role: "assistant", content: "Isolate it first.")]
        let turns = ModeSwitchHandover.directTurns(from: messages)
        XCTAssertEqual(turns.map(\.speaker), [.wearer, .assistant])
        XCTAssertEqual(turns.map(\.text), ["Is it live?", "Isolate it first."])
        XCTAssertEqual(turns.map(\.at), [messages[1].timestamp, messages[2].timestamp])
    }

    // MARK: - The reconnect handover is unchanged

    func testTheConnectionLostPreambleIsStillTheDefault() throws {
        let block = try XCTUnwrap(LiveContextHandover.build(turns: liveTurns))
        XCTAssertTrue(block.contains("The live connection dropped and the previous session could not be restored"))
        XCTAssertFalse(block.contains("switched assistants"))
    }
}
