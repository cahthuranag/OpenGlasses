import XCTest
@testable import OpenGlasses

/// Plan IU — on-demand tool schemas: the pure decision (every row of the setting × window table),
/// the context windows it is measured against, the core set, the lookup tool, the prompt's
/// on-demand block, the organisation pin, and the log line.
@MainActor
final class ToolExposurePolicyTests: XCTestCase {

    private let available = ["calculate", "define_word", "get_weather", "set_timer", "smart_home"]
    private let core: Set<String> = ["get_weather", "set_timer", "not_registered_here"]

    private func decide(_ mode: ToolDefinitionsMode, bytes: Int = 80_000, window: Int?,
                        remembered: Set<String> = []) -> ToolExposureDecision {
        ToolExposurePolicy.decide(mode: mode, available: available, fullSetBytes: bytes,
                                  contextWindow: window, core: core, remembered: remembered)
    }

    // MARK: - The decision table

    func testNeverIsTheFullListWhateverTheWindow() {
        for window in [nil, 4_096, 32_768, 1_048_576] as [Int?] {
            let decision = decide(.never, window: window)
            XCTAssertEqual(decision.exposure, .full)
            XCTAssertEqual(decision.reason, .setting)
            XCTAssertEqual(decision.declared, Set(available), "full exposure declares every available tool")
        }
    }

    func testAlwaysIsTheCoreSetWhateverTheWindow() {
        for window in [nil, 4_096, 1_048_576] as [Int?] {
            let decision = decide(.always, window: window)
            XCTAssertEqual(decision.exposure, .core)
            XCTAssertEqual(decision.reason, .setting)
            XCTAssertEqual(decision.declared, ["get_weather", "set_timer"],
                           "core is intersected with what is available")
        }
    }

    func testAutomaticGoesOnDemandWhenTheFullSetTakesMoreThanATenth() {
        // 80 000 bytes ≈ 20 000 tokens: more than a tenth of 128k, less than a tenth of 272k.
        let small = decide(.automatic, window: 128_000)
        XCTAssertEqual(small.exposure, .core)
        XCTAssertEqual(small.reason, .contextShare)
        XCTAssertEqual(small.fullSetTokens, 20_000)

        let large = decide(.automatic, window: 272_000)
        XCTAssertEqual(large.exposure, .full)
        XCTAssertEqual(large.reason, .contextShare)
    }

    func testAutomaticAtExactlyATenthKeepsTheFullList() {
        // 40 000 bytes = 10 000 tokens = exactly a tenth of 100 000: not *more* than a tenth.
        XCTAssertEqual(decide(.automatic, bytes: 40_000, window: 100_000).exposure, .full)
        XCTAssertEqual(decide(.automatic, bytes: 40_004, window: 100_000).exposure, .core)
    }

    func testAutomaticWithNoKnownWindowKeepsTodaysFullList() {
        let decision = decide(.automatic, window: nil)
        XCTAssertEqual(decision.exposure, .full)
        XCTAssertEqual(decision.reason, .default)
        XCTAssertNil(decision.contextWindow)
    }

    func testAToolUsedOrLookedUpEarlierIsDeclaredFromTheStart() {
        let decision = decide(.always, window: nil, remembered: ["define_word", "gone_since"])
        XCTAssertEqual(decision.declared, ["get_weather", "set_timer", "define_word"],
                       "remembered tools join core, but only while still available")
    }

    func testTheMeasuredSizesFromTheSupportReport() {
        // A tester's ChatGPT turns weighed the tools block at 76 575 (an upper-bound estimate):
        // about 19k tokens. Large cloud windows keep the full list; small ones go on demand.
        let tokens = ToolExposurePolicy.estimatedTokens(bytes: 76_575)
        XCTAssertEqual(tokens, 19_143)
        XCTAssertFalse(ToolExposurePolicy.crowds(fullSetTokens: tokens, contextWindow: 272_000), "ChatGPT subscription")
        XCTAssertFalse(ToolExposurePolicy.crowds(fullSetTokens: tokens, contextWindow: 200_000), "Claude")
        XCTAssertFalse(ToolExposurePolicy.crowds(fullSetTokens: tokens, contextWindow: 1_048_576), "Gemini")
        XCTAssertTrue(ToolExposurePolicy.crowds(fullSetTokens: tokens, contextWindow: 128_000), "gpt-4o, DeepSeek, Mistral")
        XCTAssertTrue(ToolExposurePolicy.crowds(fullSetTokens: tokens, contextWindow: 32_768), "Gemini 1.0")
        XCTAssertTrue(ToolExposurePolicy.crowds(fullSetTokens: tokens, contextWindow: 8_192), "an on-device model")
    }

