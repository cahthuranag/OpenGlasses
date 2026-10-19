import XCTest
@testable import OpenGlasses

/// Plan HU P3 — the office's warnings said once, at Start: warning site requirements in full, then
/// warning flags, recorded as counts on the job's log so a resumed job says nothing more.
@MainActor
final class JobStartFlagSpeechTests: XCTestCase {

    private typealias F = OfficeHistoryFixtures

    private var root: URL!
    private var service: FieldSessionService!
    private var upcoming: UpcomingJobStore!
    private var flow: GuidedJobFlow!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var previousEnabled: Any?

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("JobStartFlags-\(UUID().uuidString)", isDirectory: true)
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

    private func logEvents(_ id: String) -> [SessionLogger.Event] {
        SessionLogger.readEvents(at: root.appendingPathComponent("sessions").appendingPathComponent(id, isDirectory: true))
    }

    // MARK: - The pure lines

    func testStartedLinesSayRequirementsInFullThenWarningFlags() {
        let lines = GuidedJobFlow.startedLines(for: F.job())
        XCTAssertEqual(lines, [
            "Starting job 1007 at Fixture Holdings, 1 Example Way.",
            "Site requirements from the office: Hazard: \(F.hazard) Induction: \(F.induction)",
            "Office flag: Replacement pattern: \(F.flagText)",
        ])
        XCTAssertFalse(lines.joined().contains(F.access), "an info requirement is not said unprompted")
        XCTAssertFalse(lines.joined().contains("Annual service"), "nor an info flag")
    }

    func testAJobWithNothingFromTheOfficeSaysOnlyItsStartedLine() {
        let job = F.job(history: nil, requirements: nil)
        XCTAssertEqual(GuidedJobFlow.startedLines(for: job), [GuidedJobFlow.startedLine(for: job)])
    }

    func testASiteWideScheduleWarningIsSaidAsAboutTheSite() {
        let history = F.history(flags: [
            .init(kind: .maintenanceDue, unit: nil, text: "Filter and belt check.", severity: .warning,
                  basis: .schedule, due: "2026-11-01", schedule: "Annual service"),
        ])
        let lines = GuidedJobFlow.startedLines(for: F.job(history: history, requirements: nil))
        XCTAssertEqual(lines.last,
                       "Office flag: Annual service due on \(OfficeBriefText.day("2026-11-01")) for the whole site: Filter and belt check.")
    }

    func testMoreThanTwoWarningFlagsAreCountedNotRead() {
        let flags = (1...3).map {
            OfficeServiceHistory.Flag(kind: .recurringFailure, unit: F.serial, text: "Flag \($0).",
                                      evidence: ["J\($0)"], severity: .warning)
        }
        let lines = GuidedJobFlow.startedLines(for: F.job(history: F.history(flags: flags), requirements: nil))
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines.last, "And 1 more office flag, on the job's page.")
    }

    // MARK: - Once

    func testTheWarningsAreSaidOnceAtStartAndNotOnResume() throws {
        let added = try XCTUnwrap(flow.addUpcomingJob(F.job()))
        let session = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        let first = flow.startLines(for: added)
        XCTAssertEqual(first, GuidedJobFlow.startedLines(for: added))

        // The same job again — a second tap, a re-entry — says only that it started.
        XCTAssertEqual(flow.startLines(for: added), [GuidedJobFlow.startedLine(for: added)])

        // Pausing and resuming the job says nothing of the office's warnings either.
        _ = try service.pauseSession()
        _ = try service.resumeSession()
        XCTAssertTrue(service.officeWarningsAlreadySpoken)
        XCTAssertFalse(service.recordOfficeWarningsSpoken(JobStartWarnings(job: added)))

        // …and nor does a relaunch: the log is the record.
        let relaunched = FieldSessionService(sessionsRoot: root.appendingPathComponent("sessions"))
        XCTAssertEqual(relaunched.activeSession?.id, session.id)
        XCTAssertTrue(relaunched.officeWarningsAlreadySpoken)

        let spoken = logEvents(session.id).filter { $0.kind == .officeFlagsSpoken || $0.kind == .officeSiteRequirementsSpoken }
        XCTAssertEqual(spoken.map(\.kind), [.officeSiteRequirementsSpoken, .officeFlagsSpoken], "one of each, once")
    }

    func testTheLogRecordsCountsOnly() throws {
        let added = try XCTUnwrap(flow.addUpcomingJob(F.job()))
        let session = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        _ = flow.startLines(for: added)
        let events = logEvents(session.id)
        let flags = try XCTUnwrap(events.first { $0.kind == .officeFlagsSpoken })
        XCTAssertEqual(flags.payload?["count"]?.value as? Int, 1)
        XCTAssertEqual(flags.payload?["read"]?.value as? Int, 1)
        let requirements = try XCTUnwrap(events.first { $0.kind == .officeSiteRequirementsSpoken })
        XCTAssertEqual(requirements.payload?["count"]?.value as? Int, 2)
        let log = try String(contentsOf: root.appendingPathComponent("sessions").appendingPathComponent(session.id)
            .appendingPathComponent("log.jsonl"), encoding: .utf8)
        for secret in [F.flagText, F.hazard, F.induction] {
            XCTAssertFalse(log.contains(secret), "the office's words never reach the log")
        }
    }

    func testAJobWithNoWarningsLogsNothing() throws {
        let job = F.job(history: F.history(flags: []), requirements: F.requirements([.init(kind: .access, text: F.access, severity: .info)]))
        let added = try XCTUnwrap(flow.addUpcomingJob(job))
        let session = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        XCTAssertEqual(flow.startLines(for: added), [GuidedJobFlow.startedLine(for: added)])
        XCTAssertFalse(logEvents(session.id).contains { $0.kind == .officeFlagsSpoken || $0.kind == .officeSiteRequirementsSpoken })
    }

    func testThePageStartsTheJobThroughTheOnceOnlyPath() throws {
        // The job's page is where a job ahead is started; it must say the lines through
        // `startLines(for:)`, which records them, not the pure `startedLines(for:)`.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("OpenGlasses/Sources/App/Views/Job/UpcomingJobViews.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("flow.startLines(for: job)"))
        XCTAssertFalse(source.contains("GuidedJobFlow.startedLine(for: job)"))
    }
}
