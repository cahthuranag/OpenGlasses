import XCTest
@testable import OpenGlasses

/// Tests for the pure TTS engine-selection policy (Additional Capabilities #1 — the Kokoro tier):
/// given availability (ElevenLabs key + online, Kokoro model present), the user's preference, and
/// urgency, `TTSEngineSelector` produces the `ElevenLabs → Kokoro → AVSpeech` fallback chain.
final class TTSEngineSelectorTests: XCTestCase {

    private typealias Availability = TTSEngineSelector.Availability

    private func chain(_ preference: TTSEnginePreference,
                       _ availability: Availability,
                       _ urgency: TextToSpeechService.SpeechUrgency = .low) -> [TTSEngine] {
        TTSEngineSelector.chain(preference: preference, availability: availability, urgency: urgency)
    }

    // MARK: - Terminal fallback

    func testChainAlwaysTerminatesInSystem() {
        // Every preference × availability combination must end in the always-available system voice.
        for preference in TTSEnginePreference.allCases {
            for eleven in [false, true] {
                for kokoro in [false, true] {
                    let result = chain(preference, Availability(elevenLabsReady: eleven, kokoroReady: kokoro))
                    XCTAssertEqual(result.last, .system, "\(preference) eleven=\(eleven) kokoro=\(kokoro)")
                    XCTAssertEqual(result.filter { $0 == .system }.count, 1, "system appears exactly once")
                    XCTAssertFalse(result.isEmpty)
                }
            }
        }
    }

    func testNothingAvailableFallsToSystemOnly() {
        let result = chain(.auto, Availability(elevenLabsReady: false, kokoroReady: false))
        XCTAssertEqual(result, [.system])
    }

    // MARK: - Auto cascade

    func testAutoWithElevenLabsOnly() {
        let result = chain(.auto, Availability(elevenLabsReady: true, kokoroReady: false))
        XCTAssertEqual(result, [.elevenLabs, .system])  // today's behaviour, unchanged
        XCTAssertEqual(TTSEngineSelector.select(preference: .auto,
                                                availability: Availability(elevenLabsReady: true, kokoroReady: false)),
                       .elevenLabs)
    }

    func testAutoWithKokoroOnly() {
        let result = chain(.auto, Availability(elevenLabsReady: false, kokoroReady: true))
        XCTAssertEqual(result, [.kokoro, .system])
    }

    func testAutoWithBothReadyPrefersElevenLabsAtLowUrgency() {
        let result = chain(.auto, Availability(elevenLabsReady: true, kokoroReady: true))
        XCTAssertEqual(result, [.elevenLabs, .kokoro, .system])
    }

    // MARK: - Urgency adjustment

    func testHighUrgencyPromotesReadyKokoroAheadOfNetworkElevenLabs() {
        // A hazard-level alert shouldn't wait on a network round-trip when an on-device neural
        // voice is ready — Kokoro leads, ElevenLabs is kept as the next fallback.
        let result = chain(.auto, Availability(elevenLabsReady: true, kokoroReady: true), .high)
        XCTAssertEqual(result, [.kokoro, .elevenLabs, .system])
        XCTAssertEqual(TTSEngineSelector.select(preference: .auto,
                                                availability: Availability(elevenLabsReady: true, kokoroReady: true),
                                                urgency: .high),
                       .kokoro)
    }

    func testHighUrgencyDoesNotDowngradeToSystemWhenKokoroUnavailable() {
        // No on-device neural option → keep ElevenLabs first; never drop to the robotic voice
        // purely for speed.
        let result = chain(.auto, Availability(elevenLabsReady: true, kokoroReady: false), .high)
        XCTAssertEqual(result, [.elevenLabs, .system])
    }

    func testMediumUrgencyDoesNotReorder() {
        let result = chain(.auto, Availability(elevenLabsReady: true, kokoroReady: true), .medium)
        XCTAssertEqual(result, [.elevenLabs, .kokoro, .system])
    }

    // MARK: - Explicit preferences

