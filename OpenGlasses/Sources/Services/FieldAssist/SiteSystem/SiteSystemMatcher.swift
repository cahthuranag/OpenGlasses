import Foundation

/// What a job knows that can say which documented site it is at (Plan HV §3): the serials on it,
/// the models it names, and — from a format-3 job file (Plan HT) — the other system's id for the
/// location and for each machine. Kept on the match, so a serial heard mid-job is weighed with
/// what the job ahead already said rather than instead of it.
///
/// Bounded and identifier-only: no site text, no customer detail, nothing a model wrote.
struct SiteSystemEvidence: Codable, Equatable, Sendable {
    /// Normalised (`SiteSystemMatcher.normalisedSerial`), de-duplicated.
    var serials: [String] = []
    /// As given, de-duplicated by their normalised form.
    var models: [String] = []
    /// The job file's `external.system` with each `external.equipment_ids` value — the id a
    /// machine is known by there, whether the job keys it by its `unit_key` or its serial.
    var equipmentIDs: [SiteSystemDocument.ExternalRef] = []
    /// The job file's `external.system` with its `external.location_id`.
    var location: SiteSystemDocument.ExternalRef?

    static let maximumEntries = 24

    var isEmpty: Bool { serials.isEmpty && models.isEmpty && equipmentIDs.isEmpty && location == nil }

    enum CodingKeys: String, CodingKey {
        case serials, models
        case equipmentIDs = "equipment_ids"
        case location
    }

    init(serials: [String] = [], models: [String] = [],
         equipmentIDs: [SiteSystemDocument.ExternalRef] = [], location: SiteSystemDocument.ExternalRef? = nil) {
        self.serials = []
        self.models = []
        self.equipmentIDs = []
        self.location = location
        add(serials: serials, models: models, equipmentIDs: equipmentIDs)
    }

    /// What a job ahead says: its machines' serials and models, and the job file's identifiers.
    init(job: UpcomingJob) {
        self.init(equipment: job.equipment, external: job.provenance?.external)
    }

    init(equipment: [KnownEquipment], external: ExternalJobReference?) {
        var ids: [SiteSystemDocument.ExternalRef] = []
        if let external, let map = external.equipmentIDs {
            // Keyed by each machine's `unit_key` when it has one, else its serial (HT, FX27 §6.2),
            // so a machine with no serial still reaches its id through its `unit_key`.
            for machine in equipment {
                guard let key = machine.unitKey ?? machine.serial, let id = map[key] else { continue }
                ids.append(.init(system: external.system, id: id))
            }
            for key in map.keys.sorted() where !equipment.contains(where: { ($0.unitKey ?? $0.serial) == key }) {
                if let id = map[key] { ids.append(.init(system: external.system, id: id)) }
            }
        }
        let location = external.flatMap { ref in ref.locationID.map { SiteSystemDocument.ExternalRef(system: ref.system, id: $0) } }
        self.init(serials: equipment.compactMap(\.serial), models: equipment.compactMap(\.model),
                  equipmentIDs: ids, location: location)
    }

    /// What an open job has learned on site: every serial written down, every unit recognised,
    /// and the job file it was started from.
    init(session: FieldSession) {
        var serials = session.visitedUnits.compactMap(\.serial)
        serials += session.identityFields.filter { $0.name.lowercased().contains("serial") }.map(\.value)
        var models = session.visitedUnits.map(\.modelToken)
        if let equipment = session.equipment { models.append(equipment.modelToken) }
        let external = session.jobFile?.external
        self.init(equipment: session.officeEquipment ?? [], external: external)
        add(serials: serials, models: models, equipmentIDs: [])
    }

    mutating func add(serials newSerials: [String], models newModels: [String],
                      equipmentIDs newIDs: [SiteSystemDocument.ExternalRef]) {
        for serial in newSerials.map(SiteSystemMatcher.normalisedSerial) where !serial.isEmpty
            && !serials.contains(serial) && serials.count < Self.maximumEntries {
            serials.append(serial)
        }
        for model in newModels {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = EquipmentRecognition.normalised(trimmed)
            guard !key.isEmpty, models.count < Self.maximumEntries,
                  !models.contains(where: { EquipmentRecognition.normalised($0) == key }) else { continue }
            models.append(trimmed)
        }
        for id in newIDs where !equipmentIDs.contains(id) && equipmentIDs.count < Self.maximumEntries {
            equipmentIDs.append(id)
        }
    }

