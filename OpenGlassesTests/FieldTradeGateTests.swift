import XCTest
@testable import OpenGlasses

/// What a trade gates beyond its tiles (Plan IS trade presets): the tools offered to the model, the
/// trade's own Settings section, and the redirect a call to a hidden trade's tool gets. A matrix of
/// the five resolutions that matter — no trade set, Refrigeration only, Electrical only, both, and
/// an explicit empty choice — across every surface, plus the general set no trade ever touches.
@MainActor
final class FieldTradeGateTests: XCTestCase {

    private struct Case {
        let name: String
        let selection: FieldTradeSelection
        /// Refrigeration's tools and Settings section are offered.
        let refrigerationSurfaces: Bool
        /// Refrigeration's tiles are on the grid.
        let refrigerationTiles: Bool
    }

    private let cases: [Case] = [
        Case(name: "none", selection: FieldTradeResolver.resolve(explicit: nil, organization: nil, vault: nil),
             refrigerationSurfaces: true, refrigerationTiles: false),
        Case(name: "refrigeration only", selection: FieldTradeResolver.resolve(
            explicit: ["refrigeration_hvac"], organization: nil, vault: nil),
             refrigerationSurfaces: true, refrigerationTiles: true),
        Case(name: "electrical only", selection: FieldTradeResolver.resolve(
            explicit: ["electrical"], organization: ["refrigeration_hvac"], vault: nil),
             refrigerationSurfaces: false, refrigerationTiles: false),
        Case(name: "both", selection: FieldTradeResolver.resolve(
            explicit: nil, organization: ["electrical", "refrigeration_hvac"], vault: nil),
             refrigerationSurfaces: true, refrigerationTiles: true),
        Case(name: "explicit empty", selection: FieldTradeResolver.resolve(
            explicit: [], organization: ["electrical"], vault: ["electrical"]),
             refrigerationSurfaces: true, refrigerationTiles: false),
    ]

    /// Every tool a field job declares, plus a general tool outside the profile.
    private var allTools: [String] { (FieldToolProfile.names.sorted() + ["get_news"]) }

    private let refrigerationTools = ["refrigerant_gauges", "domain_calc"]
    private let refrigerationTiles = ["fa-read-gauges", "fa-pt-lookup"]

    // MARK: - The matrix

    func testEverySurfaceFollowsTheResolution() {
        for c in cases {
            let trades = c.selection.trades

            // Tiles.
            let grid = Config.withFieldAssistActions([], active: true, trades: trades).map(\.id)
            for tile in refrigerationTiles {
                XCTAssertEqual(grid.contains(tile), c.refrigerationTiles, "\(c.name): tile \(tile)")
            }

            // Tools: out of a job, during one, and through the declaration filter.
            let outOfJob = FieldToolProfile.declaredNames(all: allTools, fieldJobActive: false, enabled: true,
                                                          activeTrades: trades)
            let inJob = FieldToolProfile.declaredNames(all: allTools, fieldJobActive: true, enabled: true,
                                                       activeTrades: trades)
            let declarable = ToolDeclarations.declarableNames(allTools, isEnabled: { _ in true }, hipaaMode: false,
                                                              hipaaDisabled: [], fieldJobActive: false,
                                                              fieldProfileEnabled: true, activeTrades: trades)
            for tool in refrigerationTools {
                XCTAssertEqual(outOfJob.contains(tool), c.refrigerationSurfaces, "\(c.name): \(tool) out of a job")
                XCTAssertEqual(inJob.contains(tool), c.refrigerationSurfaces, "\(c.name): \(tool) in a job")
                XCTAssertEqual(declarable.contains(tool), c.refrigerationSurfaces, "\(c.name): \(tool) declared")
                XCTAssertEqual(FieldTradeGate.redirect(forTool: tool, activeTrades: trades) != nil,
                               !c.refrigerationSurfaces, "\(c.name): \(tool) redirect")
            }

            // Settings.
            XCTAssertEqual(FieldTradeGate.isAvailable(.refrigerationHVAC, activeTrades: trades),
                           c.refrigerationSurfaces, "\(c.name): Refrigeration Units section")

            // The prompt's routing rule for the hidden trade.
            let rules = SystemPromptBuilder.routingRules(toolNames: outOfJob,
                                                         hiddenTrades: FieldTradeGate.hiddenTrades(activeTrades: trades))
            XCTAssertEqual(rules.contains(FieldTradeGate.redirectMessage(.refrigerationHVAC)),
                           !c.refrigerationSurfaces, "\(c.name): routing rule")
        }
    }

