import XCTest
@testable import OpenGlasses

final class RealtimeTextContractTests: XCTestCase {
    func testQwenContextRefreshPreservesAudioAndNeverRequestsInference() throws {
        let adapter = QwenRealtimeAdapter(voice: "Tina")
        _ = try adapter.encode(.configure(instructions: "base", tools: []))
        _ = try adapter.encode(.audio(Data([0, 0])))
        let messages = try adapter.encode(.updateContext(instructions: "base plus current job"))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["type"] as? String, "session.update")
        let session = try XCTUnwrap(messages[0]["session"] as? [String: Any])
        XCTAssertEqual(session["instructions"] as? String, "base plus current job")
        XCTAssertNil(session["audio"])
        XCTAssertNil(session["turn_detection"])
        let refresh = try XCTUnwrap(adapter.encode(.configure(instructions: "changed", tools: [])).first?["session"] as? [String: Any])
        XCTAssertNil(refresh["audio"])
        XCTAssertThrowsError(try adapter.encode(.text("answer now", completeTurn: true)))
    }
    func testDoubaoRetainsRequiredConfigurationDuringContextUpdate() throws {
        let adapter = DoubaoRealtimeAdapter(model: "1.2.6.1", voice: "fixture-voice")
        _ = try adapter.encode(.configure(instructions: "base", tools: [["name": "fixture_tool"]]))
        _ = adapter.decode(["type": "session.created"])
        let messages = try adapter.encode(.updateContext(instructions: "current app state"))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["type"] as? String, "session.update")
        let session = try XCTUnwrap(messages[0]["session"] as? [String: Any])
        XCTAssertEqual(session["model"] as? String, "1.2.6.1")
        XCTAssertEqual(session["instructions"] as? String, "current app state")
        XCTAssertNotNil(session["audio"])
        XCTAssertNotNil(session["tools"])
    }
    func testDoubaoSpeechIsExactTextAndDoesNotInventUserTurns() throws {
        let adapter = DoubaoRealtimeAdapter(model: "1.2.6.1", voice: "fixture-voice")
        let speech = try adapter.encode(.speakText("Your report is ready."))
        XCTAssertEqual(speech.map { $0["type"] as? String }, ["speech_text_buffer.replacement.append", "speech_text_buffer.replacement.commit"])
        XCTAssertEqual(speech[0]["text"] as? String, "Your report is ready.")
        XCTAssertNil(speech[1]["text"], "Commit must not repeat the spoken text")
        XCTAssertTrue(adapter.decode(["type": "response.output_audio.done"]).contains { if case .speechFinished = $0 { return true }; return false })
        XCTAssertThrowsError(try adapter.encode(.text("answer now", completeTurn: true)))
    }
    func testQwenAudioIsASeparateAuthenticatedTextTurnProfile() throws {
        var model = try XCTUnwrap(RealtimeProviderCatalog.template("qwen-audio")).modelConfiguration()
        model.apiKey = "fixture-key"
        model.endpoint = model.endpoint.replacingOccurrences(of: "{workspace}", with: "fixture-workspace")
        XCTAssertEqual(model.model, "qwen-audio-3.1-realtime-plus")
        XCTAssertEqual(model.voice, "longanqian_v3.1")
        XCTAssertEqual(RealtimeProviderCatalog.profiles(for: "qwen-audio"), [.qwenAudioV1])
        XCTAssertEqual(RealtimeProviderCatalog.profiles(for: "qwen"), [.qwenOmniV1])
        let request = try model.request(build: .release)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Beta"))
        let adapter = try RealtimeAdapterRegistry.make(for: model)
        let setup = try XCTUnwrap(adapter.encode(.configure(instructions: "base", tools: [["type": "function", "name": "fixture_tool"]])).first?["session"] as? [String: Any])
        XCTAssertEqual(setup["input_audio_format"] as? String, "pcm")
        XCTAssertEqual(setup["voice"] as? String, model.voice)
        XCTAssertEqual(((setup["tools"] as? [[String: Any]])?.first?["function"] as? [String: Any])?["name"] as? String, "fixture_tool")
        let turn = try adapter.encode(.text("Read this result", completeTurn: true))
        XCTAssertEqual(turn.map { $0["type"] as? String }, ["conversation.item.create", "response.create"])
        let item = try XCTUnwrap(turn[0]["item"] as? [String: Any])
        XCTAssertEqual(item["role"] as? String, "user")
        XCTAssertEqual((item["content"] as? [[String: Any]])?.first?["text"] as? String, "Read this result")
        XCTAssertEqual(try adapter.encode(.text("Background only", completeTurn: false)).count, 1)
        XCTAssertThrowsError(try adapter.encode(.image(Data(), prompt: nil)))
        let refresh = try XCTUnwrap(adapter.encode(.configure(instructions: "changed", tools: [])).first?["session"] as? [String: Any])
        XCTAssertNil(refresh["voice"])
        XCTAssertNil(refresh["turn_detection"])
        adapter.reset()
        let resetSetup = try XCTUnwrap(adapter.encode(.configure(instructions: "base", tools: [])).first?["session"] as? [String: Any])
        XCTAssertEqual(resetSetup["voice"] as? String, model.voice)
    }
    func testCapabilitiesSeparateSilentContextSpeechAndGeneratedTurns() {
        let omni = RealtimeProtocolProfile.qwenOmniV1.capabilities
        XCTAssertTrue(omni.contextUpdate); XCTAssertFalse(omni.textTurn); XCTAssertFalse(omni.suppliedSpeech)
        let doubao = RealtimeProtocolProfile.doubaoDuplexV3.capabilities
        XCTAssertTrue(doubao.contextUpdate); XCTAssertFalse(doubao.textTurn); XCTAssertTrue(doubao.suppliedSpeech)
        let audio = RealtimeProtocolProfile.qwenAudioV1.capabilities
        XCTAssertTrue(audio.contextUpdate); XCTAssertTrue(audio.textTurn); XCTAssertFalse(audio.vision)
    }
    func testContextReplacesIndependentLanesAndPreservesBasePrompt() {
        var context = RealtimeAppContext()
        context.update("Job 1004", key: "job")
        context.update("Debrief open", key: "debrief")
        context.update("Job 1005", key: "job")
        let combined = context.instructions(appendingTo: "Keep the user's base instructions.")
        XCTAssertTrue(combined.hasPrefix("Keep the user's base instructions."))
        XCTAssertTrue(combined.contains("Job 1005")); XCTAssertTrue(combined.contains("Debrief open"))
        XCTAssertFalse(combined.contains("Job 1004"))
        context.update("", key: "debrief")
        XCTAssertFalse(context.instructions(appendingTo: "base").contains("Debrief open"))
    }
    func testAppContextIsBoundedAndNewestStateWins() {
        var context = RealtimeAppContext()
        context.update("obsolete", key: "old")
        context.update(String(repeating: "新", count: 9000), key: "new")
        let combined = context.instructions(appendingTo: "base")
        XCTAssertFalse(combined.contains("obsolete"))
        XCTAssertEqual(combined.filter { $0 == "新" }.count, RealtimeAppContext.maximumCharacters)
        for index in 0..<20 { context.update("entry-\(index)", key: "lane-\(index)") }
        let bounded = context.instructions(appendingTo: "base")
        XCTAssertFalse(bounded.contains("entry-0\n"))
        XCTAssertTrue(bounded.contains("entry-19"))
    }
}

