import Foundation

/// What `service_history` looks in (Plan HU §5): the office's history for one job, the machines
/// that job names, and the unit in front of the technician when the open job knows it. Built from
/// what is already on the phone; nothing here reaches a network.
struct ServiceHistorySource {
    /// "Job 1007" — the job the history came with.
    var jobTitle: String
    /// Whether it is the next job ahead rather than the open one, so the answer says which.
    var isJobAhead: Bool
    var history: OfficeServiceHistory?
    var equipment: [KnownEquipment]
    /// How people name the system the office took the history from (`external.system_name`).
    var systemName: String?
    /// The serial of the unit in front of the technician, when the open job has recorded one.
    var activeSerial: String?
    /// How many of this phone's own finished visits were on a serial.
    var phoneVisits: (String) -> Int = { _ in 0 }
}

/// The tool's answer, as deterministic text (Plan HU §5). Every answer that says anything from
/// the history starts with where it is from and the date it is as of; the office's words are
/// quoted as the office's, and nothing on this phone is presented as the office's.
enum ServiceHistoryAnswer {

    static let noJobLine = "No job is open and none is waiting on this phone, so there is no office history to look in."

    static func answer(_ source: ServiceHistorySource?, unit wanted: String?, about: String?) -> String {
        guard let source else { return noJobLine }
        let job = source.isJobAhead ? "\(source.jobTitle), the next job ahead" : source.jobTitle
        guard let history = source.history else {
            return "There's no office history for this job: the office sent no service history with \(job)."
        }
        switch resolve(wanted, source: source, history: history) {
        case .unit(let index):
            return unitAnswer(history.units[index], source: source, history: history, job: job, about: about)
        case .noHistory(let name, let serial):
            var line = "There's no office history for this unit: the office sent no service history for \(name) with \(job)."
            if let serial, source.phoneVisits(serial) > 0 {
                let count = source.phoneVisits(serial)
                line += " This phone's own job history has \(count == 1 ? "1 earlier visit" : "\(count) earlier visits") on it, in the brief's site and history section."
            }
            return line + siteFlags(history, source: source, lead: " For the whole site, the office flagged: ")
        case .ambiguous(let indices):
            let names = indices.map { OfficeBriefText.unitName(history.units[$0], equipment: source.equipment) }
            return "The office sent service history for \(indices.count) units with \(job): "
                + names.joined(separator: "; ") + ". Ask which one the technician means, then call again with 'unit'."
        case .notFound(let asked):
            let names = history.units.map { OfficeBriefText.unitName($0, equipment: source.equipment) }
            return "\(source.jobTitle) has no unit matching \u{201C}\(asked)\u{201D}. The office's history covers "
                + (names.isEmpty ? "no unit" : names.joined(separator: "; ")) + "."
        case .noUnits:
            let flags = siteFlags(history, source: source, lead: "")
            guard !flags.isEmpty else {
                return "There's no office history for any unit on \(job): the office sent none."
            }
            return "From the office, as of \(OfficeBriefText.asOf(history.asOf)), for \(job): no unit history, but for the whole site the office flagged: " + flags
        }
    }

    // MARK: - Which unit

    enum Resolution: Equatable {
        case unit(Int)
        case noHistory(name: String, serial: String?)
        case ambiguous([Int])
        case notFound(String)
        case noUnits
    }

    /// A named serial or model, resolved against the job's machines; omitted, the unit in front
    /// of the technician; else the job's one unit with history; else ask.
    static func resolve(_ wanted: String?, source: ServiceHistorySource,
                        history: OfficeServiceHistory) -> Resolution {
        let asked = wanted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !asked.isEmpty {
            if let serial = JobHistoryIndex.normalised(asked),
               let index = history.units.firstIndex(where: { JobHistoryIndex.normalised($0.serial) == serial }) {
                return .unit(index)
            }
            let machines = source.equipment.filter { matches($0, asked) }
            let indices = Array(Set(machines.compactMap { machine in
                OfficeBriefText.unit(for: machine, in: history).flatMap { unit in
                    history.units.firstIndex(of: unit)
                }
            })).sorted()
            if indices.count == 1 { return .unit(indices[0]) }
            if indices.count > 1 { return .ambiguous(indices) }
            if let machine = machines.first {
                return .noHistory(name: machine.serial.map { "serial \($0)" } ?? "that unit", serial: machine.serial)
            }
            return .notFound(asked)
        }
        if let active = JobHistoryIndex.normalised(source.activeSerial) {
            if let index = history.units.firstIndex(where: { JobHistoryIndex.normalised($0.serial) == active }) {
                return .unit(index)
            }
            return .noHistory(name: "serial \(source.activeSerial ?? active)", serial: source.activeSerial)
        }
        switch history.units.count {
        case 0: return .noUnits
        case 1: return .unit(0)
        default: return .ambiguous(Array(history.units.indices))
        }
    }

