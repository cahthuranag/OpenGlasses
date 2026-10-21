import XCTest
@testable import OpenGlasses

/// Plan JM P1 — the "Type instead" chip: two misses in a row, or one "didn't understand", shows it;
/// one good turn of either kind clears it; never outside Direct mode.
final class TypeInsteadPolicyTests: XCTestCase {

    func testTwoConsecutiveFailuresShow() {
        var policy = TypeInsteadPolicy()
        XCTAssertFalse(policy.note(.noSpeech, mode: .direct), "one miss is not a pattern")
        XCTAssertFalse(policy.isShowing)
        XCTAssertTrue(policy.note(.noSpeech, mode: .direct))
        XCTAssertTrue(policy.isShowing)
    }

    func testEitherKindOfFailureCounts() {
        var policy = TypeInsteadPolicy()
        XCTAssertFalse(policy.note(.shortTranscript, mode: .direct))
        XCTAssertTrue(policy.note(.noSpeech, mode: .direct))

        var other = TypeInsteadPolicy()
        XCTAssertFalse(other.note(.noSpeech, mode: .direct))
        XCTAssertTrue(other.note(.shortTranscript, mode: .direct))
    }

    func testOneSuccessBetweenFailuresResets() {
        var policy = TypeInsteadPolicy()
        XCTAssertFalse(policy.note(.noSpeech, mode: .direct))
        XCTAssertFalse(policy.note(.recognised, mode: .direct))
        XCTAssertEqual(policy.consecutiveFailures, 0)
        XCTAssertFalse(policy.note(.noSpeech, mode: .direct), "the count starts again")
        XCTAssertTrue(policy.note(.shortTranscript, mode: .direct))
    }

    func testNotUnderstoodShowsAtOnce() {
        var policy = TypeInsteadPolicy()
        XCTAssertTrue(policy.note(.notUnderstood, mode: .direct))
        XCTAssertTrue(policy.isShowing)
    }

    func testATypedTurnClears() {
        var policy = TypeInsteadPolicy()
        policy.note(.noSpeech, mode: .direct)
        policy.note(.noSpeech, mode: .direct)
        XCTAssertTrue(policy.isShowing)
        XCTAssertFalse(policy.note(.typedTurn, mode: .direct))
        XCTAssertFalse(policy.isShowing)
        XCTAssertEqual(policy.consecutiveFailures, 0)
        XCTAssertFalse(policy.note(.noSpeech, mode: .direct), "cleared means counting from zero")
    }

    func testAGoodSpokenTurnClears() {
        var policy = TypeInsteadPolicy()
        policy.note(.notUnderstood, mode: .direct)
        XCTAssertTrue(policy.isShowing)
        XCTAssertFalse(policy.note(.recognised, mode: .direct))
        XCTAssertFalse(policy.isShowing)
    }

    func testNoCountingOutsideDirectMode() {
        for mode in AppMode.allCases where mode != .direct {
            var policy = TypeInsteadPolicy()
            for event in [TypeInsteadPolicy.Event.noSpeech, .shortTranscript, .noSpeech, .notUnderstood] {
                XCTAssertFalse(policy.note(event, mode: mode), "\(mode)")
            }
            XCTAssertFalse(policy.isShowing, "\(mode)")
            XCTAssertEqual(policy.consecutiveFailures, 0, "\(mode)")
        }
    }

    func testLeavingDirectModeDropsTheOffer() {
        var policy = TypeInsteadPolicy()
        policy.note(.noSpeech, mode: .direct)
        policy.note(.noSpeech, mode: .direct)
        XCTAssertTrue(policy.isShowing)
        XCTAssertFalse(policy.note(.noSpeech, mode: .geminiLive))
        XCTAssertFalse(policy.isShowing)
    }

    func testIsShowingTransitions() {
        var policy = TypeInsteadPolicy()
        var seen: [Bool] = []
        for event in [TypeInsteadPolicy.Event.noSpeech, .noSpeech, .noSpeech, .typedTurn,
                      .shortTranscript, .recognised, .notUnderstood, .recognised] {
            policy.note(event, mode: .direct)
            seen.append(policy.isShowing)
        }
        XCTAssertEqual(seen, [false, true, true, false, false, false, true, false])
    }

    func testShorterThanAWord() {
        for text in ["", "   ", ".", " ?! ", "…", "-"] {
            XCTAssertTrue(TypeInsteadPolicy.isShorterThanAWord(text), "'\(text)'")
            XCTAssertEqual(TypeInsteadPolicy.event(forTranscript: text), .shortTranscript)
        }
        for text in ["a", "I", "5", "yes", " R-410A "] {
            XCTAssertFalse(TypeInsteadPolicy.isShorterThanAWord(text), "'\(text)'")
            XCTAssertEqual(TypeInsteadPolicy.event(forTranscript: text), .recognised)
        }
    }
}
