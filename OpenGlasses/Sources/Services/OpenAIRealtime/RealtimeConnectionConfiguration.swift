import Foundation

/// Immutable connection parameters. A live session keeps this value through every reconnect.
struct RealtimeConnectionConfiguration: Codable, Equatable {
    static let openAIEndpoint = "wss://api.openai.com/v1/realtime"

    var endpoint: String
    var apiKey: String
    var model: String
    var isCustom: Bool = true

    enum ValidationError: LocalizedError {
        case invalidEndpoint
        case insecureEndpoint
        case missingModel
        case missingAPIKey

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return String(localized: "Enter a full ws:// or wss:// Realtime endpoint with a host and no URL credentials or fragment.")
            case .insecureEndpoint: return String(localized: "Use wss:// for a public Realtime server. Unencrypted ws:// is only supported on your local network.")
            case .missingModel: return String(localized: "Enter a Realtime model ID.")
            case .missingAPIKey: return String(localized: "Enter a Realtime API key.")
            }
        }
    }

    var route: NetworkRoute { isCustom ? .openAICompatibleRealtimeSession : .openAIRealtimeSession }

    /// Validate the endpoint before adding authentication. Errors never include the URL/key.
    func request(build: EndpointPolicy.BuildFlavor = .current) throws -> URLRequest {
        guard var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["ws", "wss"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              let endpointURL = components.url else { throw ValidationError.invalidEndpoint }
        // Do not surface EndpointPolicy's URL-bearing diagnostics: a gateway URL may carry a token.
        switch EndpointPolicy.validate(url: endpointURL, for: route, build: build) {
        case .success: break
        case .failure(.cleartextHTTPNotPermitted): throw ValidationError.insecureEndpoint
        case .failure:
            throw ValidationError.invalidEndpoint
        }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw ValidationError.missingModel }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ValidationError.missingAPIKey
        }
        // Keep gateway tokens byte-for-byte: decoding/re-encoding an existing %2B as a literal
        // '+' changes its meaning on servers that parse queries using form encoding.
        var query = (components.percentEncodedQueryItems ?? []).filter {
            $0.name.removingPercentEncoding != "model"
        }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            throw ValidationError.missingModel
        }
        query.append(URLQueryItem(name: "model", value: encodedModel))
        components.percentEncodedQueryItems = query
        guard let url = components.url else { throw ValidationError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if !isCustom { request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta") }
        return request
    }

    var isConfigured: Bool { (try? request()) != nil }
}

extension Config {
    /// URLs can contain gateway tokens, so the entire configuration belongs in Keychain.
    static var compatibleRealtimeConfiguration: RealtimeConnectionConfiguration {
        guard let data = KeychainService.data(for: "compatibleRealtimeConfiguration"),
              var configuration = try? JSONDecoder().decode(RealtimeConnectionConfiguration.self, from: data) else {
            return RealtimeConnectionConfiguration(endpoint: "", apiKey: "", model: "")
        }
        configuration.isCustom = true
        return configuration
    }

    @discardableResult
    static func setCompatibleRealtimeConfiguration(_ configuration: RealtimeConnectionConfiguration) -> Bool {
        var custom = configuration
        custom.isCustom = true
        guard let data = try? JSONEncoder().encode(custom) else { return false }
        return KeychainService.setData(data, for: "compatibleRealtimeConfiguration")
    }

    static func realtimeConnectionConfiguration(for mode: AppMode) -> RealtimeConnectionConfiguration? {
        switch mode {
        case .openaiCompatibleRealtime: return compatibleRealtimeConfiguration
        case .openaiRealtime:
            guard let config = openAIRealtimeModelConfig else { return nil }
            return RealtimeConnectionConfiguration(endpoint: RealtimeConnectionConfiguration.openAIEndpoint,
                                                   apiKey: config.apiKey, model: config.model, isCustom: false)
        case .direct, .geminiLive: return nil
        }
    }
}
