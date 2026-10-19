import Foundation

// Job-file format 3 (Contracts/job-file.md §10; Plans HT P0 and HU P0): format 2's file, plus
// four optional things the office may say about a job — the job's identity in another system
// (`external`), what the office knows about each unit (`history`), what the site asks of the
// person arriving (`site_requirements`), and, on each machine, a `unit_key`, a `make` and a
// `label`. Everything here is office-authored, read-only on the phone, and untrusted input:
// every member is bounded, typed and closed, and an unknown one is refused, as in every format.

// MARK: - The job's identity in another system (Plan HT)

/// Which system a job came from, and that system's identifiers for it. **Opaque identity:** the
/// phone never calls it, never opens it as a link, never looks anything up with it and never
/// shows an identifier. Echoed verbatim in the visit's record (`work_record.job_file.external`).
struct ExternalJobReference: Codable, Equatable, Sendable {
    /// An opaque lowercase token naming the system. Compared to nothing.
    let system: String
    /// How people name the system, for display. The phone holds no table of names.
    let systemName: String?
    /// The system's identifier for the job. Never shown, and never decides whether two files are
    /// the same job: that is the office's `job_id`.
    let jobID: String
    /// The number people use for the job. When present it is the job's number on the phone.
    let jobNumber: String?
    /// The visit or booking the job file is for.
    let appointmentID: String?
    let locationID: String?
    let customerID: String?
    /// Echoed only. The phone stores no technician identifier of its own.
    let technicianID: String?
    /// The system's identifier for each machine on the job, keyed by the machine's `unit_key`
    /// when it has one and by its serial otherwise.
    let equipmentIDs: [String: String]?

    enum CodingKeys: String, CodingKey {
        case system
        case systemName = "system_name"
        case jobID = "job_id"
        case jobNumber = "job_number"
        case appointmentID = "appointment_id"
        case locationID = "location_id"
        case customerID = "customer_id"
        case technicianID = "technician_id"
        case equipmentIDs = "equipment_ids"
    }
}

// MARK: - What the office knows about each unit (Plan HU)

/// How loudly the office wants something said. The office decides; the phone never promotes one.
enum OfficeNoticeSeverity: String, Codable, Equatable, Sendable {
    case info, warning
}

/// The office's service history for the units on a job, and the maintenance flags its rules
/// raised. Compiled by the office from its own records; never created, edited or inferred on the
/// phone. Internal: never on the work order, the customer's summary, the sign-off or the record,
/// and dropped from the visit when it closes.
struct OfficeServiceHistory: Codable, Equatable, Sendable {

    struct Warranty: Codable, Equatable, Sendable {
        enum Status: String, Codable, Equatable, Sendable {
            case inWarranty = "in_warranty"
            case expired
            case unknown
        }
        let status: Status
        /// ISO 8601 date (`YYYY-MM-DD`).
        let until: String?
        let note: String?
    }

    struct Visit: Codable, Equatable, Sendable {
        /// ISO 8601 date (`YYYY-MM-DD`). Visits are newest first.
        let date: String
        let jobNumber: String?
        let summary: String
        let findings: [String]
        let partsReplaced: [String]
        let technicianInitials: String?
        /// A token naming the system the visit was recorded in, as `ExternalJobReference.system`.
        let source: String?

        enum CodingKeys: String, CodingKey {
            case date
            case jobNumber = "job_number"
            case summary, findings
            case partsReplaced = "parts_replaced"
            case technicianInitials = "technician_initials"
            case source
        }

        init(date: String, jobNumber: String? = nil, summary: String, findings: [String] = [],
             partsReplaced: [String] = [], technicianInitials: String? = nil, source: String? = nil) {
            self.date = date
            self.jobNumber = jobNumber
            self.summary = summary
            self.findings = findings
            self.partsReplaced = partsReplaced
            self.technicianInitials = technicianInitials
            self.source = source
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decode(String.self, forKey: .date)
            jobNumber = try c.decodeIfPresent(String.self, forKey: .jobNumber)
            summary = try c.decode(String.self, forKey: .summary)
            findings = try c.decodeIfPresent([String].self, forKey: .findings) ?? []
            partsReplaced = try c.decodeIfPresent([String].self, forKey: .partsReplaced) ?? []
            technicianInitials = try c.decodeIfPresent(String.self, forKey: .technicianInitials)
            source = try c.decodeIfPresent(String.self, forKey: .source)
        }
    }