    /// Whether what was asked names this machine: its serial, its model, its make and model, or
    /// where it sits.
    private static func matches(_ machine: KnownEquipment, _ asked: String) -> Bool {
        if let serial = JobHistoryIndex.normalised(machine.serial), serial == JobHistoryIndex.normalised(asked) {
            return true
        }
        let tokens = JobHistoryIndex.modelTokens(asked)
        if !tokens.isEmpty, !JobHistoryIndex.modelTokens(machine.model).isDisjoint(with: tokens) { return true }
        // A model said with its punctuation dropped or round other words: "the FX-AH".
        if let model = JobHistoryIndex.normalised(machine.model), model.count >= 3,
           JobHistoryIndex.normalised(asked)?.contains(model) == true {
            return true
        }
        let lowered = asked.lowercased()
        if let label = machine.label?.lowercased(), label.count >= 3,
           lowered.contains(label) || label.contains(lowered) {
            return true
        }
        return false
    }

    // MARK: - The answer for one unit

    private static func unitAnswer(_ unit: OfficeServiceHistory.Unit, source: ServiceHistorySource,
                                   history: OfficeServiceHistory, job: String, about: String?) -> String {
        let name = OfficeBriefText.unitName(unit, equipment: source.equipment)
        let system = source.systemName.map { " (\($0))" } ?? ""
        var parts = ["From the office's service history\(system) for \(name), as of \(OfficeBriefText.asOf(history.asOf)), sent with \(job):"]
        let words = searchWords(about)

        // "Is it under warranty?"
        if words.contains(where: { $0.hasPrefix("warrant") }) {
            parts.append(OfficeBriefText.warrantyAnswer(unit.warranty))
            return parts.joined(separator: " ")
        }

        let visits = words.isEmpty ? unit.visits : unit.visits.filter { mentions($0, words) }
        if unit.visits.isEmpty {
            parts.append("No earlier visits on file.")
        } else if visits.isEmpty {
            parts.append("None of its \(unit.visits.count == 1 ? "1 visit" : "\(unit.visits.count) visits") on file mention \u{201C}\(about ?? "")\u{201D}.")
        } else {
            parts += visits.map(visitLine)
        }
        if words.isEmpty, let installed = unit.installed {
            parts.append("Installed \(OfficeBriefText.day(installed)).")
        }
        let flags = history.flags.filter { $0.unit == unit.key }
        if !flags.isEmpty {
            parts.append("Flagged by the office: " + flags.map { flagLine($0, history: history, source: source) }
                .joined(separator: " "))
        }
        let site = siteFlags(history, source: source, lead: "For the whole site, the office flagged: ")
        if !site.isEmpty { parts.append(site) }
        if words.isEmpty, unit.warranty != nil {
            parts.append(OfficeBriefText.warrantyAnswer(unit.warranty))
        }
        return parts.joined(separator: " ")
    }

    /// "14 May 2026, job 0993: No heat, E200. Found: Inducer bearing noisy. Parts replaced:
    /// Inducer motor 14T65. Technician JR; recorded in fsm."
    static func visitLine(_ visit: OfficeServiceHistory.Visit) -> String {
        var line = OfficeBriefText.day(visit.date) + (visit.jobNumber.map { ", job \($0)" } ?? "") + ": "
            + OfficeBriefText.sentence(visit.summary)
        if !visit.findings.isEmpty {
            line += " Found: " + OfficeBriefText.sentence(visit.findings.joined(separator: "; "))
        }
        if !visit.partsReplaced.isEmpty {
            line += " Parts replaced: " + OfficeBriefText.sentence(visit.partsReplaced.joined(separator: "; "))
        }
        let who = visit.technicianInitials.map { "Technician \($0)" }
        let whereFrom = visit.source.map { "recorded in \($0)" }
        let tail = [who, whereFrom].compactMap { $0 }
        if !tail.isEmpty { line += " " + OfficeBriefText.capitalised(tail.joined(separator: "; ")) + "." }
        return line
    }

    private static func flagLine(_ flag: OfficeServiceHistory.Flag, history: OfficeServiceHistory,
                                 source: ServiceHistorySource) -> String {
        let evidence = flag.evidence.isEmpty ? ""
            : " (evidence: \(flag.evidence.count == 1 ? "job" : "jobs") \(flag.evidence.joined(separator: ", ")))"
        let text = OfficeBriefText.flagText(flag, history: history, equipment: source.equipment)
        return evidence.isEmpty ? text : String(text.dropLast()) + evidence + "."
    }

    private static func siteFlags(_ history: OfficeServiceHistory, source: ServiceHistorySource, lead: String) -> String {
        let flags = history.flags.filter(\.isSiteWide)
        guard !flags.isEmpty else { return "" }
        return lead + flags.map { flagLine($0, history: history, source: source) }.joined(separator: " ")
    }

    // MARK: - "about"

