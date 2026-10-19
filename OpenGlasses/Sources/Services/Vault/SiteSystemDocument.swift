import Foundation

/// How the units at one site work together (Plan HV): which units are there, how they are
/// connected, which controller commands which, the systems outside the site they talk to, the
/// settings someone set on site, and the faults known to come from the link between two of them.
///
/// **An overlay, never a unit.** A site document refers to units by the model their own vault
/// section already uses; each unit keeps its own identity, specifications and manuals, and nothing
/// here changes how a unit is identified, scoped or recorded. It is chosen by the job (see
/// `SiteSystemMatcher`), not by the turn, and only the matched site's block is ever sent.
///
/// **Generic, not one trade's.** Connection and integration kinds are a small vocabulary — power,
/// control, communication, data, fluid, air, mechanical — and the trade's own words (refrigerant,
/// a fieldbus name, a line set's sizes) are free text, so the same shape serves heating, process
/// plant, a comms room, building services or a dairy shed.
///
/// **Untrusted input.** A vault is authored outside the phone. Every member is typed, closed and
/// bounded, every text is plain (no markup, no control characters, no links), and an unknown
/// member is refused rather than ignored — see `SiteSystemValidator`. The text is vault content:
/// it reaches a prompt only quoted as data, and never a log.
struct SiteSystemDocument: Codable, Equatable, Sendable {

    static let format = "avenkin.site-system"
    static let version = 1

    /// Another system's identifier for a site or a unit: which system, and its id there. Opaque —
    /// compared for equality and nothing else; never shown, never opened, never looked up.
    struct ExternalRef: Codable, Equatable, Hashable, Sendable {
        /// `[a-z0-9_-]{1,32}`, the same token a job file's `external.system` is.
        let system: String
        /// 1–128 printable ASCII characters, no spaces, never a link.
        let id: String
    }

    struct Unit: Codable, Equatable, Sendable {
        /// `[a-z0-9_-]{1,32}`, unique within the document; shares one namespace with integrations.
        let id: String
        /// The model spelling the unit's own vault section uses.
        let model: String
        let serial: String?
        /// Where the unit is at the site: "basement furnace".
        let label: String?
        /// False for an honest out-of-vault component (a thermostat with no section), which is how
        /// it is told apart from a typo. Absent means true.
        let covered: Bool?
        /// The unit's identifier in another system, matched against a job's
        /// `external.equipment_ids` of the same system.
        let externalIDs: [ExternalRef]?

        var isCovered: Bool { covered ?? true }
        /// What the unit is called wherever it is named: its label, else its model.
        var name: String { label ?? model }

        enum CodingKeys: String, CodingKey {
            case id, model, serial, label, covered
            case externalIDs = "external_ids"
        }
    }

    enum ConnectionKind: String, Codable, CaseIterable, Sendable {
        case power, control, communication, data, fluid, air, mechanical, other
    }

    enum ConnectionDirection: String, Codable, CaseIterable, Sendable {
        case oneWay = "one_way"
        case twoWay = "two_way"
    }

    struct Connection: Codable, Equatable, Sendable {
        let from: String
        let to: String
        let kind: ConnectionKind
        /// Refrigerant, water, steam, milk, compressed air.
        let medium: String?
        /// A fieldbus name, a serial bus, Ethernet, a wireless standard.
        let `protocol`: String?
        /// Absent means two-way.
        let direction: ConnectionDirection?
        let detail: String?
    }

    enum ControlMode: String, Codable, CaseIterable, Sendable {
        case communicating, conventional, other
    }

    struct Control: Codable, Equatable, Sendable {
        let controller: String
        let commands: [String]
        let mode: ControlMode
        let detail: String?
    }

    enum IntegrationKind: String, Codable, CaseIterable, Sendable {
        case bms, scada
        case cloudPortal = "cloud_portal"
        case networkManagement = "network_management"
        case businessApplication = "business_application"
        case metering, other

