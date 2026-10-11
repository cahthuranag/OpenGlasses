import Foundation

/// A saved protocol version is independent of a provider's changing model aliases.
enum RealtimeProtocolProfile: String, Codable, CaseIterable, Identifiable {
    case openAIBetaV1 = "openai.beta.v1"
    case geminiLiveV1 = "gemini.live.v1"
    case qwenOmniV1 = "qwen.omni.v1"
    case qwenAudioV1 = "qwen.audio.v1"
    case doubaoDuplexV3 = "doubao.duplex.json.v3"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAIBetaV1: return String(localized: "OpenAI Realtime")
        case .geminiLiveV1: return String(localized: "Gemini Live")
        case .qwenOmniV1: return String(localized: "Qwen Omni")
        case .qwenAudioV1: return String(localized: "Qwen Audio")
        case .doubaoDuplexV3: return String(localized: "Doubao full duplex 3.0")
        }
    }
    var capabilities: RealtimeCapabilities {
        switch self {
        case .openAIBetaV1: return .init(vision: true, contextUpdate: true, textTurn: true, suppliedSpeech: false, truncation: true, resumption: false)
        case .geminiLiveV1: return .init(vision: true, contextUpdate: true, textTurn: true, suppliedSpeech: false, truncation: false, resumption: true)
        case .qwenOmniV1: return .init(vision: true, contextUpdate: true, textTurn: false, suppliedSpeech: false, truncation: false, resumption: false)
        case .qwenAudioV1: return .init(vision: false, contextUpdate: true, textTurn: true, suppliedSpeech: false, truncation: false, resumption: false)
        case .doubaoDuplexV3: return .init(vision: false, contextUpdate: true, textTurn: false, suppliedSpeech: true, truncation: false, resumption: false)
        }
    }
    var mediaPolicy: RealtimeMediaPolicy {
        switch self {
        case .qwenOmniV1:
            return .init(imageRequiresAudio: true, imageMaxBase64Bytes: 256 * 1024,
                         imageMaxDimension: 720, imageMaxJPEGBytes: 190_000,
                         backgroundImageInterval: 1, usesVoiceSetting: true)
        case .doubaoDuplexV3:
            return .init(audioPacketBytes: 640, audioPacketInterval: 0.02,
                         closeGracePeriod: 0.5, usesVoiceSetting: true)
        case .qwenAudioV1: return .init(usesVoiceSetting: true)
        case .openAIBetaV1, .geminiLiveV1: return .init()
        }
    }
    var inputSampleRate: Double {
        switch self {
        case .openAIBetaV1: return 24000
        case .geminiLiveV1, .qwenOmniV1, .qwenAudioV1, .doubaoDuplexV3: return 16000
        }
    }
    var audioConfiguration: RealtimeAudioEngineConfig {
        let gemini = self == .geminiLiveV1
        return .init(owner: gemini ? .geminiLive : .openAIRealtime,
                     logPrefix: "[Realtime Audio]", lifecycleQueueLabel: "realtime.audio.lifecycle",
                     accumulatorQueueLabel: "realtime.audio.accumulator", inputSampleRate: inputSampleRate,
                     outputSampleRate: 24000, channels: 1, bitsPerSample: 16,
                     vad: gemini ? nil : .init(amplitudeThreshold: 0.05, requiredHighFrames: 3))
    }
}

/// Media limits and pacing travel with the protocol version, never with SwiftUI or the engine.
struct RealtimeMediaPolicy {
    var audioPacketBytes: Int? = nil
    var audioPacketInterval: TimeInterval = 0
    var closeGracePeriod: TimeInterval = 0
    var imageRequiresAudio = false
    var imageMaxBase64Bytes: Int? = nil
    var imageMaxDimension: Double? = nil
    var imageMaxJPEGBytes: Int? = nil
    var backgroundImageInterval: TimeInterval = 0
    var usesVoiceSetting = false
}

struct RealtimeCapabilities: Equatable {
    let vision: Bool
    let contextUpdate: Bool
    let textTurn: Bool
    let suppliedSpeech: Bool
    // Compatibility for existing consumers: a text turn requests model generation.
    var textInjection: Bool { textTurn }
    let truncation: Bool
    let resumption: Bool
}

struct RealtimeProviderTemplate: Identifiable {
    let id: String
    let name: String
    let profile: RealtimeProtocolProfile
    let endpoint: String
    let model: String
    let voice: String
    let help: String
    func modelConfiguration() -> RealtimeModelConfig {
        .init(id: UUID().uuidString, name: name, providerID: id, profileID: profile.rawValue,
              endpoint: endpoint, apiKey: "", model: model, voice: voice)
    }
}