    /// One machine on the job, named by exactly one of its serial or its `unit_key` — never by
    /// its model, which two machines can share.
    struct Unit: Codable, Equatable, Sendable {
        let serial: String?
        let unitKey: String?
        /// ISO 8601 date the machine was installed, only when the office's records say so.
        let installed: String?
        let warranty: Warranty?
        let visits: [Visit]

        /// What a flag names this unit by.
        var key: String { serial ?? unitKey ?? "" }

        enum CodingKeys: String, CodingKey {
            case serial
            case unitKey = "unit_key"
            case installed, warranty, visits
        }

        init(serial: String? = nil, unitKey: String? = nil, installed: String? = nil,
             warranty: Warranty? = nil, visits: [Visit] = []) {
            self.serial = serial
            self.unitKey = unitKey
            self.installed = installed
            self.warranty = warranty
            self.visits = visits
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            serial = try c.decodeIfPresent(String.self, forKey: .serial)
            unitKey = try c.decodeIfPresent(String.self, forKey: .unitKey)
            installed = try c.decodeIfPresent(String.self, forKey: .installed)
            warranty = try c.decodeIfPresent(Warranty.self, forKey: .warranty)
            visits = try c.decodeIfPresent([Visit].self, forKey: .visits) ?? []
        }
    }

    struct Flag: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Equatable, Sendable, CaseIterable {
            case recurringFailure = "recurring_failure"
            case replacementPattern = "replacement_pattern"
            case overdueMaintenance = "overdue_maintenance"
            case maintenanceDue = "maintenance_due"
            case recallOrBulletin = "recall_or_bulletin"

            /// The kinds a maintenance schedule can raise, which alone may say `basis: schedule`.
            var isMaintenance: Bool { self == .overdueMaintenance || self == .maintenanceDue }
        }

        /// What raised the flag: one of the office's rules over the history, or a maintenance
        /// schedule the office's records hold. Absent means `rule`.
        enum Basis: String, Codable, Equatable, Sendable {
            case schedule, rule
        }

        let kind: Kind
        /// The unit, by the key its `history.units` entry is named by. Absent only on a
        /// schedule's maintenance flag, where it means the whole site.
        let unit: String?
        let text: String
        /// Job numbers. Empty only for a flag a schedule raised.
        let evidence: [String]
        let severity: OfficeNoticeSeverity
        let basis: Basis?
        /// ISO 8601 date the maintenance falls due.
        let due: String?
        /// The office's short plain-text name for the scheduled service ("Annual service").
        let schedule: String?

        var effectiveBasis: Basis { basis ?? .rule }
        var isSiteWide: Bool { unit == nil }

        init(kind: Kind, unit: String?, text: String, evidence: [String] = [],
             severity: OfficeNoticeSeverity, basis: Basis? = nil, due: String? = nil,
             schedule: String? = nil) {
            self.kind = kind
            self.unit = unit
            self.text = text
            self.evidence = evidence
            self.severity = severity
            self.basis = basis
            self.due = due
            self.schedule = schedule
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(Kind.self, forKey: .kind)
            unit = try c.decodeIfPresent(String.self, forKey: .unit)
            text = try c.decode(String.self, forKey: .text)
            evidence = try c.decodeIfPresent([String].self, forKey: .evidence) ?? []
            severity = try c.decode(OfficeNoticeSeverity.self, forKey: .severity)
            basis = try c.decodeIfPresent(Basis.self, forKey: .basis)
            due = try c.decodeIfPresent(String.self, forKey: .due)
            schedule = try c.decodeIfPresent(String.self, forKey: .schedule)
        }
    }

    /// When the office compiled it, ISO 8601. Every use says it.
    let asOf: String
    let units: [Unit]
    let flags: [Flag]

    var asOfDate: Date? { JobFileValidator.parseDate(asOf) }
    var visitCount: Int { units.reduce(0) { $0 + $1.visits.count } }

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case units, flags
    }

    init(asOf: String, units: [Unit] = [], flags: [Flag] = []) {
        self.asOf = asOf
        self.units = units
        self.flags = flags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOf = try c.decode(String.self, forKey: .asOf)
        units = try c.decodeIfPresent([Unit].self, forKey: .units) ?? []
        flags = try c.decodeIfPresent([Flag].self, forKey: .flags) ?? []
    }
}

