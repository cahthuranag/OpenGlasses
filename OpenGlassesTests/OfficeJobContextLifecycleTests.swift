import XCTest
@testable import OpenGlasses

/// What the office sent about a job's units and site, from the job ahead to the closed visit
/// (Plan HU P0): carried onto the session, logged as counts only, never in the record, dropped at
/// close leaving only how much there was, and erased when the phone leaves the organisation.
@MainActor
final class OfficeJobContextLifecycleTests: XCTestCase {

    private var root: URL!
    private var service: FieldSessionService!
    private var upcoming: UpcomingJobStore!
    private var flow: GuidedJobFlow!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var previousEnabled: Any?

    /// Text that must never reach the log, the record or a closed session.
    private let secretSummary = "Fixture visit summary that names a colleague"
    private let secretRequirement = "Fixture hazard text for the plant room"
    private let secretFlag = "Fixture flag text about the inducer"

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfficeJobContext-\(UUID().uuidString)", isDirectory: true)
        for folder in ["sessions", "store", "upcoming"] {
            try? FileManager.default.createDirectory(at: root.appendingPathComponent(folder),
                                                     withIntermediateDirectories: true)
        }
        previousEnabled = UserDefaults.standard.object(forKey: "fieldAssistEnabled")
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousEntitlement = EntitlementTestScope.grant()
        VaultRegistry.shared.resetCache()
        service = FieldSessionService(sessionsRoot: root.appendingPathComponent("sessions"))
        upcoming = UpcomingJobStore(directory: root.appendingPathComponent("upcoming"))
        flow = GuidedJobFlow(sessions: service, store: ConversationStore(directory: root.appendingPathComponent("store")),
                             seams: .init(speak: { _ in }, persistenceEnabled: { true }))
        flow.connectUpcoming(upcoming)
    }

    override func tearDown() {
        flow = nil
        service = nil
        upcoming = nil
        try? FileManager.default.removeItem(at: root)
        if let previousEnabled { UserDefaults.standard.set(previousEnabled, forKey: "fieldAssistEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled") }
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    private var history: OfficeServiceHistory {
        OfficeServiceHistory(
            asOf: "2027-01-10T18:00:00Z",
            units: [.init(serial: "S1", installed: "2021-03-04",
                          warranty: .init(status: .inWarranty, until: "2027-03-01", note: nil),
                          visits: [.init(date: "2026-11-14", jobNumber: "0993", summary: secretSummary),
                                   .init(date: "2025-09-02", jobNumber: "0871", summary: "Earlier.")])],
            flags: [.init(kind: .replacementPattern, unit: "S1", text: secretFlag, evidence: ["0871", "0993"],
                          severity: .warning),
                    .init(kind: .maintenanceDue, unit: nil, text: "Annual service due.", severity: .info,
                          basis: .schedule, due: "2027-02-01", schedule: "Annual service")])
    }

    private var requirements: OfficeSiteRequirements {
        OfficeSiteRequirements(asOf: "2027-01-10T18:00:00Z",
                               items: [.init(kind: .hazard, text: secretRequirement, severity: .warning),
                                       .init(kind: .ppe, text: "Hard hat on site.", severity: .warning),
                                       .init(kind: .access, text: "North entrance.", severity: .info)])
    }

    private var external: ExternalJobReference {
        ExternalJobReference(system: "fixture-fsm", systemName: "Fixture FSM", jobID: "FSM-J-1", jobNumber: "88001",
                             appointmentID: nil, locationID: nil, customerID: nil, technicianID: nil,
                             equipmentIDs: ["S1": "FSM-E-1"])
    }

    private func jobAhead() -> UpcomingJob {
        UpcomingJob(jobReference: "88001", site: JobSite(customer: "Fixture Service"),
                    equipment: [KnownEquipment(model: "FX-90", serial: "S1")], origin: .jobFile,
                    provenance: JobFileProvenance(fileName: "88001.ogjob", signature: .signed, signer: "Fixture Service Ltd",
                                                  digest: "d", identity: .init(jobID: "job-1", revision: 1, sha256: "s"),
                                                  external: external),
                    officeReference: "FX-1", officeHistory: history, siteRequirements: requirements)
    }

    private func sessionDirectory(_ id: String) -> URL {
        root.appendingPathComponent("sessions").appendingPathComponent(id, isDirectory: true)
    }

    private func onDisk(_ id: String) throws -> String {
        let dir = sessionDirectory(id)
        let meta = try String(contentsOf: dir.appendingPathComponent("session.json"), encoding: .utf8)
        let log = (try? String(contentsOf: dir.appendingPathComponent("log.jsonl"), encoding: .utf8)) ?? ""
        return meta + log
    }

    // MARK: - The job ahead

    func testTheJobAheadKeepsItAcrossARelaunchAndOlderJobsLoad() throws {
        let added = try XCTUnwrap(flow.addUpcomingJob(jobAhead()))
        let reloaded = try XCTUnwrap(UpcomingJobStore(directory: root.appendingPathComponent("upcoming")).job(id: added.id))
        XCTAssertEqual(reloaded.officeHistory, history)
        XCTAssertEqual(reloaded.siteRequirements, requirements)
        XCTAssertEqual(reloaded.officeReference, "FX-1")
        XCTAssertEqual(reloaded.provenance?.external, external)

        let old = Data(#"{"id":"a","origin":"typed","created_at":0,"site":{},"equipment":[],"attachments":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(UpcomingJob.self, from: old)
        XCTAssertNil(decoded.officeHistory)
        XCTAssertNil(decoded.siteRequirements)
        XCTAssertNil(decoded.officeReference)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertNil(encoded["office_history"], "a job without it encodes without it")
        XCTAssertNil(encoded["site_requirements"])
        XCTAssertNil(encoded["office_reference"])
    }

    // MARK: - On the visit

    func testStartingTheJobCarriesItOntoTheSessionAndLogsCountsOnly() throws {
        let added = try XCTUnwrap(flow.addUpcomingJob(jobAhead()))
        let session = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        XCTAssertEqual(session.officeHistory, history)
        XCTAssertEqual(session.officeSiteRequirements, requirements)
        XCTAssertNil(session.officeContext)
        XCTAssertEqual(session.jobFile?.external, external)

        let started = try XCTUnwrap(SessionLogger.readEvents(at: sessionDirectory(session.id))
            .first { $0.kind == .jobAheadStarted })
        XCTAssertEqual(started.payload?["office_history_units"]?.value as? Int, 1)
        XCTAssertEqual(started.payload?["office_flags"]?.value as? Int, 2)
        XCTAssertEqual(started.payload?["office_site_requirements"]?.value as? Int, 3)
        let log = try String(contentsOf: sessionDirectory(session.id).appendingPathComponent("log.jsonl"), encoding: .utf8)
        for secret in [secretSummary, secretFlag, secretRequirement] {
            XCTAssertFalse(log.contains(secret), "the office's text never reaches the log")
        }

        // Nothing of it is in the visit's record.
        let record = String(decoding: try JSONEncoder().encode(WorkRecord(session: session, vaultName: "Refrigeration")),
                            as: UTF8.self)
        for secret in [secretSummary, secretFlag, secretRequirement, "in_warranty", "Annual service"] {
            XCTAssertFalse(record.contains(secret), secret)
        }
        XCTAssertTrue(record.contains("FSM-J-1"), "the external identity is echoed in the record")
    }

    func testAJobAheadWithoutItLogsExactlyAsBefore() throws {
        var job = jobAhead()
        job.officeHistory = nil
        job.siteRequirements = nil
        let added = try XCTUnwrap(flow.addUpcomingJob(job))
        let session = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        XCTAssertNil(session.officeHistory)
        let started = try XCTUnwrap(SessionLogger.readEvents(at: sessionDirectory(session.id))
            .first { $0.kind == .jobAheadStarted })
        XCTAssertEqual(Set((started.payload ?? [:]).keys),
                       ["origin", "has_site", "has_fault_report", "has_brief", "job_file", "signature", "signer",
                        "received_at", "digest", "job_id", "revision"])
        _ = try service.endSession()
        XCTAssertNil(service.history.first { $0.id == session.id }?.officeContext, "nothing was sent, nothing is said")
    }

    // MARK: - At close

    func testClosingTheJobDropsTheRawBlocksAndKeepsOnlyTheSummary() throws {
        let added = try XCTUnwrap(flow.addUpcomingJob(jobAhead()))
        let started = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        let closed = try service.endSession()
        XCTAssertNil(closed.officeHistory)
        XCTAssertNil(closed.officeSiteRequirements)
        let summary = try XCTUnwrap(closed.officeContext)
        XCTAssertEqual(summary.historyUnits, 1)
        XCTAssertEqual(summary.historyVisits, 2)
        XCTAssertEqual(summary.flags, 2)
        XCTAssertEqual(summary.warningFlags, 1)
        XCTAssertEqual(summary.siteRequirements, 3)
        XCTAssertEqual(summary.historyAsOf, "2027-01-10T18:00:00Z")
        XCTAssertEqual(summary.lines.count, 3)
        XCTAssertTrue(summary.lines[0].hasPrefix("The office sent service history for 1 unit (2 earlier visits), as of "))
        XCTAssertEqual(summary.lines[1], "The office raised 2 maintenance flags, 1 marked as a warning.")
        XCTAssertTrue(summary.lines[2].hasPrefix("The office sent 3 site requirements, as of "))
        XCTAssertEqual(closed.jobFile?.external, external, "the identity stays: it is the record's")

        // Not on disk either, once closed, and not in the history this phone keeps.
        let disk = try onDisk(started.id)
        for secret in [secretSummary, secretFlag, secretRequirement] {
            XCTAssertFalse(disk.contains(secret), secret)
        }
        XCTAssertNil(service.history.first { $0.id == started.id }?.officeHistory)
        // A closed session reloads with only the summary.
        let reloaded = FieldSessionService(sessionsRoot: root.appendingPathComponent("sessions"))
        let restored = try XCTUnwrap(reloaded.history.first { $0.id == started.id })
        XCTAssertNil(restored.officeHistory)
        XCTAssertEqual(restored.officeContext, summary)
    }

    func testASessionRecordedBeforeThisDecodes() throws {
        var session = FieldSession(id: "s", vaultId: "v", assetId: nil, mode: .aiOnly, startedAt: Date(timeIntervalSince1970: 0),
                                   outcome: .inProgress, escalations: [], billableSeconds: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(session)
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("office"))
        let decoded = try JSONDecoder().decode(FieldSession.self, from: before)
        XCTAssertNil(decoded.officeHistory)
        XCTAssertNil(decoded.officeSiteRequirements)
        XCTAssertNil(decoded.officeContext)
        // Dropping nothing leaves nothing.
        session.dropOfficeSuppliedContext()
        XCTAssertNil(session.officeContext)
        XCTAssertEqual(try encoder.encode(session), before)
    }

    // MARK: - Leaving the organisation

    func testLeavingTheOrganisationErasesItFromTheOpenJob() throws {
        let added = try XCTUnwrap(flow.addUpcomingJob(jobAhead()))
        let started = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        XCTAssertNotNil(service.activeSession?.officeHistory)
        service.eraseOfficeSuppliedContext()
        XCTAssertNil(service.activeSession?.officeHistory)
        XCTAssertNil(service.activeSession?.officeSiteRequirements)
        XCTAssertEqual(service.activeSession?.officeContext?.historyUnits, 1)
        let disk = try onDisk(started.id)
        XCTAssertFalse(disk.contains(secretSummary))
        XCTAssertFalse(disk.contains(secretRequirement))
        // With nothing open, or nothing from the office, it does nothing.
        _ = try service.endSession()
        service.eraseOfficeSuppliedContext()
        XCTAssertNil(service.activeSession)
    }

    func testTheDepartureErasesTheJobsAheadAndTheOpenJobsOfficeContext() throws {
        // The production departure seam calls both; the jobs ahead go with `removeAll`.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("OpenGlasses/Sources/App/OpenGlassesApp.swift"), encoding: .utf8)
        let erase = try XCTUnwrap(source.range(of: "eraseContent: {"))
        let records = try XCTUnwrap(source.range(of: "hasEndpoint:", range: erase.upperBound..<source.endIndex))
        let body = source[erase.upperBound..<records.lowerBound]
        XCTAssertTrue(body.contains("self.upcomingJobs.removeAll()"))
        XCTAssertTrue(body.contains("FieldSessionService.shared.eraseOfficeSuppliedContext()"))

        _ = try XCTUnwrap(flow.addUpcomingJob(jobAhead()))
        upcoming.removeAll()
        XCTAssertTrue(UpcomingJobStore(directory: root.appendingPathComponent("upcoming")).jobs.isEmpty)
    }
}
