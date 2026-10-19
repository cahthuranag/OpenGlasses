import XCTest
@testable import OpenGlasses

/// A Field Assist job turn does not run on Apple's on-device model when something that can hold
/// the job is configured; when nothing is, or the offline hand-off chose the phone, it stays. And
/// a window the on-device model fills is named as one, in the report and in the cascade.
@MainActor
final class OnDeviceJobRoutePolicyTests: XCTestCase {

    private let claude = OnDeviceJobRoutePolicy.Alternative(id: "c", name: "Work Claude", provider: .anthropic,
                                                            model: "claude-sonnet-4-5")
    private let gemma = OnDeviceJobRoutePolicy.Alternative(id: "g", name: "Gemma", provider: .local,
                                                           model: "gemma-4")

    private func inputs(jobOpen: Bool = true, jobTurn: Bool = false,
                        active: LLMProvider = .appleOnDevice,
                        alternatives: [OnDeviceJobRoutePolicy.Alternative]? = nil,
                        offline: Bool = false, announced: Bool = false) -> OnDeviceJobRoutePolicy.Inputs {
        .init(jobOpen: jobOpen, jobTurn: jobTurn, activeProvider: active,
              alternatives: alternatives ?? [claude, gemma], offlineHandoff: offline,
              announcedThisProcess: announced)
    }

    func testAnOpenJobOnTheOnDeviceModelGoesToTheFirstAlternativeWithTheSentenceOnce() {
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs()), .handOff(to: claude, announce: true))
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(announced: true)), .handOff(to: claude, announce: false),
                       "one sentence per process")
    }

    func testAJobStartTurnRoutesBeforeAnyJobIsOpen() {
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(jobOpen: false, jobTurn: true)),
                       .handOff(to: claude, announce: true))
    }

    func testANonJobTurnOrAnotherProviderIsLeftAlone() {
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(jobOpen: false, jobTurn: false)), .unchanged)
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(active: .anthropic)), .unchanged)
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(active: .local)), .unchanged)
    }

    func testALocalModelIsAnAlternativeToo() {
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(alternatives: [gemma])), .handOff(to: gemma, announce: true))
    }

    func testItStaysOnTheDeviceWhenNothingElseCanTakeTheTurnOrTheHandOffChoseThePhone() {
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(alternatives: [])), .stayOnDevice(.noAlternative))
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(offline: true)), .stayOnDevice(.offlineHandoff),
                       "the offline hand-off put the turn on the phone on purpose")
        let anotherApple = OnDeviceJobRoutePolicy.Alternative(id: "a2", name: "Apple again", provider: .appleOnDevice,
                                                              model: "apple-foundation-model")
        XCTAssertEqual(OnDeviceJobRoutePolicy.decide(inputs(alternatives: [anotherApple])),
                       .stayOnDevice(.noAlternative))
    }

    func testAlternativesFollowTheFallbackOrderThenTheSavedOrderAndSkipTheUnusable() {
        let saved = [
            ModelConfig(id: "apple", name: "Apple", provider: LLMProvider.appleOnDevice.rawValue, apiKey: "",
                        model: "apple-foundation-model", baseURL: ""),
            ModelConfig(id: "groq", name: "Groq", provider: LLMProvider.groq.rawValue, apiKey: "",
                        model: "llama", baseURL: ""),
            ModelConfig(id: "gpt", name: "GPT", provider: LLMProvider.openai.rawValue, apiKey: "k",
                        model: "gpt-5", baseURL: ""),
            ModelConfig(id: "claude", name: "Claude", provider: LLMProvider.anthropic.rawValue, apiKey: "k",
                        model: "claude-sonnet-4-5", baseURL: ""),
        ]
        let ordered = OnDeviceJobRoutePolicy.orderedAlternatives(
            activeId: "apple", saved: saved, fallbackOrder: ["claude", "unknown"],
            isUsable: { !$0.apiKey.isEmpty })
        XCTAssertEqual(ordered.map(\.id), ["claude", "gpt"], "fallback order first; the keyless one and the active one out")
    }

    func testTheSentenceNamesTheModel() {
        XCTAssertEqual(OnDeviceJobRoutePolicy.notice(modelName: "Work Claude"),
                       "Using Work Claude for this job; Apple Intelligence can't hold the manuals.")
        XCTAssertFalse(OnDeviceJobRoutePolicy.notice(modelName: " ").contains("Using  for"))
    }

    // MARK: - Naming the overflow

    func testAFullWindowIsNamedAsOneAndAMaxTokensStopKeepsItsName() {
        let overflow = SafeErrorSummary(LLMError.contextOverflow(provider: "Apple Intelligence", toolsRan: false))
        XCTAssertEqual(overflow.category, .contextOverflow)
        XCTAssertEqual(overflow.description, "contextOverflow(beforeTools)")
        XCTAssertEqual(AppState.plainReason(overflow.description),
                       "the on-device model's window was too small for this turn: it cannot hold the instructions and tools together — use a cloud model for this")

        let truncated = SafeErrorSummary(LLMError.outputTruncated(provider: "Anthropic"))
        XCTAssertEqual(truncated.description, "outputTruncated(max_tokens)")
    }

    func testTheCascadeTreatsAnOverflowLikeATruncationUntilAToolHasRun() {
        XCTAssertEqual(ModelFallbackChain.classify(LLMError.contextOverflow(provider: "Apple Intelligence", toolsRan: false)),
                       ModelFallbackChain.classify(LLMError.outputTruncated(provider: "Apple Intelligence")))
        XCTAssertEqual(ModelFallbackChain.classify(LLMError.contextOverflow(provider: "Apple Intelligence", toolsRan: true)),
                       .terminalForTurn, "restarting elsewhere could run the tool a second time")
    }

    // MARK: - Support report

    func testThePhoneSectionSaysItIsTheSettingNow() {
        let config = ModelConfig(id: "gpt", name: "Office GPT", provider: LLMProvider.openai.rawValue, apiKey: "k",
                                 model: "gpt-5", baseURL: "")
        let line = AppState.activeModelReportLine(config)
        XCTAssertTrue(line.hasPrefix("AI model set now: Office GPT"))
        XCTAssertTrue(line.contains("each turn above names the model that answered it"))
        XCTAssertEqual(AppState.activeModelReportLine(nil), "AI model set now: none")
    }
}
