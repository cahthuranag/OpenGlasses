import Foundation

enum RealtimeCommand {
    case configure(instructions: String, tools: [[String: Any]])
    case audio(Data)
    case image(Data, prompt: String?)
    /// `toolsAllowed: false` marks an announcement (Plan HY P3): the response it starts may not
    /// call a tool. Protocols with no per-response tool switch ignore it.
    case text(String, completeTurn: Bool, toolsAllowed: Bool = true)
    /// Replace the complete system instruction without changing audio/VAD configuration.
    case updateContext(instructions: String)
    /// Speak exact app text; this does not ask the model to compose a response.
    case speakText(String)
    case toolResult(id: String, output: String)
    case interrupt(itemID: String?, contentIndex: Int, playedMilliseconds: Int)
    case mute(Bool)
    case close
}

enum RealtimeEvent {
    case configureRequested, ready
    case audio(Data, itemID: String?, contentIndex: Int)
    case inputTranscript(String, complete: Bool)
    case outputTranscript(String)
    case userSpeaking(Bool), interrupted, turnComplete
    case speechFinished
    case toolCalls([OpenAIRealtimeFunctionCall])
    case usage(tokensIn: Int, tokensOut: Int)
    case failure(message: String, retryable: Bool)
    case closed
}

enum RealtimeAdapterError: LocalizedError {
    case unsupportedOperation(String)
    case imageTooLarge
    case imageBeforeAudio
    var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let operation): return String(localized: "This realtime protocol does not support \(operation).")
        case .imageTooLarge: return String(localized: "This realtime provider's image size limit was exceeded.")
        case .imageBeforeAudio: return String(localized: "This realtime provider requires audio before the first image.")
        }
    }
}

/// Only wire semantics live here. Connection policy and app lifecycle are engine responsibilities.
protocol RealtimeProtocolAdapter: AnyObject {
    var profile: RealtimeProtocolProfile { get }
    var createsSessionOnOpen: Bool { get }
    func encode(_ command: RealtimeCommand) throws -> [[String: Any]]
    func decode(_ json: [String: Any]) -> [RealtimeEvent]
    func reset()
}

enum RealtimeAdapterRegistry {
    static func make(for model: RealtimeModelConfig) throws -> RealtimeProtocolAdapter {
        guard let profile = model.profile else { throw RealtimeModelConfig.ConfigurationError.unknownProtocol }
        switch profile {
        case .openAIRealtimeV1:
            let adapter = OpenAIRealtimeGAAdapter()
            adapter.offersProtocolChoice = model.providerID == "compatible"
            return adapter
        case .openAIBetaV1:
            let adapter = OpenAIRealtimeAdapter()
            adapter.offersProtocolChoice = model.providerID == "compatible"
            return adapter
        case .qwenOmniV1: return QwenRealtimeAdapter(voice: model.voice)
        case .qwenAudioV1: return QwenAudioRealtimeAdapter(voice: model.voice)
        case .doubaoDuplexV3: return DoubaoRealtimeAdapter(model: model.model, voice: model.voice)
        case .geminiLiveV1: throw RealtimeAdapterError.unsupportedOperation(String(localized: "Gemini through a JSON-event adapter"))
        }
    }
}
