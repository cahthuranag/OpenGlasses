import Foundation

/// Qwen Omni v1 has its own session schema, tool nesting and image buffer ordering.
final class QwenRealtimeAdapter: OpenAIRealtimeAdapter {
    override var profile: RealtimeProtocolProfile { .qwenOmniV1 }
    private let voice: String
    private var hasAudio = false
    private var configured = false
    init(voice: String) { self.voice = voice.isEmpty ? "Tina" : voice }
    override func reset() { super.reset(); hasAudio = false; configured = false }
    override func encode(_ command: RealtimeCommand) throws -> [[String: Any]] {
        switch command {
        case .configure(let instructions, let tools):
            if configured {
                return [["type": "session.update", "session": ["instructions": instructions, "tools": nestedTools(tools)]]]
            }
            var session: [String: Any] = [
                "modalities": ["text", "audio"], "instructions": instructions,
                "audio": ["input": ["format": ["type": "pcm", "sample_rate": 16000, "sample_format": "s16le", "channels": 1, "packing": "interleaved", "channel_layout": "mono"]],
                          "output": ["voice": voice, "format": ["type": "pcm", "sample_rate": 24000]]],
                "input_audio_transcription": ["model": "qwen3-asr-flash-realtime"],
                "turn_detection": ["type": "server_vad", "threshold": 0.5, "silence_duration_ms": 500]
            ]
            if !tools.isEmpty {
                session["tools"] = nestedTools(tools)
            }
            configured = true
            return [["type": "session.update", "session": session]]
        case .audio: hasAudio = true; return try super.encode(command)
        case .image(let data, _):
            guard hasAudio else { throw RealtimeAdapterError.imageBeforeAudio }
            let encoded = data.base64EncodedString()
            guard encoded.utf8.count <= 256 * 1024 else { throw RealtimeAdapterError.imageTooLarge }
            return [["type": "input_image_buffer.append", "image": encoded]]
        case .text: throw RealtimeAdapterError.unsupportedOperation(String(localized: "text injection"))
        case .interrupt: return [["type": "response.cancel"]]
        default: return try super.encode(command)
        }
    }
    private func nestedTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.map { tool in
            var function = tool; function.removeValue(forKey: "type")
            return ["type": "function", "function": function]
        }
    }
}