    func testElevenLabsPreferenceFallsThroughToKokoroThenSystem() {
        let result = chain(.elevenLabs, Availability(elevenLabsReady: false, kokoroReady: true))
        XCTAssertEqual(result, [.kokoro, .system])  // graceful fallback when the cloud is unavailable
    }

    func testKokoroPreferenceNeverFallsBackToPaidCloud() {
        // User explicitly chose on-device → ElevenLabs is excluded even when it's available.
        let result = chain(.kokoro, Availability(elevenLabsReady: true, kokoroReady: true))
        XCTAssertEqual(result, [.kokoro, .system])
    }

    func testKokoroPreferenceWithoutModelIsSystemOnly() {
        let result = chain(.kokoro, Availability(elevenLabsReady: true, kokoroReady: false))
        XCTAssertEqual(result, [.system])  // still no paid cloud
    }

    func testKokoroPreferenceHighUrgencyStaysOnDevice() {
        let result = chain(.kokoro, Availability(elevenLabsReady: true, kokoroReady: true), .high)
        XCTAssertEqual(result, [.kokoro, .system])
    }

    func testSystemPreferenceForcesSystemEvenWhenEverythingReady() {
        let result = chain(.system, Availability(elevenLabsReady: true, kokoroReady: true), .high)
        XCTAssertEqual(result, [.system])
    }

    // MARK: - select == chain.first

    func testSelectMatchesChainHead() {
        let combos: [(TTSEnginePreference, Availability, TextToSpeechService.SpeechUrgency)] = [
            (.auto, Availability(elevenLabsReady: true, kokoroReady: true), .low),
            (.auto, Availability(elevenLabsReady: false, kokoroReady: true), .high),
            (.kokoro, Availability(elevenLabsReady: true, kokoroReady: false), .low),
            (.system, Availability(elevenLabsReady: true, kokoroReady: true), .medium),
        ]
        for (preference, availability, urgency) in combos {
            let head = TTSEngineSelector.chain(preference: preference, availability: availability, urgency: urgency).first
            let selected = TTSEngineSelector.select(preference: preference, availability: availability, urgency: urgency)
            XCTAssertEqual(selected, head)
        }
    }

    // MARK: - OpenAI and xAI voices (Plan ID item 5)

    private func ready(eleven: Bool = false, openAI: Bool = false, xai: Bool = false,
                       gemini: Bool = false, kokoro: Bool = false) -> Availability {
        Availability(elevenLabsReady: eleven, kokoroReady: kokoro, openAIReady: openAI, xaiReady: xai,
                     geminiReady: gemini)
    }

    /// Auto tries every cloud voice that is ready, ElevenLabs then OpenAI then xAI, then the phone.
    func testAutoOrdersEveryCombinationOfTheThreeCloudVoices() {
        for eleven in [false, true] {
            for openAI in [false, true] {
                for xai in [false, true] {
                    for kokoro in [false, true] {
                        var expected: [TTSEngine] = []
                        if eleven { expected.append(.elevenLabs) }
                        if openAI { expected.append(.openAI) }
                        if xai { expected.append(.xai) }
                        if kokoro { expected.append(.kokoro) }
                        expected.append(.system)
                        XCTAssertEqual(chain(.auto, ready(eleven: eleven, openAI: openAI, xai: xai, kokoro: kokoro)),
                                       expected, "eleven=\(eleven) openAI=\(openAI) xai=\(xai) kokoro=\(kokoro)")
                    }
                }
            }
        }
    }

    func testAutoWithOnlyAnOpenAIKeyUsesTheOpenAIVoice() {
        XCTAssertEqual(TTSEngineSelector.select(preference: .auto, availability: ready(openAI: true)), .openAI)
    }

    /// A chosen cloud voice falls back to the phone, never to another paid cloud.
    func testAChosenCloudVoiceFallsBackToKokoroThenSystemOnly() {
        let everything = ready(eleven: true, openAI: true, xai: true, kokoro: true)
        XCTAssertEqual(chain(.openAI, everything), [.openAI, .kokoro, .system])
        XCTAssertEqual(chain(.xai, everything), [.xai, .kokoro, .system])
        XCTAssertEqual(chain(.elevenLabs, everything), [.elevenLabs, .kokoro, .system])

        let chosenUnavailable = ready(eleven: true, openAI: false, xai: true, kokoro: true)
        XCTAssertEqual(chain(.openAI, chosenUnavailable), [.kokoro, .system])
        XCTAssertEqual(chain(.openAI, ready(eleven: true, xai: true)), [.system])
    }

