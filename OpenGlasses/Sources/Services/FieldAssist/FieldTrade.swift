import Foundation

/// A trade a Field Assist technician works in. A trade brings its own quick-action tiles to the
/// Field Assist grid (`QuickAction.tradeActions(for:)`), after the general job tiles, so a tile only
/// one trade uses — reading refrigerant gauges — is not on every technician's grid.
///
/// The raw value is what a vault manifest's `trades` array, the technician's stored choice and an
/// organisation profile's `fieldAssistDefaultTrades` say. Add a trade by adding a case; a value
/// this build does not know is ignored wherever it is read, never an error.
enum FieldTrade: String, CaseIterable, Identifiable, Sendable {
    case refrigerationHVAC = "refrigeration_hvac"
    case electrical

    var id: String { rawValue }

    /// The name on the Settings toggle.
    var title: String {
        switch self {
        case .refrigerationHVAC: return String(localized: "Refrigeration & HVAC")
        case .electrical: return String(localized: "Electrical")
        }
    }

    /// The known trades among `raw`, once each, in `allCases` order. Unknown values are dropped:
    /// a vault or a profile written for a newer build still gives this one what it understands.
    static func known(_ raw: [String]) -> [FieldTrade] {
        let named = Set(raw.compactMap { FieldTrade(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) })
        return allCases.filter(named.contains)
    }
}

/// Which trades are active and where that came from.
struct FieldTradeSelection: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// The technician chose in Settings › Field Assist (possibly none).
        case technician
        /// The organisation profile's starting value.
        case organization
        /// The trades the default vault's manifest declares.
        case vault
        /// Nothing says: the general job tiles only, as before trades existed.
        case none
    }

    let trades: [FieldTrade]
    let source: Source

    static let none = FieldTradeSelection(trades: [], source: .none)

    func contains(_ trade: FieldTrade) -> Bool { trades.contains(trade) }
}

/// The active trades, by precedence. Pure.
///
/// 1. The technician's explicit choice. An empty choice is a choice — "no trade" — and is not read
///    as unset, so a technician who switched every trade off is not handed the vault's again.
/// 2. Else the organisation profile's default.
/// 3. Else the trades the active vault's manifest declares.
/// 4. Else none.
///
/// `nil` means "says nothing"; an empty array means "says none". Unknown values in any layer are
/// ignored without the layer losing its place.
enum FieldTradeResolver {
    static func resolve(explicit: [String]?, organization: [String]?, vault: [String]?) -> FieldTradeSelection {
        if let explicit { return FieldTradeSelection(trades: FieldTrade.known(explicit), source: .technician) }
        if let organization { return FieldTradeSelection(trades: FieldTrade.known(organization), source: .organization) }
        if let vault { return FieldTradeSelection(trades: FieldTrade.known(vault), source: .vault) }
        return .none
    }
}

/// Where the three layers are stored, and the selection in force.
enum FieldTradeSetting {
    /// The technician's own choice: comma-separated raw values. Absent = no choice made; an empty
    /// string = the technician chose none. A string rather than an array so `@AppStorage` can bind it.
    nonisolated static let key = "fieldAssistTrades"

    /// The organisation profile's starting value (`SettingKey.fieldAssistDefaultTrades`), an array.
    /// Its own key, not the technician's: the technician's choice outranks it rather than
    /// overwriting it, and removing the profile puts back what was there before.
    nonisolated static var organizationKey: String { SettingKey.fieldAssistDefaultTrades.rawValue }

    nonisolated static func encode(_ trades: [FieldTrade]) -> String {
        FieldTrade.allCases.filter(trades.contains).map(\.rawValue).joined(separator: ",")
    }

    /// Decodes a stored choice. `nil` stays nil (no choice); `""` is an empty choice.
    nonisolated static func decode(_ stored: String?) -> [String]? {
        guard let stored else { return nil }
        return stored.split(separator: ",").map(String.init)
    }

    static func explicitChoice(_ defaults: UserDefaults = .standard) -> [String]? {
        decode(defaults.string(forKey: key))
    }

