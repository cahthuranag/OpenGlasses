import XCTest
@testable import OpenGlasses

/// Plan JM P0 — the phone-mic hint: once per process, only after a turn the wearer opened heard
/// nothing on the glasses mic, only in Direct mode.
final class MicRouteHintPolicyTests: XCTestCase {

    func testHintsOnceThenNeverAgain() {
        var policy = MicRouteHintPolicy()
        XCTAssertTrue(policy.shouldHint(route: .glasses, outcome: .noSpeech, mode: .direct))
        XCTAssertTrue(policy.hasHinted)
        for _ in 0..<5 {
            XCTAssertFalse(policy.shouldHint(route: .glasses, outcome: .noSpeech, mode: .direct))
        }
    }

    func testNeverInTheRealtimeModes() {
        var policy = MicRouteHintPolicy()
        for mode in AppMode.allCases where mode != .direct {
            XCTAssertFalse(policy.shouldHint(route: .glasses, outcome: .noSpeech, mode: mode), "\(mode)")
        }
        XCTAssertFalse(policy.hasHinted, "a refusal spends nothing")
        XCTAssertTrue(policy.shouldHint(route: .glasses, outcome: .noSpeech, mode: .direct))
    }

    func testOnlyOnTheGlassesMic() {
        var policy = MicRouteHintPolicy()
        XCTAssertFalse(policy.shouldHint(route: .phone, outcome: .noSpeech, mode: .direct))
        XCTAssertFalse(policy.shouldHint(route: .headset, outcome: .noSpeech, mode: .direct))
        XCTAssertFalse(policy.hasHinted)
    }

    func testOnlyAfterAWearerOpenedTurnHeardNothing() {
        var policy = MicRouteHintPolicy()
        XCTAssertFalse(policy.shouldHint(route: .glasses, outcome: .recognised, mode: .direct))
        XCTAssertFalse(policy.shouldHint(route: .glasses, outcome: .followUpUnanswered, mode: .direct),
                       "a follow-up nobody answered is the end of a conversation, not noise")
        XCTAssertFalse(policy.hasHinted)
        XCTAssertTrue(policy.shouldHint(route: .glasses, outcome: .noSpeech, mode: .direct))
    }

    func testResetAllowsOneMore() {
        var policy = MicRouteHintPolicy()
        XCTAssertTrue(policy.shouldHint(route: .glasses, outcome: .noSpeech, mode: .direct))
        policy.reset()
        XCTAssertFalse(policy.hasHinted)
        XCTAssertTrue(policy.shouldHint(route: .glasses, outcome: .noSpeech, mode: .direct))
        XCTAssertFalse(policy.shouldHint(route: .glasses, outcome: .noSpeech, mode: .direct))
    }

    func testTheHintNamesTheRealSettingAndNoPlanLetter() {
        let message = MicRouteHintPolicy.message
        XCTAssertTrue(message.contains("iPhone Mic"), "names the choice as the picker shows it")
        XCTAssertTrue(message.contains(MicRoute.phone.label))
        XCTAssertTrue(message.contains("Hardware & Privacy"))
        XCTAssertFalse(message.contains("Plan"))
    }
}
