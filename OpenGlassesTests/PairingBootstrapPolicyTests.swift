import XCTest
@testable import OpenGlasses

/// Plan AR: the table that decides when a gateway-issued device token may be stored.
final class PairingBootstrapPolicyTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let window: TimeInterval = 600

    private func apply(_ event: PairingBootstrapPolicy.Event,
                       to state: PairingBootstrapPolicy.State) -> PairingBootstrapPolicy.Transition {
        PairingBootstrapPolicy.apply(event, to: state)
    }

    private var pairingA: PairingBootstrapPolicy.State {
        .bootstrapping(gatewayId: "A", deadline: t0.addingTimeInterval(window))
    }

    // MARK: - Starting

    func testStartOpensAWindowForThatGateway() {
        let transition = apply(.started(gatewayId: "A", at: t0, window: window), to: .idle)
        XCTAssertEqual(transition.state, pairingA)
        XCTAssertNil(transition.token)
        XCTAssertNil(transition.ended)
    }

    func testRestartReplacesTheRunningBootstrap() {
        let later = t0.addingTimeInterval(100)
        let transition = apply(.started(gatewayId: "B", at: later, window: window), to: pairingA)
        XCTAssertEqual(transition.state,
                       .bootstrapping(gatewayId: "B", deadline: later.addingTimeInterval(window)))
    }

    func testDefaultWindowIsTenMinutes() {
        let transition = apply(.started(gatewayId: "A", at: t0), to: .idle)
        XCTAssertEqual(transition.state,
                       .bootstrapping(gatewayId: "A", deadline: t0.addingTimeInterval(600)))
    }

    // MARK: - device.paired (unsolicited)

    func testUnsolicitedPairedEventWhileIdleIsIgnored() {
        let transition = apply(.pairedEventToken(gatewayId: "A", at: t0), to: .idle)
        XCTAssertEqual(transition.token, .ignore(.noBootstrap))
        XCTAssertEqual(transition.state, .idle)
        XCTAssertNil(transition.ended)
    }

    func testPairedEventInsideTheWindowIsStoredAndEndsTheBootstrap() {
        let transition = apply(.pairedEventToken(gatewayId: "A", at: t0.addingTimeInterval(30)), to: pairingA)
        XCTAssertEqual(transition.token, .store)
        XCTAssertEqual(transition.state, .idle)
        XCTAssertEqual(transition.ended, .paired)
    }

    func testPairedEventAtTheDeadlineIsStillInside() {
        let transition = apply(.pairedEventToken(gatewayId: "A", at: t0.addingTimeInterval(window)), to: pairingA)
        XCTAssertEqual(transition.token, .store)
    }

    func testSecondTokenInOneBootstrapIsIgnored() {
        let first = apply(.pairedEventToken(gatewayId: "A", at: t0.addingTimeInterval(10)), to: pairingA)
        XCTAssertEqual(first.token, .store)
        let second = apply(.pairedEventToken(gatewayId: "A", at: t0.addingTimeInterval(11)), to: first.state)
        XCTAssertEqual(second.token, .ignore(.noBootstrap))
        XCTAssertNil(second.ended, "the bootstrap already ended once")
    }

    func testPairedEventWhenAlreadyPairedIsIgnored() {
        // Paired by the handshake: the reply's token closed the bootstrap.
        let paired = apply(.connectReplyToken(gatewayId: "A", at: t0.addingTimeInterval(5)), to: pairingA)
        XCTAssertEqual(paired.ended, .paired)
        let planted = apply(.pairedEventToken(gatewayId: "A", at: t0.addingTimeInterval(6)), to: paired.state)
        XCTAssertEqual(planted.token, .ignore(.noBootstrap))
    }

    func testPairedEventAfterTheWindowIsIgnoredAndEndsTheBootstrap() {
        let late = t0.addingTimeInterval(window + 1)
        let transition = apply(.pairedEventToken(gatewayId: "A", at: late), to: pairingA)
        XCTAssertEqual(transition.token, .ignore(.bootstrapExpired))
        XCTAssertEqual(transition.state, .idle)
        XCTAssertEqual(transition.ended, .timedOut)
    }

    func testPairedEventAfterTheTimerFiredIsIgnored() {
        let timedOut = apply(.timerFired(at: t0.addingTimeInterval(window + 1)), to: pairingA)
        XCTAssertEqual(timedOut.ended, .timedOut)
        let late = apply(.pairedEventToken(gatewayId: "A", at: t0.addingTimeInterval(window + 2)), to: timedOut.state)
        XCTAssertEqual(late.token, .ignore(.noBootstrap))
    }

    func testPairedEventAfterCancelIsIgnored() {
        let cancelled = apply(.cancelled, to: pairingA)
        XCTAssertEqual(cancelled.ended, .cancelled)
        XCTAssertEqual(cancelled.state, .idle)
        let late = apply(.pairedEventToken(gatewayId: "A", at: t0.addingTimeInterval(1)), to: cancelled.state)
        XCTAssertEqual(late.token, .ignore(.noBootstrap))
    }

    func testPairedEventFromAnotherGatewayIsIgnoredAndKeepsWaiting() {
        let transition = apply(.pairedEventToken(gatewayId: "B", at: t0.addingTimeInterval(1)), to: pairingA)
        XCTAssertEqual(transition.token, .ignore(.otherGateway))
        XCTAssertEqual(transition.state, pairingA)
        XCTAssertNil(transition.ended)
    }

    func testPairedEventOnASocketWithNoGatewayIsIgnored() {
        let transition = apply(.pairedEventToken(gatewayId: nil, at: t0.addingTimeInterval(1)), to: pairingA)
        XCTAssertEqual(transition.token, .ignore(.otherGateway))
    }

    // MARK: - The connect reply

    func testConnectReplyTokenIsStoredWhileIdle() {
        // The answer to our own connect is the handshake, not an unsolicited claim.
        let transition = apply(.connectReplyToken(gatewayId: "A", at: t0), to: .idle)
        XCTAssertEqual(transition.token, .store)
        XCTAssertEqual(transition.state, .idle)
        XCTAssertNil(transition.ended)
    }

    func testConnectReplyTokenCompletesTheBootstrapForItsGateway() {
        let transition = apply(.connectReplyToken(gatewayId: "A", at: t0.addingTimeInterval(1)), to: pairingA)
        XCTAssertEqual(transition.token, .store)
        XCTAssertEqual(transition.state, .idle)
        XCTAssertEqual(transition.ended, .paired)
    }

    func testConnectReplyTokenForAnotherGatewayLeavesTheBootstrapRunning() {
        let transition = apply(.connectReplyToken(gatewayId: "B", at: t0.addingTimeInterval(1)), to: pairingA)
        XCTAssertEqual(transition.token, .store)
        XCTAssertEqual(transition.state, pairingA)
        XCTAssertNil(transition.ended)
    }

    // MARK: - Timer and cancel

    func testTimerBeforeTheDeadlineChangesNothing() {
        let transition = apply(.timerFired(at: t0.addingTimeInterval(window - 1)), to: pairingA)
        XCTAssertEqual(transition.state, pairingA)
        XCTAssertNil(transition.ended)
    }

    func testStaleTimerDoesNotEndARestartedBootstrap() {
        let restarted = apply(.started(gatewayId: "A", at: t0.addingTimeInterval(500), window: window), to: pairingA)
        // The first bootstrap's timer fires at its own deadline, inside the new window.
        let transition = apply(.timerFired(at: t0.addingTimeInterval(window + 1)), to: restarted.state)
        XCTAssertEqual(transition.state, restarted.state)
        XCTAssertNil(transition.ended)
    }

    func testTimerAndCancelWhileIdleDoNothing() {
        XCTAssertEqual(apply(.timerFired(at: t0), to: .idle), .init(state: .idle))
        XCTAssertEqual(apply(.cancelled, to: .idle), .init(state: .idle))
    }

    func testLifecycleEventsNeverCarryATokenVerdict() {
        for event: PairingBootstrapPolicy.Event in [
            .started(gatewayId: "A", at: t0, window: window), .cancelled, .timerFired(at: t0),
        ] {
            for state: PairingBootstrapPolicy.State in [.idle, pairingA] {
                XCTAssertNil(apply(event, to: state).token, "\(event) on \(state)")
            }
        }
    }
}