    /// The general job tools and tiles, and every untagged tool, are offered under every trade
    /// combination — the gate takes away only what `toolTrades` names.
    func testTheGeneralSetIsNeverGated() {
        let general = allTools.filter { FieldTradeGate.toolTrades[$0] == nil }
        let generalTiles = QuickAction.fieldAssistActions.map(\.id)
        let combinations: [[FieldTrade]] = [[], [.refrigerationHVAC], [.electrical], [.refrigerationHVAC, .electrical]]
        for trades in combinations {
            let offered = Set(FieldToolProfile.declaredNames(all: allTools, fieldJobActive: false, enabled: true,
                                                             activeTrades: trades))
            XCTAssertTrue(Set(general).isSubset(of: offered), "\(trades): \(Set(general).subtracting(offered))")
            for tool in ["safety_assessment", "photo_log", "manual_lookup", "deliver_report", "equipment_lookup",
                         "calculate", "convert_units"] {
                XCTAssertTrue(offered.contains(tool), "\(trades): \(tool)")
                XCTAssertNil(FieldTradeGate.redirect(forTool: tool, activeTrades: trades), tool)
            }
            let grid = Config.withFieldAssistActions([], active: true, trades: trades).map(\.id)
            XCTAssertEqual(Array(grid.prefix(generalTiles.count)), generalTiles, "\(trades): general tiles lead")
        }
    }

    func testOnlyTradeToolsAreTaggedAndTheyAreRegisteredTools() {
        XCTAssertEqual(Set(FieldTradeGate.toolTrades.keys), Set(refrigerationTools))
        for tool in FieldTradeGate.toolTrades.keys {
            XCTAssertTrue(FieldToolProfile.names.contains(tool), "\(tool) is a field tool")
        }
        XCTAssertNil(FieldTradeGate.requestPhrases(.electrical), "no electrical tool to redirect yet")
        XCTAssertEqual(SystemPromptBuilder.routingRules(toolNames: [], hiddenTrades: [.electrical]), "")
    }

    func testTheGateKeepsOrderAndChangesNothingWithoutATrade() {
        let names = ["zeta", "domain_calc", "alpha", "refrigerant_gauges"]
        XCTAssertEqual(FieldTradeGate.allowedToolNames(names, activeTrades: []), names)
        XCTAssertEqual(FieldTradeGate.allowedToolNames(names, activeTrades: [.electrical]), ["zeta", "alpha"])
        XCTAssertEqual(FieldToolProfile.declaredNames(all: names, fieldJobActive: false, enabled: false), names,
                       "the old call, with no trades, is the old answer")
    }

    // MARK: - The redirect at the router

    private final class ExecutionSpy { var count = 0 }

    private struct SpyTool: NativeTool {
        let name: String
        let description = "spy"
        let spy: ExecutionSpy
        var parametersSchema: [String: Any] { ["type": "object"] }
        func execute(args: [String: Any]) async throws -> String {
            spy.count += 1
            return "ran:\(name)"
        }
    }

    private func router(trades: [FieldTrade], spy: ExecutionSpy) -> NativeToolRouter {
        let registry = NativeToolRegistry(locationService: LocationService())
        for name in refrigerationTools + ["calculate"] { registry.register(SpyTool(name: name, spy: spy)) }
        let router = NativeToolRouter(registry: registry)
        router.activeTrades = { trades }
        return router
    }

    func testSuperheatAskedForUnderElectricalOnlyIsRedirected() async {
        let spy = ExecutionSpy()
        let electrical = router(trades: [.electrical], spy: spy)
        for tool in refrigerationTools {
            let outcome = await electrical.executeRoot(name: tool, args: ["operation": "superheat"])
            XCTAssertEqual(outcome, .rejected(reason:
                "That's a refrigeration tool. Turn on the Refrigeration trade in Field Assist settings to use it."), tool)
        }
        XCTAssertEqual(spy.count, 0, "a redirect that still executes is the bug")

        let general = await electrical.executeRoot(name: "calculate", args: [:])
        XCTAssertEqual(general.text, "ran:calculate")
    }

    func testWithNoTradeOrRefrigerationTheToolsRun() async {
        for trades in [[], [FieldTrade.refrigerationHVAC], [.refrigerationHVAC, .electrical]] {
            let spy = ExecutionSpy()
            let outcome = await router(trades: trades, spy: spy).executeRoot(name: "domain_calc", args: [:])
            XCTAssertEqual(outcome.text, "ran:domain_calc", "\(trades)")
            XCTAssertEqual(spy.count, 1)
        }
    }
}
