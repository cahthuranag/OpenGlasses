import XCTest
@testable import OpenGlasses

/// Model Studio's Beijing and Singapore regions: the endpoint moves with the region, and a
/// workspace URL or key entered for one region never travels to the other.
final class ModelStudioRegionTests: XCTestCase {
    private let realtimeBeijing = "wss://{workspace}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime"
    private let chatBeijing = "https://{workspace}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions"

    func testEveryQwenTemplateIsAModelStudioBeijingEndpoint() throws {
        for id in ["qwen", "qwen-audio"] {
            let template = try XCTUnwrap(RealtimeProviderCatalog.template(id))
            XCTAssertEqual(ModelStudioRegion.region(of: template.endpoint), .beijing, id)
        }
        let chat = try XCTUnwrap(RealtimeProviderCatalog.chatTemplates.first { $0.id == "qwen" })
        XCTAssertEqual(ModelStudioRegion.region(of: chat.endpoint), .beijing)
    }

    func testSingaporeEndpointsUseTheRegionalWorkspaceHost() {
        XCTAssertEqual(ModelStudioRegion.endpoint(realtimeBeijing, in: .singapore),
                       "wss://{workspace}.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/realtime")
        XCTAssertEqual(ModelStudioRegion.endpoint(chatBeijing, in: .singapore),
                       "https://{workspace}.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions")
        XCTAssertEqual(ModelStudioRegion.endpoint(realtimeBeijing, in: .beijing), realtimeBeijing)
    }

    func testRegionIsReadFromTheHostOnly() {
        XCTAssertEqual(ModelStudioRegion.region(of: "wss://ws-123.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/realtime?model=m"), .singapore)
        XCTAssertEqual(ModelStudioRegion.region(of: "https://WS-123.CN-BEIJING.MAAS.ALIYUNCS.COM:443/compatible-mode/v1"), .beijing)
        XCTAssertNil(ModelStudioRegion.region(of: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"))
        XCTAssertNil(ModelStudioRegion.region(of: "https://proxy.example/x.cn-beijing.maas.aliyuncs.com/v1"))
        XCTAssertNil(ModelStudioRegion.region(of: "cn-beijing.maas.aliyuncs.com"))
        XCTAssertNil(ModelStudioRegion.region(of: ""))
    }

    func testOnlyBeijingTemplatesAreRewritten() {
        let custom = "wss://relay.example/realtime"
        XCTAssertEqual(ModelStudioRegion.endpoint(custom, in: .singapore), custom)
        let singapore = ModelStudioRegion.endpoint(realtimeBeijing, in: .singapore)
        XCTAssertEqual(ModelStudioRegion.endpoint(singapore, in: .beijing), singapore)
    }

    func testSwitchingRegionStartsWithNoKeyAndTheRegionsTemplate() {
        var drafts = ModelStudioRegionDrafts()
        let beijing = ModelStudioRegionDrafts.Draft(
            endpoint: "wss://ws-bj.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime", apiKey: "beijing-fixture-key")
        let singapore = drafts.switchRegion(from: .beijing, to: .singapore, current: beijing, templateEndpoint: realtimeBeijing)
        XCTAssertEqual(singapore.apiKey, "", "A Beijing key must never be offered to Singapore")
        XCTAssertEqual(singapore.endpoint, "wss://{workspace}.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/realtime")
    }

    func testSwitchingBackRestoresWhatWasEnteredForEachRegion() {
        var drafts = ModelStudioRegionDrafts()
        let beijing = ModelStudioRegionDrafts.Draft(
            endpoint: "wss://ws-bj.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime", apiKey: "beijing-fixture-key")
        var singapore = drafts.switchRegion(from: .beijing, to: .singapore, current: beijing, templateEndpoint: realtimeBeijing)
        singapore.endpoint = "wss://ws-sg.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/realtime"
        singapore.apiKey = "singapore-fixture-key"
        XCTAssertEqual(drafts.switchRegion(from: .singapore, to: .beijing, current: singapore, templateEndpoint: realtimeBeijing), beijing)
        XCTAssertEqual(drafts.switchRegion(from: .beijing, to: .singapore, current: beijing, templateEndpoint: realtimeBeijing), singapore)
    }

    func testSingaporeRealtimeModelBuildsAnAuthenticatedRequest() throws {
        var model = try XCTUnwrap(RealtimeProviderCatalog.template("qwen")).modelConfiguration()
        model.endpoint = ModelStudioRegion.endpoint(model.endpoint, in: .singapore)
            .replacingOccurrences(of: "{workspace}", with: "fixture-workspace")
        model.apiKey = "fixture-key"
        let request = try model.request(build: .release)
        XCTAssertEqual(request.url?.host, "fixture-workspace.ap-southeast-1.maas.aliyuncs.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
    }

    func testSingaporeWorkspaceStillNeedsItsID() throws {
        var model = try XCTUnwrap(RealtimeProviderCatalog.template("qwen-audio")).modelConfiguration()
        model.endpoint = ModelStudioRegion.endpoint(model.endpoint, in: .singapore)
        model.apiKey = "fixture-key"
        XCTAssertThrowsError(try model.request(build: .release))
    }

    func testBothRegionsCountAsAnAIProviderInTheNetworkLog() {
        XCTAssertEqual(NetworkCategory.categorize(host: "ws-1.cn-beijing.maas.aliyuncs.com"), .aiProvider)
        XCTAssertEqual(NetworkCategory.categorize(host: "ws-1.ap-southeast-1.maas.aliyuncs.com"), .aiProvider)
    }
}
