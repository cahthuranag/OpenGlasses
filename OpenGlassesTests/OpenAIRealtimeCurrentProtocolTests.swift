import XCTest
@testable import OpenGlasses

/// OpenAI's current Realtime protocol (`openai.realtime.v1`), beside the beta it replaced.
final class OpenAIRealtimeCurrentProtocolTests: XCTestCase {
    private func fixture(_ name: String) throws -> [[String: Any]] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/Realtime/\(name).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
    private func openAIModel() -> RealtimeModelConfig {
        var model = RealtimeProviderCatalog.template("openai")!.modelConfiguration()
        model.apiKey = "fixture-key"
        return model
    }
    private func compatibleModel(_ profile: RealtimeProtocolProfile) -> RealtimeModelConfig {
        var model = RealtimeProviderCatalog.template("compatible")!.modelConfiguration()
        model.endpoint = "wss://gateway.example/realtime"
        model.model = "fixture-model"
        model.apiKey = "fixture-key"
        model.profileID = profile.rawValue
        return model
    }
    private func failure(_ events: [RealtimeEvent]) -> (String, Bool)? {
        guard case .failure(let message, let retryable)? = events.first else { return nil }
        return (message, retryable)
    }

    // MARK: - Profiles and requests

    func testTheOpenAITemplateUsesTheCurrentProtocolOnly() {
        XCTAssertEqual(RealtimeProviderCatalog.template("openai")?.profile, .openAIRealtimeV1)
        XCTAssertEqual(RealtimeProviderCatalog.profiles(for: "openai"), [.openAIRealtimeV1])
        let compatible = RealtimeProviderCatalog.profiles(for: "compatible")
        XCTAssertTrue(compatible.contains(.openAIRealtimeV1))
        XCTAssertTrue(compatible.contains(.openAIBetaV1))
        XCTAssertEqual(RealtimeProviderCatalog.template("compatible")?.profile, .openAIBetaV1,
                       "compatible setups keep the protocol they had")
    }