/// What the site asks of the person arriving: access, induction, PPE, hazards, who to ask for.
/// Office-authored, internal like the history, and dropped from the visit when it closes. Nothing
/// is kept per site between jobs: a later job at the same site carries its own.
struct OfficeSiteRequirements: Codable, Equatable, Sendable {

    struct Item: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Equatable, Sendable, CaseIterable {
            case access, induction, ppe, hazard, contact, other
        }
        let kind: Kind
        let text: String
        let severity: OfficeNoticeSeverity
    }

    let asOf: String
    let items: [Item]

    var asOfDate: Date? { JobFileValidator.parseDate(asOf) }

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case items
    }
}

/// What a finished job keeps of what the office sent once the raw blocks are gone: counts and the
/// date they were compiled, never a word of their text (Plan HU, decided 2026-10-20).
struct OfficeContextSummary: Codable, Equatable, Sendable {
    var historyAsOf: String?
    var historyUnits: Int = 0
    var historyVisits: Int = 0
    var flags: Int = 0
    var warningFlags: Int = 0
    var siteRequirementsAsOf: String?
    var siteRequirements: Int = 0

    init?(history: OfficeServiceHistory?, siteRequirements: OfficeSiteRequirements?) {
        guard history != nil || siteRequirements != nil else { return nil }
        historyAsOf = history?.asOf
        historyUnits = history?.units.count ?? 0
        historyVisits = history?.visitCount ?? 0
        flags = history?.flags.count ?? 0
        warningFlags = history?.flags.filter { $0.severity == .warning }.count ?? 0
        siteRequirementsAsOf = siteRequirements?.asOf
        self.siteRequirements = siteRequirements?.items.count ?? 0
    }

    /// What the finished job's page says the office sent.
    var lines: [String] {
        func asOf(_ raw: String?) -> String {
            guard let date = raw.flatMap(JobFileValidator.parseDate) else { return "" }
            return ", as of \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        func plural(_ count: Int, _ one: String, _ many: String) -> String {
            "\(count) \(count == 1 ? one : many)"
        }
        var lines: [String] = []
        if historyAsOf != nil {
            lines.append("The office sent service history for \(plural(historyUnits, "unit", "units")) (\(plural(historyVisits, "earlier visit", "earlier visits")))\(asOf(historyAsOf)).")
            if flags > 0 {
                lines.append("The office raised \(plural(flags, "maintenance flag", "maintenance flags")), \(warningFlags) marked as a warning.")
            }
        }
        if siteRequirementsAsOf != nil {
            lines.append("The office sent \(plural(siteRequirements, "site requirement", "site requirements"))\(asOf(siteRequirementsAsOf)).")
        }
        return lines
    }
}

// MARK: - The machine's format-3 members

extension JobFile {
    /// What format 3 adds to one machine on the job, in the order of `body.equipment`.
    struct UnitDetail: Equatable, Sendable {
        /// The office's own short handle for the machine, for one with no serial. Never an
        /// identifier from another system, never shown.
        var unitKey: String?
        var make: String?
        /// Where the machine sits at the site: "Roof, AHU-2".
        var label: String?
    }

    /// Everything a format-3 job carries beyond format 2's fields. Nil for formats 1 and 2.
    struct Format3: Equatable, Sendable {
        var units: [UnitDetail] = []
        var external: ExternalJobReference?
        var history: OfficeServiceHistory?
        var siteRequirements: OfficeSiteRequirements?
    }
}

// MARK: - Validation

/// The format-3 rules, over a job that has already passed format 2's. Pure.
enum JobFileFormat3Validator {

    static let externalMembers: Set<String> = [
        "system", "system_name", "job_id", "job_number", "appointment_id", "location_id",
        "customer_id", "technician_id", "equipment_ids",
    ]
    static let historyMembers: Set<String> = ["as_of", "units", "flags"]
    static let unitMembers: Set<String> = ["serial", "unit_key", "installed", "warranty", "visits"]
    static let warrantyMembers: Set<String> = ["status", "until", "note"]
    static let visitMembers: Set<String> = [
        "date", "job_number", "summary", "findings", "parts_replaced", "technician_initials", "source",
    ]
    static let flagMembers: Set<String> = [
        "kind", "unit", "text", "evidence", "severity", "basis", "due", "schedule",
    ]
    static let siteRequirementMembers: Set<String> = ["as_of", "items"]
    static let requirementMembers: Set<String> = ["kind", "text", "severity"]