        /// How a line names the kind: "cloud portal", "BMS".
        var words: String {
            switch self {
            case .bms: return "BMS"
            case .scada: return "SCADA"
            default: return rawValue.replacingOccurrences(of: "_", with: " ")
            }
        }
    }

    enum IntegrationDirection: String, Codable, CaseIterable, Sendable {
        case inbound, outbound, both
    }

    /// A system outside the site the units talk to. Not a unit: no model, never the active unit,
    /// never in the unit ledger. A declared endpoint, so a connection or a fault may name it.
    struct Integration: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let kind: IntegrationKind
        let units: [String]
        let direction: IntegrationDirection?
        let `protocol`: String?
        let detail: String?
    }

    struct Setting: Codable, Equatable, Sendable {
        let unit: String
        let name: String
        let value: String
        let note: String?
    }

    struct InteractionFault: Codable, Equatable, Sendable {
        let seenOn: String
        let code: String?
        /// What the fault crosses: a declared unit or integration, or a connection kind.
        let link: String?
        let text: String

        enum CodingKeys: String, CodingKey {
            case seenOn = "seen_on"
            case code, link, text
        }
    }

    let format: String
    let version: Int
    let id: String
    let name: String
    let locationLabel: String?
    let externalLocationIDs: [ExternalRef]?
    let units: [Unit]
    let connections: [Connection]?
    let controls: [Control]?
    let integrations: [Integration]?
    let settings: [Setting]?
    let interactionFaults: [InteractionFault]?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case format, version, id, name
        case locationLabel = "location_label"
        case externalLocationIDs = "external_location_ids"
        case units, connections, controls, integrations, settings
        case interactionFaults = "interaction_faults"
        case notes
    }

    func unit(id: String) -> Unit? { units.first { $0.id == id } }
    func integration(id: String) -> Integration? { (integrations ?? []).first { $0.id == id } }

    /// What a line calls a declared unit or integration: the unit's label (else model) or the
    /// integration's name; the id itself when it names neither.
    func displayName(_ id: String) -> String {
        unit(id: id)?.name ?? integration(id: id)?.name ?? id
    }

    /// Decode a site file **already passed by `SiteSystemValidator`**. Nil for anything else; the
    /// validator, not this, is what says why.
    static func decode(_ data: Data) -> SiteSystemDocument? {
        try? JSONDecoder().decode(SiteSystemDocument.self, from: data)
    }
}

// MARK: - Validation

/// The site-document rules (Plan HV §2), over one file and then across a vault's files. Pure:
/// every input is handed in, so each rule is a test. Every finding is an issue — the vault does
/// not install — except a rendered block over its bound, which is a warning naming what clips.
enum SiteSystemValidator {

    /// Bounds, a document and a vault.
    static let maximumFileBytes = 8 * 1024
    static let maximumSiteDocuments = 100
    static let maximumUnits = 12
    static let maximumIntegrations = 8
    static let maximumConnections = 30
    static let maximumControls = 12
    static let maximumSettings = 30
    static let maximumInteractionFaults = 20
    static let maximumExternalIDs = 4
    static let maximumReferences = 12

    /// Length caps, in characters.
    static let nameLimit = 80
    static let labelLimit = 80
    static let modelLimit = 64
    static let serialLimit = 64
    static let mediumLimit = 40
    static let protocolLimit = 60
    static let detailLimit = 240
    static let codeLimit = 24
    static let faultTextLimit = 300
    static let settingNameLimit = 60
    static let settingValueLimit = 60
    static let settingNoteLimit = 160
    static let integrationDetailLimit = 300
    static let notesLimit = 600
    static let externalIdentifierLimit = 128

    /// Where site files live, relative to the vault root.
    static let directory = "sites/"