    // MARK: - The Gemini voice (Plan JZ)

    /// Chosen, it is tried first and falls back to the phone, never to another paid cloud.
    func testAChosenGeminiVoiceFallsBackToKokoroThenSystemOnly() {
        let everything = ready(eleven: true, openAI: true, xai: true, gemini: true, kokoro: true)
        XCTAssertEqual(chain(.gemini, everything), [.gemini, .kokoro, .system])
        XCTAssertEqual(chain(.gemini, ready(eleven: true, openAI: true, xai: true, kokoro: true)),
                       [.kokoro, .system], "no Gemini key: the phone, not another cloud")
        XCTAssertEqual(chain(.gemini, everything, .high), [.kokoro, .gemini, .system])
    }

    /// Auto tries Gemini last of the cloud voices, and only with a Gemini key saved.
    func testAutoTriesGeminiLastOfTheCloudVoicesWhenItsKeyIsSaved() {
        XCTAssertEqual(chain(.auto, ready(gemini: true, kokoro: true)), [.gemini, .kokoro, .system])
        XCTAssertEqual(chain(.auto, ready(eleven: true, openAI: true, xai: true, gemini: true, kokoro: true)),
                       [.elevenLabs, .openAI, .xai, .gemini, .kokoro, .system])
        XCTAssertEqual(chain(.auto, ready(xai: true, gemini: true)), [.xai, .gemini, .system])
        XCTAssertEqual(chain(.auto, ready(eleven: true, openAI: true, xai: true, kokoro: true)),
                       [.elevenLabs, .openAI, .xai, .kokoro, .system], "no Gemini key: never tried")
        XCTAssertEqual(chain(.auto, ready(gemini: true, kokoro: true), .high), [.kokoro, .gemini, .system])
        for preference in TTSEnginePreference.allCases where ![.gemini, .auto].contains(preference) {
            XCTAssertFalse(chain(preference, ready(eleven: true, openAI: true, xai: true, gemini: true,
                                                   kokoro: true)).contains(.gemini), "\(preference)")
        }
    }

    func testKokoroAndSystemPreferencesNeverReachTheNewCloudVoices() {
        let everything = ready(eleven: true, openAI: true, xai: true, kokoro: true)
        XCTAssertEqual(chain(.kokoro, everything), [.kokoro, .system])
        XCTAssertEqual(chain(.system, everything), [.system])
    }

    /// Urgency behaves as before: a ready Kokoro goes ahead of every network voice, and nothing
    /// else moves.
    func testHighUrgencyPromotesKokoroAheadOfEveryCloudVoice() {
        let everything = ready(eleven: true, openAI: true, xai: true, kokoro: true)
        XCTAssertEqual(chain(.auto, everything, .high), [.kokoro, .elevenLabs, .openAI, .xai, .system])
        XCTAssertEqual(chain(.auto, ready(openAI: true, kokoro: true), .high), [.kokoro, .openAI, .system])
        XCTAssertEqual(chain(.openAI, everything, .high), [.kokoro, .openAI, .system])
        XCTAssertEqual(chain(.auto, ready(openAI: true, xai: true), .high), [.openAI, .xai, .system],
                       "no Kokoro, no reordering")
        XCTAssertEqual(chain(.auto, everything, .medium), [.elevenLabs, .openAI, .xai, .kokoro, .system])
    }

    func testEveryPreferenceStillEndsInSystemWithTheNewVoices() {
        for preference in TTSEnginePreference.allCases {
            for bits in 0..<32 {
                let availability = ready(eleven: bits & 1 != 0, openAI: bits & 2 != 0,
                                         xai: bits & 4 != 0, gemini: bits & 16 != 0,
                                         kokoro: bits & 8 != 0)
                let result = chain(preference, availability)
                XCTAssertEqual(result.last, .system, "\(preference) \(bits)")
                XCTAssertEqual(result.filter { $0 == .system }.count, 1)
                XCTAssertEqual(Set(result).count, result.count, "no engine twice")
            }
        }
    }

