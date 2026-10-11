import XCTest
@testable import OpenGlasses

final class CompatibleRealtimeTests: XCTestCase {
    private func configuration(_ endpoint: String = "wss://gateway.example/realtime") -> RealtimeConnectionConfiguration {
        RealtimeConnectionConfiguration(endpoint: endpoint, apiKey: "gateway-key", model: "custom-model")
    }

    func testBuiltInOpenAIRequestKeepsItsEndpointAndHeaders() throws {
        let config = RealtimeConnectionConfiguration(endpoint: RealtimeConnectionConfiguration.openAIEndpoint,
                                                     apiKey: "openai-key", model: "gpt-realtime", isCustom: false)
        let request = try config.request(build: .release)
        XCTAssertEqual(request.url?.absoluteString, "wss://api.openai.com/v1/realtime?model=gpt-realtime")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "realtime=v1")
    }

    func testCustomRequestPreservesPathAndQueriesAndReplacesModel() throws {
        var config = configuration("wss://gateway.example:9443/prefix/socket?tenant=team%2Bone&model=old&model=duplicate&api-version=2026-01")
        config.model = "provider/model + variant?"
        let request = try config.request(build: .release)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.path, "/prefix/socket")
        XCTAssertEqual(url.port, 9443)
        XCTAssertEqual(components.queryItems?.filter { $0.name == "model" },
                       [URLQueryItem(name: "model", value: config.model)])
        XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "tenant", value: "team+one")) == true)
        XCTAssertTrue(components.percentEncodedQuery?.contains("tenant=team%2Bone") == true,
                      "Gateway tokens must retain encoded plus signs on the wire")
        XCTAssertTrue(components.percentEncodedQuery?.contains("model=provider%2Fmodel%20%2B%20variant%3F") == true)
        XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "api-version", value: "2026-01")) == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gateway-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Beta"))
    }

    func testWhitespaceIsTrimmed() throws {
        let config = RealtimeConnectionConfiguration(endpoint: "  wss://gateway.example/socket\n",
                                                     apiKey: " key ", model: " model ")
        let request = try config.request()
        XCTAssertEqual(request.url?.absoluteString, "wss://gateway.example/socket?model=model")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
    }

    func testInvalidEndpointsFailWithoutLeakingURLSecrets() {
        for endpoint in ["", "relative/path", "https://gateway.example", "file:///tmp/socket",
                         "wss:///socket", "wss://user:secret@gateway.example/socket",
                         "wss://gateway.example/socket?token=secret#fragment"] {
            XCTAssertThrowsError(try configuration(endpoint).request(build: .release)) { error in
                XCTAssertFalse(error.localizedDescription.contains("secret"))
                XCTAssertFalse(error.localizedDescription.contains("gateway.example"))
            }
        }
    }

    func testLocalServersAreSupportedButPublicCleartextIsRejected() {
        for endpoint in ["ws://192.168.1.10:8080/realtime", "wss://server.local/realtime", "ws://127.0.0.1:8080/realtime"] {
            XCTAssertNoThrow(try configuration(endpoint).request(build: .release))
        }
        XCTAssertThrowsError(try configuration("ws://gateway.example/realtime").request(build: .release))
        var builtIn = configuration("wss://192.168.1.10/realtime")
        builtIn.isCustom = false
        XCTAssertThrowsError(try builtIn.request(build: .release), "A custom-server exception cannot widen the built-in route")
    }

    func testMissingModelOrKeyAndHeaderInjectionAreRejected() {
        var config = configuration()
        config.model = "  "
        XCTAssertFalse(config.isConfigured)
        config.model = "custom"
        config.apiKey = ""
        XCTAssertFalse(config.isConfigured)
        config.apiKey = "key\r\nInjected: value"
        XCTAssertThrowsError(try config.request())
    }

    func testCustomModeHasIndependentAvailability() throws {
        let options = ConversationModeAvailability.options(for: .init(
            hasGeminiKey: false, hasOpenAIRealtimeModel: false, hasChatGPTAccount: false,
            hasCompatibleRealtimeConfiguration: true))
        XCTAssertTrue(try XCTUnwrap(options.first { $0.mode == .openaiCompatibleRealtime }).isAvailable)
        XCTAssertFalse(try XCTUnwrap(options.first { $0.mode == .openaiRealtime }).isAvailable)
        XCTAssertFalse(try XCTUnwrap(options.first { $0.mode == .geminiLive }).isAvailable)
        let missing = ConversationModeAvailability.options(for: .init(
            hasGeminiKey: true, hasOpenAIRealtimeModel: true))
        let option = try XCTUnwrap(missing.first { $0.mode == .openaiCompatibleRealtime })
        XCTAssertFalse(option.isAvailable)
        XCTAssertTrue(option.unavailableReason?.contains("Settings") == true)
    }

    func testSwitchingBetweenBuiltInAndCustomRealtimeTearsDownAndRedials() {
        for (from, to): (AppMode, AppMode) in [(.openaiRealtime, .openaiCompatibleRealtime),
                                             (.openaiCompatibleRealtime, .openaiRealtime),
                                             (.geminiLive, .openaiCompatibleRealtime)] {
            let actions = ModeSwitchPolicy.actions(from: from, to: to, wasSessionActive: true, autoRedial: true)
            XCTAssertEqual(actions, [.teardown(from), .settleDelay, .startSubstrate(to), .startSession(to)])
        }
        XCTAssertTrue(AppMode.openaiCompatibleRealtime.isRealtime)
        XCTAssertTrue(AppMode.openaiCompatibleRealtime.usesOpenAIRealtimeTransport)
    }

    func testCustomServerStillBlockedByMedicalLocalOnly() {
        XCTAssertFalse(MedicalEgressGuard.decide(.openAICompatibleRealtimeSession, mode: .localOnly).isAllowed)
        XCTAssertTrue(MedicalEgressGuard.decide(.openAICompatibleRealtimeSession, mode: .off).isAllowed)
    }

    func testDestinationSummaryNamesCustomHostForEveryLiveDataRow() {
        let host = ProcessingFacts.host(of: "wss://gateway.example:9443/secret-path?token=secret")
        let summary = ProcessingSummary.compose(facts: ProcessingFacts(
            liveProviderName: "your compatible Realtime server", liveEndpointHost: host))
        for row in summary.rows where row.kind != .remoteTools {
            XCTAssertEqual(row.destination, .customEndpoint(host: "gateway.example:9443"))
        }
        XCTAssertFalse(summary.spoken.contains("secret"))
        XCTAssertFalse(summary.spoken.contains("OpenAI"))
    }

    @MainActor
    func testServiceReconnectRequestRetainsTheSessionSnapshot() throws {
        let key = "compatibleRealtimeConfiguration"
        let previous = KeychainService.data(for: key)
        defer { KeychainService.setData(previous, for: key) }
        let service = OpenAIRealtimeService()
        var edited = configuration()
        XCTAssertTrue(Config.setCompatibleRealtimeConfiguration(edited))
        service.configure(connection: Config.compatibleRealtimeConfiguration, systemInstruction: "test")
        let first = try service.connectionRequest()
        edited.endpoint = "wss://different.example/socket"
        edited.apiKey = "different-key"
        edited.model = "different-model"
        XCTAssertTrue(Config.setCompatibleRealtimeConfiguration(edited))
        // The request path used by connect/reconnect must ignore settings edited mid-session.
        XCTAssertEqual(try service.connectionRequest(), first)
        service.configure(connection: Config.compatibleRealtimeConfiguration, systemInstruction: "new session")
        XCTAssertEqual(try service.connectionRequest().url?.host, "different.example")
        service.disconnect()
    }

    func testConfigurationPersistsWithoutUsingUserDefaults() throws {
        let key = "compatibleRealtimeConfiguration"
        let previous = KeychainService.data(for: key)
        defer { KeychainService.setData(previous, for: key) }
        let config = configuration("wss://gateway.example/socket?token=secret")
        XCTAssertTrue(Config.setCompatibleRealtimeConfiguration(config))
        XCTAssertEqual(Config.compatibleRealtimeConfiguration, config)
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    @MainActor
    func testSupersededStartupCannotContinueIntoTheNewSession() async throws {
        let key = "compatibleRealtimeConfiguration"
        let previous = KeychainService.data(for: key)
        let previousMode = Config.appMode
        let previousMedicalMode = MedicalEgressGuard.currentMode
        defer {
            KeychainService.setData(previous, for: key)
            Config.setAppMode(previousMode)
            MedicalEgressGuard.currentMode = previousMedicalMode
        }
        MedicalEgressGuard.currentMode = { .off }
        XCTAssertTrue(Config.setCompatibleRealtimeConfiguration(configuration()))
        Config.setAppMode(.openaiCompatibleRealtime)

        let manager = OpenAIRealtimeSessionManager()
        let firstCue = expectation(description: "First startup is waiting on its cue")
        let secondCue = expectation(description: "Replacement startup is waiting on its cue")
        var releaseFirst: CheckedContinuation<Void, Never>?
        var releaseSecond: CheckedContinuation<Void, Never>?
        manager.onWillConnect = {
            await withCheckedContinuation { continuation in
                if releaseFirst == nil {
                    releaseFirst = continuation
                    firstCue.fulfill()
                } else {
                    releaseSecond = continuation
                    secondCue.fulfill()
                }
            }
        }
        var cameraStarts = 0
        manager.onRequestStartCamera = {
            cameraStarts += 1
            return false
        }
        let first = Task { await manager.startSession() }
        await fulfillment(of: [firstCue], timeout: 2)
        manager.stopSession()
        XCTAssertTrue(Config.setCompatibleRealtimeConfiguration(configuration("wss://replacement.example/socket")))
        let second = Task { await manager.startSession() }
        await fulfillment(of: [secondCue], timeout: 2)
        releaseFirst?.resume()
        await first.value
        XCTAssertTrue(manager.isActive, "Finishing the old startup must leave the new one alone")
        XCTAssertEqual(cameraStarts, 0, "An old startup cannot acquire resources or reconfigure the replacement")
        manager.stopSession()
        releaseSecond?.resume()
        await second.value
        XCTAssertEqual(cameraStarts, 0)
    }
}
