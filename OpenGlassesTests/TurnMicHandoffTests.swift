import XCTest
@testable import OpenGlasses

/// Plan GU §2 — switch first, then listen. The tone (`startTurn`) only ever comes after the route
/// resolved to the target **and** live frames arrived, or at the deadline on the phone.
final class TurnMicHandoffTests: XCTestCase {

    // MARK: - Target

    func testTargetIsTheConversationMicWhenItIsThere() {
        XCTAssertEqual(TurnMicHandoff.target(micRoute: .glasses, glassesStoodDown: false, glassesWorn: true,
                                             routePortAvailable: true), .glasses)
        XCTAssertEqual(TurnMicHandoff.target(micRoute: .glasses, glassesStoodDown: false, glassesWorn: nil,
                                             routePortAvailable: true), .glasses,
                       "unknown worn state (non-Meta glasses) keeps the glasses mic")
        XCTAssertEqual(TurnMicHandoff.target(micRoute: .headset, glassesStoodDown: false, glassesWorn: nil,
                                             routePortAvailable: true), .headset)
        XCTAssertEqual(TurnMicHandoff.target(micRoute: .phone, glassesStoodDown: false, glassesWorn: true,
                                             routePortAvailable: true), .phone)
    }

    func testGlassesNotInUseGoStraightToThePhone() {
        XCTAssertEqual(TurnMicHandoff.target(micRoute: .glasses, glassesStoodDown: true, glassesWorn: true,
                                             routePortAvailable: true), .phone, "stood down")
        XCTAssertEqual(TurnMicHandoff.target(micRoute: .glasses, glassesStoodDown: false, glassesWorn: false,
                                             routePortAvailable: true), .phone,
                       "off the face with the link up: the phone (Greig, answer 2)")
        XCTAssertEqual(TurnMicHandoff.target(micRoute: .glasses, glassesStoodDown: false, glassesWorn: true,
                                             routePortAvailable: false), .phone, "port not there")
        XCTAssertEqual(TurnMicHandoff.target(micRoute: .headset, glassesStoodDown: false, glassesWorn: nil,
                                             routePortAvailable: false), .phone)
    }

    // MARK: - Why the phone

    func testPhoneReasonNamesWhyABluetoothTurnWentToThePhone() {
        XCTAssertEqual(TurnMicHandoff.phoneReason(micRoute: .glasses, glassesStoodDown: true, glassesWorn: true,
                                                  routePortAvailable: true), .stoodDown)
        XCTAssertEqual(TurnMicHandoff.phoneReason(micRoute: .glasses, glassesStoodDown: true, glassesWorn: false,
                                                  routePortAvailable: false), .stoodDown, "stood down wins")
        XCTAssertEqual(TurnMicHandoff.phoneReason(micRoute: .glasses, glassesStoodDown: false, glassesWorn: false,
                                                  routePortAvailable: true), .notWorn)
        XCTAssertEqual(TurnMicHandoff.phoneReason(micRoute: .glasses, glassesStoodDown: false, glassesWorn: nil,
                                                  routePortAvailable: false), .portUnavailable)
        XCTAssertEqual(TurnMicHandoff.phoneReason(micRoute: .headset, glassesStoodDown: true, glassesWorn: false,
                                                  routePortAvailable: false), .portUnavailable,
                       "a headset does not care about the glasses")
    }

    func testNoPhoneReasonWhenTheTurnKeepsItsMicOrThePhoneWasChosen() {
        XCTAssertNil(TurnMicHandoff.phoneReason(micRoute: .glasses, glassesStoodDown: false, glassesWorn: true,
                                                routePortAvailable: true))
        XCTAssertNil(TurnMicHandoff.phoneReason(micRoute: .phone, glassesStoodDown: true, glassesWorn: false,
                                                routePortAvailable: false), "the phone by choice is no fallback")
    }

