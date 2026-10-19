import XCTest
@testable import OpenGlasses

/// Tests for Live Coach (Plan C) pure logic: domain parsing, per-domain prompts, and dedup
/// similarity. The frame loop itself (camera + live LLM) isn't unit-tested.
@MainActor
final class LiveCoachTests: XCTestCase {

    func testDomainParsingAliases() {
        XCTAssertEqual(LiveCoachDomain(rawValue: "posture"), .posture)
        XCTAssertEqual(LiveCoachDomain(rawValue: "sports"), .sportsTactics)
        XCTAssertEqual(LiveCoachDomain(rawValue: "COOKING"), .cookingForm)
        XCTAssertNil(LiveCoachDomain(rawValue: "underwater_basket_weaving"))
    }

    func testDomainPromptRespectsMaxWords() {
        let prompt = LiveCoachDomain.posture.systemPrompt(maxWords: 12, customPrompt: nil)
        XCTAssertTrue(prompt.contains("12 words"))
        XCTAssertTrue(prompt.lowercased().contains("spine"))
    }

    func testCustomDomainUsesCustomPrompt() {
        let prompt = LiveCoachDomain.custom.systemPrompt(maxWords: 20, customPrompt: "Watch my pottery wheel centering.")
        XCTAssertTrue(prompt.contains("pottery wheel centering"))
    }

    func testDedupTreatsNearIdenticalAsSimilar() {
        XCTAssertTrue(LiveCoachService.isSimilar("Straighten your back and relax shoulders",
                                                 "Straighten your back, relax your shoulders"))
    }

    func testDedupTreatsDifferentAdviceAsDistinct() {
        XCTAssertFalse(LiveCoachService.isSimilar("Straighten your back",
                                                  "Move your left foot to the higher hold"))
    }

    func testNotConfiguredByDefaultDoesNotCrashStatus() {
        XCTAssertEqual(LiveCoachService.shared.statusSummary(), "Live Coach is not running.")
    }

    // MARK: - Plan HY P2: the change gate and the call budget

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let sameView: UInt64 = 0x0F0F_0F0F_0F0F_0F0F
    private let otherView: UInt64 = 0xF0F0_F0F0_F0F0_F0F0

    func testUnchangedViewIsNotReSentBeforeTheHeartbeat() {
        var pacer = LiveCoachPacer()
        XCTAssertEqual(pacer.consider(hash: sameView, now: t0), .send, "the first frame goes")
        for second in stride(from: 2.0, to: LiveCoachPacer.heartbeat, by: 2) {
            XCTAssertEqual(pacer.consider(hash: sameView, now: t0.addingTimeInterval(second)), .unchanged,
                           "an unchanged view at \(second) s")
        }
        XCTAssertEqual(pacer.consider(hash: sameView, now: t0.addingTimeInterval(LiveCoachPacer.heartbeat)),
                       .send, "the heartbeat re-sends a still scene")
        XCTAssertEqual(LiveCoachPacer.heartbeat, 30)
    }

    func testAChangedViewGoesAtOnce() {
        var pacer = LiveCoachPacer()
        _ = pacer.consider(hash: sameView, now: t0)
        XCTAssertEqual(pacer.consider(hash: otherView, now: t0.addingTimeInterval(2)), .send)
    }

    func testAnUnreadableFrameIsSent() {
        var pacer = LiveCoachPacer()
        _ = pacer.consider(hash: sameView, now: t0)
        XCTAssertEqual(pacer.consider(hash: nil, now: t0.addingTimeInterval(2)), .send)
    }

    func testOnlyForwardedFramesSpendTheBudget() {
        var pacer = LiveCoachPacer(budget: CallBudget(limit: 5, window: 3600))
        _ = pacer.consider(hash: sameView, now: t0)
        for second in stride(from: 2.0, to: 30, by: 2) {
            _ = pacer.consider(hash: sameView, now: t0.addingTimeInterval(second))
        }
        XCTAssertEqual(pacer.budget.remaining(now: t0.addingTimeInterval(30)), 4,
                       "fourteen dropped frames cost nothing")
    }

    func testBudgetSpentIsSaidOnce() {
        var pacer = LiveCoachPacer(budget: CallBudget(limit: 2, window: 3600))
        XCTAssertEqual(pacer.checkBudget(now: t0), .open)
        _ = pacer.consider(hash: sameView, now: t0)
        XCTAssertEqual(pacer.checkBudget(now: t0.addingTimeInterval(2)), .open)
        _ = pacer.consider(hash: otherView, now: t0.addingTimeInterval(2))

        XCTAssertEqual(pacer.checkBudget(now: t0.addingTimeInterval(4)), .spent(announce: true))
        XCTAssertEqual(pacer.checkBudget(now: t0.addingTimeInterval(6)), .spent(announce: false))
        XCTAssertEqual(pacer.checkBudget(now: t0.addingTimeInterval(600)), .spent(announce: false),
                       "said once, not once per tick")
        XCTAssertEqual(LiveCoachPacer.spentLine,
                       "I've given a lot of advice this hour; I'll check in less often.")
    }

    /// Spent is not stopped: the coach checks in again as soon as the window frees a call.
    func testASpentBudgetChecksInAgainWhenTheWindowFreesACall() {
        var pacer = LiveCoachPacer(budget: CallBudget(limit: 1, window: 3600))
        _ = pacer.consider(hash: sameView, now: t0)
        _ = pacer.checkBudget(now: t0.addingTimeInterval(10))
        XCTAssertEqual(pacer.nextCallAt(now: t0.addingTimeInterval(10)), t0.addingTimeInterval(3600))
        XCTAssertEqual(pacer.checkBudget(now: t0.addingTimeInterval(3600)), .open)
        XCTAssertEqual(pacer.consider(hash: otherView, now: t0.addingTimeInterval(3600)), .send)
    }

    /// A tick the budget refuses never reaches the gate, so it cannot stand in for a send: the next
    /// unchanged view after the window frees is judged against the last frame that really went.
    func testARefusedTickDoesNotMoveTheGate() {
        var pacer = LiveCoachPacer(budget: CallBudget(limit: 1, window: 60))
        _ = pacer.consider(hash: sameView, now: t0)
        XCTAssertEqual(pacer.checkBudget(now: t0.addingTimeInterval(10)), .spent(announce: true))
        XCTAssertEqual(pacer.gate.evaluatedCount, 1)
        XCTAssertEqual(pacer.checkBudget(now: t0.addingTimeInterval(60)), .open)
        XCTAssertEqual(pacer.consider(hash: sameView, now: t0.addingTimeInterval(60)), .send,
                       "past the heartbeat since the last real send")
    }
}
