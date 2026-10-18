import XCTest
@testable import OpenGlasses

/// Plan JD P0 — which tools Apple's on-device model is offered: a priority list cut to a token
/// budget, Field Assist first when the feature is on, nothing that needs the network on an
/// offline-handoff turn.
final class AppleOnDeviceToolSetTests: XCTestCase {

    private let registered = ["calculate", "field_session", "get_datetime", "get_weather",
                              "reading", "web_search", "where_am_i", "capture_photo"]

    func testFieldAssistToolsLeadWhenTheFeatureIsOn() {
        let names = AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: true,
                                                       offlineHandoff: false)
        XCTAssertEqual(names.first, "field_session", "\"open a new job\" is the first thing said")
        XCTAssertEqual(names.prefix(2).map { $0 }, ["field_session", "reading"])
        XCTAssertEqual(names.last, "web_search", "the network tool comes last")
        XCTAssertFalse(names.contains("capture_photo"), "not on any priority list — never offered here")
    }

    func testFieldAssistToolsAreAbsentWhenTheFeatureIsOff() {
        let names = AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: false,
                                                       offlineHandoff: false)
        XCTAssertFalse(names.contains("field_session"))
        XCTAssertFalse(names.contains("reading"))
        XCTAssertEqual(names.first, "get_datetime")
        XCTAssertTrue(names.contains("web_search"))
    }

    func testOnlyRegisteredNamesSurvive() {
        let names = AppleOnDeviceToolSet.priorityNames(registered: ["get_datetime"], fieldAssistActive: true,
                                                       offlineHandoff: false)
        XCTAssertEqual(names, ["get_datetime"])
    }

    func testOfflineHandoffDropsWhatNeedsTheNetwork() {
        let online = AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: true,
                                                        offlineHandoff: false)
        let offline = AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: true,
                                                         offlineHandoff: true)
        XCTAssertFalse(offline.contains("web_search"))
        XCTAssertFalse(offline.contains("get_weather"))
        XCTAssertTrue(offline.contains("get_datetime"))
        XCTAssertTrue(offline.contains("field_session"), "a job runs without signal")
        XCTAssertEqual(offline, online.filter(OfflineToolPolicy.isOfferedOffline), "order kept")
    }

    func testEveryPriorityNameIsAlsoOnTheLocalSafeListOrAFieldOrNetworkTool() {
        // The everyday list is the MLX path's safe set: tools that resolve their own inputs. A
        // name added here that is not there needs the same justification.
        for name in AppleOnDeviceToolSet.everydayPriority {
            XCTAssertTrue(LLMService.localSafeTools.contains(name), "\(name) is not a self-contained tool")
        }
        XCTAssertEqual(Set(AppleOnDeviceToolSet.everydayPriority), LLMService.localSafeTools,
                       "the everyday set is the local safe set, in priority order")
    }

    func testFitKeepsCandidatesInOrderWhileTheBudgetHoldsAndSkipsTheOnesThatDoNotFit() {
        let candidates: [AppleOnDeviceToolSet.Candidate] = [
            .init(name: "a", estimatedTokens: 600),
            .init(name: "b", estimatedTokens: 600),
            .init(name: "c", estimatedTokens: 600),   // 1800 > 1500: skipped
            .init(name: "d", estimatedTokens: 200),   // still fits after c was skipped
        ]
        XCTAssertEqual(AppleOnDeviceToolSet.fit(candidates, budget: 1_500).map(\.name), ["a", "b", "d"])
        XCTAssertEqual(AppleOnDeviceToolSet.fit(candidates, budget: 0), [])
        XCTAssertEqual(AppleOnDeviceToolSet.fit([], budget: 1_500), [])
    }

    @MainActor
    func testTheHeadlineToolsFitTheBudgetTogether() {
        // The invariant that makes the feature work: the field session tool (with its large schema)
        // and the everyday essentials fit the definition budget at once, after condensing.
        let session = FieldSessionTool()
        let root = AppleToolSchema.root(toolName: session.name, parameters: session.parametersSchema)
        let sessionTokens = AppleToolSchema.estimatedTokens(
            name: session.name, description: AppleToolSchema.toolDescription(session.description), root: root)
        XCTAssertLessThan(sessionTokens, AppleOnDeviceToolSet.definitionBudgetTokens / 2,
                          "field_session alone must leave room for the everyday set")
    }
}
