import XCTest
import AVFoundation
@testable import OpenGlasses

/// A backgrounded turn whose idle listener is on the phone's own mic (the default) cannot re-tune
/// the live session — iOS refuses it — so it hands the session back and activates it afresh in the
/// mixable hands-free shape (`TurnMicHandoff.SessionSwitch.freshActivation`). Driven through
/// `WakeWordService.pauseOtherAudio()` with a fresh coordinator over a fake session — never the
/// shared one. The simulator lists no glasses port, so each turn here ends on the phone; what is
/// asserted is how the session was reached.
@MainActor
final class ConversationFreshActivationTests: XCTestCase {

    private final class FakeSession: AudioSessionConforming, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
        var refuseActivation = false
        var currentRoutePortTypes: [AVAudioSession.Port] = []
        private func record(_ s: String) { lock.lock(); _calls.append(s); lock.unlock() }
        func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                         options: AVAudioSession.CategoryOptions) throws {
            var shape = options.contains(.mixWithOthers) ? "mixable" : "exclusive"
            if options.contains(.allowBluetoothHFP) { shape += "+handsFree" }
            record("setCategory:\(shape)")
        }
        func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
            if active {
                record("activate")
                if refuseActivation {
                    throw NSError(domain: NSOSStatusErrorDomain, code: 560557684)
                }
            } else {
                record(options.contains(.notifyOthersOnDeactivation) ? "deactivateNotify" : "deactivate")
            }
        }
        func overrideOutputAudioPort(_ port: AVAudioSession.PortOverride) throws {}
        func setPreferredSampleRate(_ sampleRate: Double) throws {}
        func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {}
    }

    private func makeService(foreground: Bool, session: FakeSession,
                             coordinator: AudioSessionCoordinator) -> WakeWordService {
        let service = WakeWordService()
        service.sessionCoordinator = { coordinator }
        service.appInForeground = { foreground }
        service.wakeListenInputs = {
            WakeListenPolicy.Inputs(listeningEnabled: true, silentMode: false, wakeListenMic: .iPhone,
                                    micRoute: .glasses, speechGateEnabled: false)
        }
        // The idle listener's lease, as `configureAudioSession` leaves it.
        service.sessionLease = coordinator.assumeOwnership(.wakeWord)
        return service
    }

    func testABackgroundedTurnHandsBackAndActivatesTheHandsFreeShapeAfresh() async {
        let session = FakeSession()
        let coordinator = AudioSessionCoordinator(session: session)
        let service = makeService(foreground: false, session: session, coordinator: coordinator)

        await service.pauseOtherAudio()

        XCTAssertEqual(session.calls, ["deactivateNotify", "setCategory:mixable+handsFree", "activate"],
                       "a real hand-back, then a fresh mixable hands-free activation — never a re-tune")
        XCTAssertEqual(coordinator.currentOwner, .wakeWord, "ownership re-assumed after the hand-back")
        XCTAssertNotNil(service.sessionLease)
        XCTAssertNotNil(service.turnMicRoute)
    }

    func testARefusedFreshActivationPutsTheIdleShapeBack() async {
        let session = FakeSession()
        session.refuseActivation = true
        let coordinator = AudioSessionCoordinator(session: session)
        let service = makeService(foreground: false, session: session, coordinator: coordinator)

        await service.pauseOtherAudio()

        XCTAssertEqual(session.calls, ["deactivateNotify", "setCategory:mixable+handsFree", "activate",
                                       "setCategory:mixable", "activate"],
                       "the phone-mic idle shape is asked for again, so the turn has a session")
        XCTAssertEqual(service.turnMicRoute, .phone, "the turn goes to the phone, as before")
        XCTAssertFalse(service.turnPhoneChosenInForeground,
                       "chosen from the background: a follow-up in the foreground asks again")
    }

    func testAReplyStillPlayingIsNeverCutOff() async {
        let session = FakeSession()
        let coordinator = AudioSessionCoordinator(session: session)
        let service = makeService(foreground: false, session: session, coordinator: coordinator)
        let rider = coordinator.beginCoexisting(.textToSpeech)
        defer { coordinator.endCoexisting(rider) }

        await service.pauseOtherAudio()

        XCTAssertFalse(session.calls.contains("deactivateNotify"), "a coexisting rider keeps the session up")
        XCTAssertEqual(session.calls.first, "setCategory:exclusive+handsFree", "today's re-tune attempt")
    }

    func testTheForegroundReTunesInPlaceAsBefore() async {
        let session = FakeSession()
        let coordinator = AudioSessionCoordinator(session: session)
        let service = makeService(foreground: true, session: session, coordinator: coordinator)

        await service.pauseOtherAudio()

        XCTAssertEqual(session.calls, ["setCategory:exclusive+handsFree", "activate"],
                       "non-mixable, in place, other audio paused")
        XCTAssertEqual(service.turnMicRoute, .phone, "no glasses port in the simulator")
        XCTAssertTrue(service.turnPhoneChosenInForeground)
    }
}
