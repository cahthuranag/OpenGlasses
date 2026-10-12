import AVFoundation
import XCTest
@testable import OpenGlasses

/// A question dictated on the watch is a typed turn on the phone, answered where the wearer is.
///
/// The watch has no speech recogniser an app can run, so its own microphone reaches the assistant
/// one way: the system's dictation turns speech into text on the wrist, and the text is sent. These
/// checks hold the two ends to the same words, the bounds on what arrives, and the one decision
/// the phone makes that a typed turn in the app does not — whether to say the answer aloud.
final class WatchDictationTests: XCTestCase {

    // MARK: - The wire

    /// The watch and the phone share no code, so each names the command itself.
    func testBothEndsNameTheSameCommand() {
        XCTAssertEqual(WatchDictationWire.command, WatchDictation.command)
        XCTAssertEqual(WatchDictationWire.textKey, WatchDictation.textKey)
    }

    func testThePhoneRecognisesTheCommand() {
        XCTAssertNotNil(WatchConnectivityManager.commandToken(WatchDictation.command))
    }

    // MARK: - What arrives

    func testTheQuestionIsTrimmed() {
        XCTAssertEqual(WatchDictation.question(from: [WatchDictation.textKey: "  what time is it \n"]),
                       "what time is it")
    }

    func testNothingToAskIsNoQuestion() {
        XCTAssertNil(WatchDictation.question(from: [:]))
        XCTAssertNil(WatchDictation.question(from: [WatchDictation.textKey: "   \n"]))
        XCTAssertNil(WatchDictation.question(from: [WatchDictation.textKey: 42]))
        XCTAssertNil(WatchDictation.question(from: ["prompt": "the photo path's key, not this one"]))
    }

    func testAnOverlongQuestionIsCutNotRefused() throws {
        let long = String(repeating: "a", count: WatchDictation.maxCharacters + 500)
        let question = try XCTUnwrap(WatchDictation.question(from: [WatchDictation.textKey: long]))
        XCTAssertEqual(question.count, WatchDictation.maxCharacters)
    }

    // MARK: - Where the answer is said

    /// Into glasses, earbuds, wired headphones or a car: the wearer is listening there.
    func testTheAnswerIsSpokenIntoWhatTheWearerHasOn() {
        for output in [AVAudioSession.Port.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .carAudio] {
            XCTAssertTrue(WatchDictation.speaksAnswer(outputs: [output]), output.rawValue)
        }
    }

    /// A phone in a pocket or another room does not read the answer out to whoever is near it.
    func testTheAnswerIsNotReadOutByAnUnattendedPhone() {
        XCTAssertFalse(WatchDictation.speaksAnswer(outputs: [.builtInSpeaker]))
        XCTAssertFalse(WatchDictation.speaksAnswer(outputs: [.builtInReceiver]))
        XCTAssertFalse(WatchDictation.speaksAnswer(outputs: [.builtInReceiver, .builtInSpeaker]))
        XCTAssertFalse(WatchDictation.speaksAnswer(outputs: []))
    }

    // MARK: - The two ends, as written

    /// The phone runs it as a typed turn, and never answers with the turn before.
    func testThePhoneRunsATypedTurnAndRefusesWhileBusy() throws {
        let manager = try Self.source("OpenGlasses/Sources/Services/WatchConnectivityManager.swift")
        let start = try XCTUnwrap(manager.range(of: "case WatchDictation.command:"))
        let end = try XCTUnwrap(manager.range(of: "case \"persona\":", range: start.upperBound..<manager.endIndex))
        let body = String(manager[start.lowerBound..<end.lowerBound])

        let busy = try XCTUnwrap(body.range(of: "appState.isProcessing"),
                                 "a turn in flight makes sendTextMessage do nothing, and the reply "
                                     + "would carry the previous answer")
        let send = try XCTUnwrap(body.range(of: "appState.sendTextMessage(question"))
        XCTAssertLessThan(busy.lowerBound, send.lowerBound)
        XCTAssertTrue(body.contains("speakResponse: WatchDictation.speaksAnswerNow()"), body)
        XCTAssertFalse(body.contains("PrivacyLog"), "the wearer's question is never logged")
    }

    func testTheWatchSendsWhatWasDictated() throws {
        let view = try Self.source("OpenGlassesWatch/WatchMainView.swift")
        let row = try XCTUnwrap(view.range(of: "TextFieldLink("),
                                "the watch's own microphone is reached through the system's text input")
        let body = view[row.lowerBound...].prefix(1_200)
        XCTAssertTrue(body.contains("connectivity.sendCommand(WatchDictationWire.command"), String(body))
        XCTAssertTrue(body.contains("[WatchDictationWire.textKey: question]"), String(body))

        // The status push carries only the opening of an answer; the full one must survive it.
        let service = try Self.source("OpenGlassesWatch/WatchConnectivityService.swift")
        XCTAssertTrue(service.contains("lastResponse.hasPrefix(response)"),
                      "a full answer is not replaced by its own first lines")
    }

    // MARK: - Helpers

    /// `#filePath` is the repo anchor: `<repo>/OpenGlassesTests/<thisfile>.swift`.
    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
