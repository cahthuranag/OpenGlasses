import Foundation

/// Qwen-Audio has text turns but no Omni image buffer. Keep its contract version separate.
final class QwenAudioRealtimeAdapter: OpenAIRealtimeAdapter {
    override var profile: RealtimeProtocolProfile { .qwenAudioV1 }
    private let voice: String
    private var configured = false
    init(voice: String) { self.voice = voice.isEmpty ? "longanqian_v3.1" : voice }
    override func reset() { super.reset(); configured = false }
    override func encode(_ command: RealtimeCommand) throws -> [[String: Any]] {
        switch command {
        case .configure(let instructions, let tools):
            var session: [String: Any] = ["instructions": instructions,
                "tools": tools.map { tool -> [String: Any] in
                    var function = tool; function.removeValue(forKey: "type")
                    return ["type": "function", "function": function]
                }]
            if !configured {
                session["modalities"] = ["audio", "text"]
                session["voice"] = voice
                session["input_audio_format"] = "pcm"
                session["output_audio_format"] = "pcm"
                session["turn_detection"] = ["type": "server_vad", "threshold": 0.5, "silence_duration_ms": 800]
                configured = true
            }
            return [["type": "session.update", "session": session]]
        case .image: throw RealtimeAdapterError.unsupportedOperation(String(localized: "images"))
        case .interrupt: return [["type": "response.cancel"]]
        default: return try super.encode(command)
        }
    }
}