    /// Exact encoded bytes of each member, as the job carries it.
    static let maximumExternalBytes = 2 * 1024
    static let maximumHistoryBytes = 24 * 1024
    static let maximumVisitBytes = 2 * 1024
    static let maximumSiteRequirementsBytes = 4 * 1024

    static let maximumVisitsPerUnit = 10
    static let maximumFlagsPerUnit = 3
    static let maximumFlags = 12
    static let maximumFindings = 6
    static let maximumPartsReplaced = 8
    static let maximumEvidence = 10
    static let maximumEquipmentIDs = 10
    static let maximumSiteRequirements = 8

    /// Length caps, in characters.
    static let systemNameLimit = 40
    static let externalIdentifierLimit = 128
    static let jobNumberLimit = 64
    static let summaryLimit = 600
    static let findingLimit = 200
    static let partLimit = 80
    static let initialsLimit = 4
    static let flagTextLimit = 240
    static let scheduleLimit = 80
    static let warrantyNoteLimit = 160
    static let requirementTextLimit = 240
    static let timestampLimit = 40

    typealias Refusal = JobFileValidator.Refusal

    /// The machines a job names, as the history and the identifiers refer to them.
    private struct Machine {
        let serial: String?
        let unitKey: String?
    }

    /// Check a format-3 job's own members and read them. `members` are the job's top-level
    /// members as its exact bytes spell them.
    static func check(_ job: [String: Any], members: [String: Data]) throws -> JobFile.Format3 {
        let (machines, details) = try checkEquipment(job["equipment"])
        var result = JobFile.Format3(units: details)
        if let raw = members["external"] {
            try checkExternal(job["external"], bytes: raw, machines: machines)
            result.external = try decode(ExternalJobReference.self, raw)
        }
        if let raw = members["history"] {
            try checkHistory(job["history"], bytes: raw, machines: machines)
            result.history = try decode(OfficeServiceHistory.self, raw)
        }
        if let raw = members["site_requirements"] {
            try checkSiteRequirements(job["site_requirements"], bytes: raw)
            result.siteRequirements = try decode(OfficeSiteRequirements.self, raw)
        }
        return result
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ raw: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: raw) else { throw Refusal.notAJobFile }
        return value
    }

    // MARK: Equipment

    /// The format-1 checks have run; these are format 3's: a `unit_key` is a token, unique within
    /// the job, and never any machine's serial.
    private static func checkEquipment(_ value: Any?) throws -> ([Machine], [JobFile.UnitDetail]) {
        guard let list = value as? [[String: Any]] else { return ([], []) }
        let serials = list.compactMap { $0["serial"] as? String }
        var keys = Set<String>()
        var machines: [Machine] = []
        var details: [JobFile.UnitDetail] = []
        for unit in list {
            var unitKey: String?
            if let raw = unit["unit_key"] {
                guard let key = raw as? String, isToken(key) else { throw Refusal.invalidValue("unit_key") }
                guard keys.insert(key).inserted,
                      !serials.contains(where: { $0.lowercased() == key }) else {
                    throw Refusal.invalidValue("unit_key")
                }
                unitKey = key
            }
            machines.append(Machine(serial: unit["serial"] as? String, unitKey: unitKey))
            details.append(JobFile.UnitDetail(unitKey: unitKey, make: JobSite.cleaned(unit["make"] as? String),
                                              label: JobSite.cleaned(unit["label"] as? String)))
        }
        return (machines, details)
    }

    // MARK: External

    private static func checkExternal(_ value: Any?, bytes: Data, machines: [Machine]) throws {
        guard let external = value as? [String: Any] else { throw Refusal.wrongType("external") }
        guard bytes.count <= maximumExternalBytes else { throw Refusal.tooLong("external") }
        try checkKeys(external, allowed: externalMembers)
        guard let system = external["system"] as? String, isToken(system) else {
            throw Refusal.invalidValue("system")
        }
        try text(external["system_name"], "system_name", limit: systemNameLimit, noLinks: true)
        try identifier(external["job_id"], "job_id", required: true)
        try text(external["job_number"], "job_number", limit: jobNumberLimit, noLinks: true)
        for key in ["appointment_id", "location_id", "customer_id", "technician_id"] {
            try identifier(external[key], key, required: false)
        }
        if let raw = external["equipment_ids"] {
            guard let ids = raw as? [String: Any] else { throw Refusal.wrongType("equipment_ids") }
            guard ids.count <= maximumEquipmentIDs else { throw Refusal.tooMany("equipment identifiers") }
            for (key, value) in ids {
                // The unit's `unit_key` when it has one, else its serial.
                let names = machines.contains { $0.unitKey == key }
                    || machines.contains { $0.unitKey == nil && $0.serial == key }
                guard names else { throw Refusal.invalidValue("equipment_ids") }
                try identifier(value, "equipment_ids", required: true)
            }
        }
    }

    /// 1–128 printable ASCII characters, no spaces, never `://`. The system's own identifier,
    /// which some systems encode with `=`, `/` or `+`.
    private static func identifier(_ value: Any?, _ name: String, required: Bool) throws {
        guard let value else {
            if required { throw Refusal.invalidValue(name) }
            return
        }
        guard let text = value as? String else { throw Refusal.wrongType(name) }
        guard !text.isEmpty, text.utf8.count <= externalIdentifierLimit,
              text.utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else { throw Refusal.invalidValue(name) }
        if text.contains("://") { throw Refusal.containsLink(name) }
    }

    // MARK: History

    private static func checkHistory(_ value: Any?, bytes: Data, machines: [Machine]) throws {
        guard let history = value as? [String: Any] else { throw Refusal.wrongType("history") }
        guard bytes.count <= maximumHistoryBytes else { throw Refusal.tooLong("history") }
        try checkKeys(history, allowed: historyMembers)
        try timestamp(history["as_of"], "as_of")
        let historyMembersBytes = JobFileJSON.members(bytes) ?? [:]

        // Units: each names exactly one machine on the job, once.
        var unitKeys: [String: Int] = [:]
        if let raw = history["units"] {
            guard let units = raw as? [Any] else { throw Refusal.wrongType("units") }
            guard units.count <= JobFileValidator.maximumEquipment else { throw Refusal.tooMany("units") }
            let unitBytes = historyMembersBytes["units"].flatMap(JobFileJSON.elements) ?? []
            guard unitBytes.count == units.count else { throw Refusal.notAJobFile }
            var named = Set<Int>()
            for (index, entry) in units.enumerated() {
                guard let unit = entry as? [String: Any] else { throw Refusal.wrongType("units") }
                try checkKeys(unit, allowed: unitMembers)
                let machine: Int
                let key: String
                // Exactly one of the two, and as text: never both, never neither, never the model.
                let serial = unit["serial"], unitKey = unit["unit_key"]
                if let serial, unitKey == nil {
                    guard let serial = serial as? String,
                          let found = machines.firstIndex(where: { $0.serial == serial }) else {
                        throw Refusal.invalidValue("serial")
                    }
                    (machine, key) = (found, serial)
                } else if let unitKey, serial == nil {
                    guard let unitKey = unitKey as? String, isToken(unitKey),
                          let found = machines.firstIndex(where: { $0.unitKey == unitKey }) else {
                        throw Refusal.invalidValue("unit_key")
                    }
                    (machine, key) = (found, unitKey)
                } else {
                    throw Refusal.invalidValue("units")
                }
                guard named.insert(machine).inserted, unitKeys[key] == nil else { throw Refusal.invalidValue("units") }
                unitKeys[key] = machine
                if let installed = unit["installed"] { try date(installed, "installed") }
                if let warranty = unit["warranty"] { try checkWarranty(warranty) }
                if let visits = unit["visits"] {
                    let visitBytes = JobFileJSON.members(unitBytes[index])?["visits"].flatMap(JobFileJSON.elements)
                    try checkVisits(visits, bytes: visitBytes)
                }
            }
        }

        if let raw = history["flags"] {
            guard let flags = raw as? [Any] else { throw Refusal.wrongType("flags") }
            guard flags.count <= maximumFlags else { throw Refusal.tooMany("maintenance flags") }
            var perUnit: [Int: Int] = [:]
            for entry in flags {
                guard let flag = entry as? [String: Any] else { throw Refusal.wrongType("flags") }
                try checkKeys(flag, allowed: flagMembers)
                guard let kindName = flag["kind"] as? String,
                      let kind = OfficeServiceHistory.Flag.Kind(rawValue: kindName) else {
                    throw Refusal.invalidValue("kind")
                }
                let basis: OfficeServiceHistory.Flag.Basis
                if let raw = flag["basis"] {
                    guard let name = raw as? String, let parsed = OfficeServiceHistory.Flag.Basis(rawValue: name) else {
                        throw Refusal.invalidValue("basis")
                    }
                    basis = parsed
                } else {
                    basis = .rule
                }
                // Only a maintenance kind can come from a schedule, and only a schedule's flag
                // names a schedule.
                if basis == .schedule, !kind.isMaintenance { throw Refusal.invalidValue("basis") }
                if flag["schedule"] != nil, basis != .schedule { throw Refusal.invalidValue("schedule") }
                if flag["due"] != nil, !kind.isMaintenance { throw Refusal.invalidValue("due") }
                try severity(flag["severity"])
                try text(flag["text"], "text", limit: flagTextLimit, required: true)
                try text(flag["schedule"], "schedule", limit: scheduleLimit)
                if let due = flag["due"] { try date(due, "due") }

                if let raw = flag["unit"] {
                    guard let unit = raw as? String, let machine = unitKeys[unit] else {
                        throw Refusal.invalidValue("unit")
                    }
                    perUnit[machine, default: 0] += 1
                    guard perUnit[machine]! <= maximumFlagsPerUnit else { throw Refusal.tooMany("flags for one unit") }
                } else if basis != .schedule {
                    // Absent means the whole site, which only a schedule can say.
                    throw Refusal.invalidValue("unit")
                }

                let evidence: [Any]
                if let raw = flag["evidence"] {
                    guard let list = raw as? [Any] else { throw Refusal.wrongType("evidence") }
                    evidence = list
                } else {
                    evidence = []
                }
                guard evidence.count <= maximumEvidence else { throw Refusal.tooMany("evidence jobs") }
                // A rule shows its evidence; a schedule's evidence is the schedule itself.
                if evidence.isEmpty, basis != .schedule { throw Refusal.invalidValue("evidence") }
                for item in evidence { try text(item, "evidence", limit: jobNumberLimit, required: true) }
            }
        }
    }

    private static func checkWarranty(_ value: Any) throws {
        guard let warranty = value as? [String: Any] else { throw Refusal.wrongType("warranty") }
        try checkKeys(warranty, allowed: warrantyMembers)
        guard let status = warranty["status"] as? String,
              OfficeServiceHistory.Warranty.Status(rawValue: status) != nil else {
            throw Refusal.invalidValue("status")
        }
        if let until = warranty["until"] { try date(until, "until") }
        try text(warranty["note"], "note", limit: warrantyNoteLimit)
    }

    private static func checkVisits(_ value: Any, bytes: [Data]?) throws {
        guard let visits = value as? [Any] else { throw Refusal.wrongType("visits") }
        guard visits.count <= maximumVisitsPerUnit else { throw Refusal.tooMany("visits for one unit") }
        guard let bytes, bytes.count == visits.count else { throw Refusal.notAJobFile }
        var previous: String?
        for (index, entry) in visits.enumerated() {
            guard let visit = entry as? [String: Any] else { throw Refusal.wrongType("visits") }
            guard bytes[index].count <= maximumVisitBytes else { throw Refusal.tooLong("visits") }
            try checkKeys(visit, allowed: visitMembers)
            guard let day = visit["date"] as? String else { throw Refusal.invalidValue("date") }
            try date(day, "date")
            // Newest first: the office orders them, the phone never reorders.
            if let previous, day > previous { throw Refusal.invalidValue("visits") }
            previous = day
            try text(visit["job_number"], "job_number", limit: jobNumberLimit)
            try text(visit["summary"], "summary", limit: summaryLimit, required: true)
            try textList(visit["findings"], "findings", count: maximumFindings, limit: findingLimit)
            try textList(visit["parts_replaced"], "parts_replaced", count: maximumPartsReplaced, limit: partLimit)
            if let raw = visit["technician_initials"] {
                guard let initials = raw as? String, (1...initialsLimit).contains(initials.count),
                      initials.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
                    throw Refusal.invalidValue("technician_initials")
                }
            }
            if let raw = visit["source"] {
                guard let source = raw as? String, isToken(source) else { throw Refusal.invalidValue("source") }
            }
        }
    }

    // MARK: Site requirements

    private static func checkSiteRequirements(_ value: Any?, bytes: Data) throws {
        guard let requirements = value as? [String: Any] else { throw Refusal.wrongType("site_requirements") }
        guard bytes.count <= maximumSiteRequirementsBytes else { throw Refusal.tooLong("site_requirements") }
        try checkKeys(requirements, allowed: siteRequirementMembers)
        try timestamp(requirements["as_of"], "as_of")
        guard let items = requirements["items"] as? [Any] else { throw Refusal.wrongType("items") }
        guard items.count <= maximumSiteRequirements else { throw Refusal.tooMany("site requirements") }
        for entry in items {
            guard let item = entry as? [String: Any] else { throw Refusal.wrongType("items") }
            try checkKeys(item, allowed: requirementMembers)
            guard let kind = item["kind"] as? String, OfficeSiteRequirements.Item.Kind(rawValue: kind) != nil else {
                throw Refusal.invalidValue("kind")
            }
            try text(item["text"], "text", limit: requirementTextLimit, required: true)
            try severity(item["severity"])
        }
    }

    // MARK: Values

    /// `[a-z0-9_-]{1,32}`.
    static func isToken(_ value: String) -> Bool {
        let bytes = value.utf8
        return (1...32).contains(bytes.count) && bytes.allSatisfy {
            (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x5F || $0 == 0x2D
        }
    }

    /// An ISO 8601 calendar date, `YYYY-MM-DD`, that exists.
    static func isDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 0x2D, bytes[7] == 0x2D,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (0x30...0x39).contains($0.element) }),
              let year = Int(value.prefix(4)), let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)), year >= 1, (1...12).contains(month), day >= 1 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: first) else { return false }
        return days.contains(day)
    }

    private static func date(_ value: Any, _ name: String) throws {
        guard let text = value as? String, isDate(text) else { throw Refusal.unreadableDate(name) }
    }

    private static func timestamp(_ value: Any?, _ name: String) throws {
        guard let text = value as? String, text.utf8.count <= timestampLimit,
              JobFileValidator.parseDate(text) != nil else { throw Refusal.unreadableDate(name) }
    }

    private static func severity(_ value: Any?) throws {
        guard let name = value as? String, OfficeNoticeSeverity(rawValue: name) != nil else {
            throw Refusal.invalidValue("severity")
        }
    }

    /// Plain text under the job file's rules: no markup, no control characters, not blank, within
    /// its limit — and, where asked, nothing that reads as a link.
    private static func text(_ value: Any?, _ name: String, limit: Int, required: Bool = false,
                             noLinks: Bool = false) throws {
        guard let value else {
            if required { throw Refusal.invalidValue(name) }
            return
        }
        guard let text = value as? String else { throw Refusal.wrongType(name) }
        guard JobSite.cleaned(text) != nil else { throw Refusal.invalidValue(name) }
        guard text.count <= limit else { throw Refusal.tooLong(name) }
        if JobFileValidator.containsMarkup(text) { throw Refusal.containsMarkup(name) }
        if text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw Refusal.notPlainText(name)
        }
        if noLinks, text.contains("://") { throw Refusal.containsLink(name) }
    }

    private static func textList(_ value: Any?, _ name: String, count: Int, limit: Int) throws {
        guard let value else { return }
        guard let list = value as? [Any] else { throw Refusal.wrongType(name) }
        guard list.count <= count else { throw Refusal.tooMany(name.replacingOccurrences(of: "_", with: " ")) }
        for item in list { try text(item, name, limit: limit, required: true) }
    }

    private static func checkKeys(_ object: [String: Any], allowed: Set<String>) throws {
        if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw Refusal.unexpectedField(unknown)
        }
    }
}
