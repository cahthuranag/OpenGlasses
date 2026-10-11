import Foundation

/// OpenAI's beta contract. Compatible endpoints explicitly opt into this version.
class OpenAIRealtimeAdapter: RealtimeProtocolAdapter {
    var profile: RealtimeProtocolProfile { .openAIBetaV1 }
    var createsSessionOnOpen: Bool { false }
    private var names: [String: String] = [:]
    private var deliveredCalls: Set<String> = []
    func reset() { names.removeAll(); deliveredCalls.removeAll() }

    func encode(_ command: RealtimeCommand) throws -> [[String: Any]] {
        switch command {
        case .configure(let instructions, let tools): return [Self.sessionUpdate(instructions: instructions, tools: tools)]
        case .updateContext(let instructions): return [["type": "session.update", "session": ["instructions": instructions]]]
        case .speakText: throw RealtimeAdapterError.unsupportedOperation(String(localized: "speaking supplied text"))
        case .audio(let data): return [["type": "input_audio_buffer.append", "audio": data.base64EncodedString()]]
        case .image(let data, let prompt): return [LiveInjectionEnvelope.realtimeImage(base64JPEG: data.base64EncodedString(), prompt: prompt)]
        case .text(let text, let complete):
            return [LiveInjectionEnvelope.realtimeText(text)] + (complete ? [LiveInjectionEnvelope.realtimeResponseCreate()] : [])
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
        case "session.created": return [.configureRequested]
        case "session.updated": return [.ready]
        case "response.audio.delta":
            guard let delta = json["delta"] as? String, let data = Data(base64Encoded: delta) else { return [] }
            return [.audio(data, itemID: json["item_id"] as? String, contentIndex: json["content_index"] as? Int ?? 0)]
        case "response.audio_transcript.delta": return (json["delta"] as? String).map { [.outputTranscript($0)] } ?? []
        case "response.done":
            var events: [RealtimeEvent] = [.turnComplete]
            if let usage = RealtimeUsage.openAIResponseUsage(json) { events.append(.usage(tokensIn: usage.tokensIn, tokensOut: usage.tokensOut)) }
            return events
        case "input_audio_buffer.speech_started": return [.userSpeaking(true)]
        case "input_audio_buffer.speech_stopped": return [.userSpeaking(false)]
        case "conversation.item.input_audio_transcription.completed":
            return (json["transcript"] as? String).map { [.inputTranscript($0, complete: true)] } ?? []
        case "response.output_item.added":
            if let item = json["item"] as? [String: Any], item["type"] as? String == "function_call",
               let id = item["call_id"] as? String, let name = item["name"] as? String { names[id] = name }
            return []
        case "response.function_call_arguments.done": return completedCall(json)
        case "response.output_item.done":
            guard let item = json["item"] as? [String: Any], item["type"] as? String == "function_call" else { return [] }
            return completedCall(item)
        case "error":
            let error = json["error"] as? [String: Any] ?? json
            let code = error["code"] as? String
            let message = error["message"] as? String
            // Cancelling an already-ended reply is harmless. Authentication/configuration errors
            // cannot be repaired by repeatedly reconnecting with the same snapshot.
            guard RealtimeReconnect.isFatalOpenAIError(code: code, message: message) else { return [] }
            let terminal = ["invalid_api_key", "invalid_request_error", "model_not_found", "permission_denied", "invalid_value"].contains(code ?? "")
                || error["type"] as? String == "invalid_request_error"
            if terminal { return [.failure(message: String(localized: "Realtime authentication or configuration was rejected. Check the saved model settings."), retryable: false)] }
            if RealtimeReconnect.isFatalOpenAIError(code: code, message: message) {
                return [.failure(message: String(localized: "The realtime service ended the connection."), retryable: true)]
            }
            return []
        default: return []
        }
    }
    private func completedCall(_ item: [String: Any]) -> [RealtimeEvent] {
        guard let id = item["call_id"] as? String, let name = item["name"] as? String ?? names[id],
              deliveredCalls.insert(id).inserted else { return [] }
        names.removeValue(forKey: id)
        return [.toolCalls([.init(callId: id, name: name, argumentsJSON: item["arguments"] as? String ?? "{}")])]
    }
}