    func merged(with other: SiteSystemEvidence) -> SiteSystemEvidence {
        var result = self
        result.add(serials: other.serials, models: other.models, equipmentIDs: other.equipmentIDs)
        if result.location == nil { result.location = other.location }
        return result
    }
}

/// Which documented site a job is at, how strongly that is known, and the little the brief, the
/// live line, the announcement and the job's page need to say so without re-reading the vault
/// (Plan HV §3). Kept on the job ahead and copied to the visit.
///
/// The site's own text (connections, settings, faults) is **not** here: it is the vault's, read
/// from the vault each time it is rendered, so an updated vault is what the model reads.
struct SiteSystemMatch: Codable, Equatable, Sendable {

    enum Strength: String, Codable, Equatable, Sendable {
        /// A serial, a unit's identifier in another system, or the location's, names this site.
        case confirmed
        /// Nothing confirmed, and exactly one site lists every model the job names. Said as
        /// unconfirmed, with "the serial will confirm it".
        case probable
        /// Several sites fit the models, or the evidence names more than one site. Nothing is
        /// injected; the brief says how many and that the serial will say which.
        case ambiguous
        /// The vault has site documents and none fits. Kept only so what the job ahead said is
        /// weighed again when a serial is heard; nothing is said or injected.
        case unmatched

        /// Whether the site is said and its block sent.
        var isMatch: Bool { self == .confirmed || self == .probable }
    }

    enum Basis: String, Codable, Equatable, Sendable {
        case serial
        /// A machine's id in another system (`external.equipment_ids`), keyed by its `unit_key`
        /// or its serial.
        case equipmentID = "equipment_id"
        case location
        case model
    }

    /// One unit the site lists, as the job's line and page name it.
    struct Unit: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let model: String
    }

    let vaultId: String
    let strength: Strength
    let siteId: String?
    let siteName: String?
    /// What the technician hears the site called: its `location_label`, else its name.
    let siteLabel: String?
    let basis: Basis?
    /// The site's units, in the document's order. Empty unless `strength.isMatch`.
    let units: [Unit]
    /// Units the job's own evidence named — by serial, by an identifier, or by its model.
    let matchedUnitIDs: [String]
    /// How many site documents fit, for `ambiguous`; 1 for a match.
    let candidateCount: Int
    let evidence: SiteSystemEvidence

    enum CodingKeys: String, CodingKey {
        case vaultId = "vault_id"
        case strength
        case siteId = "site_id"
        case siteName = "site_name"
        case siteLabel = "site_label"
        case basis, units
        case matchedUnitIDs = "matched_unit_ids"
        case candidateCount = "candidate_count"
        case evidence
    }

    /// The units the site lists that the job's evidence did not name.
    var otherUnits: [Unit] { units.filter { !matchedUnitIDs.contains($0.id) } }

    /// Whether this match is about the vault a session or a brief is reading.
    func applies(toVault id: String) -> Bool { vaultId == id && strength.isMatch }
}

/// Matches a job to one of a vault's site documents (Plan HV §3). Pure over the documents, the
/// vault's model index and what the job knows. **Honest about strength:** a serial or an
/// identifier names a unit; a model does not, since one model is at many sites.
enum SiteSystemMatcher {

    /// Upper-case letters and digits only, so a serial read as "af80 2201" and printed
    /// "AF80-2201" are one serial.
    static func normalisedSerial(_ serial: String) -> String {
        EquipmentRecognition.normalised(serial)
    }

    /// How two model spellings are compared: the vault section both resolve to (`exact` or
    /// `alias`), else the spelling itself normalised.
    static func modelKey(index: VaultModelIndex) -> (String) -> String {
        { model in
            if let section = EquipmentRecognition.resolve(stated: model, index: index).coveredSection {
                return "section:" + section
            }
            return "model:" + EquipmentRecognition.normalised(model)
        }
    }