@MainActor
private final class TextDeliveryInjector: LiveSessionInjecting {
    var canInject = true
    var supportsTextInjection = false
    var supportsSuppliedSpeech = false
    var supportsContextUpdates = true
    var isBusyForInjection = false
    var liveSessionIdentity = 1
    var spoken: [String] = []
    var textTurns: [(String, Bool)] = []
    func injectSharpImage(jpegData: Data) {}
    func injectText(_ text: String, completeTurn: Bool) { textTurns.append((text, completeTurn)) }
    func speakSuppliedText(_ text: String) { spoken.append(text) }
}

@MainActor
final class LiveAnnouncementDeliveryTests: XCTestCase {
    func testExactSpeechWinsOverGeneratedTurn() {
        let injector = TextDeliveryInjector()
        injector.supportsTextInjection = true; injector.supportsSuppliedSpeech = true
        XCTAssertTrue(LiveAnnouncementDelivery.deliver("Report ready", using: injector))
        XCTAssertEqual(injector.spoken, ["Report ready"])
        XCTAssertTrue(injector.textTurns.isEmpty)
    }
    func testGeneratedDeliveryCompletesTheTurn() {
        let injector = TextDeliveryInjector(); injector.supportsTextInjection = true
        XCTAssertTrue(LiveAnnouncementDelivery.deliver("Report ready", using: injector))
        XCTAssertEqual(injector.textTurns.count, 1)
        XCTAssertTrue(injector.textTurns[0].1)
        XCTAssertTrue(injector.textTurns[0].0.contains("Report ready"))
    }
    func testContextOnlyAndDisconnectedSessionsRequireLocalSpeech() {
        let injector = TextDeliveryInjector()
        XCTAssertFalse(LiveAnnouncementDelivery.deliver("Report ready", using: injector))
        injector.supportsSuppliedSpeech = true; injector.canInject = false
        XCTAssertFalse(LiveAnnouncementDelivery.deliver("Report ready", using: injector))
        XCTAssertTrue(injector.spoken.isEmpty); XCTAssertTrue(injector.textTurns.isEmpty)
    }
}
