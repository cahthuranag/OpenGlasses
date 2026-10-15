import XCTest
@testable import OpenGlasses

/// The decision side of the relative-time guard: when the wearer's "in 15 minutes" replaces the
/// number the model worked out for `set_timer` and `reminder`, and when it leaves it alone.
final class RelativeTimeGuardTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: - The pure decision

    func testAgreementKeepsTheModel() {
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: 900, model: .offset(900), tolerance: 1),
                       .keepModel)
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: 900, model: .offset(1000), tolerance: 120),
                       .keepModel, "within tolerance")
    }

    func testDisagreementBeyondToleranceUsesTheSentence() {
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: 900, model: .offset(15), tolerance: 1),
                       .useParsed(seconds: 900, disagreement: .minutes))
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: 900, model: .offset(900 + 3600),
                                                tolerance: 120),
                       .useParsed(seconds: 900, disagreement: .hours))
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: 900, model: .offset(-3600), tolerance: 120),
                       .useParsed(seconds: 900, disagreement: .hours), "a past time is a disagreement")
    }

    func testNoParseOrNoModelValueKeepsTheModel() {
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: nil, model: .offset(15), tolerance: 1),
                       .keepModel)
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: 900, model: .absent, tolerance: 1),
                       .keepModel, "the guard corrects a value; it never invents one")
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: 0, model: .offset(15), tolerance: 1),
                       .keepModel)
    }

    func testAnUnreadableModelValueUsesTheSentence() {
        XCTAssertEqual(RelativeTimeGuard.decide(parsed: 60, model: .unreadable, tolerance: 1),
                       .useParsed(seconds: 60, disagreement: .unreadable))
    }

    func testDisagreementClasses() {
        XCTAssertEqual(RelativeTimeGuard.disagreement(of: 5), .underAMinute)
        XCTAssertEqual(RelativeTimeGuard.disagreement(of: 59.9), .underAMinute)
        XCTAssertEqual(RelativeTimeGuard.disagreement(of: 60), .minutes)
        XCTAssertEqual(RelativeTimeGuard.disagreement(of: 3599), .minutes)
        XCTAssertEqual(RelativeTimeGuard.disagreement(of: 3600), .hours)
        XCTAssertEqual(RelativeTimeGuard.disagreement(of: 86_400), .days)
    }

    // MARK: - set_timer

    func testTimerModelForgotToMultiply() {
        let resolution = TimerDurationResolution.resolve(modelArgument: 15,
                                                         utterance: "set a timer for 15 minutes")
        XCTAssertEqual(resolution, TimerDurationResolution(seconds: 900, overridden: .minutes))
    }

    func testTimerAgreementIsUntouched() {
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: 900,
                                                       utterance: "set a timer for 15 minutes"),
                       TimerDurationResolution(seconds: 900, overridden: nil))
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: 900.0,
                                                       utterance: "a fifteen minute timer"),
                       TimerDurationResolution(seconds: 900, overridden: nil))
    }

    func testTimerWithoutAnUtteranceIsTodaysBehaviour() {
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: 15, utterance: nil),
                       TimerDurationResolution(seconds: 15, overridden: nil))
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: 42.7, utterance: nil),
                       TimerDurationResolution(seconds: 42, overridden: nil))
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: nil, utterance: nil),
                       TimerDurationResolution(seconds: nil, overridden: nil))
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: "900", utterance: nil),
                       TimerDurationResolution(seconds: nil, overridden: nil))
    }

    func testTimerWithAnAmbiguousUtteranceKeepsTheModel() {
        for utterance in ["set a timer for a few minutes", "set a timer for 15",
                          "set a timer for 10 minutes and remind me in an hour",
                          "pon un temporizador de 15 minutos"] {
            XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: 300, utterance: utterance),
                           TimerDurationResolution(seconds: 300, overridden: nil), utterance)
        }
    }

    func testTimerMissingSecondsIsNotFilledIn() {
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: nil,
                                                       utterance: "set a timer for 15 minutes"),
                       TimerDurationResolution(seconds: nil, overridden: nil))
    }

    func testTimerUnreadableSecondsTakeTheSentence() {
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: "fifteen minutes",
                                                       utterance: "set a timer for 15 minutes"),
                       TimerDurationResolution(seconds: 900, overridden: .unreadable))
    }

    func testTimerHalfMinuteRounds() {
        XCTAssertEqual(TimerDurationResolution.resolve(modelArgument: 60,
                                                       utterance: "timer for one and a half minutes"),
                       TimerDurationResolution(seconds: 90, overridden: .underAMinute))
    }

    // MARK: - reminder

    func testReminderOffByAnHourTakesTheSentence() {
        let modelDue = now.addingTimeInterval(900 + 3600)
        let resolution = ReminderDueResolution.resolve(
            modelDueAt: iso(modelDue), utterance: "remind me in 15 minutes to call Mum", now: now)
        XCTAssertEqual(resolution, .parsed(now.addingTimeInterval(900), .hours))
    }

    func testReminderWithinToleranceKeepsTheModel() {
        let modelDue = iso(now.addingTimeInterval(900 + 60))
        XCTAssertEqual(ReminderDueResolution.resolve(modelDueAt: modelDue,
                                                     utterance: "remind me in 15 minutes", now: now),
                       .model(modelDue))
    }

    func testReminderInThePastTakesTheSentence() {
        let modelDue = iso(now.addingTimeInterval(-10 * 3600))
        XCTAssertEqual(ReminderDueResolution.resolve(modelDueAt: modelDue,
                                                     utterance: "remind me in an hour", now: now),
                       .parsed(now.addingTimeInterval(3600), .hours))
    }

    func testReminderUnreadableDateTakesTheSentence() {
        XCTAssertEqual(ReminderDueResolution.resolve(modelDueAt: "in 15 minutes",
                                                     utterance: "remind me in 15 minutes", now: now),
                       .parsed(now.addingTimeInterval(900), .unreadable))
    }

    func testReminderAbsoluteRequestIsNeverOverridden() {
        let modelDue = iso(now.addingTimeInterval(20 * 3600))
        for utterance in ["remind me tomorrow at 9", "remind me at 3pm",
                          "remind me tomorrow in 2 hours", "remind me in 2 days"] {
            XCTAssertEqual(ReminderDueResolution.resolve(modelDueAt: modelDue,
                                                         utterance: utterance, now: now),
                           .model(modelDue), utterance)
        }
    }

    func testReminderWithoutDueOrUtteranceIsTodaysBehaviour() {
        XCTAssertEqual(ReminderDueResolution.resolve(modelDueAt: nil,
                                                     utterance: "remind me in 15 minutes", now: now),
                       .model(nil), "no due time is not filled in")
        XCTAssertEqual(ReminderDueResolution.resolve(modelDueAt: "  ",
                                                     utterance: "remind me in 15 minutes", now: now),
                       .model("  "))
        let modelDue = iso(now.addingTimeInterval(7 * 3600))
        XCTAssertEqual(ReminderDueResolution.resolve(modelDueAt: modelDue, utterance: nil, now: now),
                       .model(modelDue))
    }

    func testReminderDoesNotReadATimersFor() {
        let modelDue = iso(now.addingTimeInterval(3600))
        XCTAssertEqual(ReminderDueResolution.resolve(modelDueAt: modelDue,
                                                     utterance: "remind me to stretch for 10 minutes",
                                                     now: now),
                       .model(modelDue))
    }

    // MARK: - Which utterance is trusted

    func testNoUtteranceOutsideAModelCall() {
        XCTAssertNil(RelativeTimeGuard.utteranceForCurrentCall())
        TurnUtteranceScope.$current.withValue("set a timer for 15 minutes") {
            XCTAssertNil(RelativeTimeGuard.utteranceForCurrentCall(),
                         "a call outside the tool router is not a model call")
        }
    }

    func testTheTurnUtteranceReachesAModelCall() {
        let call = ResolvedToolCall.root(name: "set_timer", origin: .model)
        TurnUtteranceScope.$current.withValue("set a timer for 15 minutes") {
            ToolInvocationScope.$current.withValue(call) {
                XCTAssertEqual(RelativeTimeGuard.utteranceForCurrentCall(),
                               "set a timer for 15 minutes")
            }
        }
    }

    func testNonModelOriginsAreNeverSecondGuessed() {
        for origin in [ToolInvocationOrigin.user, .skillPack, .siriAction, .appInternal] {
            let call = ResolvedToolCall.root(name: "set_timer", origin: origin)
            TurnUtteranceScope.$current.withValue("set a timer for 15 minutes") {
                ToolInvocationScope.$current.withValue(call) {
                    XCTAssertNil(RelativeTimeGuard.utteranceForCurrentCall(), origin.rawValue)
                }
            }
        }
    }

    /// A live session or an agent task calls tools with `.model` origin but outside any Direct
    /// turn, so no utterance is bound.
    func testAModelCallOutsideADirectTurnHasNoUtterance() {
        let call = ResolvedToolCall.root(name: "reminder", origin: .model)
        ToolInvocationScope.$current.withValue(call) {
            XCTAssertNil(RelativeTimeGuard.utteranceForCurrentCall())
        }
    }

    @MainActor
    func testTheTurnRunnerBindsTheUtteranceAroundSend() async {
        let seen = Box<String?>(nil)
        await ConversationTurnRunner.run(.init(
            send: { seen.value = TurnUtteranceScope.current; return "ok" },
            postProcess: { $0 },
            accept: { _ in },
            speak: { _ in },
            onCancelled: {},
            onError: { _ in },
            finish: {},
            utterance: "remind me in 15 minutes"))
        XCTAssertEqual(seen.value, "remind me in 15 minutes")
        XCTAssertNil(TurnUtteranceScope.current, "the binding ends with the send")
    }

    // MARK: - The log line

    func testTheOverrideLogCarriesNoContent() {
        let event = PrivacyLog.toolRun(.relativeTimeOverridden, tool: "set_timer",
                                       detail: PrivacyToken(RelativeTimeGuard.Disagreement.hours.rawValue))
        let line = PrivacyEventEncoder.encode(event)
        XCTAssertTrue(line.contains("relativeTimeOverridden"), line)
        XCTAssertTrue(line.contains("detail=hours"), line)
        XCTAssertTrue(line.contains("tool=set_timer"), line)
    }
}