    /// The match for this evidence, or nil when the vault has no site documents or the job has
    /// said nothing at all.
    static func match(evidence: SiteSystemEvidence, documents: [SiteSystemDocument], vaultId: String,
                      modelKey: (String) -> String) -> SiteSystemMatch? {
        guard !documents.isEmpty, !evidence.isEmpty else { return nil }
        let serials = Set(evidence.serials)
        let ids = Set(evidence.equipmentIDs)

        // Confirmed: a serial, a machine's identifier, or the location's.
        var confirmed: [(document: SiteSystemDocument, basis: SiteSystemMatch.Basis, units: [String])] = []
        for document in documents {
            let bySerial = document.units.filter { $0.serial.map { serials.contains(normalisedSerial($0)) } ?? false }
            let byID = document.units.filter { !ids.isDisjoint(with: $0.externalIDs ?? []) }
            let byLocation = evidence.location.map { (document.externalLocationIDs ?? []).contains($0) } ?? false
            let named = (bySerial + byID).map(\.id)
            guard !named.isEmpty || byLocation else { continue }
            let basis: SiteSystemMatch.Basis = !bySerial.isEmpty ? .serial : !byID.isEmpty ? .equipmentID : .location
            confirmed.append((document, basis, unique(named)))
        }
        if confirmed.count == 1, let hit = confirmed.first {
            let named = unique(hit.units + modelMatched(hit.document, evidence: evidence, modelKey: modelKey))
            return make(hit.document, vaultId: vaultId, strength: .confirmed, basis: hit.basis,
                        matched: named, evidence: evidence)
        }
        if confirmed.count > 1 {
            // Two sites each named by a serial or an identifier: the job's evidence disagrees with
            // itself, and nothing is said as though it did not.
            return SiteSystemMatch(vaultId: vaultId, strength: .ambiguous, siteId: nil, siteName: nil,
                                   siteLabel: nil, basis: nil, units: [], matchedUnitIDs: [], candidateCount: confirmed.count,
                                   evidence: evidence)
        }

        // Probable: exactly one site lists every model the job names.
        let wanted = Set(evidence.models.map(modelKey))
        guard !wanted.isEmpty else { return unmatched(vaultId: vaultId, evidence: evidence) }
        let candidates = documents.filter { document in
            wanted.isSubset(of: Set(document.units.map { modelKey($0.model) }))
        }
        switch candidates.count {
        case 0:
            return unmatched(vaultId: vaultId, evidence: evidence)
        case 1:
            let document = candidates[0]
            return make(document, vaultId: vaultId, strength: .probable, basis: .model,
                        matched: modelMatched(document, evidence: evidence, modelKey: modelKey),
                        evidence: evidence)
        default:
            return SiteSystemMatch(vaultId: vaultId, strength: .ambiguous, siteId: nil, siteName: nil,
                                   siteLabel: nil, basis: .model, units: [], matchedUnitIDs: [], candidateCount: candidates.count,
                                   evidence: evidence)
        }
    }

    /// Which of a site's units is the one in front of the technician: its serial when one is
    /// written down, else the only unit of its model. Nil when the site has two of that model and
    /// no serial says which.
    static func unit(in document: SiteSystemDocument, model: String?, serial: String?,
                     modelKey: (String) -> String) -> SiteSystemDocument.Unit? {
        if let serial {
            let wanted = normalisedSerial(serial)
            if let unit = document.units.first(where: { $0.serial.map(normalisedSerial) == wanted }) { return unit }
        }
        guard let model else { return nil }
        let key = modelKey(model)
        let same = document.units.filter { modelKey($0.model) == key }
        return same.count == 1 ? same[0] : nil
    }

    // MARK: -

    /// The site's units the job's models name, where each model names exactly one of them.
    private static func modelMatched(_ document: SiteSystemDocument, evidence: SiteSystemEvidence,
                                     modelKey: (String) -> String) -> [String] {
        evidence.models.compactMap { model in
            let key = modelKey(model)
            let same = document.units.filter { modelKey($0.model) == key }
            return same.count == 1 ? same[0].id : nil
        }
    }

    private static func make(_ document: SiteSystemDocument, vaultId: String, strength: SiteSystemMatch.Strength,
                             basis: SiteSystemMatch.Basis, matched: [String],
                             evidence: SiteSystemEvidence) -> SiteSystemMatch {
        SiteSystemMatch(vaultId: vaultId, strength: strength, siteId: document.id, siteName: document.name,
                        siteLabel: document.locationLabel ?? document.name, basis: basis,
                        units: document.units.map { .init(id: $0.id, name: $0.name, model: $0.model) },
                        matchedUnitIDs: unique(matched), candidateCount: 1, evidence: evidence)
    }

    private static func unmatched(vaultId: String, evidence: SiteSystemEvidence) -> SiteSystemMatch {
        SiteSystemMatch(vaultId: vaultId, strength: .unmatched, siteId: nil, siteName: nil, siteLabel: nil, basis: nil,
                        units: [], matchedUnitIDs: [], candidateCount: 0, evidence: evidence)
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

private extension EquipmentRecognition.Resolution {
    /// The section an `exact` or `alias` resolution names; nil for anything weaker.
    var coveredSection: String? {
        switch self {
        case .exact(let model), .alias(let model, _): return model.heading
        case .near, .series, .unmatched: return nil
        }
    }
}
