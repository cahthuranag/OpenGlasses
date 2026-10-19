import PDFKit
import XCTest
@testable import OpenGlasses

/// Plan HU §6 — what the office sends about a job is internal. With its history, flags, warranty
/// and site requirements on the visit and in the brief the technician heard, none of their words
/// reaches the work record, its summary lines, the customer's summary, the exported record or the
/// work-order PDF; and once the job closes, none of it is left on the visit at all.
@MainActor
final class OfficeHistoryAudienceTests: XCTestCase {

    private typealias F = OfficeHistoryFixtures

    private var root: URL!
    private var service: FieldSessionService!
    private var upcoming: UpcomingJobStore!
    private var flow: GuidedJobFlow!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var previousEnabled: Any?

    /// Every string the office sent that must stay internal — warranty included.
    private let internalStrings = [F.visitSummary, F.finding, F.part, F.flagText, F.hazard, F.induction, F.access,
                                   F.warrantyNote, "Filter and belt check", "under warranty", "Office record",
                                   "Office service history", "Flagged by the office", "in_warranty"]

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfficeAudience-\(UUID().uuidString)", isDirectory: true)
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

    /// A job ahead with everything the office can send, briefed and started, with one task done.
    private func startedJob() throws -> FieldSession {
        let added = try XCTUnwrap(flow.addUpcomingJob(F.job()))
        let brief = try XCTUnwrap(flow.assembleBrief(jobId: added.id, vaultId: "refrigeration", now: F.now))
        XCTAssertTrue(brief.hasOfficeContent, "the brief the technician heard carries the office's lines")
        let session = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        XCTAssertEqual(session.brief, brief)
        _ = flow.startLines(for: added)
        let task = try service.addOperatorTask(title: "Replaced the igniter", why: "Cracked")
        _ = try service.startTask(id: task.id)
        _ = try service.completeTask(id: task.id, note: "Fitted and tested.")
        return try XCTUnwrap(service.activeSession)
    }

    private func assertFree(_ text: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        for secret in internalStrings {
            XCTAssertFalse(text.contains(secret), "\(what) carries \u{201C}\(secret)\u{201D}", file: file, line: line)
        }
    }

    // MARK: - While the job is open

    func testTheRecordAndTheCustomersSummaryCarryNoneOfItWhileTheJobIsOpen() throws {
        let session = try startedJob()
        XCTAssertNotNil(session.officeHistory)
        let record = WorkRecord(session: session, vaultName: "Refrigeration")
        assertFree(String(decoding: try JSONEncoder().encode(record), as: UTF8.self), "the work record")
        assertFree(record.summaryLines.joined(separator: "\n"), "the record's summary lines")
        assertFree(CustomerSummary.lines(for: record).joined(separator: "\n"), "the customer's summary")
        XCTAssertTrue(CustomerSummary.lines(for: record).joined().contains("Replaced the igniter"), "the work done is there")
    }

    // MARK: - The report

    func testTheExportedRecordAndTheWorkOrderPDFCarryNoneOfIt() throws {
        let session = try startedJob()
        let finished = try service.endSession(outcome: .resolved)
        let directory = root.appendingPathComponent("sessions").appendingPathComponent(finished.id, isDirectory: true)

        let export = try XCTUnwrap(SessionExporter.buildExport(sessionDir: directory))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        assertFree(String(decoding: try encoder.encode(export), as: UTF8.self), "the exported record")

        for recipients in [["office@fixture.example"], ["customer@fixture.example"]] {
            let delivery = service.reportDelivery(for: .email, sessionId: session.id, recipients: recipients)
            for attachment in delivery.attachments {
                switch attachment.kind {
                case .pdf:
                    let text = try XCTUnwrap(PDFDocument(url: attachment.url)?.string)
                    XCTAssertTrue(text.contains("Replaced the igniter") || text.contains("Field Assist"), "it is the work order")
                    assertFree(text, "the work-order PDF for \(recipients)")
                case .json:
                    assertFree(try String(contentsOf: attachment.url, encoding: .utf8), "the JSON for \(recipients)")
                default:
                    break
                }
            }
        }
    }

    // MARK: - After close

    func testClosingTheJobLeavesNoneOfItOnTheVisitOrOnDisk() throws {
        let session = try startedJob()
        let closed = try service.endSession(outcome: .resolved)
        XCTAssertNil(closed.officeHistory)
        XCTAssertNil(closed.officeSiteRequirements)
        XCTAssertNil(closed.officeEquipment)
        let brief = try XCTUnwrap(closed.brief, "the brief stays, without the office's lines")
        XCTAssertFalse(brief.hasOfficeContent)
        XCTAssertTrue(brief.allItems.contains { $0.text == "Customer: Fixture Holdings." })
        XCTAssertEqual(closed.officeContext?.warningFlags, 1, "only the counts")

        let directory = root.appendingPathComponent("sessions").appendingPathComponent(session.id, isDirectory: true)
        let disk = try String(contentsOf: directory.appendingPathComponent("session.json"), encoding: .utf8)
            + ((try? String(contentsOf: directory.appendingPathComponent("log.jsonl"), encoding: .utf8)) ?? "")
        assertFree(disk, "the closed visit on disk")
    }

    func testLeavingTheOrganisationTakesItOutOfTheOpenJobsBriefToo() throws {
        _ = try startedJob()
        service.eraseOfficeSuppliedContext()
        let session = try XCTUnwrap(service.activeSession)
        XCTAssertEqual(session.brief?.hasOfficeContent, false)
        XCTAssertNil(session.officeEquipment)
    }

    // MARK: - Not the personal brain

    func testNothingInFieldAssistFeedsThePersonalBrain() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OpenGlasses/Sources")
        let files = ["Services/FieldAssist/Job/OfficeBriefText.swift", "Services/FieldAssist/Job/JobBrief.swift",
                     "Services/NativeTools/ServiceHistoryTool.swift", "Services/FieldAssist/Job/JobFileFormat3.swift"]
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("BrainStore"), file)
        }
    }
}
