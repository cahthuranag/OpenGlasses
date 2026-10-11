import Foundation

/// Legacy shortcut identity. Session coordination is shared by every realtime provider.
@MainActor
final class GeminiLiveSessionManager: RealtimeSessionManager {
    init() { super.init(legacyMode: .geminiLive) }
}