    // MARK: - Readiness of a cloud voice

    private func cloudReady(_ engine: TTSEngine, credential: Bool = true, quota: Bool = false,
                            onDeviceOnly: Bool = false, online: Bool = true,
                            medical: MedicalEgressGuard.Mode = .off) -> Bool {
        TTSEngineSelector.cloudVoiceReady(engine, hasCredential: credential, quotaExhausted: quota,
                                          onDeviceOnly: onDeviceOnly, online: online,
                                          medicalMode: medical)
    }

    func testACloudVoiceIsReadyOnlyWithEverySignalGreen() {
        for engine in TTSEngine.cloudVoices {
            XCTAssertTrue(cloudReady(engine), "\(engine)")
            XCTAssertFalse(cloudReady(engine, credential: false), "\(engine) without a credential")
            XCTAssertFalse(cloudReady(engine, quota: true), "\(engine) out of credit")
            XCTAssertFalse(cloudReady(engine, onDeviceOnly: true), "\(engine) for on-device-only text")
            XCTAssertFalse(cloudReady(engine, online: false), "\(engine) offline")
        }
        XCTAssertFalse(cloudReady(.kokoro), "not a cloud voice")
        XCTAssertFalse(cloudReady(.system), "not a cloud voice")
    }

    /// Medical local-only takes every cloud voice out of the chain; Medical Compliance without
    /// local-only does not.
    func testMedicalLocalOnlyRemovesEveryCloudVoice() {
        for engine in TTSEngine.cloudVoices {
            XCTAssertFalse(cloudReady(engine, medical: .localOnly), "\(engine)")
            XCTAssertTrue(cloudReady(engine, medical: .init(hipaaMode: true, localOnly: false)), "\(engine)")
        }
        let medical = Availability(
            elevenLabsReady: cloudReady(.elevenLabs, medical: .localOnly),
            kokoroReady: true,
            openAIReady: cloudReady(.openAI, medical: .localOnly),
            xaiReady: cloudReady(.xai, medical: .localOnly),
            geminiReady: cloudReady(.gemini, medical: .localOnly))
        XCTAssertEqual(chain(.auto, medical), [.kokoro, .system])
        XCTAssertEqual(chain(.openAI, medical), [.kokoro, .system])
        XCTAssertEqual(chain(.xai, medical), [.kokoro, .system])
        XCTAssertEqual(chain(.gemini, medical), [.kokoro, .system])
    }

    func testEachCloudVoiceNamesItsVendorAndRoute() {
        XCTAssertEqual(TTSEngine.cloudVoices, [.elevenLabs, .openAI, .xai, .gemini])
        XCTAssertEqual(TTSEngine.gemini.speechRoute, .geminiSpeechSynthesis)
        XCTAssertEqual(TTSEngine.gemini.vendorName, "Gemini")
        XCTAssertTrue(TTSEngine.gemini.isCloud)
        XCTAssertEqual(TTSEnginePreference.gemini.displayName, "Cloud (Gemini)")
        XCTAssertEqual(TTSEnginePreference.gemini.cloudEngine, .gemini)
        XCTAssertEqual(TTSEngine.openAI.speechRoute, .openAISpeechSynthesis)
        XCTAssertEqual(TTSEngine.xai.speechRoute, .xaiSpeechSynthesis)
        XCTAssertEqual(TTSEngine.elevenLabs.speechRoute, .elevenLabsSpeechSynthesis)
        XCTAssertNil(TTSEngine.kokoro.speechRoute)
        XCTAssertEqual(TTSEngine.openAI.vendorName, "OpenAI")
        XCTAssertEqual(TTSEngine.xai.vendorName, "xAI")
        XCTAssertEqual(TTSEnginePreference.openAI.displayName, "Cloud (OpenAI)")
        XCTAssertEqual(TTSEnginePreference.xai.displayName, "Cloud (xAI)")
    }
}
