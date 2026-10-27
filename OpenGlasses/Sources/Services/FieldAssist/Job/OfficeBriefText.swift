import Foundation

/// How what the office sent about a job — its service history, warranty status, maintenance flags
/// and site requirements — is put into words on the phone (Plan HU P1–P3).
///
/// Pure, and the one place the wording lives, so the brief, the job's page, the words said at
/// Start, a job update and the `service_history` tool cannot drift apart. **Nothing here computes
/// a pattern or promotes a severity:** every line restates what the office wrote, with when it was
/// compiled and where it came from. The office's text is internal — never the work order's, the
/// customer summary's or the record's — and none of it is logged.
enum OfficeBriefText {

    // MARK: - Dates

    /// "14 May 2026" in the phone's own style, for an ISO 8601 date (`YYYY-MM-DD`). Read in UTC,
    /// so it is the day the office wrote wherever the phone is. A value that is not a date is
    /// returned as it came (the validator refuses one, so this is belt and braces).
    static func day(_ iso: String) -> String {
        guard let date = isoDay.date(from: iso) else { return iso }
        return shownDay.string(from: date)
    }

    /// When the office compiled something — an ISO 8601 timestamp — as a day on this phone.
    static func asOf(_ raw: String) -> String {
        guard let date = JobFileValidator.parseDate(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shownDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Citations

    /// "Office service history (Fixture FSM), as of 7 Oct 2026" — the system's name from the job
    /// file's `external.system_name` when it gave one.
    static func historyCitation(_ history: OfficeServiceHistory, systemName: String?) -> String {
        let system = systemName.map { " (\($0))" } ?? ""
        return "Office service history\(system), as of \(asOf(history.asOf))"
    }

    static func requirementsCitation(_ requirements: OfficeSiteRequirements) -> String {
        "From the office, as of \(asOf(requirements.asOf))"
    }

    /// "Flagged by the office, as of 7 Oct 2026 (evidence: jobs 0871, 0993)". A schedule's flag
    /// with no jobs behind it says so instead.
    static func flagCitation(_ flag: OfficeServiceHistory.Flag, history: OfficeServiceHistory) -> String {
        let when = asOf(history.asOf)
        switch flag.evidence.count {
        case 0:
            return flag.effectiveBasis == .schedule
                ? "Flagged by the office from its maintenance schedule, as of \(when)"
                : "Flagged by the office, as of \(when)"
        case 1:
            return "Flagged by the office, as of \(when) (evidence: job \(flag.evidence[0]))"
        default:
            return "Flagged by the office, as of \(when) (evidence: jobs \(flag.evidence.joined(separator: ", ")))"
        }
    }

    // MARK: - Units

    /// The machine on the job a history entry names, as a technician would say it: "serial
    /// 5919K01234", or, for one with no serial, where it sits or its model. **Never the office's
    /// `unit_key`**, which is a handle and is never shown.
    static func unitName(_ unit: OfficeServiceHistory.Unit, equipment: [KnownEquipment]) -> String {
        if let serial = unit.serial { return "serial \(serial)" }
        let machine = equipment.first { $0.unitKey != nil && $0.unitKey == unit.unitKey }
        if let label = machine?.label { return "the unit at \(label)" }
        if let model = machine?.model { return "the \(model)" }
        return "the unit with no serial"
    }

    /// The history entry a flag names, by the key it is filed under.
    static func unit(named key: String?, in history: OfficeServiceHistory) -> OfficeServiceHistory.Unit? {
        guard let key else { return nil }
        return history.units.first { $0.key == key }
    }

    /// The history entry for one machine the job names: by serial, compared as serials are, else
    /// by the office's own key for it.
    static func unit(for machine: KnownEquipment, in history: OfficeServiceHistory) -> OfficeServiceHistory.Unit? {
        if let serial = JobHistoryIndex.normalised(machine.serial),
           let found = history.units.first(where: { JobHistoryIndex.normalised($0.serial) == serial }) {
            return found
        }
        guard let key = machine.unitKey else { return nil }
        return history.units.first { $0.unitKey == key }
    }

    // MARK: - Visits

    /// "Office record, 14 May 2026, job 0993 (serial 5919K01234): No heat, E200. Parts replaced:
    /// Inducer motor 14T65."
    static func visitLine(_ visit: OfficeServiceHistory.Visit, unitName: String) -> String {
        let job = visit.jobNumber.map { ", job \($0)" } ?? ""
        var line = "Office record, \(day(visit.date))\(job) (\(unitName)): \(sentence(visit.summary))"
        if !visit.partsReplaced.isEmpty {
            line += " Parts replaced: " + sentence(visit.partsReplaced.joined(separator: "; "))
        }
        return line
    }

    /// "And 4 more earlier visits from the office: ask for the service history."
    static func moreVisitsLine(_ count: Int) -> String {
        count == 1
            ? "And 1 more earlier visit from the office: ask for the service history."
            : "And \(count) more earlier visits from the office: ask for the service history."
    }

    // MARK: - Warranty

    /// The warranty phrase on a unit's line: "Serial 5919K01234: under warranty until 1 Mar 2027
    /// (office, as of 7 Oct 2026)." An `unknown` status is not said unprompted, so it has none.
    static func warrantyLine(_ warranty: OfficeServiceHistory.Warranty, unitName: String,
                             history: OfficeServiceHistory) -> String? {
        let office = "(office, as of \(asOf(history.asOf)))"
        let phrase: String
        switch warranty.status {
        case .inWarranty:
            phrase = "under warranty" + (warranty.until.map { " until \(day($0))" } ?? "")
        case .expired:
            phrase = "warranty expired" + (warranty.until.map { " \(day($0))" } ?? "")
        case .unknown:
            return nil
        }
        return "\(capitalised(unitName)): \(phrase) \(office)."
    }

    /// What the `service_history` tool says when asked about a unit's warranty.
    static func warrantyAnswer(_ warranty: OfficeServiceHistory.Warranty?) -> String {
        guard let warranty else { return "The office sent no warranty status for this unit." }
        var answer: String
        switch warranty.status {
        case .inWarranty:
            answer = "Under warranty" + (warranty.until.map { " until \(day($0))" } ?? "") + "."
        case .expired:
            answer = "Warranty expired" + (warranty.until.map { " \(day($0))" } ?? "") + "."
        case .unknown:
            answer = "The office's records don't say whether it is under warranty."
        }
        if let note = warranty.note { answer += " " + sentence(note) }
        return answer
    }

    // MARK: - Flags

    /// A flag in words, the same on the page and aloud: its kind, what it is about, then the
    /// office's own text. A maintenance flag says when it falls due and the service's name when
    /// the office gave them; a site-wide one says it is about the whole site.
    ///
    /// - "Replacement pattern: Inducer motor replaced twice in 14 months."
    /// - "Annual service due on 1 Nov 2026 for the whole site: Filter and belt check."
    /// - "Maintenance overdue since 1 Oct 2026 for serial 5919K01234: Last service missed."
    static func flagText(_ flag: OfficeServiceHistory.Flag, history: OfficeServiceHistory,
                         equipment: [KnownEquipment]) -> String {
        let scope: String
        if flag.isSiteWide {
            scope = " for the whole site"
        } else if history.units.count > 1, let unit = unit(named: flag.unit, in: history) {
            scope = (flag.kind.isMaintenance ? " for " : " on ") + unitName(unit, equipment: equipment)
        } else {
            scope = ""
        }
        let headline: String
        switch flag.kind {
        case .maintenanceDue:
            headline = (flag.schedule ?? "Maintenance") + " due" + (flag.due.map { " on \(day($0))" } ?? "")
        case .overdueMaintenance:
            headline = (flag.schedule ?? "Maintenance") + " overdue" + (flag.due.map { " since \(day($0))" } ?? "")
        case .recurringFailure:
            headline = "Recurring failure"
        case .replacementPattern:
            headline = "Replacement pattern"
        case .recallOrBulletin:
            headline = "Recall or bulletin"
        }
        return "\(headline)\(scope): \(sentence(flag.text))"
    }

    /// The flags as brief lines, the office's warnings first and otherwise in the office's order.
    static func flagItems(_ history: OfficeServiceHistory?, equipment: [KnownEquipment]) -> [JobBrief.Item] {
        guard let history else { return [] }
        let ordered = history.flags.filter { $0.severity == .warning } + history.flags.filter { $0.severity != .warning }
        return ordered.map { flag in
            JobBrief.Item(text: flagText(flag, history: history, equipment: equipment),
                          citation: flagCitation(flag, history: history),
                          officeOrigin: .flag, severity: flag.severity)
        }
    }

    // MARK: - Site requirements

    static func requirementText(_ item: OfficeSiteRequirements.Item) -> String {
        let kind: String
        switch item.kind {
        case .access: kind = "Access"
        case .induction: kind = "Induction"
        case .ppe: kind = "PPE"
        case .hazard: kind = "Hazard"
        case .contact: kind = "Contact"
        case .other: kind = "On site"
        }
        return "\(kind): \(sentence(item.text))"
    }

    /// The requirements as brief lines: the office's warnings first, each one line, then the rest.
    static func requirementItems(_ requirements: OfficeSiteRequirements?) -> [JobBrief.Item] {
        guard let requirements else { return [] }
        let citation = requirementsCitation(requirements)
        let ordered = requirements.items.filter { $0.severity == .warning }
            + requirements.items.filter { $0.severity != .warning }
        return ordered.map {
            JobBrief.Item(text: requirementText($0), citation: citation, officeOrigin: .siteRequirement,
                          severity: $0.severity)
        }
    }

    // MARK: - Helpers

    /// The office's text as a sentence: ends in a full stop unless it already ends in one.
    static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    static func capitalised(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

// MARK: - The office's warnings, aloud

/// The office's warnings as they are said, at Start and at the head of the brief (Plan HU P3):
/// every `warning` site requirement in full — a safety requirement the office marked is never
/// trimmed to "and N more" — then at most two `warning` flags, and how many more there are.
/// `info` items are on the page and in "say more about history", never read unprompted.
enum OfficeWarningSpeech {

    /// How many warning flags are read before the rest are counted.
    static let flagsRead = 2

    static func lines(requirements: [String], flags: [String]) -> [String] {
        var lines: [String] = []
        if !requirements.isEmpty {
            lines.append("Site requirements from the office: " + requirements.joined(separator: " "))
        }
        for flag in flags.prefix(flagsRead) { lines.append("Office flag: " + flag) }
        let rest = flags.count - min(flags.count, flagsRead)
        if rest > 0 {
            lines.append(rest == 1 ? "And 1 more office flag, on the job's page."
                                   : "And \(rest) more office flags, on the job's page.")
        }
        return lines
    }
}

/// What the office marked as a warning on a job, counted and worded from the job's own blocks —
/// what Start says and the `officeFlagsSpoken` / `officeSiteRequirementsSpoken` events count.
struct JobStartWarnings: Equatable {
    let requirements: [String]
    let flags: [String]

    init(history: OfficeServiceHistory?, requirements: OfficeSiteRequirements?, equipment: [KnownEquipment]) {
        self.requirements = (requirements?.items ?? []).filter { $0.severity == .warning }
            .map(OfficeBriefText.requirementText)
        self.flags = history.map { history in
            history.flags.filter { $0.severity == .warning }
                .map { OfficeBriefText.flagText($0, history: history, equipment: equipment) }
        } ?? []
    }

    init(job: UpcomingJob) {
        self.init(history: job.officeHistory, requirements: job.siteRequirements, equipment: job.equipment)
    }

    var isEmpty: Bool { requirements.isEmpty && flags.isEmpty }
    var spoken: [String] { OfficeWarningSpeech.lines(requirements: requirements, flags: flags) }
}

// MARK: - A mark on the job before it is opened

/// The small mark a job ahead carries on the Jobs list and the job-day card when the office has
/// flagged one of its units as a warning (Plan HU, decided 2026-10-20) — so a technician sees it
/// before opening the job. Only the office's `warning` flags count; `info` ones are on the page.
struct OfficeFlagMark: Equatable, Hashable {
    let warnings: Int

    static let symbol = "flag.fill"

    static func mark(for job: UpcomingJob) -> OfficeFlagMark? {
        let count = job.officeHistory?.flags.filter { $0.severity == .warning }.count ?? 0
        return count > 0 ? OfficeFlagMark(warnings: count) : nil
    }

    /// What it says, on screen and to VoiceOver.
    var label: String {
        warnings == 1 ? String(localized: "1 warning flag from the office") : String(localized: "\(warnings) warning flags from the office")
    }
}

// MARK: - A job update that changes a warning

/// Which of the office's warnings a job update changed, to be read once as it arrives (Plan HU,
/// decided 2026-10-20): a `warning` site requirement or a `warning` flag the update carries that
/// the job did not carry before, word for word — new, reworded, or newly marked a warning. A
/// warning the job already had is not read again, so an update that changes something else says
/// nothing, and the same warning is never repeated. A warning the update removes is not read: it
/// is gone from the page, and saying what no longer applies is the office's to word.
///
/// Pure: it compares what the job held with what the update holds. Wired to the job-file
/// revision path (`JobFileService.accept`); the open-job update path (Plan HN) is not built, and
/// is to call this with the visit's blocks when it is.
enum OfficeWarningChanges {

    static func changed(previousHistory: OfficeServiceHistory?, previousRequirements: OfficeSiteRequirements?,
                        history: OfficeServiceHistory?, requirements: OfficeSiteRequirements?,
                        equipment: [KnownEquipment]) -> JobStartWarnings {
        // Compared on what the office wrote, not on the words the phone puts round it: a second
        // unit arriving changes how a flag is introduced, not the flag.
        let heldRequirements = (previousRequirements?.items ?? []).filter { $0.severity == .warning }
        let heldFlags = (previousHistory?.flags ?? []).filter { $0.severity == .warning }
        let newRequirements = (requirements?.items ?? [])
            .filter { $0.severity == .warning && !heldRequirements.contains($0) }
        let newFlags = (history?.flags ?? [])
            .filter { $0.severity == .warning && !heldFlags.contains($0) }
        return JobStartWarnings(
            requirements: newRequirements.map(OfficeBriefText.requirementText),
            flags: history.map { history in
                newFlags.map { OfficeBriefText.flagText($0, history: history, equipment: equipment) }
            } ?? [])
    }

    static func changed(from previous: UpcomingJob, to revised: UpcomingJob) -> JobStartWarnings {
        changed(previousHistory: previous.officeHistory, previousRequirements: previous.siteRequirements,
                history: revised.officeHistory, requirements: revised.siteRequirements,
                equipment: revised.equipment)
    }

    /// What is said as the update is accepted, or nothing when no warning changed.
    static func spoken(from previous: UpcomingJob, to revised: UpcomingJob) -> String? {
        let changes = changed(from: previous, to: revised)
        guard !changes.isEmpty else { return nil }
        var lines = ["The office changed a warning on \(revised.title)."]
        if !changes.requirements.isEmpty {
            lines.append("Site requirements: " + changes.requirements.joined(separator: " "))
        }
        lines += changes.flags.map { "Office flag: " + $0 }
        return lines.joined(separator: " ")
    }
}

extension JobStartWarnings {
    init(requirements: [String], flags: [String]) {
        self.requirements = requirements
        self.flags = flags
    }
}
