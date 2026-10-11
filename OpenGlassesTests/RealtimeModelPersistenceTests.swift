import XCTest
@testable import OpenGlasses

final class RealtimeModelPersistenceTests: XCTestCase {
    private var saved: [String: Data?] = [:]
    private var defaults: [String: Any] = [:]
    private let keys = ["savedRealtimeModels", "compatibleRealtimeConfiguration", "savedModelConfigs"]
    private let preferenceKeys = ["activeRealtimeModelID", "realtimeModelsMigrated_v1", "activeModelId"]
    override func setUp() {
        for key in keys { saved[key] = .some(KeychainService.data(for: key)); KeychainService.delete(key) }
        for key in preferenceKeys {
            defaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    override func tearDown() {
        for key in keys { KeychainService.setData(saved[key] ?? nil, for: key) }
        for key in preferenceKeys {
            if let value = defaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
    func testLiveModelsStayInKeychainAndRetainExplicitProtocolVersion() {
        var qwen = RealtimeProviderCatalog.template("qwen")!.modelConfiguration()
        qwen.apiKey = "fixture-key"
        XCTAssertTrue(Config.setSavedRealtimeModels([qwen]))
        XCTAssertEqual(Config.savedRealtimeModels, [qwen])
        XCTAssertNil(UserDefaults.standard.object(forKey: "savedRealtimeModels"))
        XCTAssertEqual(Config.savedRealtimeModels.first?.profileID, "qwen.omni.v1")
        XCTAssertTrue(Config.knownSecretValues.contains("fixture-key"))
    }
    func testUnknownSavedProfileIsPreservedButCannotConnect() throws {
        var model = RealtimeProviderCatalog.template("doubao")!.modelConfiguration()
        model.profileID = "doubao.future.v4"
        XCTAssertTrue(Config.setSavedRealtimeModels([model]))
        let restored = try XCTUnwrap(Config.savedRealtimeModels.first)
        XCTAssertEqual(restored.profileID, model.profileID)
        XCTAssertThrowsError(try restored.request())
    }
    func testMigrationIsIdempotentAndKeepsIndependentLegacyConnection() {
        let legacy = RealtimeConnectionConfiguration(endpoint: "wss://fixture.example/socket?tenant=one", apiKey: "fixture-key", model: "fixture-model")
        XCTAssertTrue(Config.setCompatibleRealtimeConfiguration(legacy))
        XCTAssertTrue(Config.migrateRealtimeModelsIfNeeded())
        XCTAssertTrue(Config.migrateRealtimeModelsIfNeeded())
        XCTAssertEqual(Config.savedRealtimeModels.count, 1)
        XCTAssertEqual(Config.savedRealtimeModels.first?.id, "legacy-compatible")
        XCTAssertEqual(Config.savedRealtimeModels.first?.endpoint, legacy.endpoint)
        XCTAssertEqual(Config.compatibleRealtimeConfiguration, legacy)
    }
    func testSelectedLiveModelDoesNotDependOnTextModel() {
        var first = RealtimeProviderCatalog.template("qwen")!.modelConfiguration()
        first.apiKey = "fixture-qwen-key"
        let second = RealtimeProviderCatalog.template("doubao")!.modelConfiguration()
        XCTAssertTrue(Config.setSavedRealtimeModels([first, second]))
        Config.setActiveRealtimeModelID(first.id)
        Config.setSavedModels([ModelConfig.defaultConfig(for: .anthropic)])
        XCTAssertEqual(Config.realtimeModel(for: .openaiCompatibleRealtime), first)
        Config.setSavedModels([ModelConfig.defaultConfig(for: .openai)])
        XCTAssertEqual(Config.realtimeModel(for: .openaiCompatibleRealtime), first)
    }
    func testLegacyChatModelsDecodeWithoutTemplateMetadata() throws {
        let data = Data(#"{"id":"fixture","name":"Custom","provider":"custom","apiKey":"fixture","model":"fixture-model","baseURL":"https://fixture.example/v1"}"#.utf8)
        let config = try JSONDecoder().decode(ModelConfig.self, from: data)
        XCTAssertNil(config.providerTemplateID)
        XCTAssertEqual(config.providerDisplayName, LLMProvider.custom.displayName)
    }
}
