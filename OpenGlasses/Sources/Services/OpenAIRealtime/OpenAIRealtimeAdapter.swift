import Foundation

/// OpenAI's beta contract. OpenAI removed it on 2026-05-12; compatible endpoints that still speak it
/// opt into this version, and the Qwen adapters inherit it.
class OpenAIRealtimeAdapter: RealtimeProtocolAdapter {
    var profile: RealtimeProtocolProfile { .openAIBetaV1 }
    var createsSessionOnOpen: Bool { false }
    /// Set for a compatible model, where the editor offers the other OpenAI protocol.
    var offersProtocolChoice = false
    private var calls = OpenAIRealtimeCallTracker()
    func reset() { calls.reset() }

    func encode(_ command: RealtimeCommand) throws -> [[String: Any]] {
        switch command {
        case .configure(let instructions, let tools): return [Self.sessionUpdate(instructions: instructions, tools: tools)]
        case .updateContext(let instructions): return [["type": "session.update", "session": ["instructions": instructions]]]
        case .speakText: throw RealtimeAdapterError.unsupportedOperation(String(localized: "speaking supplied text"))
        case .audio(let data): return [["type": "input_audio_buffer.append", "audio": data.base64EncodedString()]]
        case .image(let data, let prompt): return [LiveInjectionEnvelope.realtimeImage(base64JPEG: data.base64EncodedString(), prompt: prompt)]
        case .text(let text, let complete, let toolsAllowed):
            return [LiveInjectionEnvelope.realtimeText(text)]
                + (complete ? [LiveInjectionEnvelope.realtimeResponseCreate(toolsAllowed: toolsAllowed)] : [])
        case .toolResult(let id, let output): return OpenAIRealtimeToolRouter.outputMessages(callId: id, output: output)
        case .interrupt(let id, let index, let milliseconds):
            var messages: [[String: Any]] = [["type": "response.cancel"]]
            if let id, milliseconds > 0 { messages.append(["type": "conversation.item.truncate", "item_id": id, "content_index": index, "audio_end_ms": milliseconds]) }
            return messages
        case .mute, .close: return []
        }
    }
    static func sessionUpdate(instructions: String, tools: [[String: Any]]) -> [String: Any] {
        var session: [String: Any] = [
            "modalities": ["text", "audio"], "instructions": instructions,
            "input_audio_format": "pcm16", "output_audio_format": "pcm16",
            "input_audio_transcription": ["model": "gpt-4o-mini-transcribe"],
            "turn_detection": ["type": "server_vad", "threshold": 0.5, "prefix_padding_ms": 300,
                               "silence_duration_ms": 500, "create_response": true, "interrupt_response": true]
        ]
        if !tools.isEmpty { session["tools"] = tools; session["tool_choice"] = "auto" }
        return ["type": "session.update", "session": session]
    }
    func decode(_ json: [String: Any]) -> [RealtimeEvent] {
        let type = json["type"] as? String ?? ""
        switch type {
        case "response.audio.delta": return OpenAIRealtimeEvents.audio(json)
        case "response.audio_transcript.delta": return OpenAIRealtimeEvents.transcript(json)
        case "error": return OpenAIRealtimeEvents.error(json, offersProtocolChoice: offersProtocolChoice)
        default: return OpenAIRealtimeEvents.shared(type, json, calls: &calls)
        }
    }
}

/// The current (GA) contract on `api.openai.com`. A sibling of the beta adapter, not a subclass, so
/// the Qwen adapters keep inheriting the beta shape unchanged.
final class OpenAIRealtimeGAAdapter: RealtimeProtocolAdapter {
    /// Live audio transcription for the wearer's side of the conversation.
    static let transcriptionModel = "gpt-live-transcribe"
    var profile: RealtimeProtocolProfile { .openAIRealtimeV1 }
    var createsSessionOnOpen: Bool { false }
    var offersProtocolChoice = false
    private var calls = OpenAIRealtimeCallTracker()
    func reset() { calls.reset() }

    func encode(_ command: RealtimeCommand) throws -> [[String: Any]] {
        switch command {
        case .configure(let instructions, let tools): return [Self.sessionUpdate(instructions: instructions, tools: tools)]
        case .updateContext(let instructions):
            return [["type": "session.update", "session": ["type": "realtime", "instructions": instructions]]]
        case .image(let data, let prompt):
            return [LiveInjectionEnvelope.realtimeImageDataURI(base64JPEG: data.base64EncodedString(), prompt: prompt)]
        case .speakText, .audio, .text, .toolResult, .interrupt, .mute, .close:
            // Unchanged between the beta and the current protocol.
            return try OpenAIRealtimeAdapter().encode(command)
        }
    }
    static func sessionUpdate(instructions: String, tools: [[String: Any]]) -> [String: Any] {
        let pcm: [String: Any] = ["type": "audio/pcm", "rate": 24000]
        var session: [String: Any] = [
            "type": "realtime", "output_modalities": ["audio"], "instructions": instructions,
            "audio": [
                "input": [
                    "format": pcm,
                    "transcription": ["model": transcriptionModel],
                    "turn_detection": ["type": "server_vad", "threshold": 0.5, "prefix_padding_ms": 300,
                                       "silence_duration_ms": 500, "create_response": true, "interrupt_response": true]
                ],
                "output": ["format": pcm]
            ]
        ]
        if !tools.isEmpty { session["tools"] = tools; session["tool_choice"] = "auto" }
        return ["type": "session.update", "session": session]
    }
    func decode(_ json: [String: Any]) -> [RealtimeEvent] {
        let type = json["type"] as? String ?? ""
        switch type {
        case "response.output_audio.delta": return OpenAIRealtimeEvents.audio(json)
        case "response.output_audio_transcript.delta": return OpenAIRealtimeEvents.transcript(json)
        case "error": return OpenAIRealtimeEvents.error(json, offersProtocolChoice: offersProtocolChoice)
        default: return OpenAIRealtimeEvents.shared(type, json, calls: &calls)
        }
    }
}

