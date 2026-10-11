import Foundation

/// The app's top-level operating mode: wake-word direct mode or a realtime streaming session.
enum AppMode: String, CaseIterable {
    case direct = "direct"
    case geminiLive = "geminiLive"
    case openaiRealtime = "openaiRealtime"
    case openaiCompatibleRealtime = "openaiCompatibleRealtime"

    var displayName: String {
        switch self {
        case .direct: return String(localized: "Direct Mode")
        case .geminiLive: return String(localized: "Gemini Live")
        case .openaiRealtime: return String(localized: "OpenAI Realtime")
        case .openaiCompatibleRealtime: return String(localized: "Realtime")
        }
    }

    var description: String {
        switch self {
        case .direct: return String(localized: "Wake word, any LLM provider, text-to-speech")
        case .geminiLive: return String(localized: "Real-time audio/video streaming via Gemini")
        case .openaiRealtime: return String(localized: "Real-time audio/video streaming via OpenAI")
        case .openaiCompatibleRealtime: return String(localized: "Live voice with your selected realtime model")
        }
    }

    /// Whether this mode is a real-time streaming mode (as opposed to wake-word direct mode).
    var isRealtime: Bool {
        self == .geminiLive || usesOpenAIRealtimeTransport
    }

    var usesOpenAIRealtimeTransport: Bool {
        self == .openaiRealtime || self == .openaiCompatibleRealtime
    }
}
