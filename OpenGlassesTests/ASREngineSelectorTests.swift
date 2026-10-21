import XCTest
@testable import OpenGlasses

/// Tests for the pure ASR engine-selection policy (Additional Capabilities #8): given availability
/// (Apple Speech authorized, SenseVoice model present, online), the user's preference, it produces the
/// `On-Device ↔ Apple Speech` fallback chain.
final class ASREngineSelectorTests: XCTestCase {

    private typealias Availability = ASREngineSelector.Availability

    private func chain(_ p: ASREnginePreference, _ a: Availability) -> [ASREngine] {
        ASREngineSelector.chain(preference: p, availability: a, hipaa: false)
    }

    func testAutoPrefersAppleSpeechWhenOnline() {
        let result = chain(.auto, Availability(appleSpeechReady: true, onDeviceReady: true, online: true))
        XCTAssertEqual(result, [.appleSpeech, .onDevice])
    }

    func testAutoPromotesOnDeviceWhenOffline() {
        // Apple Speech may need the network; offline, the fully-local recognizer leads.
        let result = chain(.auto, Availability(appleSpeechReady: true, onDeviceReady: true, online: false))
        XCTAssertEqual(result, [.onDevice, .appleSpeech])
    }

    func testAutoOfflineWithoutModelStaysOnAppleSpeech() {
        let result = chain(.auto, Availability(appleSpeechReady: true, onDeviceReady: false, online: false))
        XCTAssertEqual(result, [.appleSpeech])
    }

    func testAutoWithoutModelIsAppleSpeechOnly() {
        let result = chain(.auto, Availability(appleSpeechReady: true, onDeviceReady: false, online: true))
        XCTAssertEqual(result, [.appleSpeech])
    }

    func testOnDevicePreferenceLeadsWithOnDevice() {
        let result = chain(.onDevice, Availability(appleSpeechReady: true, onDeviceReady: true, online: true))
        XCTAssertEqual(result, [.onDevice, .appleSpeech])
    }

    func testOnDevicePreferenceFallsBackWhenModelAbsent() {
        let result = chain(.onDevice, Availability(appleSpeechReady: true, onDeviceReady: false, online: true))
        XCTAssertEqual(result, [.appleSpeech])
    }

    func testAppleSpeechPreferenceForcesAppleFirst() {
        let result = chain(.appleSpeech, Availability(appleSpeechReady: true, onDeviceReady: true, online: false))
        XCTAssertEqual(result.first, .appleSpeech)   // even offline, the user forced Apple
    }

    func testNothingAvailableYieldsEmptyChainAndNilSelection() {
        // Apple Speech unauthorized and no on-device model → no recognizer at all.
        let availability = Availability(appleSpeechReady: false, onDeviceReady: false, online: true)
        XCTAssertTrue(chain(.auto, availability).isEmpty)
        XCTAssertNil(ASREngineSelector.select(preference: .auto, availability: availability, hipaa: false))
    }

    func testOnDeviceOnlyWhenAppleUnauthorized() {
        let result = chain(.auto, Availability(appleSpeechReady: false, onDeviceReady: true, online: true))
        XCTAssertEqual(result, [.onDevice])
    }

    func testSelectMatchesChainHead() {
        let combos: [(ASREnginePreference, Availability)] = [
            (.auto, Availability(appleSpeechReady: true, onDeviceReady: true, online: true)),
            (.onDevice, Availability(appleSpeechReady: true, onDeviceReady: true, online: false)),
            (.auto, Availability(appleSpeechReady: true, onDeviceReady: false, online: true)),
        ]
        for (p, a) in combos {
            XCTAssertEqual(ASREngineSelector.select(preference: p, availability: a, hipaa: false),
                           ASREngineSelector.chain(preference: p, availability: a, hipaa: false).first)
        }
    }

    // MARK: - Cloud dictation (Plan JM P2)

    private func cloudAvailability(online: Bool, deepgram: Bool = true, openAI: Bool = true,
                                   onDevice: Bool = true) -> Availability {
        Availability(appleSpeechReady: true, onDeviceReady: onDevice, online: online,
                     deepgramReady: deepgram, openAIReady: openAI)
    }

