import XCTest
@testable import OpenGlasses

/// Plan JM P1 — "Check what I said before sending": only where somebody can read it, and a short
/// countdown that sends by itself unless the wearer touches the text.
final class SendReviewPolicyTests: XCTestCase {

    private let surfaces: [SendReviewPolicy.Surface] = [.phone, .carPlay, .watch, .glassesOnly]

    // MARK: - The table

    func testReviewsOnlyWhenEveryConditionHolds() {
        var reviewed = 0
        for enabled in [false, true] {
            for mode in AppMode.allCases {
                for foreground in [false, true] {
                    for screenOn in [false, true] {
                        for surface in surfaces {
                            let result = SendReviewPolicy.shouldReview(
                                enabled: enabled, mode: mode, foreground: foreground,
                                screenOn: screenOn, surface: surface)
                            let expected = enabled && mode == .direct && foreground && screenOn
                                && surface == .phone
                            XCTAssertEqual(result, expected,
                                           "\(enabled) \(mode) \(foreground) \(screenOn) \(surface)")
                            if result { reviewed += 1 }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(reviewed, 1, "exactly one combination waits")
    }

    func testOffMeansNoReviewAnywhere() {
        for surface in surfaces {
            XCTAssertFalse(SendReviewPolicy.shouldReview(enabled: false, mode: .direct, foreground: true,
                                                         screenOn: true, surface: surface))
        }
    }

    func testNeverInTheRealtimeModesOrGeminiLive() {
        for mode in AppMode.allCases where mode != .direct {
            XCTAssertFalse(SendReviewPolicy.shouldReview(enabled: true, mode: mode, foreground: true,
                                                         screenOn: true, surface: .phone), "\(mode)")
        }
    }

    // MARK: - Leaving the screen

    func testBackgroundSendsAnUntouchedTranscriptAsSpoken() {
        XCTAssertEqual(SendReviewPolicy.resolutionOnBackground(edited: false), .sendAsSpoken)
    }

    func testBackgroundKeepsADraftTheWearerHadTakenOver() {
        XCTAssertEqual(SendReviewPolicy.resolutionOnBackground(edited: true), .keepDraft)
    }

    // MARK: - The countdown

    func testDefaultIsThreeSeconds() {
        XCTAssertEqual(SendReviewPolicy.Countdown.defaultSeconds, 3)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: 3).seconds, 3)
    }

    func testClampsToTwoThroughTen() {
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: 0).seconds, 2)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: -4).seconds, 2)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: 1.9).seconds, 2)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: 2).seconds, 2)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: 7).seconds, 7)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: 10).seconds, 10)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: 60).seconds, 10)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: .nan).seconds, 3)
        XCTAssertEqual(SendReviewPolicy.Countdown(seconds: .infinity).seconds, 3)
    }

    func testCountsDownThenSendsAtTheBoundary() {
        let countdown = SendReviewPolicy.Countdown(seconds: 3)
        XCTAssertEqual(countdown.state(at: 0, edited: false), .counting(remaining: 3))
        XCTAssertEqual(countdown.state(at: 1, edited: false), .counting(remaining: 2))
        XCTAssertEqual(countdown.state(at: 2.999, edited: false), .counting(remaining: 3 - 2.999))
        XCTAssertEqual(countdown.state(at: 3, edited: false), .send, "the boundary sends")
        XCTAssertEqual(countdown.state(at: 30, edited: false), .send)
        XCTAssertEqual(countdown.state(at: -1, edited: false), .counting(remaining: 3),
                       "a clock that went backwards does not stretch the count")
    }

    func testEditedHoldsAtAnyElapsed() {
        let countdown = SendReviewPolicy.Countdown(seconds: 3)
        for elapsed in [0, 0.5, 2.99, 3, 10] as [TimeInterval] {
            XCTAssertEqual(countdown.state(at: elapsed, edited: true), .held, "\(elapsed)")
        }
    }

    func testProgressFillsTheRing() {
        let countdown = SendReviewPolicy.Countdown(seconds: 4)
        XCTAssertEqual(countdown.progress(at: 0), 0)
        XCTAssertEqual(countdown.progress(at: 2), 0.5)
        XCTAssertEqual(countdown.progress(at: 4), 1)
        XCTAssertEqual(countdown.progress(at: 9), 1)
        XCTAssertEqual(countdown.progress(at: -1), 0)
    }

    func testAPendingTranscriptCountsFromWhenItArrived() {
        let start = Date(timeIntervalSince1970: 1_000)
        var pending = PendingTranscript(text: "supply air is 140", startedAt: start, seconds: 3)
        XCTAssertEqual(pending.state(at: start.addingTimeInterval(1)), .counting(remaining: 2))
        XCTAssertEqual(pending.state(at: start.addingTimeInterval(3)), .send)
        pending.isHeld = true
        XCTAssertEqual(pending.state(at: start.addingTimeInterval(3)), .held)
        XCTAssertEqual(PendingTranscript(text: "x", seconds: 99).countdown.seconds, 10)
    }

    // MARK: - The settings

    private let keys = ["checkBeforeSendingEnabled", "checkBeforeSendingSeconds"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testTheOptionIsOffByDefault() {
        XCTAssertFalse(Config.checkBeforeSendingEnabled)
        Config.checkBeforeSendingEnabled = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: "checkBeforeSendingEnabled") as? Bool, true)
    }

    func testTheSecondsDefaultAndClampOnRead() {
        XCTAssertEqual(Config.checkBeforeSendingSeconds, 3)
        UserDefaults.standard.set(45.0, forKey: "checkBeforeSendingSeconds")
        XCTAssertEqual(Config.checkBeforeSendingSeconds, 10, "a stored value out of range is clamped on read")
        UserDefaults.standard.set(0.5, forKey: "checkBeforeSendingSeconds")
        XCTAssertEqual(Config.checkBeforeSendingSeconds, 2)
        Config.checkBeforeSendingSeconds = 6
        XCTAssertEqual(UserDefaults.standard.object(forKey: "checkBeforeSendingSeconds") as? Double, 6)
    }
}