    /// The reason and the target are one rule read two ways: a reason exactly when a Bluetooth
    /// route was sent to the phone.
    func testPhoneReasonAgreesWithTarget() {
        for route in MicRoute.allCases {
            for stoodDown in [false, true] {
                for worn in [Bool?.none, true, false] {
                    for available in [false, true] {
                        let target = TurnMicHandoff.target(micRoute: route, glassesStoodDown: stoodDown,
                                                           glassesWorn: worn, routePortAvailable: available)
                        let reason = TurnMicHandoff.phoneReason(micRoute: route, glassesStoodDown: stoodDown,
                                                                glassesWorn: worn, routePortAvailable: available)
                        XCTAssertEqual(reason != nil, route != .phone && target == .phone,
                                       "\(route) stoodDown=\(stoodDown) worn=\(String(describing: worn)) available=\(available)")
                    }
                }
            }
        }
    }

    // MARK: - Re-reading a port that was just there

    func testAPortSeenBeforeTheSwitchIsReReadBeforeFallingBack() {
        XCTAssertTrue(TurnMicHandoff.shouldRecheckPort(wanted: .glasses, portAvailable: false,
                                                       portSeenBeforeSwitch: true))
        XCTAssertTrue(TurnMicHandoff.shouldRecheckPort(wanted: .headset, portAvailable: false,
                                                       portSeenBeforeSwitch: true))
    }

    func testNoReReadWhenThePortIsThereWasNeverSeenOrThePhoneIsWanted() {
        XCTAssertFalse(TurnMicHandoff.shouldRecheckPort(wanted: .glasses, portAvailable: true,
                                                        portSeenBeforeSwitch: true), "already there")
        XCTAssertFalse(TurnMicHandoff.shouldRecheckPort(wanted: .glasses, portAvailable: false,
                                                        portSeenBeforeSwitch: false),
                       "glasses in their case: fall back at once, as before")
        XCTAssertFalse(TurnMicHandoff.shouldRecheckPort(wanted: .phone, portAvailable: false,
                                                        portSeenBeforeSwitch: true))
    }

    func testTheReReadIsShortAgainstTheHandOffDeadline() {
        let total = Double(TurnMicHandoff.portRecheckAttempts) * TurnMicHandoff.portRecheckInterval
        XCTAssertGreaterThanOrEqual(total, 0.3)
        XCTAssertLessThanOrEqual(total, 0.5)
        XCTAssertLessThan(total, TurnMicHandoff.deadline)
    }

    // MARK: - Keeping the idle session in the background

    /// Locked phone, idle listener live on the glasses' hands-free port: no re-tune at all — iOS
    /// refuses it from the background and the refusal costs the turn its glasses mic.
    func testABackgroundedTurnOnALiveHandsFreeSessionKeepsIt() {
        for route in [MicRoute.glasses, .headset] {
            XCTAssertEqual(TurnMicHandoff.sessionSwitch(wanted: route, appInForeground: false,
                                                        portSeenBeforeSwitch: true, engineRunning: true),
                           .keepIdleSession, "\(route)")
        }
    }

    func testTheForegroundStillReconfigures() {
        XCTAssertEqual(TurnMicHandoff.sessionSwitch(wanted: .glasses, appInForeground: true,
                                                    portSeenBeforeSwitch: true, engineRunning: true),
                       .reconfigure, "in the foreground the non-mixable switch works and pauses other audio")
    }

    func testABackgroundedTurnWithNothingLiveToKeepReconfigures() {
        XCTAssertEqual(TurnMicHandoff.sessionSwitch(wanted: .glasses, appInForeground: false,
                                                    portSeenBeforeSwitch: false, engineRunning: true),
                       .reconfigure, "an idle phone-mic session lists no hands-free port")
        XCTAssertEqual(TurnMicHandoff.sessionSwitch(wanted: .glasses, appInForeground: false,
                                                    portSeenBeforeSwitch: true, engineRunning: false),
                       .reconfigure, "no running engine: the session may not be active, nothing to keep")
        XCTAssertEqual(TurnMicHandoff.sessionSwitch(wanted: .phone, appInForeground: false,
                                                    portSeenBeforeSwitch: true, engineRunning: true),
                       .reconfigure, "the phone route leaves the hands-free shape")
    }

