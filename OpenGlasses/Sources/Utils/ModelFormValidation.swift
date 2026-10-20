import Foundation

/// Shared credential rules for adding a model and fetching its available model IDs.
enum ModelFormValidation {
    static func credentialsReady(
        provider: LLMProvider, apiKey: String,
        claudeConnected: Bool, chatgptConnected: Bool, googleConnected: Bool,
        xaiConnected: Bool = false
    ) -> Bool {
        let hasKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch provider {
        case .local, .appleOnDevice, .custom:
            return true
        case .chatgpt:
            return chatgptConnected
        case .geminiVertex:
            return googleConnected
        case .anthropic:
            return hasKey || claudeConnected
        case .xai:
            // A key, or the xAI account sign-in, whose token the public API accepts as a bearer.
            return hasKey || xaiConnected
        case .openai, .gemini, .groq, .deepseek, .mistral, .zai, .qwen, .minimax, .openrouter:
            return hasKey
        }
    }

    static func canAdd(
        provider: LLMProvider, model: String, baseURL: String, apiKey: String,
        claudeConnected: Bool, chatgptConnected: Bool, googleConnected: Bool,
        xaiConnected: Bool = false
    ) -> Bool {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if provider.showBaseURL {
            guard let url = URL(string: baseURL),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host, !host.isEmpty else { return false }
        }
        return credentialsReady(
            provider: provider, apiKey: apiKey,
            claudeConnected: claudeConnected, chatgptConnected: chatgptConnected,
            googleConnected: googleConnected, xaiConnected: xaiConnected
        )
    }
}