/// Both editors read this catalog. Templates contain defaults, never credentials.
enum RealtimeProviderCatalog {
    static let templates: [RealtimeProviderTemplate] = [
        .init(id: "openai", name: "OpenAI", profile: .openAIBetaV1,
              endpoint: RealtimeConnectionConfiguration.openAIEndpoint, model: "gpt-realtime", voice: "",
              help: String(localized: "Use an OpenAI API key. Realtime is separate from a ChatGPT subscription.")),
        .init(id: "gemini", name: "Gemini", profile: .geminiLiveV1,
              endpoint: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent",
              model: GeminiLiveModelPolicy.offlineFallbackModel, voice: "",
              help: String(localized: "Use a Gemini API key and a model enabled for Live audio on your account.")),
        .init(id: "qwen", name: "Qwen (China API)", profile: .qwenOmniV1,
              endpoint: "wss://{workspace}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime",
              model: "qwen3.8-omni-flash-realtime", voice: "Tina",
              help: String(localized: "Replace {workspace} with your Model Studio workspace ID. Use its Beijing API key. Images are limited to one per second. App context updates are supported; text turns are unavailable.")),
        .init(id: "qwen-audio", name: "Qwen Audio (China API)", profile: .qwenAudioV1,
              endpoint: "wss://{workspace}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime",
              model: "qwen-audio-3.1-realtime-plus", voice: "longanqian_v3.1",
              help: String(localized: "Replace {workspace} with your Model Studio workspace ID and use its Beijing key. Supports voice, tools and text turns; images are unavailable.")),
        .init(id: "doubao", name: "Doubao", profile: .doubaoDuplexV3,
              endpoint: "wss://openspeech.bytedance.com/api/v3/duplex/realtime/dialogue",
              model: "1.2.6.1", voice: "zh_female_vv_jupiter_bigtts",
              help: String(localized: "Use a Speech Console API key, separate from an Ark chat key. Full duplex 3.0 uses model version 1.2.6.1. Supports audio, tools, app context updates and speaking supplied text. Images and model-generated text turns are unavailable.")),
        .init(id: "compatible", name: "Custom / compatible", profile: .openAIBetaV1,
              endpoint: "", model: "", voice: "",
              help: String(localized: "Choose the protocol your server implements and enter the full WebSocket URL. Public endpoints require wss://."))
    ]
    static func template(_ id: String) -> RealtimeProviderTemplate? { templates.first { $0.id == id } }
    static func profiles(for providerID: String) -> [RealtimeProtocolProfile] {
        if providerID == "compatible" { return RealtimeProtocolProfile.allCases }
        if providerID == "qwen-audio" { return [.qwenAudioV1] }
        if providerID == "qwen" { return [.qwenOmniV1] }
        return RealtimeProtocolProfile.allCases.filter { $0.rawValue.hasPrefix(providerID + ".") }
    }

    struct ChatTemplate: Identifiable {
        let id: String
        let name: String
        let endpoint: String
        let model: String
        let vision: Bool
    }
    static let chatTemplates: [ChatTemplate] = [
        .init(id: "qwen", name: "Qwen (China API)",
              endpoint: "https://{workspace}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions",
              model: "qwen3.8-max", vision: true),
        .init(id: "doubao", name: "Doubao (Ark API)",
              endpoint: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
              model: "doubao-seed-2-1-pro-260628", vision: true)
    ]
}

struct RealtimeModelConfig: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var providerID: String
    var profileID: String
    var endpoint: String
    var apiKey: String
    var model: String
    var voice: String
    var profile: RealtimeProtocolProfile? { .init(rawValue: profileID) }
    var capabilities: RealtimeCapabilities? { profile?.capabilities }
    enum ConfigurationError: LocalizedError {
        case unknownProtocol, workspaceRequired, voiceRequired, unsupportedModel
        var errorDescription: String? {
            switch self {
            case .unknownProtocol: return String(localized: "This saved realtime protocol version is unsupported. Choose a supported protocol in the model editor.")
            case .workspaceRequired: return String(localized: "Replace {workspace} in the endpoint with your Model Studio workspace ID.")
            case .voiceRequired: return String(localized: "Enter a voice supported by this speech service.")
            case .unsupportedModel: return String(localized: "Doubao full duplex 3.0 requires model version 1.2.6.1.")
            }
        }
    }
    var route: NetworkRoute {
        profile == .geminiLiveV1 && providerID == "gemini" ? .geminiLiveSession
            : (providerID == "openai" ? .openAIRealtimeSession : .openAICompatibleRealtimeSession)
    }
    func request(build: EndpointPolicy.BuildFlavor = .current) throws -> URLRequest {
        guard let profile else { throw ConfigurationError.unknownProtocol }
        guard !endpoint.contains("{workspace}") else { throw ConfigurationError.workspaceRequired }
        if profile == .doubaoDuplexV3 {
            guard model == "1.2.6.1" else { throw ConfigurationError.unsupportedModel }
            guard !voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationError.voiceRequired }
        }
        // Reuse the central endpoint checks and sanitized validation errors before attaching secrets.
        var request = try RealtimeConnectionConfiguration(endpoint: endpoint, apiKey: apiKey, model: model,
                                                          isCustom: providerID != "openai").request(build: build)
        if case .failure = EndpointPolicy.validate(url: request.url!, for: route, build: build) {
            throw RealtimeConnectionConfiguration.ValidationError.invalidEndpoint
        }
        if profile == .geminiLiveV1 || profile == .doubaoDuplexV3 {
            var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            var query = (components.percentEncodedQueryItems ?? []).filter {
                !["model", "key"].contains($0.name.removingPercentEncoding ?? $0.name)
            }
            if profile == .geminiLiveV1 {
                let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
                query.append(.init(name: "key", value: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: allowed)))
            }
            components.percentEncodedQueryItems = query.isEmpty ? nil : query
            request.url = components.url
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            request.setValue(nil, forHTTPHeaderField: "OpenAI-Beta")
            if profile == .doubaoDuplexV3 { request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-Api-Key") }
        }
        return request
    }
    var isConfigured: Bool { (try? request()) != nil }
}

