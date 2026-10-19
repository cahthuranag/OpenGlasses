import UIKit
import XCTest
@testable import OpenGlasses

/// Field Assist trade presets (Plan IS): which trades are active and why, the tiles a trade adds to
/// the Field Assist grid, and the three places a trade can come from — the technician, the
/// organisation profile and the vault manifest. All pure or on a private `UserDefaults` suite.
@MainActor
final class FieldTradePresetTests: XCTestCase {

    // MARK: - The resolver

    func testTheTechniciansChoiceBeatsTheOrganisationWhichBeatsTheVault() {
        let all = FieldTradeResolver.resolve(explicit: ["electrical"], organization: ["refrigeration_hvac"],
                                             vault: ["refrigeration_hvac", "electrical"])
        XCTAssertEqual(all, FieldTradeSelection(trades: [.electrical], source: .technician))

        let noChoice = FieldTradeResolver.resolve(explicit: nil, organization: ["refrigeration_hvac"],
                                                  vault: ["electrical"])
        XCTAssertEqual(noChoice, FieldTradeSelection(trades: [.refrigerationHVAC], source: .organization))

        let vaultOnly = FieldTradeResolver.resolve(explicit: nil, organization: nil, vault: ["electrical"])
        XCTAssertEqual(vaultOnly, FieldTradeSelection(trades: [.electrical], source: .vault))

        XCTAssertEqual(FieldTradeResolver.resolve(explicit: nil, organization: nil, vault: nil), .none)
        XCTAssertTrue(FieldTradeSelection.none.trades.isEmpty)
    }

    func testAnEmptyChoiceIsAChoiceNotUnset() {
        let none = FieldTradeResolver.resolve(explicit: [], organization: ["refrigeration_hvac"],
                                              vault: ["refrigeration_hvac"])
        XCTAssertEqual(none, FieldTradeSelection(trades: [], source: .technician),
                       "a technician who switched every trade off is not handed the organisation's")
        let orgNone = FieldTradeResolver.resolve(explicit: nil, organization: [], vault: ["refrigeration_hvac"])
        XCTAssertEqual(orgNone, FieldTradeSelection(trades: [], source: .organization))
    }

    func testUnknownTradesAreIgnoredAndKnownOnesComeOnceInOrder() {
        XCTAssertEqual(FieldTrade.known(["plumbing", " Electrical ", "refrigeration_hvac", "electrical"]),
                       [.refrigerationHVAC, .electrical])
        XCTAssertEqual(FieldTradeResolver.resolve(explicit: nil, organization: nil, vault: ["plumbing"]),
                       FieldTradeSelection(trades: [], source: .vault),
                       "an unknown value is ignored, not a reason to fall through")
    }

    // MARK: - Storage

    private func suite() -> UserDefaults {
        let name = "FieldTradePresetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testTheStoredChoiceKeepsNoneApartFromUnset() {
        let defaults = suite()
        XCTAssertNil(FieldTradeSetting.explicitChoice(defaults))

        FieldTradeSetting.setExplicitChoice([], defaults)
        XCTAssertEqual(FieldTradeSetting.explicitChoice(defaults), [])
        XCTAssertEqual(defaults.string(forKey: FieldTradeSetting.key), "")

        FieldTradeSetting.setExplicitChoice([.electrical, .refrigerationHVAC], defaults)
        XCTAssertEqual(defaults.string(forKey: FieldTradeSetting.key), "refrigeration_hvac,electrical")
        XCTAssertEqual(FieldTrade.known(FieldTradeSetting.explicitChoice(defaults) ?? []),
                       [.refrigerationHVAC, .electrical])

        FieldTradeSetting.setExplicitChoice(nil, defaults)
        XCTAssertNil(FieldTradeSetting.explicitChoice(defaults))
    }

    func testTheOrganisationDefaultLivesUnderItsOwnKey() {
        let defaults = suite()
        XCTAssertNotEqual(FieldTradeSetting.organizationKey, FieldTradeSetting.key)
        defaults.set(["refrigeration_hvac"], forKey: FieldTradeSetting.organizationKey)
        XCTAssertEqual(FieldTradeSetting.organizationDefault(defaults), ["refrigeration_hvac"])
        XCTAssertNil(FieldTradeSetting.explicitChoice(defaults), "the profile never writes the technician's choice")
    }

