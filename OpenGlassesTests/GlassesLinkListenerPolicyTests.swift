import AVFoundation
import XCTest
@testable import OpenGlasses

/// The idle listener across the glasses' link going down and coming back (a tester's locked
/// phone, 2026-10-18: the link flapped in a pocket, the app stopped the listener for it, iOS let
/// the session go, and the reconnect's re-tune was refused from the background).
final class GlassesLinkListenerPolicyTests: XCTestCase {

    // MARK: - Link loss

    func testALinkDropKeepsAWantedListenerOnWhateverInputRemains() {
        XCTAssertEqual(GlassesLinkListenerPolicy.onLinkLoss(listenerWanted: true), .continueOnRemainingInput)
    }

    func testALinkDropOpensNoMicrophoneNobodyAskedFor() {
        XCTAssertEqual(GlassesLinkListenerPolicy.onLinkLoss(listenerWanted: false), .stop,
                       "listening off, push-to-talk, muted or stood down: a link drop changes nothing")
    }

    // MARK: - Link return

    func testInTheForegroundTheSessionIsRetunedOntoTheGlassesAsBefore() {
        XCTAssertEqual(GlassesLinkListenerPolicy.onLinkReturn(appInForeground: true, sessionHasRoute: true),
                       .reconfigure)
        XCTAssertEqual(GlassesLinkListenerPolicy.onLinkReturn(appInForeground: true, sessionHasRoute: false),
                       .reconfigure)
    }

    func testInTheBackgroundALiveSessionIsKeptAndOnlyItsInputMoved() {
        XCTAssertEqual(GlassesLinkListenerPolicy.onLinkReturn(appInForeground: false, sessionHasRoute: true),
                       .keepSession, "a re-tune from the background is refused with cannotInterruptOthers")
    }

    func testInTheBackgroundADeadSessionHasNothingToKeep() {
        XCTAssertEqual(GlassesLinkListenerPolicy.onLinkReturn(appInForeground: false, sessionHasRoute: false),
                       .reconfigure, "no route at all: the re-tune is attempted, as it was")
    }

    // MARK: - Route-change reason names

    func testEveryRouteChangeReasonHasATokenTheLogVocabularyAccepts() {
        let reasons: [AVAudioSession.RouteChangeReason] = [
            .unknown, .newDeviceAvailable, .oldDeviceUnavailable, .categoryChange, .override,
            .wakeFromSleep, .noSuitableRouteForCategory, .routeConfigurationChange,
        ]
        var seen: Set<String> = []
        for reason in reasons {
            let token = RouteChangeReasonName.token(reason)
            XCTAssertEqual(PrivacyToken(token).description, token, "\(token) must survive the token filter")
            XCTAssertNotEqual(token, PrivacyToken.placeholder)
            seen.insert(token)
        }
        XCTAssertEqual(seen.count, reasons.count, "distinct reasons read distinctly in a trace")
        XCTAssertEqual(RouteChangeReasonName.token(.oldDeviceUnavailable), "oldDeviceUnavailable")
    }
}