extension Config {
    static var savedRealtimeModels: [RealtimeModelConfig] {
        guard let data = KeychainService.data(for: "savedRealtimeModels"),
              let models = try? JSONDecoder().decode([RealtimeModelConfig].self, from: data) else { return [] }
        return models
    }
    @discardableResult static func setSavedRealtimeModels(_ models: [RealtimeModelConfig]) -> Bool {
        guard let data = try? JSONEncoder().encode(models) else { return false }
        return KeychainService.setData(data, for: "savedRealtimeModels")
    }
    static var activeRealtimeModelID: String { UserDefaults.standard.string(forKey: "activeRealtimeModelID") ?? "" }
    static func setActiveRealtimeModelID(_ id: String) { UserDefaults.standard.set(id, forKey: "activeRealtimeModelID") }
    static var activeRealtimeModel: RealtimeModelConfig? {
        savedRealtimeModels.first { $0.id == activeRealtimeModelID } ?? savedRealtimeModels.first
    }
    /// Legacy entry points remain explicit. A text model's credentials are used only by its
    /// existing OpenAI/Gemini shortcut, never by a newly saved live model.
    static func realtimeModel(for mode: AppMode) -> RealtimeModelConfig? {
        switch mode {
        case .direct: return nil
        case .geminiLive:
            guard let source = geminiLiveModelConfig else { return nil }
            let template = RealtimeProviderCatalog.template("gemini")!
            return .init(id: "legacy-gemini", name: "Gemini Live", providerID: "gemini", profileID: template.profile.rawValue,
                         endpoint: template.endpoint, apiKey: source.apiKey,
                         model: source.model, voice: "")
        case .openaiRealtime:
            guard let source = openAIRealtimeModelConfig else { return nil }
            return .init(id: "legacy-openai", name: source.name, providerID: "openai", profileID: RealtimeProtocolProfile.openAIBetaV1.rawValue,
                         endpoint: RealtimeConnectionConfiguration.openAIEndpoint, apiKey: source.apiKey, model: source.model, voice: "")
        case .openaiCompatibleRealtime:
            if let activeRealtimeModel { return activeRealtimeModel }
            let legacy = compatibleRealtimeConfiguration
            guard legacy.isConfigured else { return nil }
            return .init(id: "legacy-compatible", name: "Compatible Realtime", providerID: "compatible", profileID: RealtimeProtocolProfile.openAIBetaV1.rawValue,
                         endpoint: legacy.endpoint, apiKey: legacy.apiKey, model: legacy.model, voice: "")
        }
    }
    /// Copy the old independent live endpoint once; leave it intact if Keychain rejects the write.
    @discardableResult static func migrateRealtimeModelsIfNeeded() -> Bool {
        guard !UserDefaults.standard.bool(forKey: "realtimeModelsMigrated_v1") else { return true }
        var models = savedRealtimeModels
        let legacy = compatibleRealtimeConfiguration
        if legacy.isConfigured, !models.contains(where: { $0.id == "legacy-compatible" }) {
            models.append(.init(id: "legacy-compatible", name: "Compatible Realtime", providerID: "compatible",
                                profileID: RealtimeProtocolProfile.openAIBetaV1.rawValue, endpoint: legacy.endpoint,
                                apiKey: legacy.apiKey, model: legacy.model, voice: ""))
        }
        for mode in [AppMode.geminiLive, .openaiRealtime] {
            if let legacyModel = realtimeModel(for: mode), !legacyModel.apiKey.isEmpty,
               !models.contains(where: { $0.id == legacyModel.id }) { models.append(legacyModel) }
        }
        guard setSavedRealtimeModels(models) else { return false }
        UserDefaults.standard.set(true, forKey: "realtimeModelsMigrated_v1")
        return true
    }
}