    /// The bundled vaults declare no trade: the refrigeration vault is every install's default, so
    /// declaring one there would put the gauge tiles on nearly every grid.
    func testNoBuiltInVaultDeclaresATrade() {
        for id in ["refrigeration", "it_network", "health"] {
            XCTAssertNotNil(VaultRegistry.builtInManifest(id: id), id)
            XCTAssertNil(FieldTradeSetting.vaultDeclaredTrades(vaultId: id), id)
        }
        XCTAssertNil(VaultImporter.installedManifest(id: "../escape"), "an id is never a path")
    }

    // MARK: - The tiles on the grid

    private let mine = QuickAction(id: "mine", label: "Mine", icon: "star", type: .prompt, promptText: "Hello")

    private func ids(_ actions: [QuickAction]) -> [String] { actions.map(\.id) }

    func testTheRefrigerationTilesFollowTheJobTilesOnlyWhileFieldAssistIsActiveAndTheTradeIsOn() {
        let general = ids(QuickAction.fieldAssistActions)
        let both = Config.withFieldAssistActions([mine], active: true, trades: [.refrigerationHVAC])
        XCTAssertEqual(ids(both), general + ["fa-read-gauges", "fa-pt-lookup", "mine"])

        let noTrade = Config.withFieldAssistActions([mine], active: true, trades: [])
        XCTAssertEqual(ids(noTrade), general + ["mine"], "no trade is exactly the grid before trades")

        let inactive = Config.withFieldAssistActions([mine], active: false, trades: [.refrigerationHVAC])
        XCTAssertEqual(ids(inactive), ["mine"])
    }

    func testTheElectricalPresetAddsNoTilesYet() {
        XCTAssertTrue(QuickAction.tradeActions(for: .electrical).isEmpty)
        XCTAssertEqual(ids(Config.withFieldAssistActions([mine], active: true, trades: [.electrical])),
                       ids(QuickAction.fieldAssistActions) + ["mine"])
    }

    func testStaleCopiesAreStrippedWhenFieldAssistOrTheTradeGoes() {
        // A list that somehow holds copies of every injected tile, as an old build or a save might.
        let stale = QuickAction.fieldAssistManagedActions + [mine]
        XCTAssertEqual(ids(Config.withFieldAssistActions(stale, active: false, trades: [.refrigerationHVAC])), ["mine"])
        let tradeOff = Config.withFieldAssistActions(stale, active: true, trades: [])
        XCTAssertFalse(tradeOff.contains { $0.id == "fa-read-gauges" || $0.id == "fa-pt-lookup" })
        XCTAssertEqual(Set(ids(tradeOff)).count, tradeOff.count, "nothing appears twice")
        let tradeOn = Config.withFieldAssistActions(stale, active: true, trades: [.refrigerationHVAC])
        XCTAssertEqual(tradeOn.filter { $0.id == "fa-read-gauges" }.count, 1)
    }

    func testTradeTilesAreNeverPersistedOrEditable() {
        let injected = Config.withFieldAssistActions([mine], active: true, trades: [.refrigerationHVAC])
        let saved = SpeedDialEditor.applying(HomeActionDraft(name: "New", prompt: "Say hi"), to: injected)
        XCTAssertFalse(saved.contains { QuickAction.refrigerationTradeActions.map(\.id).contains($0.id) },
                       "a save never writes a trade tile back")
        for tile in QuickAction.refrigerationTradeActions {
            XCTAssertTrue(SpeedDialEditor.managedIds.contains(tile.id), tile.id)
            XCTAssertFalse(SpeedDialEditor.isEditable(tile), tile.id)
            XCTAssertTrue(DockSlot.action(.quickAction(tile)).leadsWhenUnplaced, tile.id)
        }
        XCTAssertFalse(QuickAction.defaults.contains { $0.id.hasPrefix("fa-") })
    }

    /// The real read path: copies stored under `quickActions` never come back out on their own, and
    /// reading never writes one in.
    func testTheStoredListNeverCarriesATradeTile() throws {
        try XCTSkipIf(Config.fieldAssistActive, "needs Field Assist off, as on a test runner")
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: "quickActions")
        defer { defaults.set(original, forKey: "quickActions") }