    /// Only one combination keeps the session.
    func testKeepingIsTheSingleBackgroundedLiveBluetoothCase() {
        for route in MicRoute.allCases {
            for foreground in [false, true] {
                for seen in [false, true] {
                    for running in [false, true] {
                        let step = TurnMicHandoff.sessionSwitch(wanted: route, appInForeground: foreground,
                                                                portSeenBeforeSwitch: seen, engineRunning: running)
                        let expected: TurnMicHandoff.SessionSwitch =
                            route != .phone && !foreground && seen && running ? .keepIdleSession : .reconfigure
                        XCTAssertEqual(step, expected,
                                       "\(route) foreground=\(foreground) seen=\(seen) running=\(running)")
                    }
                }
            }
        }
    }

    // MARK: - Sequencing

    func testRouteThenFramesThenTheTurn() {
        var m = TurnMicHandoff.Machine(target: .glasses)
        XCTAssertEqual(m.handle(.routeObserved(.phone)), .none, "not there yet")
        XCTAssertEqual(m.handle(.routeObserved(nil)), .none)
        XCTAssertEqual(m.handle(.routeObserved(.glasses)), .buildEngine)
        XCTAssertEqual(m.state, .waitingForFrames)
        XCTAssertEqual(m.handle(.framesNonSilent), .startTurn(on: .glasses))
        XCTAssertEqual(m.state, .live(.glasses))
    }

    func testToneNeverBeforeLive() {
        // Frames before the route was seen — a half-up link's buffers on the old input — must not
        // start the turn.
        var m = TurnMicHandoff.Machine(target: .glasses)
        XCTAssertEqual(m.handle(.framesNonSilent), .none)
        XCTAssertEqual(m.state, .waitingForRoute)
        // The route alone is not enough either.
        _ = m.handle(.routeObserved(.glasses))
        XCTAssertNotEqual(m.state, .live(.glasses))
    }

    func testDeadlineFallsBackToThePhone() {
        var waitingForRoute = TurnMicHandoff.Machine(target: .glasses)
        XCTAssertEqual(waitingForRoute.handle(.deadline), .fallBackToPhone)
        XCTAssertEqual(waitingForRoute.state, .fellBack)

        var waitingForFrames = TurnMicHandoff.Machine(target: .headset)
        _ = waitingForFrames.handle(.routeObserved(.headset))
        XCTAssertEqual(waitingForFrames.handle(.deadline), .fallBackToPhone, "a link that is up but silent")
        XCTAssertEqual(TurnMicHandoff.deadline, 2.0)
    }

    func testThePhoneStartsAtTheDeadlineRatherThanFallingFurther() {
        var m = TurnMicHandoff.Machine(target: .phone)
        XCTAssertEqual(m.handle(.deadline), .startTurn(on: .phone))
        XCTAssertEqual(m.state, .live(.phone))
    }

    func testNothingStartsTwice() {
        var m = TurnMicHandoff.Machine(target: .glasses)
        _ = m.handle(.routeObserved(.glasses))
        XCTAssertEqual(m.handle(.framesNonSilent), .startTurn(on: .glasses))
        XCTAssertEqual(m.handle(.framesNonSilent), .none)
        XCTAssertEqual(m.handle(.deadline), .none, "a deadline after going live does nothing")
        var fell = TurnMicHandoff.Machine(target: .glasses)
        _ = fell.handle(.deadline)
        XCTAssertEqual(fell.handle(.routeObserved(.glasses)), .none, "too late: the phone has the turn")
        XCTAssertEqual(fell.handle(.framesNonSilent), .none)
    }

    func testLiveFramesAreAboveTheZeroFloor() {
        XCTAssertFalse(TurnMicHandoff.isLiveFrame(rms: 0), "a half-up link's all-zero frames")
        XCTAssertFalse(TurnMicHandoff.isLiveFrame(rms: 1e-7))
        XCTAssertTrue(TurnMicHandoff.isLiveFrame(rms: 1e-4), "a quiet room is still a live mic")
    }
}
