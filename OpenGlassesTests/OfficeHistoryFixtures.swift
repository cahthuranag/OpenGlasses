import Foundation
@testable import OpenGlasses

/// Invented fixtures for what an office sends about a job's units and site (Plan HU P1–P3). No
/// real system, maker or model: every name here is made up.
enum OfficeHistoryFixtures {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let asOf = "2026-10-07T18:00:00Z"
    static let systemName = "Fixture FSM"

    static let serial = "FX90S001"
    static let secondSerial = "FX40S002"
    static let unitKey = "roof-ahu-2"

    /// Text that must never reach the work order, the customer's summary or a closed visit.
    static let visitSummary = "No heat, display shows F17."
    static let finding = "Inducer bearing noisy."
    static let part = "Inducer motor IM-14"
    static let flagText = "Inducer motor replaced twice in 14 months."
    static let hazard = "Fixture asbestos register: boiler-room ceiling. Do not disturb."
    static let induction = "Site induction at the gatehouse before entering the plant room."
    static let access = "Deliveries entrance on the north side."
    static let warrantyNote = "Parts only; labour excluded."

    static func history(units: [OfficeServiceHistory.Unit]? = nil,
                        flags: [OfficeServiceHistory.Flag]? = nil) -> OfficeServiceHistory {
        OfficeServiceHistory(
            asOf: asOf,
            units: units ?? [
                .init(serial: serial, installed: "2019-03-04",
                      warranty: .init(status: .inWarranty, until: "2027-03-01", note: warrantyNote),
                      visits: [
                        .init(date: "2026-05-14", jobNumber: "0993", summary: visitSummary,
                              findings: [finding], partsReplaced: [part], technicianInitials: "JR",
                              source: "fixture-fsm"),
                        .init(date: "2025-03-02", jobNumber: "0871", summary: "Inducer noisy at start-up.",
                              partsReplaced: [part], source: "fixture-fsm"),
                        .init(date: "2024-11-20", jobNumber: "0702", summary: "Annual service, filters changed."),
                      ]),
            ],
            flags: flags ?? [
                .init(kind: .replacementPattern, unit: serial, text: flagText, evidence: ["0871", "0993"],
                      severity: .warning),
                .init(kind: .maintenanceDue, unit: nil, text: "Filter and belt check.", severity: .info,
                      basis: .schedule, due: "2026-11-01", schedule: "Annual service"),
            ])
    }

    static func requirements(_ items: [OfficeSiteRequirements.Item]? = nil) -> OfficeSiteRequirements {
        OfficeSiteRequirements(asOf: asOf, items: items ?? [
            .init(kind: .access, text: access, severity: .info),
            .init(kind: .hazard, text: hazard, severity: .warning),
            .init(kind: .induction, text: induction, severity: .warning),
        ])
    }

    static func provenance() -> JobFileProvenance {
        JobFileProvenance(fileName: "1007.ogjob", signature: .signed, signer: "Fixture Services Ltd",
                          receivedAt: now, digest: "d",
                          identity: .init(jobID: "job-1007", revision: 1, sha256: "s"),
                          external: ExternalJobReference(system: "fixture-fsm", systemName: systemName,
                                                         jobID: "FSM-J-1007", jobNumber: nil, appointmentID: nil,
                                                         locationID: nil, customerID: nil, technicianID: nil,
                                                         equipmentIDs: nil))
    }

    static func job(id: String = "u1", reference: String? = "1007",
                    equipment: [KnownEquipment] = [KnownEquipment(model: "FX-90", serial: serial)],
                    history: OfficeServiceHistory? = OfficeHistoryFixtures.history(),
                    requirements: OfficeSiteRequirements? = OfficeHistoryFixtures.requirements(),
                    provenance: JobFileProvenance? = OfficeHistoryFixtures.provenance()) -> UpcomingJob {
        UpcomingJob(id: id, jobReference: reference,
                    site: JobSite(customer: "Fixture Holdings", address: "1 Example Way"),
                    faultReport: FaultReport(text: "No heat, F17.", source: .jobFile, receivedAt: now),
                    equipment: equipment, origin: .jobFile, provenance: provenance,
                    officeHistory: history, siteRequirements: requirements, createdAt: now)
    }

    /// A finished visit on this phone.
    static func phoneVisit(id: String, reference: String?, startedAt: Date, serial: String?,
                           model: String = "FX-90", done: [String] = ["Cleaned the inducer"]) -> FieldSession {
        var session = FieldSession(id: id, vaultId: "refrigeration", assetId: nil, mode: .aiOnly,
                                   startedAt: startedAt, endedAt: startedAt.addingTimeInterval(3_600),
                                   pausedAt: nil, resumedAt: nil, outcome: .resolved, startLocation: nil,
                                   endLocation: nil, escalations: [], billableSeconds: 3_600)
        session.jobReference = reference
        let identity = EquipmentIdentity(modelToken: model, heading: model, file: "models.md", source: .spoken)
        session.equipment = identity
        session.visitedUnits = [VisitedUnit(identity: identity, serial: serial, continuityScope: "initial",
                                            firstSeenAt: startedAt)]
        session.tasks = done.map { FieldSession.Task(title: $0, origin: .operatorAdded, status: .done) }
        return session
    }

    static func brief(_ job: UpcomingJob, sessions: [FieldSession] = []) -> JobBrief {
        JobBriefAssembler.assemble(.init(job: job, history: JobHistoryIndex(sessions: sessions),
                                         vaultName: "Fixture", now: now))
    }
}