    static let documentMembers: Set<String> = [
        "format", "version", "id", "name", "location_label", "external_location_ids", "units",
        "connections", "controls", "integrations", "settings", "interaction_faults", "notes",
    ]
    static let unitMembers: Set<String> = ["id", "model", "serial", "label", "covered", "external_ids"]
    static let externalMembers: Set<String> = ["system", "id"]
    static let connectionMembers: Set<String> = ["from", "to", "kind", "medium", "protocol", "direction", "detail"]
    static let controlMembers: Set<String> = ["controller", "commands", "mode", "detail"]
    static let integrationMembers: Set<String> = ["id", "name", "kind", "units", "direction", "protocol", "detail"]
    static let settingMembers: Set<String> = ["unit", "name", "value", "note"]
    static let faultMembers: Set<String> = ["seen_on", "code", "link", "text"]

    /// Whether a model resolves to a section of this vault: `exact` or `alias` through
    /// `EquipmentRecognition.resolve` against the vault's own index. Handed in so the rule is the
    /// recogniser's and not a second copy of it.
    typealias ModelCovered = (String) -> Bool

    /// The model rule over a vault's own index.
    static func modelCovered(by index: VaultModelIndex) -> ModelCovered {
        { model in
            switch EquipmentRecognition.resolve(stated: model, index: index) {
            case .exact, .alias: return true
            case .near, .series, .unmatched: return false
            }
        }
    }

    /// One file's result: the document when it passed, and what is wrong or clips when it did not.
    struct FileResult {
        let document: SiteSystemDocument?
        let issues: [String]
        let warnings: [String]
    }

    // MARK: The listed paths

    /// The `sites` list itself: each a `sites/<id>.json` path, safe, listed once.
    static func pathIssues(_ paths: [String]) -> [String] {
        var issues: [String] = []
        if paths.count > maximumSiteDocuments {
            issues.append("sites lists \(paths.count) site documents; a vault may carry at most \(maximumSiteDocuments)")
        }
        var seen = Set<String>()
        for path in paths {
            if !seen.insert(path).inserted { issues.append("site document listed twice: \(path)") }
            if !isSitePath(path) {
                issues.append("site document must be a .json file directly inside sites/: \(path)")
            }
        }
        return issues
    }