    /// The table: chosen cloud engine × ready × online × HIPAA. The cloud engine leads only when
    /// all three hold; otherwise the chain is exactly the `.auto` chain for the same availability.
    func testChosenCloudEngineLeadsOnlyWhenReadyOnlineAndNotHIPAA() {
        for preference in [ASREnginePreference.deepgram, .openAI] {
            let engine = preference.cloudEngine!
            for ready in [true, false] {
                for online in [true, false] {
                    for hipaa in [true, false] {
                        let availability = Availability(
                            appleSpeechReady: true, onDeviceReady: true, online: online,
                            deepgramReady: engine == .deepgram ? ready : false,
                            openAIReady: engine == .openAI ? ready : false)
                        let result = ASREngineSelector.chain(preference: preference,
                                                             availability: availability, hipaa: hipaa)
                        let autoChain = ASREngineSelector.chain(preference: .auto,
                                                                availability: availability, hipaa: hipaa)
                        let label = "\(preference) ready=\(ready) online=\(online) hipaa=\(hipaa)"
                        if ready && online && !hipaa {
                            XCTAssertEqual(result, [engine] + autoChain, label)
                        } else {
                            XCTAssertEqual(result, autoChain, label)
                        }
                        XCTAssertTrue(result.contains(.appleSpeech), "Apple Speech stays the guaranteed fallback: \(label)")
                    }
                }
            }
        }
    }

    func testDeepgramChosenOnlineFallsBackThroughTheAutoChain() {
        XCTAssertEqual(chain(.deepgram, cloudAvailability(online: true)), [.deepgram, .appleSpeech, .onDevice])
        XCTAssertEqual(chain(.openAI, cloudAvailability(online: true, onDevice: false)), [.openAI, .appleSpeech])
    }

    func testAutoNeverPicksACloudEngine() {
        for online in [true, false] {
            for preference in [ASREnginePreference.auto, .onDevice, .appleSpeech] {
                let result = chain(preference, cloudAvailability(online: online))
                XCTAssertFalse(result.contains(where: \.isCloud), "\(preference) online=\(online)")
            }
        }
    }

    func testCloudPreferenceOfflineBehavesAsAutoForThatTurn() {
        // Offline with the on-device model present, `.auto` promotes on-device; so does a cloud choice.
        let offline = cloudAvailability(online: false)
        XCTAssertEqual(chain(.deepgram, offline), [.onDevice, .appleSpeech])
        XCTAssertEqual(chain(.openAI, offline), chain(.auto, offline))
    }

    func testHIPAAStripsCloudEnginesEvenWhenTheCallerSaysReady() {
        // The caller is meant to fold HIPAA into readiness; this is the second lock if it does not.
        let readyAnyway = cloudAvailability(online: true)
        for preference in ASREnginePreference.allCases {
            let result = ASREngineSelector.chain(preference: preference, availability: readyAnyway, hipaa: true)
            XCTAssertFalse(result.contains(where: \.isCloud), "\(preference)")
            XCTAssertNotEqual(ASREngineSelector.select(preference: preference, availability: readyAnyway, hipaa: true)?.isCloud, true)
        }
    }

    func testOnlyTheChosenCloudEngineCanLead() {
        // Deepgram ready but OpenAI chosen and not ready: Deepgram is never substituted.
        let availability = cloudAvailability(online: true, deepgram: true, openAI: false)
        XCTAssertEqual(chain(.openAI, availability), [.appleSpeech, .onDevice])
    }

    func testEngineShapes() {
        XCTAssertEqual(ASREngine.appleSpeech.captureShape, .appleStreaming)
        XCTAssertEqual(ASREngine.onDevice.captureShape, .wholeUtterance)
        XCTAssertEqual(ASREngine.openAI.captureShape, .wholeUtterance)
        XCTAssertEqual(ASREngine.deepgram.captureShape, .cloudStreaming)
        XCTAssertEqual(ASREngine.allCases.filter(\.isCloud), [.deepgram, .openAI])
    }

    func testCloudPreferenceCopyIsHonest() {
        for preference in [ASREnginePreference.deepgram, .openAI] {
            XCTAssertTrue(preference.detail.contains("charged to your own"), "\(preference)")
            XCTAssertTrue(preference.detail.contains("HIPAA"), "\(preference)")
            XCTAssertFalse(preference.detail.contains("$"), "no price in the copy")
        }
        XCTAssertTrue(ASREnginePreference.openAI.detail.contains("ChatGPT sign-in"))
        XCTAssertTrue(ASREnginePreference.openAI.detail.contains("OpenAI API key"))
    }
}