        Config.setQuickActions([mine] + QuickAction.refrigerationTradeActions)
        XCTAssertFalse(Config.quickActions.contains { $0.id == "fa-read-gauges" || $0.id == "fa-pt-lookup" })

        Config.setQuickActions([mine])
        _ = Config.quickActions
        let stored = try JSONDecoder().decode([QuickAction].self,
                                              from: try XCTUnwrap(defaults.data(forKey: "quickActions")))
        XCTAssertFalse(stored.contains { $0.id.hasPrefix("fa-") })
    }

    // MARK: - What the tiles ask for

    func testReadGaugesCallsTheGaugeReaderAndAllowsVoice() throws {
        let tile = try XCTUnwrap(QuickAction.refrigerationTradeActions.first { $0.id == "fa-read-gauges" })
        XCTAssertEqual(tile.label, "Read Gauges")
        XCTAssertEqual(tile.type, .prompt)
        let prompt = try XCTUnwrap(tile.promptText)
        XCTAssertTrue(prompt.contains("refrigerant_gauges"), prompt)
        XCTAssertTrue(prompt.contains("superheat") && prompt.contains("subcooling"), prompt)
        XCTAssertTrue(prompt.contains("ask me"), prompt)
        XCTAssertTrue(prompt.contains("domain_calc"), "the voice way on when no picture can be taken: \(prompt)")
    }

    func testPTLookupAsksThenUsesDomainCalc() throws {
        let tile = try XCTUnwrap(QuickAction.refrigerationTradeActions.first { $0.id == "fa-pt-lookup" })
        XCTAssertEqual(tile.label, "P-T Lookup")
        XCTAssertEqual(tile.type, .prompt)
        let prompt = try XCTUnwrap(tile.promptText)
        XCTAssertTrue(prompt.contains("domain_calc") && prompt.contains("pt_lookup"), prompt)
        XCTAssertTrue(prompt.contains("refrigerant"), prompt)
    }

    func testTheTileIconsExist() {
        for tile in QuickAction.refrigerationTradeActions {
            XCTAssertNotNil(UIImage(systemName: tile.icon), tile.icon)
        }
    }

    /// Without glasses, Read Gauges opens the phone camera on the gauges' framing hint before its
    /// prompt; `refrigerant_gauges` then takes that staged photo. P-T Lookup needs no camera.
    func testReadGaugesOpensThePhoneCameraFirstWithoutGlasses() {
        XCTAssertEqual(PhoneCapturePolicy.preCaptureHint(forQuickAction: "fa-read-gauges", glassesConnected: false),
                       PhoneCapturePolicy.framingHint(forTool: "refrigerant_gauges"))
        XCTAssertNil(PhoneCapturePolicy.preCaptureHint(forQuickAction: "fa-read-gauges", glassesConnected: true))
        XCTAssertNil(PhoneCapturePolicy.preCaptureHint(forQuickAction: "fa-pt-lookup", glassesConnected: false))
        XCTAssertEqual(PhoneCapturePolicy.route(forTool: "refrigerant_gauges"), .askOnPhone)
    }

    // MARK: - The vault manifest

    private func manifest(_ extra: String) throws -> VaultManifest {
        let json = #"{"id":"acme","name":"Acme","version":"1.0.0","files":["a.md"]"# + extra + "}"
        return try JSONDecoder().decode(VaultManifest.self, from: Data(json.utf8))
    }

    func testAManifestDeclaresTradesAndUnknownOnesAreIgnored() throws {
        let declared = try manifest(#","trades":["refrigeration_hvac","plumbing"]"#)
        XCTAssertEqual(declared.trades, ["refrigeration_hvac", "plumbing"], "kept as written, for an export")
        XCTAssertEqual(FieldTrade.known(declared.trades ?? []), [.refrigerationHVAC])

        XCTAssertNil(try manifest("").trades, "absent means the vault says nothing")
        XCTAssertEqual(try manifest(#","trades":[]"#).trades, [])
        XCTAssertNil(try manifest(#","trades":"refrigeration_hvac""#).trades,
                     "a malformed list is ignored, never a refused manifest")
    }

    func testTradesSurviveEncodingAndAManualRemoval() throws {
        let declared = try manifest(#","trades":["electrical"]"#)
        let again = try JSONDecoder().decode(VaultManifest.self, from: try JSONEncoder().encode(declared))
        XCTAssertEqual(again.trades, ["electrical"])
        XCTAssertEqual(VaultManualRemoval.reducedManifest(declared, removing: "x.pdf").trades, ["electrical"])
        XCTAssertEqual(declared.markingDocumentsNotIncluded().trades, ["electrical"])

        let plain = try manifest("")
        let encoded = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(encoded.contains("trades"), "a manifest without trades encodes as it always did")
    }

    // MARK: - The organisation profile

    private func applyProfile(_ value: ProfileValue) -> ProfileApplier.Result {
        let profile = ConfigProfile(keyId: "test-key", profileId: "p", organizationName: "Northbridge Mechanical",
                                    issued: Date(timeIntervalSince1970: 1_790_000_000), leaseDays: 30,
                                    eraseAfterLapseDays: nil, undeliveredEraseDays: nil,
                                    settings: ["fieldAssistDefaultTrades": RawSetting(value, .default)])
        return ProfileApplier.apply(profile: profile, resolvableVaultIds: [])
    }

    func testTheOrganisationKeyIsAStartingListTheTechnicianMayChange() {
        XCTAssertEqual(SettingKey.fieldAssistDefaultTrades.kind, .startingValue(.strings))
        XCTAssertEqual(SettingKey.fieldAssistDefaultTrades.rawValue, FieldTradeSetting.organizationKey)

        let offered = applyProfile(.strings(["refrigeration_hvac"]))
        XCTAssertEqual(offered.startingValues[.fieldAssistDefaultTrades], .strings(["refrigeration_hvac"]))
        XCTAssertFalse(offered.isLocked(.fieldAssistDefaultTrades))
        XCTAssertTrue(offered.drops.isEmpty)

        XCTAssertEqual(applyProfile(.strings([])).startingValues[.fieldAssistDefaultTrades], .strings([]),
                       "an organisation may start its phones with no trade")
        XCTAssertNotNil(applyProfile(.strings(["refrigeration_hvac", "plumbing"])).startingValues[.fieldAssistDefaultTrades],
                        "a list naming a known trade keeps it")
    }

    func testAnOrganisationListNamingNoKnownTradeIsANamedDrop() {
        let unknown = applyProfile(.strings(["plumbing"]))
        XCTAssertNil(unknown.startingValues[.fieldAssistDefaultTrades])
        XCTAssertEqual(unknown.drops.map(\.key), ["fieldAssistDefaultTrades"])
        let wrongType = applyProfile(.string("refrigeration_hvac"))
        XCTAssertEqual(wrongType.drops, [.init(key: "fieldAssistDefaultTrades", reason: .wrongType(expected: .strings))])
    }

    func testTheReviewLineSaysWhichTilesItStartsWith() {
        let key = SettingKey.fieldAssistDefaultTrades
        XCTAssertEqual(key.startingValueDescription(.strings(["refrigeration_hvac"])),
                       "Field Assist starts with the Refrigeration & HVAC tiles")
        XCTAssertEqual(key.startingValueDescription(.strings(["refrigeration_hvac", "electrical"])),
                       "Field Assist starts with the Refrigeration & HVAC and Electrical tiles")
        XCTAssertEqual(key.startingValueDescription(.strings([])), "Field Assist starts with no trade tiles")
    }

    func testTheProfileWriterKnowsTheKeyAndTheTrades() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("Scripts/make-org-profile.swift"), encoding: .utf8)
        XCTAssertTrue(script.contains(#""fieldAssistDefaultTrades": "default:strings""#))
        let line = try XCTUnwrap(script.components(separatedBy: "let knownTrades: Set<String> = ").dropFirst().first)
        let list = String(line.prefix { $0 != "]" })
        let names = list.components(separatedBy: "\"").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        XCTAssertEqual(Set(names), Set(FieldTrade.allCases.map(\.rawValue)))
    }
}