    func testNoProfileSendsTheBetaHeader() throws {
        let openAI = try openAIModel().request(build: .release)
        XCTAssertEqual(openAI.url?.absoluteString, "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")
        XCTAssertEqual(openAI.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertNil(openAI.value(forHTTPHeaderField: "OpenAI-Beta"))
        for profile in [RealtimeProtocolProfile.openAIRealtimeV1, .openAIBetaV1] {
            XCTAssertNil(try compatibleModel(profile).request(build: .release).value(forHTTPHeaderField: "OpenAI-Beta"))
        }
    }

    func testBothOpenAIProfilesShareCapabilitiesAndAudio() {
        let current = RealtimeProtocolProfile.openAIRealtimeV1, beta = RealtimeProtocolProfile.openAIBetaV1
        XCTAssertEqual(current.capabilities, beta.capabilities)
        XCTAssertEqual(current.inputSampleRate, 24000)
        XCTAssertEqual(current.audioConfiguration.owner, .openAIRealtime)
        XCTAssertTrue(current.isOpenAIShape)
        XCTAssertTrue(beta.isOpenAIShape)
        XCTAssertFalse(RealtimeProtocolProfile.qwenOmniV1.isOpenAIShape)
        XCTAssertNotEqual(current.title, beta.title)
    }

    func testTheRegistryPicksTheAdapterAndTheProtocolChoiceByProvider() throws {
        let openAI = try XCTUnwrap(try RealtimeAdapterRegistry.make(for: openAIModel()) as? OpenAIRealtimeGAAdapter)
        XCTAssertFalse(openAI.offersProtocolChoice)
        let current = try XCTUnwrap(try RealtimeAdapterRegistry.make(for: compatibleModel(.openAIRealtimeV1)) as? OpenAIRealtimeGAAdapter)
        XCTAssertTrue(current.offersProtocolChoice)
        let beta = try RealtimeAdapterRegistry.make(for: compatibleModel(.openAIBetaV1))
        XCTAssertEqual(beta.profile, .openAIBetaV1)
        XCTAssertFalse(beta is OpenAIRealtimeGAAdapter)
    }

    @MainActor
    func testTheLegacyServiceEntryPointPicksTheProtocolByEndpointKind() {
        let service = OpenAIRealtimeService(transportFactory: { _ in fatalError("never connects") })
        service.configure(apiKey: "fixture-key", model: "gpt-realtime", systemInstruction: "fixture")
        XCTAssertEqual(service.modelConfiguration?.profile, .openAIRealtimeV1)
        service.configure(connection: .init(endpoint: "wss://gateway.example/realtime", apiKey: "fixture-key", model: "m"),
                          systemInstruction: "fixture")
        XCTAssertEqual(service.modelConfiguration?.profile, .openAIBetaV1)
    }

    // MARK: - Client events

    func testSessionUpdateGolden() {
        let payload = OpenAIRealtimeGAAdapter.sessionUpdate(instructions: "INSTRUCTIONS", tools: [])
        let pcm: [String: Any] = ["type": "audio/pcm", "rate": 24000]
        let expected: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "output_modalities": ["audio"],
                "instructions": "INSTRUCTIONS",
                "audio": [
                    "input": [
                        "format": pcm,
                        "transcription": ["model": "gpt-live-transcribe"],
                        "turn_detection": ["type": "server_vad", "threshold": 0.5, "prefix_padding_ms": 300,
                                           "silence_duration_ms": 500, "create_response": true, "interrupt_response": true],
                    ],
                    "output": ["format": pcm],
                ],
            ],
        ]
        XCTAssertEqual(LiveJobContract.canonicalJSON(payload), LiveJobContract.canonicalJSON(expected))
    }

    func testSessionUpdateCarriesToolsAndNoBetaFields() throws {
        let tools: [[String: Any]] = [["type": "function", "name": "fixture_tool", "parameters": ["type": "object"]]]
        let session = try XCTUnwrap(OpenAIRealtimeGAAdapter.sessionUpdate(instructions: "I", tools: tools)["session"] as? [String: Any])
        XCTAssertEqual(session["tool_choice"] as? String, "auto")
        XCTAssertEqual((session["tools"] as? [[String: Any]])?.first?["name"] as? String, "fixture_tool")
        for beta in ["modalities", "input_audio_format", "output_audio_format", "input_audio_transcription", "turn_detection", "voice"] {
            XCTAssertNil(session[beta], beta)
        }
    }

    func testContextUpdateNamesTheSessionType() throws {
        let messages = try OpenAIRealtimeGAAdapter().encode(.updateContext(instructions: "Job 1005"))
        XCTAssertEqual(LiveJobContract.canonicalJSON(messages[0]),
                       LiveJobContract.canonicalJSON(["type": "session.update",
                                                      "session": ["type": "realtime", "instructions": "Job 1005"]]))
    }

    func testImagesAreDataURIsAndTheBetaShapeIsUnchanged() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        let current = try OpenAIRealtimeGAAdapter().encode(.image(jpeg, prompt: "What is this?"))
        let content = try XCTUnwrap((current[0]["item"] as? [String: Any])?["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["input_text", "input_image"])
        XCTAssertEqual(content[1]["image_url"] as? String, "data:image/jpeg;base64,/9j/")
        XCTAssertNil(content[1]["image"])
        let beta = try OpenAIRealtimeAdapter().encode(.image(jpeg, prompt: nil))
        let betaContent = try XCTUnwrap((beta[0]["item"] as? [String: Any])?["content"] as? [[String: Any]])
        XCTAssertEqual(betaContent.first?["image"] as? String, "/9j/")
        XCTAssertNil(betaContent.first?["image_url"])
    }

    func testUnchangedCommandsMatchTheBetaWire() throws {
        let current = OpenAIRealtimeGAAdapter(), beta = OpenAIRealtimeAdapter()
        let commands: [RealtimeCommand] = [
            .audio(Data([1, 2])), .text("Your report is ready", completeTurn: true, toolsAllowed: false),
            .text("context", completeTurn: false), .toolResult(id: "call-1", output: "{}"),
            .interrupt(itemID: "reply", contentIndex: 0, playedMilliseconds: 640), .mute(true), .close,
        ]
        for command in commands {
            XCTAssertEqual(try current.encode(command).map { LiveJobContract.canonicalJSON($0) },
                           try beta.encode(command).map { LiveJobContract.canonicalJSON($0) })
        }
        XCTAssertThrowsError(try current.encode(.speakText("fixture")))
    }

    // MARK: - Server events

    func testFixtureCoversReadinessAudioTranscriptsToolsAndUsage() throws {
        let adapter = OpenAIRealtimeGAAdapter()
        let events = try fixture("openai-realtime-v1").flatMap(adapter.decode)
        XCTAssertTrue(events.contains { if case .configureRequested = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .ready = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .userSpeaking(true) = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .userSpeaking(false) = $0 { return true }; return false })
        XCTAssertTrue(events.contains {
            if case .audio(let data, let item, let index) = $0 { return data == Data([0, 0, 1, 0]) && item == "fixture-reply" && index == 0 }
            return false
        })
        XCTAssertTrue(events.contains { if case .inputTranscript(let text, true) = $0 { return text == "What's the torque for this bolt?" }; return false })
        XCTAssertTrue(events.contains { if case .outputTranscript(let text) = $0 { return text == "Let me check the manual." }; return false })
        XCTAssertTrue(events.contains { if case .usage(5, 7) = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .turnComplete = $0 { return true }; return false })
        let calls = events.compactMap { event -> [OpenAIRealtimeFunctionCall]? in
            if case .toolCalls(let calls) = event { return calls }; return nil
        }.flatMap { $0 }
        XCTAssertEqual(calls, [.init(callId: "fixture-call", name: "fixture_tool", argumentsJSON: "{\"question\":\"fixture\"}")],
                       "a call announced twice is delivered once")
    }

    func testEachProfileReadsOnlyItsOwnAudioEventNames() {
        let current = OpenAIRealtimeGAAdapter(), beta = OpenAIRealtimeAdapter()
        for name in ["response.audio.delta", "response.audio_transcript.delta"] {
            XCTAssertTrue(current.decode(["type": name, "delta": "AAAA"]).isEmpty, name)
            XCTAssertFalse(beta.decode(["type": name, "delta": "AAAA"]).isEmpty, name)
        }
        for name in ["response.output_audio.delta", "response.output_audio_transcript.delta"] {
            XCTAssertFalse(current.decode(["type": name, "delta": "AAAA"]).isEmpty, name)
            XCTAssertTrue(beta.decode(["type": name, "delta": "AAAA"]).isEmpty, name)
        }
        XCTAssertTrue(current.decode(["type": "response.output_audio.delta", "delta": "invalid base64!"]).isEmpty)
    }

    func testResetForgetsDeliveredCalls() {
        let adapter = OpenAIRealtimeGAAdapter()
        let call: [String: Any] = ["type": "response.function_call_arguments.done", "call_id": "c", "name": "n", "arguments": "{}"]
        XCTAssertEqual(adapter.decode(call).count, 1)
        XCTAssertTrue(adapter.decode(call).isEmpty)
        adapter.reset()
        XCTAssertEqual(adapter.decode(call).count, 1)
    }

    // MARK: - Errors

    func testTheBetaRefusalOpenAISendsTodayIsAProtocolMismatch() throws {
        // Recorded live on 2026-10-29 for the request the app sent before this change.
        let refusal: [String: Any] = ["type": "error", "error": [
            "type": "invalid_request_error", "code": "beta_api_shape_disabled",
            "message": "The Realtime Beta API is no longer supported. Please use /v1/realtime for the GA API."]]
        let builtIn = OpenAIRealtimeAdapter()
        let (message, retryable) = try XCTUnwrap(failure(builtIn.decode(refusal)))
        XCTAssertFalse(retryable)
        XCTAssertEqual(message, String(localized: "The realtime service did not accept this app's session settings."))
        builtIn.offersProtocolChoice = true
        XCTAssertEqual(try XCTUnwrap(failure(builtIn.decode(refusal))).0,
                       String(localized: "This server does not accept the selected realtime protocol. Choose the other OpenAI Realtime protocol in the model editor."))
        let missingType: [String: Any] = ["type": "error", "error": [
            "type": "invalid_request_error", "code": "missing_required_parameter",
            "message": "Missing required parameter: 'session.type'."]]
        XCTAssertEqual(OpenAIRealtimeEvents.rejection(code: "missing_required_parameter", type: "invalid_request_error",
                                                      message: "Missing required parameter: 'session.type'."), .protocolMismatch)
        XCTAssertNotNil(failure(OpenAIRealtimeGAAdapter().decode(missingType)))
    }

    func testRejectionsAreTerminalAndNeverEchoTheServerMessage() throws {
        let adapter = OpenAIRealtimeGAAdapter()
        let cases: [([String: Any], OpenAIRealtimeEvents.Rejection)] = [
            (["code": "invalid_api_key", "type": "invalid_request_error", "message": "Incorrect API key provided: sk-secret****"], .apiKey),
            (["code": "model_not_found", "type": "invalid_request_error", "message": "The model `secret-model` does not exist"], .model),
            (["type": "invalid_request_error", "message": "The model gpt-4o-realtime-preview has been deprecated"], .model),
            (["code": "unknown_parameter", "type": "invalid_request_error", "message": "Unknown parameter: 'session.secret'."], .protocolMismatch),
            (["code": "invalid_value", "type": "invalid_request_error", "message": "secret value"], .configuration),
        ]
        var messages: Set<String> = []
        for (error, expected) in cases {
            XCTAssertEqual(OpenAIRealtimeEvents.rejection(code: error["code"] as? String, type: error["type"] as? String,
                                                          message: error["message"] as? String), expected)
            let (message, retryable) = try XCTUnwrap(failure(adapter.decode(["type": "error", "error": error])))
            XCTAssertFalse(retryable)
            XCTAssertFalse(message.contains("secret"))
            messages.insert(message)
        }
        XCTAssertEqual(messages.count, 4, "a key, a model, a protocol and a configuration problem each read differently")
    }

    func testRecoverableAndUnknownErrorsKeepTheirOldBehaviour() throws {
        let adapter = OpenAIRealtimeGAAdapter()
        XCTAssertTrue(adapter.decode(["type": "error", "error": ["type": "invalid_request_error", "code": "response_cancel_not_active",
                                                                 "message": "Cancellation failed: no active response found"]]).isEmpty)
        let (_, retryable) = try XCTUnwrap(failure(adapter.decode(["type": "error", "error": ["type": "server_error", "message": "boom"]])))
        XCTAssertTrue(retryable)
    }

    // MARK: - Migration

    func testOpenAIModelsMoveOffTheBetaAndCompatibleModelsStay() {
        var openAI = openAIModel(); openAI.profileID = RealtimeProtocolProfile.openAIBetaV1.rawValue
        let compatible = compatibleModel(.openAIBetaV1)
        var qwen = RealtimeProviderCatalog.template("qwen")!.modelConfiguration(); qwen.apiKey = "fixture-key"
        let moved = RealtimeModelConfig.movingOpenAIOffBeta([openAI, compatible, qwen])
        XCTAssertEqual(moved?.map(\.profileID), ["openai.realtime.v1", "openai.beta.v1", "qwen.omni.v1"])
        XCTAssertEqual(moved?.first?.apiKey, "fixture-key")
        XCTAssertEqual(moved?.first?.id, openAI.id)
        XCTAssertNil(RealtimeModelConfig.movingOpenAIOffBeta(moved ?? []), "a second pass changes nothing")
        XCTAssertNil(RealtimeModelConfig.movingOpenAIOffBeta([compatible, qwen]))
    }
}