    // MARK: - Rounds and the safety net

    func testFullExposureHasNoRoundFilter() {
        XCTAssertNil(ToolExposurePolicy.roundDeclared(decide(.never, window: nil), promoted: ["define_word"]))
    }

    func testARoundDeclaresWhatWasPromotedSinceTheTurnBegan() {
        let decision = decide(.always, window: nil)
        XCTAssertEqual(ToolExposurePolicy.roundDeclared(decision, promoted: ["define_word", "not_available"]),
                       ["get_weather", "set_timer", "define_word"])
    }

    func testOnlyAnAvailableUndeclaredToolIsTurnedBack() {
        let declared: Set<String> = ["get_weather"]
        let all = Set(available)
        XCTAssertTrue(ToolExposurePolicy.isUndeclaredCall("define_word", declaredThisRound: declared, available: all))
        XCTAssertFalse(ToolExposurePolicy.isUndeclaredCall("get_weather", declaredThisRound: declared, available: all))
        XCTAssertFalse(ToolExposurePolicy.isUndeclaredCall("made_up", declaredThisRound: declared, available: all),
                       "a name the model invented is the router's to refuse, as before")
        XCTAssertFalse(ToolExposurePolicy.isUndeclaredCall(ToolLookupTool.toolName, declaredThisRound: declared, available: all))
        XCTAssertFalse(ToolExposurePolicy.isUndeclaredCall("define_word", declaredThisRound: nil, available: all),
                       "full exposure turns nothing back")
    }

    func testTheTurnedBackCallSaysNothingRan() {
        let message = ToolExposurePolicy.undeclaredCallMessage("define_word")
        XCTAssertTrue(message.contains("'define_word' was not run"))
        XCTAssertTrue(message.contains("next step"))
    }

    func testRequestedNamesAcceptTheShapesAModelSends() {
        XCTAssertEqual(ToolExposurePolicy.requestedNames(["names": ["a", " b ", "a", ""]]), ["a", "b"])
        XCTAssertEqual(ToolExposurePolicy.requestedNames(["names": "a, b,c"]), ["a", "b", "c"])
        XCTAssertEqual(ToolExposurePolicy.requestedNames(["names": ["a", 3] as [Any]]), ["a"])
        XCTAssertEqual(ToolExposurePolicy.requestedNames(["name": "a"]), ["a"])
        XCTAssertEqual(ToolExposurePolicy.requestedNames([:]), [])
    }

    // MARK: - Context windows

