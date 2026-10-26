import XCTest
@testable import OpenGlasses

/// First-run choices for Chinese-speaking and mainland users: which providers come first, and how
/// a chat template's endpoint is resolved before a key is checked or saved.
final class OnboardingProviderPolicyTests: XCTestCase {
    private func template(_ id: String) throws -> RealtimeProviderCatalog.ChatTemplate {
        try XCTUnwrap(RealtimeProviderCatalog.chatTemplates.first { $0.id == id })
    }

    func testChineseLanguageOrMainlandRegionListsChinaReachableProvidersFirst() {
        XCTAssertTrue(OnboardingProviderPolicy.prefersChinaReachableProviders(preferredLanguages: ["zh-Hans-CN"], regionCode: "CN"))
        XCTAssertTrue(OnboardingProviderPolicy.prefersChinaReachableProviders(preferredLanguages: ["zh-Hant-TW"], regionCode: "TW"))
        XCTAssertTrue(OnboardingProviderPolicy.prefersChinaReachableProviders(preferredLanguages: ["zh"], regionCode: nil))
        XCTAssertTrue(OnboardingProviderPolicy.prefersChinaReachableProviders(preferredLanguages: ["en-CN"], regionCode: "cn"))
    }

    func testOtherPhonesKeepTheUsualOrder() {
        XCTAssertFalse(OnboardingProviderPolicy.prefersChinaReachableProviders(preferredLanguages: ["en-NZ"], regionCode: "NZ"))
        XCTAssertFalse(OnboardingProviderPolicy.prefersChinaReachableProviders(preferredLanguages: ["en-US", "zh-Hans"], regionCode: "US"))
        XCTAssertFalse(OnboardingProviderPolicy.prefersChinaReachableProviders(preferredLanguages: [], regionCode: nil))
        XCTAssertFalse(OnboardingProviderPolicy.prefersChinaReachableProviders(preferredLanguages: ["zu-ZA"], regionCode: "ZA"))
    }

    func testWorkspaceIDsMustBeASingleHostLabel() {
        XCTAssertEqual(OnboardingProviderPolicy.normalizedWorkspaceID("  LLM-Abc123 \n"), "llm-abc123")
        for bad in ["", "   ", "ws.evil.example", "ws/1", "ws 1", "-ws", "ws-", "ws:443", "工作空间", String(repeating: "a", count: 64)] {
            XCTAssertNil(OnboardingProviderPolicy.normalizedWorkspaceID(bad), bad)
        }
    }

    func testQwenResolvesToTheChosenRegionsWorkspaceHost() throws {
        let qwen = try template("qwen")
        XCTAssertTrue(OnboardingProviderPolicy.needsWorkspace(qwen))
        XCTAssertEqual(OnboardingProviderPolicy.endpoint(for: qwen, region: .beijing, workspaceID: "llm-1"),
                       "https://llm-1.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions")
        XCTAssertEqual(OnboardingProviderPolicy.endpoint(for: qwen, region: .singapore, workspaceID: "llm-1"),
                       "https://llm-1.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions")
        XCTAssertNil(OnboardingProviderPolicy.endpoint(for: qwen, region: .singapore, workspaceID: ""))
        XCTAssertNil(OnboardingProviderPolicy.endpoint(for: qwen, region: .beijing, workspaceID: "a.b"))
    }

    func testTemplatesWithoutAWorkspaceIgnoreRegionAndWorkspace() throws {
        for id in ["doubao", "siliconflow"] {
            let chat = try template(id)
            XCTAssertFalse(OnboardingProviderPolicy.needsWorkspace(chat), id)
            XCTAssertEqual(OnboardingProviderPolicy.endpoint(for: chat, region: .singapore, workspaceID: ""), chat.endpoint, id)
        }
    }

    func testKeyLinksFollowTheModelStudioRegion() throws {
        let qwen = try template("qwen")
        XCTAssertEqual(OnboardingProviderPolicy.keyPage(for: qwen, region: .beijing)?.host, "bailian.console.aliyun.com")
        XCTAssertEqual(OnboardingProviderPolicy.keyPage(for: qwen, region: .singapore)?.host, "modelstudio.console.alibabacloud.com")
        for id in ["qwen", "doubao", "siliconflow"] {
            let chat = try template(id)
            for region in ModelStudioRegion.allCases {
                let page = try XCTUnwrap(OnboardingProviderPolicy.keyPage(for: chat, region: region), id)
                XCTAssertEqual(URL(string: page.url)?.scheme, "https", id)
                XCTAssertTrue(page.url.contains(page.host), id)
            }
        }
    }

    func testSiliconFlowIsAVisionChatTemplateOnItsChinaHost() throws {
        let siliconFlow = try template("siliconflow")
        XCTAssertEqual(URL(string: siliconFlow.endpoint)?.host, "api.siliconflow.cn")
        XCTAssertTrue(siliconFlow.endpoint.hasSuffix("/v1/chat/completions"))
        XCTAssertTrue(siliconFlow.vision)
        XCTAssertEqual(ModelFetcher.modelsEndpoint(from: siliconFlow.endpoint), "https://api.siliconflow.cn/v1/models")
        XCTAssertEqual(NetworkCategory.categorize(host: "api.siliconflow.cn"), .aiProvider)
        XCTAssertEqual(NetworkCategory.categorize(host: "ark.cn-beijing.volces.com"), .aiProvider)
    }

    func testEveryChatTemplateIdIsUnique() {
        let ids = RealtimeProviderCatalog.chatTemplates.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
