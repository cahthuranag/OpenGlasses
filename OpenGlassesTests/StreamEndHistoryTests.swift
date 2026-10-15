import XCTest
@testable import OpenGlasses

// Plan HJ P0 — how many times a wanted stream has ended recently, on an injected clock.

final class StreamEndHistoryTests: XCTestCase {

    /// A clock a test moves by hand.
    private final class ManualClock {
        var now: TimeInterval = 1_000
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    private func makeHistory(_ clock: ManualClock,
                             retention: TimeInterval = StreamEndRecoveryPolicy.flapWindow) -> StreamEndHistory {
        StreamEndHistory(retention: retention, clock: { clock.now })
    }

    func testEndsInsideTheWindowCount() {
        let clock = ManualClock()
        var history = makeHistory(clock)
        history.recordEnd()
        clock.advance(10)
        history.recordEnd()
        clock.advance(10)
        history.recordEnd()
        XCTAssertEqual(history.count(within: StreamEndRecoveryPolicy.flapWindow), 3)
        XCTAssertEqual(history.count(within: 15), 2)
    }

    func testEndsOutsideTheWindowAgeOut() {
        let clock = ManualClock()
        var history = makeHistory(clock)
        history.recordEnd()
        clock.advance(StreamEndRecoveryPolicy.flapWindow + 1)
        XCTAssertEqual(history.count(within: StreamEndRecoveryPolicy.flapWindow), 0)
        history.recordEnd()
        XCTAssertEqual(history.count(within: StreamEndRecoveryPolicy.flapWindow), 1)
        // And are dropped once retention has passed, so a long session does not grow the list.
        XCTAssertEqual(history.ends.count, 1)
    }

    /// The loop this exists to stop: every successful reconnect used to zero every counter.
    func testARecordedRecoveryDoesNotClear() {
        let clock = ManualClock()
        var history = makeHistory(clock)
        history.recordEnd()
        clock.advance(12)
        history.recordRecovery()
        clock.advance(8)
        history.recordEnd()
        history.recordRecovery()
        XCTAssertEqual(history.count(within: StreamEndRecoveryPolicy.flapWindow), 2)
    }

    func testSecondsSinceRecoveryIsForTheLog() {
        let clock = ManualClock()
        var history = makeHistory(clock)
        XCTAssertNil(history.secondsSinceRecovery)
        history.recordRecovery()
        clock.advance(9)
        XCTAssertEqual(history.secondsSinceRecovery, 9)
    }

    func testResetClears() {
        let clock = ManualClock()
        var history = makeHistory(clock)
        history.recordEnd()
        history.recordEnd()
        history.recordRecovery()
        history.reset()
        XCTAssertEqual(history.count(within: StreamEndRecoveryPolicy.flapWindow), 0)
        XCTAssertNil(history.secondsSinceRecovery)
    }

    /// The flap row, driven by the history the backend keeps: three ends inside the window stop
    /// the ladder even though each one was followed by a successful reconnect.
    func testThreeEndsBetweenReconnectsTripTheFlapRow() {
        let clock = ManualClock()
        var history = makeHistory(clock)
        var decisions: [StreamEndRecoveryPolicy.Decision] = []
        for _ in 0..<StreamEndRecoveryPolicy.flapLimit {
            history.recordEnd()
            decisions.append(StreamEndRecoveryPolicy.decide(
                cause: .streamStopped, presence: .foreground, streamingIntended: true,
                transitionIsOurs: false, attempt: 0,
                recentEnds: history.count(within: StreamEndRecoveryPolicy.flapWindow)))
            clock.advance(15)      // a cold start and a few seconds of frames
            history.recordRecovery()
            clock.advance(10)
        }
        XCTAssertEqual(Array(decisions.dropLast()), [.retry(after: 1.5, attempt: 0), .retry(after: 1.5, attempt: 0)])
        XCTAssertEqual(decisions.last, .giveUp(notice: StreamEndRecoveryPolicy.flapNotice))
    }

    func testTheDefaultClockMovesForward() {
        let first = StreamEndHistory.continuousSeconds()
        let second = StreamEndHistory.continuousSeconds()
        XCTAssertGreaterThanOrEqual(second, first)
    }
}
