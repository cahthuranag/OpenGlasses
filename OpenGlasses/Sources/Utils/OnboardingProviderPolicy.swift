import Foundation

/// First-run provider choices that are not plain `LLMProvider`s: the OpenAI-compatible chat
/// templates (Model Studio, Ark, SiliconFlow). Pure, so the view only lays out what this decides.
enum OnboardingProviderPolicy {
    /// List the providers that answer without a VPN in mainland China first: a Chinese-language
    /// phone, or one set to the mainland region. Elsewhere the usual order stands.
    static func prefersChinaReachableProviders(preferredLanguages: [String], regionCode: String?) -> Bool {
        if regionCode?.uppercased() == "CN" { return true }
        guard let first = preferredLanguages.first?.lowercased() else { return false }
        return first == "zh" || first.hasPrefix("zh-") || first.hasPrefix("zh_")
    }

    static var prefersChinaReachableProvidersOnThisDevice: Bool {
        prefersChinaReachableProviders(preferredLanguages: Locale.preferredLanguages,
                                       regionCode: Locale.current.region?.identifier)
    }

    /// Whether a template's endpoint needs a Model Studio workspace ID filled in.
    static func needsWorkspace(_ template: RealtimeProviderCatalog.ChatTemplate) -> Bool {
        template.endpoint.contains("{workspace}")
    }

    /// A workspace ID as typed, or nil when it can't be a host label. Model Studio shows IDs
    /// such as `llm-abc123`; anything with dots, slashes or spaces would change the host.
    static func normalizedWorkspaceID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 63,
              !trimmed.hasPrefix("-"), !trimmed.hasSuffix("-"),
              trimmed.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) })
        else { return nil }
        return trimmed
    }

    /// The endpoint to save for `template` in `region`, or nil while a needed workspace ID is
    /// missing or malformed. Templates without a workspace ignore both.
    static func endpoint(for template: RealtimeProviderCatalog.ChatTemplate, region: ModelStudioRegion,
                         workspaceID: String) -> String? {
        guard needsWorkspace(template) else { return template.endpoint }
        guard let workspace = normalizedWorkspaceID(workspaceID) else { return nil }
        return ModelStudioRegion.endpoint(template.endpoint, in: region)
            .replacingOccurrences(of: "{workspace}", with: workspace)
    }

    /// The key page the model editor links to: a chat template's own service (a Model Studio
    /// template follows the region in its endpoint), else the provider's console.
    static func keyPageURL(provider: LLMProvider, templateID: String?, baseURL: String) -> URL? {
        if let template = RealtimeProviderCatalog.chatTemplates.first(where: { $0.id == templateID }) {
            let region = ModelStudioRegion.region(of: baseURL) ?? .beijing
            return keyPage(for: template, region: region).flatMap { URL(string: $0.url) }
        }
        return provider.consoleURL
    }

    /// Where to create a key for `template`. Model Studio keys belong to one region, so the link
    /// follows the region chosen.
    static func keyPage(for template: RealtimeProviderCatalog.ChatTemplate, region: ModelStudioRegion) -> (url: String, host: String)? {
        switch template.id {
        case "qwen":
            return region == .beijing
                ? ("https://bailian.console.aliyun.com/", "bailian.console.aliyun.com")
                : ("https://modelstudio.console.alibabacloud.com/", "modelstudio.console.alibabacloud.com")
        case "doubao": return ("https://console.volcengine.com/ark", "console.volcengine.com/ark")
        case "siliconflow": return ("https://cloud.siliconflow.cn/", "cloud.siliconflow.cn")
        default: return nil
        }
    }
}
