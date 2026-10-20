import Foundation

/// The OpenAI and xAI speech requests, built as values (Plan ID item 5). `TextToSpeechService` sends
/// them; building them here keeps the request shape — the address, the bearer, the body — testable
/// without a network and without the audio session.
///
/// The credential travels only in the `Authorization` header, never in the URL, and each request
/// goes to the vendor's own fixed address: a custom base URL saved on an LLM model is never
/// followed, because a voice request is not a chat request and the key must not be sent to a
/// server it was not issued by.
enum CloudVoiceRequests {

    // MARK: OpenAI

    static let openAISpeechURL = URL(string: "https://api.openai.com/v1/audio/speech")!
    /// A fixed model: the small speech model is the one priced for spoken replies.
    static let openAISpeechModel = "gpt-4o-mini-tts"
    /// OpenAI publishes no voice list endpoint, so the picker offers its fixed set.
    static let openAIVoices = ["alloy", "ash", "ballad", "cedar", "coral", "echo", "fable",
                               "marin", "nova", "onyx", "sage", "shimmer", "verse"]
    static let defaultOpenAIVoice = "coral"

    /// POST the reply text to OpenAI's speech endpoint for MP3 audio, which `AVAudioPlayer` plays
    /// as it plays ElevenLabs's.
    static func openAISpeech(text: String, apiKey: String, voice: String) throws -> URLRequest {
        var request = URLRequest(url: openAISpeechURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "model": openAISpeechModel,
            "input": text,
            "voice": openAIVoices.contains(voice) ? voice : defaultOpenAIVoice,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: xAI

    static let xaiSpeechURL = URL(string: "https://api.x.ai/v1/tts")!
    static let xaiVoiceCatalogURL = URL(string: "https://api.x.ai/v1/tts/voices")!
    static let defaultXAIVoice = "ara"

    /// POST the reply text to xAI's speech endpoint for MP3 audio. The language is left to the
    /// endpoint, as a reply can be in any language the wearer speaks.
    static func xaiSpeech(text: String, credential: String, voice: String) throws -> URLRequest {
        var request = URLRequest(url: xaiSpeechURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        let trimmed = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "text": text,
            "voice_id": trimmed.isEmpty ? defaultXAIVoice : trimmed,
            "language": "auto",
            "output_format": ["codec": "mp3"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// GET the voices the xAI credential may use, for the picker.
    static func xaiVoiceCatalog(credential: String) -> URLRequest {
        var request = URLRequest(url: xaiVoiceCatalogURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// A voice from xAI's catalog.
    struct XAIVoice: Identifiable, Hashable, Decodable {
        let voiceId: String
        let name: String?
        let gender: String?

        var id: String { voiceId }

        /// The picker's label: the name, with the gender when the catalog gives one.
        var label: String {
            let shown = (name?.isEmpty == false ? name : nil) ?? voiceId
            guard let gender, !gender.isEmpty else { return shown }
            return "\(shown) — \(gender)"
        }

        enum CodingKeys: String, CodingKey {
            case voiceId = "voice_id"
            case name
            case gender
        }
    }

    private struct XAIVoicesResponse: Decodable {
        let voices: [XAIVoice]
    }

    /// The catalog's voices, without any entry missing an id.
    static func parseXAIVoices(_ data: Data) throws -> [XAIVoice] {
        try JSONDecoder().decode(XAIVoicesResponse.self, from: data).voices
            .filter { !$0.voiceId.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// Which saved credential each of the new cloud voices may use (Plan ID item 5). Pure over the
/// saved models, apart from asking the xAI sign-in for a token.
enum CloudVoiceCredentials {

    /// The OpenAI API key for the speech endpoint: the first saved OpenAI model whose address is
    /// OpenAI's own and that carries a key, else the legacy single-provider key.
    ///
    /// A ChatGPT sign-in never counts. It is a different provider here (`.chatgpt`), and the speech
    /// endpoint refuses a subscription token anyway: the voice is paid from API credit. A key saved
    /// on an OpenAI model pointed at another server belongs to that server and is never sent to
    /// OpenAI.
    static func openAIKey(savedModels: [ModelConfig], legacyKey: String) -> String {
        for model in savedModels where model.llmProvider == .openai && isHost(model.baseURL, "api.openai.com") {
            let key = model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        return legacyKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The key on the first saved xAI model that carries one, or empty.
    static func xaiModelKey(savedModels: [ModelConfig]) -> String {
        for model in savedModels where model.llmProvider == .xai && isHost(model.baseURL, "x.ai") {
            let key = model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        return ""
    }

    /// Where the xAI voice's credential comes from: a typed key wins, else the connected account.
    enum XAISource: Equatable {
        case modelKey
        case account
        case none
    }

    static func xaiSource(savedModels: [ModelConfig], accountConnected: Bool) -> XAISource {
        if !xaiModelKey(savedModels: savedModels).isEmpty { return .modelKey }
        return accountConnected ? .account : .none
    }

    /// The bearer for an xAI voice request: the saved key, else the account's (refreshed) token,
    /// else empty — the same order `XAIAuth` gives the chat route.
    @MainActor
    static func resolveXAICredential(savedModels: [ModelConfig], account: XAIOAuthService) async -> String {
        await XAIAuth.resolveCredential(apiKey: xaiModelKey(savedModels: savedModels), account: account)
    }

    /// Whether a saved base URL is the vendor's own host (or a subdomain of it). An empty base URL
    /// means the provider default, which is.
    static func isHost(_ baseURL: String, _ vendorHost: String) -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == vendorHost || host.hasSuffix("." + vendorHost)
    }
}
