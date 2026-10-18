import XCTest
@testable import OpenGlasses
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Plan JD P0 — the Foundation Models half of the bridge: Apple's own schema type builds from
/// every tool the app registers, a call the model makes reaches the real execution authority with
/// the arguments it produced, and the per-turn transcript is shaped from the app's history.
///
/// The system model itself is not available on the simulator (`availability` is `.unavailable`),
/// so nothing here generates — but schemas, generated content and transcripts are plain values
/// the framework builds without it.
@MainActor
final class AppleToolBridgeTests: XCTestCase {

    /// A safe read tool registered under a name the Apple set offers, so authorization runs as it
    /// does in production.
    private final class RecordingTool: NativeTool {
        let name = "get_datetime"
        let description = "Reports the current date and time."
        var parametersSchema: [String: Any] {
            ["type": "object",
             "properties": ["timezone": ["type": "string", "description": "An IANA zone."],
                            "precise": ["type": "boolean"]]]
        }
        var executionSemantics: ToolExecutionSemantics { .read() }
        private(set) var invocations: [[String: Any]] = []
        func execute(args: [String: Any]) async throws -> String {
            invocations.append(args)
            return "Monday, 15 September 2026, 9:00 am"
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func makeAdapter(_ tool: RecordingTool, router: NativeToolRouter) throws -> NativeToolAdapter {
        try AppleToolBridge.adapter(name: tool.name, description: tool.description,
                                    parameters: tool.parametersSchema) { name, json in
            let outcome = await router.executeRoot(name: name,
                                                   args: AppleToolArguments.dictionary(fromJSON: json))
            return outcome.text
        }
    }

    func testEveryRegisteredToolBuildsAnAppleSchema() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Foundation Models needs iOS 26") }
        let registry = NativeToolRegistry(locationService: LocationService())
        // Field tools register only with the entitlement; build them directly so their (largest)
        // schemas are covered whatever the test host's settings.
        var tools: [any NativeTool] = registry.allTools
        tools += [FieldSessionTool(), ReadingTool(), EvidenceTool(), PartsRequestTool(), VanStockTool()]
        XCTAssertGreaterThan(tools.count, 30)
        for tool in tools {
            XCTAssertNoThrow(
                try AppleToolBridge.adapter(name: tool.name, description: tool.description,
                                            parameters: tool.parametersSchema) { _, _ in "" },
                "\(tool.name) has a schema the framework rejects")
        }
    }

    func testACallFromTheModelReachesTheToolWithItsArguments() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Foundation Models needs iOS 26") }
        let registry = NativeToolRegistry(locationService: LocationService())
        let tool = RecordingTool()
        registry.register(tool)
        let router = NativeToolRouter(registry: registry)
        let adapter = try makeAdapter(tool, router: router)

        XCTAssertEqual(adapter.name, "get_datetime")
        XCTAssertEqual(adapter.description, "Reports the current date and time.")

        let arguments = try GeneratedContent(json: #"{"timezone":"Pacific/Auckland","precise":null}"#)
        let output = try await adapter.call(arguments: arguments)

        XCTAssertEqual(output, "Monday, 15 September 2026, 9:00 am")
        XCTAssertEqual(tool.invocations.count, 1)
        XCTAssertEqual(tool.invocations.first?["timezone"] as? String, "Pacific/Auckland")
        XCTAssertNil(tool.invocations.first?["precise"], "an omitted optional is absent, not NSNull")
    }

    func testAnUnknownToolNameComesBackAsTextNotAThrow() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Foundation Models needs iOS 26") }
        let registry = NativeToolRegistry(locationService: LocationService())
        let router = NativeToolRouter(registry: registry)
        let adapter = try AppleToolBridge.adapter(name: "no_such_tool", description: "Nothing.",
                                                  parameters: ["type": "object"]) { name, json in
            await router.executeRoot(name: name, args: AppleToolArguments.dictionary(fromJSON: json)).text
        }
        let output = try await adapter.call(arguments: try GeneratedContent(json: "{}"))
        XCTAssertFalse(output.isEmpty, "the model is told why there is no result")
    }

    func testTranscriptCarriesInstructionsThenTheNewestTurns() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Foundation Models needs iOS 26") }
        let history: [(role: String, content: String)] = [
            ("user", "one"), ("assistant", "two"), ("system", "ignored"),
            ("user", "three"), ("assistant", ""), ("assistant", "four"),
        ]
        let transcript = AppleToolBridge.transcript(instructions: "Be brief.", tools: [],
                                                    history: history, carry: 3)
        // The last three entries: ("user","three"), ("assistant",""), ("assistant","four") — the
        // empty one is dropped.
        XCTAssertEqual(transcript.count, 3)
        guard case .instructions(let instructions) = transcript[transcript.startIndex] else {
            return XCTFail("instructions lead")
        }
        XCTAssertTrue(instructions.toolDefinitions.isEmpty)
        guard case .prompt = transcript[transcript.index(after: transcript.startIndex)] else {
            return XCTFail("then the user's turn")
        }
        guard case .response = transcript[transcript.index(transcript.startIndex, offsetBy: 2)] else {
            return XCTFail("then the assistant's")
        }

        let none = AppleToolBridge.transcript(instructions: "Be brief.", tools: [], history: history, carry: 0)
        XCTAssertEqual(none.count, 1, "carry 0 is the instructions alone")
    }

    func testTranscriptInstructionsCarryTheToolDefinitions() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Foundation Models needs iOS 26") }
        let registry = NativeToolRegistry(locationService: LocationService())
        let tool = RecordingTool()
        registry.register(tool)
        let adapter = try makeAdapter(tool, router: NativeToolRouter(registry: registry))
        let transcript = AppleToolBridge.transcript(instructions: "Be brief.", tools: [adapter],
                                                    history: [], carry: 12)
        guard case .instructions(let instructions) = transcript[transcript.startIndex] else {
            return XCTFail()
        }
        XCTAssertEqual(instructions.toolDefinitions.map(\.name), ["get_datetime"])
    }

    func testGenerationFailuresMapToSpeakableErrors() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Foundation Models needs iOS 26") }
        // Only the refusal case has a public initializer for its payload; the mapping for the
        // other cases is exercised by inspection of the switch (every case is named, no default
        // swallows one — the compiler enforces it).
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let mapped = LLMService.appleGenerationFailure(.refusal(refusal, context))
        guard case .modelDeclined(let provider) = mapped else { return XCTFail("\(mapped)") }
        XCTAssertEqual(provider, "Apple Intelligence")
        guard case .outputTruncated = LLMService.appleGenerationFailure(.exceededContextWindowSize(context)) else {
            return XCTFail()
        }
    }
    #endif
}
