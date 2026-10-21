import XCTest
@testable import OpenGlasses

/// Plan JM P3 — the rule for keeping the last question's audio for the recogniser comparison.
///
/// `TranscriptionService` cannot be driven headlessly with real buffers (its capture hangs off an
/// audio engine tap), so the retention rule it delegates to is tested here as the pure value it
/// is: `beginTurn` / `append` / `endTurn` / `clear` are exactly the four calls the service makes.
final class UtteranceRetentionTests: XCTestCase {

    private let at = Date(timeIntervalSince1970: 1_000)

    private func turn(_ retention: inout UtteranceRetention, allowed: Bool, samples: [Float],
                      rate: Double = 16_000, heardSpeech: Bool = true) -> Int? {
        retention.beginTurn(allowed: allowed)
        retention.append(samples, sampleRate: rate, turn: retention.turn)
        return retention.endTurn(heardSpeech: heardSpeech, allowed: allowed, at: at)
    }

    func testNothingIsKeptWithTheSwitchOff() {
        var retention = UtteranceRetention()
        XCTAssertNil(turn(&retention, allowed: false, samples: [0.1, 0.2]))
        XCTAssertNil(retention.kept)
        XCTAssertFalse(retention.isCollecting)
    }

    func testAQuestionIsKeptWithTheSwitchOn() {
        var retention = UtteranceRetention()
        XCTAssertEqual(turn(&retention, allowed: true, samples: [0.1, 0.2, 0.3]), 3)
        XCTAssertEqual(retention.kept, KeptUtterance(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, capturedAt: at))
        XCTAssertFalse(retention.isCollecting, "collection stops when the turn ends")
    }

    func testTheNextQuestionReplacesIt() {
        var retention = UtteranceRetention()
        _ = turn(&retention, allowed: true, samples: [0.1])
        _ = turn(&retention, allowed: true, samples: [0.7, 0.8], rate: 48_000)
        XCTAssertEqual(retention.kept?.samples, [0.7, 0.8])
        XCTAssertEqual(retention.kept?.sampleRate, 48_000)
    }

    func testATurnThatHeardNothingLeavesTheLastQuestionInPlace() {
        var retention = UtteranceRetention()
        _ = turn(&retention, allowed: true, samples: [0.1])
        XCTAssertNil(turn(&retention, allowed: true, samples: [0, 0], heardSpeech: false))
        XCTAssertEqual(retention.kept?.samples, [0.1])
    }

    func testTurningTheSwitchOffForgetsIt() {
        var retention = UtteranceRetention()
        _ = turn(&retention, allowed: true, samples: [0.1])
        retention.beginTurn(allowed: false)
        XCTAssertNil(retention.kept, "the next turn with the switch off forgets the last question")

        _ = turn(&retention, allowed: true, samples: [0.1])
        retention.beginTurn(allowed: true)
        retention.append([0.2], sampleRate: 16_000, turn: retention.turn)
        XCTAssertNil(retention.endTurn(heardSpeech: true, allowed: false, at: at))
        XCTAssertNil(retention.kept, "switched off mid-question: nothing kept, and the old one gone")
    }

    func testLeavingTheScreenClearsIt() {
        var retention = UtteranceRetention()
        _ = turn(&retention, allowed: true, samples: [0.1])
        retention.beginTurn(allowed: true)
        retention.append([0.2], sampleRate: 16_000, turn: retention.turn)
        retention.clear()   // the app went to the background mid-question
        XCTAssertNil(retention.kept)
        XCTAssertFalse(retention.isCollecting)
        retention.append([0.3], sampleRate: 16_000, turn: retention.turn)
        // The turn ends in the background, where keeping is not allowed.
        XCTAssertNil(retention.endTurn(heardSpeech: true, allowed: false, at: at))
        XCTAssertNil(retention.kept)
    }

    func testBoundedAtTwoMinutes() {
        var retention = UtteranceRetention()
        let rate = 1_000.0
        retention.beginTurn(allowed: true)
        for _ in 0..<130 {   // 130 one-second buffers
            retention.append(Array(repeating: 0.1, count: 1_000), sampleRate: rate, turn: retention.turn)
        }
        XCTAssertEqual(retention.endTurn(heardSpeech: true, allowed: true, at: at), 120_000)
        XCTAssertEqual(retention.kept?.duration, UtteranceRetention.maxSeconds)
    }

    func testABufferFromAnEarlierTurnOrAnotherRateIsDropped() {
        var retention = UtteranceRetention()
        retention.beginTurn(allowed: true)
        let first = retention.turn
        retention.beginTurn(allowed: true)
        retention.append([0.9], sampleRate: 16_000, turn: first)          // late, from the last turn
        retention.append([0.1], sampleRate: 16_000, turn: retention.turn)
        retention.append([0.5], sampleRate: 8_000, turn: retention.turn)  // a route change mid-question
        retention.endTurn(heardSpeech: true, allowed: true, at: at)
        XCTAssertEqual(retention.kept?.samples, [0.1])
    }

    func testTheSwitchDefaultsOff() {
        let key = "recognizerComparisonEnabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(Config.recognizerComparisonEnabled)
    }
}