    func testContextWindowsComeFromWhatTheAppAlreadyKnows() {
        XCTAssertEqual(ModelContextWindow.resolve(provider: .chatgpt, model: "gpt-5.5", baseURL: "")?.tokens, 272_000)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .chatgpt, model: "gpt-5.5", baseURL: "",
                                                  chatGPTCatalogContext: 400_000)?.tokens, 400_000,
                       "the account catalog wins where it knows the model")
        XCTAssertEqual(ModelContextWindow.resolve(provider: .openai, model: "gpt-4o", baseURL: "")?.tokens, 128_000)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .openai, model: "gpt-5.5", baseURL: "")?.tokens, 1_050_000)
        XCTAssertNil(ModelContextWindow.resolve(provider: .openai, model: "gpt-4o",
                                                baseURL: "https://example.openai.azure.com/openai/deployments/x"),
                     "an Azure deployment's window is not the model id's")
        XCTAssertEqual(ModelContextWindow.resolve(provider: .anthropic, model: "claude-sonnet-4-5", baseURL: "")?.tokens, 200_000)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .gemini, model: "gemini-2.5-flash", baseURL: "")?.tokens, 1_048_576)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .gemini, model: "gemini-1.0-pro", baseURL: "")?.tokens, 32_768)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .geminiVertex, model: "gemini-3-pro", baseURL: "")?.tokens, 1_048_576)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .deepseek, model: "deepseek-chat", baseURL: "")?.tokens, 128_000)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .mistral, model: "mistral-large-latest", baseURL: "")?.tokens, 128_000)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .groq, model: "llama-3.3-70b-versatile", baseURL: "")?.tokens, 131_072)
        XCTAssertEqual(ModelContextWindow.resolve(provider: .local, model: "no-such-model", baseURL: "")?.tokens,
                       LocalModelBudget.defaultContextWindow)
        for provider in [LLMProvider.custom, .openrouter, .qwen, .minimax, .xai, .zai] {
            XCTAssertNil(ModelContextWindow.resolve(provider: provider, model: "anything", baseURL: "https://x.test"),
                         "\(provider.rawValue): a window the app does not know keeps the full list")
        }
        XCTAssertNil(ModelContextWindow.resolve(provider: .anthropic, model: "not-claude", baseURL: ""))
    }

    // MARK: - The core set

    /// Representative everyday asks, by the tool a turn reaches for. Each must be declared in full
    /// without a lookup, so the commonest turns cost no extra round.
    func testTheCoreSetCoversEverydayAsks() {
        let asks: [(ask: String, tool: String)] = [
            ("what's the weather", "get_weather"),
            ("what time is it", "get_datetime"),
            ("set a timer for ten minutes", "set_timer"),
            ("wake me at seven", "set_alarm"),
            ("remind me to call the plumber", "reminder"),
            ("what's on my calendar", "calendar"),
            ("brief me on my day", "daily_briefing"),
            ("where am I", "where_am_i"),
            ("find a pharmacy nearby", "find_nearby"),
            ("how do I get home", "get_directions"),
            ("search the web for", "web_search"),
            ("what's in the news", "get_news"),
            ("how much battery do I have", "device_info"),
            ("turn on the torch", "flashlight"),
            ("skip this song", "music_control"),
            ("take a note", "save_note"),
            ("read me my notes", "list_notes"),
            ("what did I tell you about", "memory_search"),
            ("text Mum I'm late", "send_message"),
            ("call Dad", "phone_call"),
            ("what's Sam's number", "lookup_contact"),
            ("take a photo", "capture_photo"),
            ("what's 15% of 80", "calculate"),
            ("how many cups in a litre", "convert_units"),
            ("how do you say thank you in Japanese", "translate"),
            ("new topic", "new_topic"),
            ("can I take ibuprofen with this", "health_check"),
        ]
        let core = ToolExposureCore.names(fieldJobActive: false, accessibilityMode: false)
        for (ask, tool) in asks {
            XCTAssertTrue(core.contains(tool), "\"\(ask)\" needs \(tool) in the core set")
        }
    }

    func testEveryCoreNameIsARealTool() throws {
        let declared = try Self.declaredToolNames()
        let all = ToolExposureCore.everyday.union(ToolExposureCore.accessibility)
        XCTAssertEqual(all.subtracting(declared).sorted(), [], "a core name must be a tool that exists")
    }

    func testAnActiveModeAddsTheToolsItIsBuiltOn() {
        let plain = ToolExposureCore.names(fieldJobActive: false, accessibilityMode: false)
        XCTAssertFalse(plain.contains("field_session"))
        XCTAssertFalse(plain.contains("identify_money"))
        let job = ToolExposureCore.names(fieldJobActive: true, accessibilityMode: false)
        XCTAssertTrue(FieldToolProfile.names.isSubset(of: job), "a field job keeps its whole profile in core")
        let sight = ToolExposureCore.names(fieldJobActive: false, accessibilityMode: true)
        XCTAssertTrue(ToolExposureCore.accessibility.isSubset(of: sight))
    }

    func testTheCoreSetIsAFractionOfTheRegistry() {
        let registry = NativeToolRegistry(locationService: LocationService())
        let core = ToolExposureCore.everyday.intersection(registry.toolNames)
        // The headless registry is the narrow one (~70 tools; an install has ~120), so a half here.
        XCTAssertLessThan(core.count * 2, registry.toolNames.count, "core is meant to be small")
    }

    // MARK: - Declarations

    func testFullExposureDeclaresExactlyWhatItAlwaysDid() {
        let registry = NativeToolRegistry(locationService: LocationService())
        let full = ToolDeclarations.exposedDeclarations(registry: registry, mcpClient: nil, declaring: nil)
        XCTAssertEqual(full.compactMap { $0["name"] as? String },
                       ToolDeclarations.nativeToolDeclarations(registry: registry).compactMap { $0["name"] as? String })
        XCTAssertFalse(full.contains { $0["name"] as? String == ToolLookupTool.toolName },
                       "the lookup tool is never part of the full list")
        XCTAssertFalse(registry.toolNames.contains(ToolLookupTool.toolName), "nor of the prompt's tool list")
        XCTAssertNotNil(registry.tool(named: ToolLookupTool.toolName), "but the router can run it")
    }

    func testCoreExposureDeclaresTheNamedToolsAndTheLookupSorted() throws {
        let registry = NativeToolRegistry(locationService: LocationService())
        let core = ToolDeclarations.exposedDeclarations(registry: registry, mcpClient: nil,
                                                        declaring: ["get_weather", "set_timer", "not_a_tool"])
        let names = core.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["get_weather", ToolLookupTool.toolName, "set_timer"])
        XCTAssertEqual(names, names.sorted(), "byte-stable for the provider's prompt cache")

        let again = ToolDeclarations.openAITools(registry: registry, includeOpenClaw: false, declaring: ["set_timer", "get_weather"])
        let first = ToolDeclarations.openAITools(registry: registry, includeOpenClaw: false, declaring: ["get_weather", "set_timer"])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: again, options: [.sortedKeys]),
                       try JSONSerialization.data(withJSONObject: first, options: [.sortedKeys]))
    }

    func testOpenClawExecuteStaysDeclaredOnDemand() {
        let registry = NativeToolRegistry(locationService: LocationService())
        let tools = ToolDeclarations.anthropicTools(registry: registry, includeOpenClaw: true, declaring: ["get_weather"])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["get_weather", ToolLookupTool.toolName, "execute"])
    }

    func testTheAvailableSetIsMeasuredWithoutTheLookupTool() {
        let registry = NativeToolRegistry(locationService: LocationService())
        let set = ToolDeclarations.availableToolSet(registry: registry, mcpClient: nil)
        XCTAssertFalse(set.names.contains(ToolLookupTool.toolName))
        XCTAssertEqual(set.names.count, ToolDeclarations.nativeToolDeclarations(registry: registry).count)
        XCTAssertGreaterThan(set.bytes, 20_000, "the headless registry's schemas are tens of kilobytes")

        // The measurement the plan quotes: the full set against the core set on the same registry.
        let core = ToolExposureCore.names(fieldJobActive: false, accessibilityMode: false)
        let coreDecls = ToolDeclarations.exposedDeclarations(registry: registry, mcpClient: nil, declaring: core)
        let coreBytes = (try? JSONSerialization.data(withJSONObject: coreDecls, options: [.sortedKeys]))?.count ?? 0
        let guide = SystemPromptBuilder.onDemandToolGuide(
            native: registry.toolDescriptions(for: registry.toolNames.filter { !core.contains($0) }), mcpNames: [])
        print("IU-measure full=\(set.bytes)B/\(set.names.count) tools core=\(coreBytes)B/\(coreDecls.count) tools guide=\(guide.utf8.count)B")
        XCTAssertLessThan(coreBytes * 2, set.bytes, "core must be well under half the full set")
    }

    // MARK: - The lookup tool

    func testTheLookupReturnsOnlyDeclarableDefinitions() {
        let declarable: [[String: Any]] = [
            ["name": "define_word", "description": "Define a word.", "parameters": ["type": "object"]],
        ]
        let reply = ToolLookupTool.render(requested: ["define_word", "disabled_tool"], declarable: declarable)
        XCTAssertTrue(reply.contains("\"name\":\"define_word\""), reply)
        XCTAssertTrue(reply.contains("Not available: disabled_tool"), reply)
        XCTAssertEqual(ToolLookupTool.returnedNames(requested: ["define_word", "disabled_tool"],
                                                    declarable: ["define_word"]), ["define_word"])
    }

    func testTheLookupIsBounded() {
        let many = (0..<12).map { "t\($0)" }
        let declarable = many.map { ["name": $0, "description": "", "parameters": [:] as [String: Any]] as [String: Any] }
        let reply = ToolLookupTool.render(requested: many, declarable: declarable)
        XCTAssertTrue(reply.contains("Only the first \(ToolLookupTool.maxNamesPerCall) names"))
        XCTAssertFalse(reply.contains("\"t8\""))
        XCTAssertEqual(ToolLookupTool.returnedNames(requested: many, declarable: Set(many)).count,
                       ToolLookupTool.maxNamesPerCall)
    }

    func testTheLookupNeverDescribesADisabledTool() async throws {
        let registry = NativeToolRegistry(locationService: LocationService())
        let wasEnabled = Config.isToolEnabled("define_word")
        Config.setToolEnabled("define_word", enabled: false)
        defer { Config.setToolEnabled("define_word", enabled: wasEnabled) }
        var lookup = ToolLookupTool()
        lookup.toolRegistry = registry
        let reply = try await lookup.execute(args: ["names": ["define_word", "get_weather"]])
        XCTAssertFalse(reply.contains("\"name\":\"define_word\""), reply)
        XCTAssertTrue(reply.contains("Not available: define_word"), reply)
        XCTAssertTrue(reply.contains("\"name\":\"get_weather\""), reply)
    }

    func testTheLookupDescribesItselfWithoutHelp() {
        let description = ToolLookupTool().description
        XCTAssertTrue(description.contains("before you call any other tool"))
        XCTAssertEqual(ToolLookupTool().executionSemantics, .read(.notCancellable))
        XCTAssertEqual(OfflineToolPolicy.availability(of: ToolLookupTool.toolName), .local)
    }

    // MARK: - The prompt

    func testTheOnDemandBlockSaysHowToGetADefinitionAndListsEveryTool() {
        let block = SystemPromptBuilder.onDemandToolGuide(
            native: [("define_word", "Define a word. Returns the meaning and an example."),
                     ("smart_home", "Control lights.\nAnd scenes.")],
            mcpNames: ["srv__lookup"])
        XCTAssertTrue(block.hasPrefix("TOOL DEFINITIONS ON DEMAND:"))
        XCTAssertTrue(block.contains("call \(ToolLookupTool.toolName) with its exact name"))
        XCTAssertTrue(block.contains("- define_word: Define a word.\n"), block)
        XCTAssertTrue(block.contains("- smart_home: Control lights.\nTools from"), "a summary is the first sentence: \(block)")
        XCTAssertTrue(block.contains("Tools from connected servers: srv__lookup."))
    }

    func testASummaryIsOneShortSentence() {
        XCTAssertEqual(SystemPromptBuilder.summary("Get the weather. Use it for forecasts."), "Get the weather.")
        let long = String(repeating: "word ", count: 60)
        let cut = SystemPromptBuilder.summary(long)
        XCTAssertLessThanOrEqual(cut.count, SystemPromptBuilder.summaryLimit + 1)
        XCTAssertTrue(cut.hasSuffix("…"))
    }

    func testTheOnDemandBlockIsSmallerThanTheSchemasItReplaces() {
        let registry = NativeToolRegistry(locationService: LocationService())
        let block = SystemPromptBuilder.onDemandToolGuide(
            native: registry.toolDescriptions(for: registry.toolNames), mcpNames: [])
        let full = ToolDeclarations.availableToolSet(registry: registry, mcpClient: nil).bytes
        XCTAssertLessThan(block.utf8.count * 3, full, "the summaries must be a fraction of the schemas")
    }

    // MARK: - The setting and the organisation pin

    func testTheSettingDefaultsToAutomaticAndPersists() {
        let previous = UserDefaults.standard.object(forKey: "toolDefinitionsMode")
        defer { UserDefaults.standard.set(previous, forKey: "toolDefinitionsMode") }
        UserDefaults.standard.removeObject(forKey: "toolDefinitionsMode")
        XCTAssertEqual(Config.userToolDefinitionsMode, .automatic)
        Config.setToolDefinitionsMode(.always)
        XCTAssertEqual(Config.userToolDefinitionsMode, .always)
        XCTAssertEqual(ToolDefinitionsMode.allCases.map(\.rawValue), ["automatic", "always", "never"])
    }

    func testAnOrganisationCanPinTheModeAndNothingElse() {
        XCTAssertEqual(SettingKey.organizationToolDefinitionsMode.kind, .profileOwned(.string))
        let profile = ConfigProfile(keyId: "k", profileId: "p", organizationName: "Org",
                                    issued: Date(timeIntervalSince1970: 1_790_000_000), leaseDays: 30,
                                    settings: ["organizationToolDefinitionsMode": RawSetting(.string("never"), .default)])
        let result = ProfileApplier.apply(profile: profile, resolvableVaultIds: [])
        XCTAssertTrue(result.drops.isEmpty, "\(result.drops)")
        XCTAssertEqual(result.effectiveValue(.organizationToolDefinitionsMode, stored: .string("")), .string("never"))
        XCTAssertTrue(result.isLocked(.organizationToolDefinitionsMode))

        let bad = ConfigProfile(keyId: "k", profileId: "p", organizationName: "Org",
                                issued: Date(timeIntervalSince1970: 1_790_000_000), leaseDays: 30,
                                settings: ["organizationToolDefinitionsMode": RawSetting(.string("sometimes"), .default)])
        let dropped = ProfileApplier.apply(profile: bad, resolvableVaultIds: [])
        XCTAssertEqual(dropped.drops.map(\.key), ["organizationToolDefinitionsMode"])
        XCTAssertFalse(dropped.isLocked(.organizationToolDefinitionsMode))
    }

    func testAPinnedModeIsHiddenFromTheTechnicianAndReadOnlyForTheAdministrator() {
        let locked: Set<SettingKey> = [.organizationToolDefinitionsMode]
        let technician = ManagedSettingsContext(managed: true, lockdown: nil, restricted: false, lockedKeys: locked)
        XCTAssertEqual(SettingsVisibilityPolicy.presentation(.key(.organizationToolDefinitionsMode), in: technician), .hidden)
        XCTAssertEqual(SettingsVisibilityPolicy.presentation(.key(.organizationToolDefinitionsMode), in: .unmanaged), .editable)
    }

    func testTheSettingLivesOnAScreenSimpleModeHides() {
        XCTAssertFalse(SettingsCatalog.visible(simpleMode: true).contains { $0.id == .intelligence })
        XCTAssertTrue(SettingsCatalog.visible(simpleMode: false).contains { $0.id == .intelligence })
    }

    // MARK: - The log

    func testTheExposureLineIsCountsAndTokensOnly() {
        let line = PrivacyEventEncoder.encode(
            PrivacyLog.model(.toolExposure, provider: PrivacyToken("chatgpt"), model: PrivacyToken("gpt-5.5"),
                             count: 34, total: 121, tokens: 19_143,
                             detail: PrivacyToken("core"), reason: PrivacyToken("contextShare")))
        XCTAssertTrue(line.contains("toolExposure"), line)
        XCTAssertTrue(line.contains("detail=core"), line)
        XCTAssertTrue(line.contains("reason=contextShare"), line)
        XCTAssertTrue(line.contains("count=34"), line)
        XCTAssertTrue(line.contains("total=121"), line)
    }

    func testTheExposureLineReachesTheSupportReportsEventLog() {
        let ring = DiagnosticRing(capacity: 50)
        ring.attach()
        defer { ring.detach() }
        PrivacyLog.model(.toolExposure, count: 2, detail: PrivacyToken("added"), reason: PrivacyToken("lookup"))
        XCTAssertTrue(ring.entries.contains { $0.line.contains("toolExposure") && $0.line.contains("reason=lookup") },
                      ring.entries.map(\.line).joined(separator: "\n"))
    }

    // MARK: - Helpers

    /// Tool names scraped from the tools' own declarations, as `OfflineToolPolicyTests` does.
    static func declaredToolNames() throws -> Set<String> {
        let toolsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OpenGlasses/Sources/Services/NativeTools", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: toolsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let pattern = try NSRegularExpression(
            pattern: #"(?:let|var) name(?:: String)? (?:= |\{ *(?:return )?)"([a-z0-9_]+)""#)
        var declared = Set<String>()
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                if let name = Range(match.range(at: 1), in: source) { declared.insert(String(source[name])) }
            }
        }
        return declared
    }
}