/// Function calls arrive twice (`function_call_arguments.done` and `output_item.done`); each is
/// delivered once.
struct OpenAIRealtimeCallTracker {
    private var names: [String: String] = [:]
    private var delivered: Set<String> = []
    mutating func reset() { names.removeAll(); delivered.removeAll() }
    mutating func noteAdded(_ item: [String: Any]) {
        if item["type"] as? String == "function_call", let id = item["call_id"] as? String,
           let name = item["name"] as? String { names[id] = name }
    }
    mutating func completed(_ item: [String: Any]) -> [RealtimeEvent] {
        guard let id = item["call_id"] as? String, let name = item["name"] as? String ?? names[id],
              delivered.insert(id).inserted else { return [] }
        names.removeValue(forKey: id)
        return [.toolCalls([.init(callId: id, name: name, argumentsJSON: item["arguments"] as? String ?? "{}")])]
    }
}

/// Server events whose shape both OpenAI protocols share.
enum OpenAIRealtimeEvents {
    static func audio(_ json: [String: Any]) -> [RealtimeEvent] {
        guard let delta = json["delta"] as? String, let data = Data(base64Encoded: delta) else { return [] }
        return [.audio(data, itemID: json["item_id"] as? String, contentIndex: json["content_index"] as? Int ?? 0)]
    }
    static func transcript(_ json: [String: Any]) -> [RealtimeEvent] {
        (json["delta"] as? String).map { [.outputTranscript($0)] } ?? []
    }
    static func shared(_ type: String, _ json: [String: Any], calls: inout OpenAIRealtimeCallTracker) -> [RealtimeEvent] {
        switch type {
        case "session.created": return [.configureRequested]
        case "session.updated": return [.ready]
        case "response.done":
            var events: [RealtimeEvent] = [.turnComplete]
            if let usage = RealtimeUsage.openAIResponseUsage(json) { events.append(.usage(tokensIn: usage.tokensIn, tokensOut: usage.tokensOut)) }
            return events
        case "input_audio_buffer.speech_started": return [.userSpeaking(true)]
        case "input_audio_buffer.speech_stopped": return [.userSpeaking(false)]
        case "conversation.item.input_audio_transcription.completed":
            return (json["transcript"] as? String).map { [.inputTranscript($0, complete: true)] } ?? []
        case "response.output_item.added":
            if let item = json["item"] as? [String: Any] { calls.noteAdded(item) }
            return []
        case "response.function_call_arguments.done": return calls.completed(json)
        case "response.output_item.done":
            guard let item = json["item"] as? [String: Any], item["type"] as? String == "function_call" else { return [] }
            return calls.completed(item)
        default: return []
        }
    }

    /// Why the server refused, in words the wearer can act on. The server's own message is read for
    /// classification only and never shown: it can echo part of a key or a gateway URL.
    enum Rejection: Equatable {
        case apiKey, model, protocolMismatch, configuration
    }
    static func rejection(code: String?, type: String?, message: String?) -> Rejection? {
        let code = code?.lowercased() ?? ""
        let message = message?.lowercased() ?? ""
        if code == "invalid_api_key" || type == "authentication_error" { return .apiKey }
        if code == "model_not_found"
            || (message.contains("model") && (message.contains("does not exist") || message.contains("not found")
                                              || message.contains("not supported") || message.contains("deprecated"))) {
            return .model
        }
        // Seen live on 2026-10-29: `beta_api_shape_disabled` for the beta header, and
        // `missing_required_parameter` naming `session.type` for a beta session without it.
        if ["beta_api_shape_disabled", "unknown_parameter"].contains(code)
            || (code == "missing_required_parameter" && message.contains("session.type"))
            || message.contains("unknown parameter") {
            return .protocolMismatch
        }
        let terminal = ["invalid_request_error", "permission_denied", "invalid_value"].contains(code)
            || type == "invalid_request_error"
        return terminal ? .configuration : nil
    }
    static func error(_ json: [String: Any], offersProtocolChoice: Bool) -> [RealtimeEvent] {
        let error = json["error"] as? [String: Any] ?? json
        let code = error["code"] as? String
        let message = error["message"] as? String
        // Cancelling an already-ended reply is harmless. Authentication/configuration errors
        // cannot be repaired by repeatedly reconnecting with the same snapshot.
        guard RealtimeReconnect.isFatalOpenAIError(code: code, message: message) else { return [] }
        switch rejection(code: code, type: error["type"] as? String, message: message) {
        case .apiKey:
            return [.failure(message: String(localized: "The realtime service did not accept this API key. Check the key in the model editor."), retryable: false)]
        case .model:
            return [.failure(message: String(localized: "The realtime service does not offer this model to this key. Choose another model in the model editor."), retryable: false)]
        case .protocolMismatch:
            let text = offersProtocolChoice
                ? String(localized: "This server does not accept the selected realtime protocol. Choose the other OpenAI Realtime protocol in the model editor.")
                : String(localized: "The realtime service did not accept this app's session settings.")
            return [.failure(message: text, retryable: false)]
        case .configuration:
            return [.failure(message: String(localized: "Realtime authentication or configuration was rejected. Check the saved model settings."), retryable: false)]
        case nil:
            return [.failure(message: String(localized: "The realtime service ended the connection."), retryable: true)]
        }
    }
}