    /// `sites/<name>.json`, one level, no traversal, no hidden file.
    static func isSitePath(_ path: String) -> Bool {
        guard path.hasPrefix(directory), path.lowercased().hasSuffix(".json") else { return false }
        let name = path.dropFirst(directory.count)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"),
              name.count <= 96 else { return false }
        return name.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
        } && name.unicodeScalars.allSatisfy(\.isASCII)
    }

    // MARK: One file

    /// Check one site file's bytes. `path` is how the file is named in every finding.
    static func check(_ data: Data, path: String, modelCovered: ModelCovered) -> FileResult {
        var issues: [String] = []
        func issue(_ text: String) { issues.append("\(path): \(text)") }

        guard data.count <= maximumFileBytes else {
            return FileResult(document: nil, issues: ["\(path): is \(data.count) bytes; a site document may be at most \(maximumFileBytes)"], warnings: [])
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return FileResult(document: nil, issues: ["\(path): is not valid JSON"], warnings: [])
        }
        if object is [Any] {
            // One file per site (decided 2026-10-20): a list of sites is several files.
            return FileResult(document: nil, issues: ["\(path): holds a list; a site file describes one site — write one file per site"], warnings: [])
        }
        guard let root = object as? [String: Any] else {
            return FileResult(document: nil, issues: ["\(path): is not a site document"], warnings: [])
        }
        checkMembers(root, allowed: documentMembers, in: "the document", issue: issue)

        if root["format"] as? String != SiteSystemDocument.format {
            issue("format must be \"\(SiteSystemDocument.format)\"")
        }
        if !isInteger(root["version"], equalTo: SiteSystemDocument.version) {
            issue("version must be \(SiteSystemDocument.version)")
        }
        let documentID = root["id"] as? String
        if let documentID {
            if !OfficeManualAssignment.safeIdentifier(documentID) {
                issue("id must be 1–80 letters, digits, '.', '-' or '_'")
            } else if path != "\(directory)\(documentID).json" {
                // One file per site, named for it, so a site's diff is its own file's.
                issue("a site document's file must be named for its id: \(directory)\(documentID).json")
            }
        } else {
            issue("id is missing")
        }
        text(root["name"], "name", limit: nameLimit, required: true, issue: issue)
        text(root["location_label"], "location_label", limit: labelLimit, issue: issue)
        externalRefs(root["external_location_ids"], "external_location_ids", issue: issue)
        text(root["notes"], "notes", limit: notesLimit, issue: issue)

        // Units, then integrations: one namespace of ids every reference below is checked against.
        var unitIDs: [String] = []
        var serials = Set<String>()
        let units = list(root["units"], "units", limit: maximumUnits, required: true, issue: issue)
        for (index, entry) in units.enumerated() {
            let at = "units[\(index)]"
            guard let unit = entry as? [String: Any] else { issue("\(at) is not an object"); continue }
            if unit["vault"] != nil || unit["vault_id"] != nil {
                // No unit references across vaults in v1 (decided 2026-10-20).
                issue("\(at) names another vault; a site document names only units in its own vault or on the job — mark a unit this vault has no section for \"covered\": false")
            }
            checkMembers(unit, allowed: unitMembers, in: at, reported: ["vault", "vault_id"], issue: issue)
            let id = token(unit["id"], "\(at).id", issue: issue)
            if let id {
                if unitIDs.contains(id) { issue("unit id '\(id)' is used twice") }
                unitIDs.append(id)
            }
            let model = text(unit["model"], "\(at).model", limit: modelLimit, required: true, issue: issue)
            if let serial = text(unit["serial"], "\(at).serial", limit: serialLimit, issue: issue) {
                if !serials.insert(SiteSystemMatcher.normalisedSerial(serial)).inserted {
                    issue("serial '\(serial)' is given to two units")
                }
            }
            text(unit["label"], "\(at).label", limit: labelLimit, issue: issue)
            var covered = true
            if let raw = unit["covered"] {
                if let flag = boolean(raw) { covered = flag } else { issue("\(at).covered must be true or false") }
            }
            externalRefs(unit["external_ids"], "\(at).external_ids", issue: issue)
            if let model, covered, !modelCovered(model) {
                issue("unit '\(id ?? at)' model '\(model)' is not a model this vault has a section for; fix the spelling, or mark it \"covered\": false if it is a component the vault does not cover")
            }
        }

        var integrationIDs: [String] = []
        let integrations = list(root["integrations"], "integrations", limit: maximumIntegrations, issue: issue)
        for (index, entry) in integrations.enumerated() {
            let at = "integrations[\(index)]"
            guard let integration = entry as? [String: Any] else { issue("\(at) is not an object"); continue }
            checkMembers(integration, allowed: integrationMembers, in: at, issue: issue)
            if let id = token(integration["id"], "\(at).id", issue: issue) {
                if unitIDs.contains(id) || integrationIDs.contains(id) {
                    issue("id '\(id)' is used twice; units and integrations share one set of ids")
                }
                integrationIDs.append(id)
            }
            text(integration["name"], "\(at).name", limit: nameLimit, required: true, issue: issue)
            enumValue(integration["kind"], "\(at).kind", SiteSystemDocument.IntegrationKind.self, required: true, issue: issue)
            for unit in references(integration["units"], "\(at).units", issue: issue) where !unitIDs.contains(unit) {
                issue("\(at).units names '\(unit)', which is not a declared unit")
            }
            enumValue(integration["direction"], "\(at).direction", SiteSystemDocument.IntegrationDirection.self, issue: issue)
            text(integration["protocol"], "\(at).protocol", limit: protocolLimit, issue: issue)
            text(integration["detail"], "\(at).detail", limit: integrationDetailLimit, issue: issue)
        }
        let endpoints = Set(unitIDs + integrationIDs)
        let declaredUnits = Set(unitIDs)

        for (index, entry) in list(root["connections"], "connections", limit: maximumConnections, issue: issue).enumerated() {
            let at = "connections[\(index)]"
            guard let connection = entry as? [String: Any] else { issue("\(at) is not an object"); continue }
            checkMembers(connection, allowed: connectionMembers, in: at, issue: issue)
            let from = token(connection["from"], "\(at).from", issue: issue)
            let to = token(connection["to"], "\(at).to", issue: issue)
            for (end, value) in [("from", from), ("to", to)] {
                if let value, !endpoints.contains(value) {
                    issue("\(at).\(end) names '\(value)', which is not a declared unit or integration")
                }
            }
            if let from, let to, from == to { issue("\(at) connects '\(from)' to itself") }
            enumValue(connection["kind"], "\(at).kind", SiteSystemDocument.ConnectionKind.self, required: true, issue: issue)
            text(connection["medium"], "\(at).medium", limit: mediumLimit, issue: issue)
            text(connection["protocol"], "\(at).protocol", limit: protocolLimit, issue: issue)
            enumValue(connection["direction"], "\(at).direction", SiteSystemDocument.ConnectionDirection.self, issue: issue)
            text(connection["detail"], "\(at).detail", limit: detailLimit, issue: issue)
        }

        for (index, entry) in list(root["controls"], "controls", limit: maximumControls, issue: issue).enumerated() {
            let at = "controls[\(index)]"
            guard let control = entry as? [String: Any] else { issue("\(at) is not an object"); continue }
            checkMembers(control, allowed: controlMembers, in: at, issue: issue)
            let controller = token(control["controller"], "\(at).controller", issue: issue)
            if let controller, !declaredUnits.contains(controller) {
                issue("\(at).controller names '\(controller)', which is not a declared unit")
            }
            let commanded = references(control["commands"], "\(at).commands", issue: issue)
            if control["commands"] != nil, commanded.isEmpty { issue("\(at).commands names no unit") }
            if control["commands"] == nil { issue("\(at).commands is missing") }
            for unit in commanded {
                if !declaredUnits.contains(unit) { issue("\(at).commands names '\(unit)', which is not a declared unit") }
                if unit == controller { issue("\(at) has '\(unit)' commanding itself") }
            }
            enumValue(control["mode"], "\(at).mode", SiteSystemDocument.ControlMode.self, required: true, issue: issue)
            text(control["detail"], "\(at).detail", limit: detailLimit, issue: issue)
        }

        for (index, entry) in list(root["settings"], "settings", limit: maximumSettings, issue: issue).enumerated() {
            let at = "settings[\(index)]"
            guard let setting = entry as? [String: Any] else { issue("\(at) is not an object"); continue }
            checkMembers(setting, allowed: settingMembers, in: at, issue: issue)
            if let unit = token(setting["unit"], "\(at).unit", issue: issue), !declaredUnits.contains(unit) {
                issue("\(at).unit names '\(unit)', which is not a declared unit")
            }
            text(setting["name"], "\(at).name", limit: settingNameLimit, required: true, issue: issue)
            text(setting["value"], "\(at).value", limit: settingValueLimit, required: true, issue: issue)
            text(setting["note"], "\(at).note", limit: settingNoteLimit, issue: issue)
        }

        let linkWords = Set(SiteSystemDocument.ConnectionKind.allCases.map(\.rawValue))
        for (index, entry) in list(root["interaction_faults"], "interaction_faults", limit: maximumInteractionFaults, issue: issue).enumerated() {
            let at = "interaction_faults[\(index)]"
            guard let fault = entry as? [String: Any] else { issue("\(at) is not an object"); continue }
            checkMembers(fault, allowed: faultMembers, in: at, issue: issue)
            if let seen = token(fault["seen_on"], "\(at).seen_on", issue: issue), !declaredUnits.contains(seen) {
                issue("\(at).seen_on names '\(seen)', which is not a declared unit")
            }
            text(fault["code"], "\(at).code", limit: codeLimit, issue: issue)
            if let link = token(fault["link"], "\(at).link", required: false, issue: issue),
               !endpoints.contains(link), !linkWords.contains(link) {
                issue("\(at).link names '\(link)', which is not a declared unit, a declared integration or a connection kind")
            }
            text(fault["text"], "\(at).text", limit: faultTextLimit, required: true, issue: issue)
        }

        guard issues.isEmpty, let document = SiteSystemDocument.decode(data) else {
            if issues.isEmpty { issue("does not decode to a site document") }
            return FileResult(document: nil, issues: issues, warnings: [])
        }
        return FileResult(document: document, issues: [], warnings: renderWarnings(document, path: path))
    }

    /// The bound the model's block is held to (`SiteSystemContract.characterLimit`) is not a
    /// refusal: a long document still installs, and its full text answers `equipment_lookup`. The
    /// author is told what the session block will leave out.
    static func renderWarnings(_ document: SiteSystemDocument, path: String) -> [String] {
        let clipped = SiteSystemContract.clipped(document)
        guard !clipped.isEmpty else { return [] }
        return ["\(path): the session's site block is held to \(SiteSystemContract.characterLimit) characters, so it will leave out \(clipped.joined(separator: ", ")); equipment_lookup's 'site system' still returns all of it"]
    }

    // MARK: Across a vault

    /// One serial is one unit in one place; one site id, one location and one unit identifier in
    /// another system name one site. Checked over every document that passed on its own.
    static func crossDocumentIssues(_ documents: [(path: String, document: SiteSystemDocument)]) -> [String] {
        var issues: [String] = []
        var ids: [String: String] = [:]
        var serials: [String: String] = [:]
        var locations: [SiteSystemDocument.ExternalRef: String] = [:]
        var unitRefs: [SiteSystemDocument.ExternalRef: String] = [:]
        for (path, document) in documents {
            if let other = ids[document.id] { issues.append("\(path): site id '\(document.id)' is also used by \(other)") }
            ids[document.id] = ids[document.id] ?? path
            for unit in document.units {
                if let serial = unit.serial {
                    let key = SiteSystemMatcher.normalisedSerial(serial)
                    if let other = serials[key], other != path {
                        issues.append("\(path): serial '\(serial)' is also listed in \(other); one serial is one unit in one place")
                    }
                    serials[key] = serials[key] ?? path
                }
                for ref in unit.externalIDs ?? [] {
                    if let other = unitRefs[ref] {
                        issues.append("\(path): unit identifier \(ref.system) '\(ref.id)' is also given to a unit in \(other)")
                    }
                    unitRefs[ref] = unitRefs[ref] ?? path
                }
            }
            for ref in document.externalLocationIDs ?? [] {
                if let other = locations[ref] {
                    issues.append("\(path): location \(ref.system) '\(ref.id)' is also given to \(other)")
                }
                locations[ref] = locations[ref] ?? path
            }
        }
        return issues
    }

    // MARK: Values

    private static func checkMembers(_ object: [String: Any], allowed: Set<String>, in place: String,
                                     reported: Set<String> = [], issue: (String) -> Void) {
        for key in object.keys.sorted() where !allowed.contains(key) && !reported.contains(key) {
            issue("\(place) has an unknown member '\(key)'")
        }
    }

    private static func list(_ value: Any?, _ name: String, limit: Int, required: Bool = false,
                             issue: (String) -> Void) -> [Any] {
        guard let value else {
            if required { issue("\(name) is missing") }
            return []
        }
        guard let items = value as? [Any] else { issue("\(name) must be a list"); return [] }
        if required, items.isEmpty { issue("\(name) is empty") }
        if items.count > limit { issue("\(name) has \(items.count) entries; at most \(limit)") }
        return Array(items.prefix(limit))
    }

    /// `[a-z0-9_-]{1,32}`, as a job file's tokens.
    @discardableResult
    private static func token(_ value: Any?, _ name: String, required: Bool = true,
                              issue: (String) -> Void) -> String? {
        guard let value else {
            if required { issue("\(name) is missing") }
            return nil
        }
        guard let text = value as? String, JobFileFormat3Validator.isToken(text) else {
            issue("\(name) must be 1–32 lowercase letters, digits, '-' or '_'")
            return nil
        }
        return text
    }

    private static func references(_ value: Any?, _ name: String, issue: (String) -> Void) -> [String] {
        guard let value else { return [] }
        guard let items = value as? [Any] else { issue("\(name) must be a list"); return [] }
        if items.count > maximumReferences { issue("\(name) has \(items.count) entries; at most \(maximumReferences)") }
        var seen = Set<String>()
        return items.prefix(maximumReferences).compactMap { item in
            guard let id = token(item, name, issue: issue) else { return nil }
            if !seen.insert(id).inserted { issue("\(name) names '\(id)' twice") }
            return id
        }
    }

    private static func externalRefs(_ value: Any?, _ name: String, issue: (String) -> Void) {
        guard let value else { return }
        guard let items = value as? [Any] else { issue("\(name) must be a list of {system, id}"); return }
        if items.count > maximumExternalIDs { issue("\(name) has \(items.count) entries; at most \(maximumExternalIDs)") }
        var seen = Set<SiteSystemDocument.ExternalRef>()
        var systems = Set<String>()
        for (index, item) in items.enumerated() {
            let at = "\(name)[\(index)]"
            guard let ref = item as? [String: Any] else {
                // The survey's standard (decided 2026-10-20): an identifier always says whose it is.
                issue("\(at) must be {\"system\": …, \"id\": …}, naming the system the identifier belongs to")
                continue
            }
            checkMembers(ref, allowed: externalMembers, in: at, issue: issue)
            let system = token(ref["system"], "\(at).system", issue: issue)
            var id: String?
            if let raw = ref["id"] as? String, !raw.isEmpty, raw.utf8.count <= externalIdentifierLimit,
               raw.utf8.allSatisfy({ (0x21...0x7E).contains($0) }), !raw.contains("://") {
                id = raw
            } else {
                issue("\(at).id must be 1–\(externalIdentifierLimit) printable characters with no spaces and no link")
            }
            if let system, let id {
                if !seen.insert(.init(system: system, id: id)).inserted { issue("\(at) is listed twice") }
                if !systems.insert(system).inserted, name.hasSuffix("external_ids") {
                    issue("\(at): a unit has one identifier per system")
                }
            }
        }
    }

    private static func enumValue<E: RawRepresentable & CaseIterable>(_ value: Any?, _ name: String, _ type: E.Type,
                                                                       required: Bool = false,
                                                                       issue: (String) -> Void) where E.RawValue == String {
        guard let value else {
            if required { issue("\(name) is missing") }
            return
        }
        // An unknown kind is refused, so a typo is never quietly `other`.
        guard let raw = value as? String, E(rawValue: raw) != nil else {
            let allowed = E.allCases.map(\.rawValue).joined(separator: ", ")
            issue("\(name) must be one of: \(allowed)")
            return
        }
    }

    /// Plain text under the job file's rules: not blank, within its limit, no markup, no control
    /// characters — and never a link, which nothing in a site document has a reason to carry.
    @discardableResult
    private static func text(_ value: Any?, _ name: String, limit: Int, required: Bool = false,
                             issue: (String) -> Void) -> String? {
        guard let value else {
            if required { issue("\(name) is missing") }
            return nil
        }
        guard let text = value as? String else { issue("\(name) must be text"); return nil }
        guard JobSite.cleaned(text) != nil else { issue("\(name) is blank"); return nil }
        if text.count > limit { issue("\(name) is \(text.count) characters; at most \(limit)") }
        if JobFileValidator.containsMarkup(text) { issue("\(name) contains markup; site documents are plain text") }
        if text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            issue("\(name) contains a line break or control character; site documents are plain text")
        }
        if text.lowercased().contains("://") || text.lowercased().contains("www.") {
            issue("\(name) contains a link; site documents carry no links")
        }
        return text
    }

    private static func boolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func isInteger(_ value: Any?, equalTo expected: Int) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number.doubleValue == Double(expected)
    }
}