/// The saved-model migration against the real Keychain-backed store.
final class OpenAIRealtimeProtocolMigrationTests: XCTestCase {
    private var saved: Data??
    private var flags: [String: Any] = [:]
    private var savedChatModels: Data??
    private let flagKeys = ["realtimeModelsMigrated_v1", "realtimeModelsMigrated_v2", "realtimeModelsMigrated_v3",
                                  "pendingRealtimeModelNotice", "activeModelId"]
    override func setUp() {
        saved = .some(KeychainService.data(for: "savedRealtimeModels"))
        savedChatModels = .some(KeychainService.data(for: "savedModelConfigs"))
        for key in flagKeys { flags[key] = UserDefaults.standard.object(forKey: key); UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: "realtimeModelsMigrated_v1")
    }
    override func tearDown() {
        KeychainService.setData(saved ?? nil, for: "savedRealtimeModels")
        KeychainService.setData(savedChatModels ?? nil, for: "savedModelConfigs")
        for key in flagKeys {
            if let value = flags[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
    func testMigrationMovesSavedOpenAIModelsOnceAndSetsItsFlag() {
        var openAI = RealtimeProviderCatalog.template("openai")!.modelConfiguration()
        openAI.apiKey = "fixture-key"; openAI.profileID = "openai.beta.v1"
        var compatible = RealtimeProviderCatalog.template("compatible")!.modelConfiguration()
        compatible.endpoint = "wss://gateway.example/realtime"
        XCTAssertTrue(Config.setSavedRealtimeModels([openAI, compatible]))
        XCTAssertTrue(Config.migrateRealtimeModelsIfNeeded())
        XCTAssertEqual(Config.savedRealtimeModels.map(\.profileID), ["openai.realtime.v1", "openai.beta.v1"])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "realtimeModelsMigrated_v2"))
        // Once flagged it never runs again, even if a beta OpenAI model reappears.
        XCTAssertTrue(Config.setSavedRealtimeModels([openAI]))
        XCTAssertTrue(Config.migrateRealtimeModelsIfNeeded())
        XCTAssertEqual(Config.savedRealtimeModels.first?.profileID, "openai.beta.v1")
    }
    func testTheLegacyOpenAIShortcutResolvesToTheCurrentProtocol() throws {
        var chat = ModelConfig.defaultConfig(for: .openai)
        chat.apiKey = "fixture-key"; chat.model = "gpt-realtime-2.1"
        Config.setSavedModels([chat])
        let model = try XCTUnwrap(Config.realtimeModel(for: .openaiRealtime))
        XCTAssertEqual(model.profile, .openAIRealtimeV1)
        XCTAssertNil(try model.request(build: .release).value(forHTTPHeaderField: "OpenAI-Beta"))
    }
}