    /// The words of `about` worth looking for: three letters or more, without the small words a
    /// question carries. "the inducer motor" looks for "inducer" and "motor".
    static func searchWords(_ about: String?) -> [String] {
        guard let about else { return [] }
        let skip: Set<String> = ["the", "and", "has", "have", "been", "was", "were", "before", "ever", "this",
                                 "that", "any", "unit", "with", "for", "replaced", "replacement", "done", "last", "time"]
        return about.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !skip.contains($0) }
    }

    private static func mentions(_ visit: OfficeServiceHistory.Visit, _ words: [String]) -> Bool {
        let haystack = ([visit.summary] + visit.findings + visit.partsReplaced).joined(separator: " ").lowercased()
        return words.contains { haystack.contains($0) }
    }
}

/// "Has the inducer been replaced before?" answered from what the office sent with the job
/// (Plan HU §5, P2): the open job's office history, or the next job ahead's when none is open.
/// Nothing else — no field service system, no network, no model call — so it works with no signal.
/// Read-only, and internal: it is the organisation's record of the unit, for the technician.
@MainActor
final class ServiceHistoryTool: NativeTool {
    let name = "service_history"
    let description = """
    What the office's records say was done on a unit before, sent with the Field Assist job: earlier \
    visits with their dates, findings and parts replaced, the office's maintenance flags, and the \
    unit's warranty status. Use it when the technician asks what was done last time, whether a part \
    has been replaced before, how often a fault has come back, or whether the unit is under \
    warranty. Pass 'unit' (a serial, a model, or where it sits) or leave it out for the unit in \
    front of the technician, and 'about' for what to look for ('inducer', 'compressor', \
    'warranty'). It reads only what came with the open job, or the next job ahead when none is \
    open, and works without signal. Say the date it is as of and that it is the office's record in \
    anything you tell the technician; a flag is the office's, with its evidence, never a diagnosis. \
    When it says nothing is on file, say so; never fill in history it did not return. It is \
    internal: never put any of it in a task, the work order or the customer's summary.
    """

    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "unit": [
                "type": "string",
                "description": "Which unit: its serial, its model, or where it sits. Leave out for the unit in front of the technician."
            ],
            "about": [
                "type": "string",
                "description": "What to look for in the history: a part or a fault ('inducer', 'E200'), or 'warranty'."
            ],
        ],
    ]

    private let injectedSource: (() -> ServiceHistorySource?)?
    private weak var flow: GuidedJobFlow?
    private let sessions: @MainActor () -> FieldSessionService

    /// - Parameter source: what to look in, for tests. Nil reads the open job, else the next job
    ///   ahead on `flow`.
    init(source: (() -> ServiceHistorySource?)? = nil, flow: GuidedJobFlow? = nil,
         sessions: @escaping @MainActor () -> FieldSessionService = { FieldSessionService.shared }) {
        self.injectedSource = source
        self.flow = flow
        self.sessions = sessions
    }

    func execute(args: [String: Any]) async throws -> String {
        guard Config.fieldAssistActive else {
            return "Field Assist is disabled. Enable it in Settings → Field Assist."
        }
        let source = injectedSource?() ?? Self.liveSource(sessions: sessions(), flow: flow)
        return ServiceHistoryAnswer.answer(source, unit: args["unit"] as? String, about: args["about"] as? String)
    }

    /// The open job's history; with no job open, the next job ahead's.
    static func liveSource(sessions: FieldSessionService, flow: GuidedJobFlow?) -> ServiceHistorySource? {
        let phoneVisits: (String) -> Int = { serial in
            JobHistoryIndex(sessions: sessions.history).visits(serial: serial).count
        }
        if let session = sessions.activeSession {
            return ServiceHistorySource(
                jobTitle: session.jobReference.map { "Job \($0)" } ?? "this job",
                isJobAhead: false,
                history: session.officeHistory,
                equipment: session.officeEquipment ?? [],
                systemName: session.jobFile?.external?.systemName,
                activeSerial: activeSerial(session),
                phoneVisits: phoneVisits)
        }
        guard let job = flow?.nextUpcomingJob else { return nil }
        return ServiceHistorySource(jobTitle: job.title, isJobAhead: true, history: job.officeHistory,
                                    equipment: job.equipment, systemName: job.provenance?.external?.systemName,
                                    activeSerial: nil, phoneVisits: phoneVisits)
    }

    /// The serial of the unit being worked on now: one recorded for the current equipment, else
    /// the latest unit visited on it.
    static func activeSerial(_ session: FieldSession) -> String? {
        let recorded = session.identityFields.last { field in
            field.name.lowercased().contains("serial")
                && (session.identityEquipmentScopes[field.name.lowercased()] ?? "initial") == session.continuityScope
        }
        if let recorded { return recorded.value }
        return session.visitedUnits.last { $0.continuityScope == session.continuityScope }?.serial
    }
}