    static func setExplicitChoice(_ trades: [FieldTrade]?, _ defaults: UserDefaults = .standard) {
        if let trades {
            defaults.set(encode(trades), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func organizationDefault(_ defaults: UserDefaults = .standard) -> [String]? {
        defaults.stringArray(forKey: organizationKey)
    }

    /// The trades the vault Field Assist opens on declares, or nil when it declares none (or is
    /// not installed). The vault is the default one — the vault the Field Assist tile starts a
    /// job on — so the grid does not change shape mid-job.
    static func vaultDeclaredTrades(vaultId: String = Config.fieldAssistDefaultVaultId) -> [String]? {
        if let builtIn = VaultRegistry.builtInManifest(id: vaultId) { return builtIn.trades }
        return VaultImporter.installedManifest(id: vaultId)?.trades
    }

    /// The selection in force on this phone.
    static var current: FieldTradeSelection {
        let defaults = UserDefaults.standard
        let explicit = explicitChoice(defaults)
        let organization = explicit == nil ? organizationDefault(defaults) : nil
        // The vault's manifest is read only when nothing above it decides.
        let vault = explicit == nil && organization == nil ? vaultDeclaredTrades() : nil
        return FieldTradeResolver.resolve(explicit: explicit, organization: organization, vault: vault)
    }
}

/// What a trade gates beyond its tiles: the tools offered to the model and the trade's own Settings
/// sections. Pure, except `currentActiveTrades`.
///
/// - No trade resolved, or a resolved empty set (the technician, the organisation or the vault
///   chose none): everything is offered, as before trades existed. Only the trade tiles need a
///   trade; nothing else is taken away for not having one.
/// - One or more trades active: a trade-specific surface of a trade that is not active is hidden,
///   and a call that still reaches one is answered with `redirectMessage`.
/// - General job tools and tiles, and vault content, are never gated: only what `toolTrades`
///   names is.
enum FieldTradeGate {
    /// The tools that belong to one trade. `domain_calc` is here whole: every operation it has —
    /// `pt_lookup`, `superheat`, `subcool` — is refrigerant saturation math, so there is no general
    /// function to keep visible. General arithmetic is `calculate`/`convert_units`, never gated.
    static let toolTrades: [String: FieldTrade] = [
        "refrigerant_gauges": .refrigerationHVAC,
        "domain_calc": .refrigerationHVAC,
    ]

    /// Whether `trade`'s surfaces are offered under `activeTrades`.
    static func isAvailable(_ trade: FieldTrade, activeTrades: [FieldTrade]) -> Bool {
        activeTrades.isEmpty || activeTrades.contains(trade)
    }

    /// The trades whose surfaces are hidden: none until some trade is active.
    static func hiddenTrades(activeTrades: [FieldTrade]) -> [FieldTrade] {
        FieldTrade.allCases.filter { !isAvailable($0, activeTrades: activeTrades) }
    }

    /// `names` without the tools of hidden trades, order kept.
    static func allowedToolNames(_ names: [String], activeTrades: [FieldTrade]) -> [String] {
        guard !activeTrades.isEmpty else { return names }
        return names.filter { name in toolTrades[name].map { isAvailable($0, activeTrades: activeTrades) } ?? true }
    }

    /// The answer to a call that reaches a hidden trade's tool, or nil when the tool is offered.
    static func redirect(forTool name: String, activeTrades: [FieldTrade]) -> String? {
        guard let trade = toolTrades[name], !isAvailable(trade, activeTrades: activeTrades) else { return nil }
        return redirectMessage(trade)
    }

    static func redirectMessage(_ trade: FieldTrade) -> String {
        switch trade {
        case .refrigerationHVAC:
            return "That's a refrigeration tool. Turn on the Refrigeration trade in Field Assist settings to use it."
        case .electrical:
            return "That's an electrical tool. Turn on the Electrical trade in Field Assist settings to use it."
        }
    }

    /// What a hidden trade's requests sound like, for the prompt's routing rule: the model has no
    /// tool to reach for, and must say why rather than answer from its own knowledge.
    static func requestPhrases(_ trade: FieldTrade) -> String? {
        switch trade {
        case .refrigerationHVAC:
            return "superheat, subcooling, a pressure-temperature (P-T) lookup or reading refrigerant gauges"
        case .electrical:
            return nil   // No electrical tool exists yet (Plans IN and IR).
        }
    }

    /// The trades in force on this phone, for gating.
    static var currentActiveTrades: [FieldTrade] { FieldTradeSetting.current.trades }

    /// The hidden trades the prompt's routing rules name: only while Field Assist is on, since
    /// only then are the trade tools registered at all.
    static var promptHiddenTrades: [FieldTrade] {
        Config.fieldAssistActive ? hiddenTrades(activeTrades: currentActiveTrades) : []
    }
}
