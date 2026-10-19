import XCTest
@testable import OpenGlasses

/// Plan HU P2 — `service_history` answers from the office history the job carried, and from
/// nothing else: dated and sourced, filtered by what was asked about, asking when it cannot tell
/// which unit, saying so when nothing is on file, refusing with Field Assist off — and gated,
/// classified and offered like every Field Assist tool.
@MainActor
final class ServiceHistoryToolTests: XCTestCase {

    private typealias F = OfficeHistoryFixtures

    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var previousEnabled: Any?

    override func setUp() {
        super.setUp()
        previousEnabled = UserDefaults.standard.object(forKey: "fieldAssistEnabled")
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousEntitlement = EntitlementTestScope.grant()
    }

    override func tearDown() {
        if let previousEnabled { UserDefaults.standard.set(previousEnabled, forKey: "fieldAssistEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled") }
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    private func source(history: OfficeServiceHistory? = F.history(),
                        equipment: [KnownEquipment] = [KnownEquipment(model: "FX-90", serial: F.serial)],
                        activeSerial: String? = nil, isJobAhead: Bool = false,
                        phoneVisits: Int = 0) -> ServiceHistorySource {
        ServiceHistorySource(jobTitle: "Job 1007", isJobAhead: isJobAhead, history: history, equipment: equipment,
                             systemName: F.systemName, activeSerial: activeSerial, phoneVisits: { _ in phoneVisits })
    }

    private var header: String {
        "From the office's service history (\(F.systemName)) for serial \(F.serial), as of \(OfficeBriefText.asOf(F.asOf)), sent with Job 1007:"
    }

    private func run(_ source: ServiceHistorySource?, _ args: [String: Any]) async throws -> String {
        try await ServiceHistoryTool(source: { source }).execute(args: args)
    }

    // MARK: - Answers

    func testHasTheInducerBeenReplacedBeforeIsAnsweredWithDateAndSource() async throws {
        let answer = try await run(source(activeSerial: F.serial), ["about": "has the inducer been replaced before?"])
        XCTAssertTrue(answer.hasPrefix(header), answer)
        XCTAssertTrue(answer.contains("\(OfficeBriefText.day("2026-05-14")), job 0993: \(F.visitSummary) Found: \(F.finding.dropLast()). Parts replaced: \(F.part). Technician JR; recorded in fixture-fsm."), answer)
        XCTAssertTrue(answer.contains("\(OfficeBriefText.day("2025-03-02")), job 0871"))
        XCTAssertFalse(answer.contains("job 0702"), "a visit that does not mention it is left out")
        XCTAssertTrue(answer.contains("Flagged by the office: Replacement pattern: Inducer motor replaced twice in 14 months (evidence: jobs 0871, 0993)."))
    }

    func testANamedSerialAModelAndAPlaceAllFindTheUnit() async throws {
        let equipment = [KnownEquipment(model: "FX-90", serial: F.serial),
                         KnownEquipment(model: "FX-AH", unitKey: F.unitKey, label: "Roof, AHU-2")]
        let history = F.history(units: [
            .init(serial: F.serial, visits: [.init(date: "2026-01-01", jobNumber: "S1", summary: "Serial unit visit.")]),
            .init(unitKey: F.unitKey, visits: [.init(date: "2026-02-02", jobNumber: "R1", summary: "Roof unit visit.")]),
        ], flags: [])
        let s = source(history: history, equipment: equipment)
        let bySerial = try await run(s, ["unit": F.serial.lowercased()])
        XCTAssertTrue(bySerial.contains("Serial unit visit."))
        XCTAssertFalse(bySerial.contains("Roof unit visit."))
        let byModel = try await run(s, ["unit": "the FX-AH"])
        XCTAssertTrue(byModel.contains("for the unit at Roof, AHU-2"), byModel)
        XCTAssertTrue(byModel.contains("Roof unit visit."))
        XCTAssertFalse(byModel.contains(F.unitKey), "the office's handle is never said")
        let byPlace = try await run(s, ["unit": "roof, ahu-2"])
        XCTAssertTrue(byPlace.contains("Roof unit visit."))
    }

    func testTheActiveUnitIsUsedWhenNoneIsNamed() async throws {
        let answer = try await run(source(activeSerial: F.serial), [:])
        XCTAssertTrue(answer.hasPrefix(header))
        XCTAssertTrue(answer.contains("job 0702"), "with nothing asked about, every visit")
        XCTAssertTrue(answer.contains("Installed \(OfficeBriefText.day("2019-03-04"))."))
        XCTAssertTrue(answer.contains("For the whole site, the office flagged: Annual service due on"))
    }

    func testTheNextJobAheadIsNamedWhenNoJobIsOpen() async throws {
        let answer = try await run(source(isJobAhead: true), [:])
        XCTAssertTrue(answer.contains("sent with Job 1007, the next job ahead:"), answer)
    }

    func testSeveralUnitsAreListedAndTheModelIsToldToAsk() async throws {
        let equipment = [KnownEquipment(model: "FX-90", serial: F.serial),
                         KnownEquipment(model: "FX-40", serial: F.secondSerial)]
        let history = F.history(units: [.init(serial: F.serial), .init(serial: F.secondSerial)], flags: [])
        let answer = try await run(source(history: history, equipment: equipment), [:])
        XCTAssertEqual(answer, "The office sent service history for 2 units with Job 1007: serial \(F.serial); serial \(F.secondSerial). Ask which one the technician means, then call again with 'unit'.")
    }

    func testNothingOnFileIsSaidPlainly() async throws {
        // A unit in front of the technician the office sent nothing for.
        let other = try await run(source(activeSerial: "ZZ-999", phoneVisits: 2), [:])
        XCTAssertTrue(other.hasPrefix("There's no office history for this unit: the office sent no service history for serial ZZ-999 with Job 1007."), other)
        XCTAssertTrue(other.contains("This phone's own job history has 2 earlier visits on it, in the brief's site and history section."))
        XCTAssertFalse(other.contains("From the office's service history"), "this phone's visits are never presented as the office's")
        // A job that came with no history at all.
        let none = try await run(source(history: nil), [:])
        XCTAssertEqual(none, "There's no office history for this job: the office sent no service history with Job 1007.")
        // No job open and none ahead.
        let nothing = try await run(nil, [:])
        XCTAssertEqual(nothing, ServiceHistoryAnswer.noJobLine)
        // A unit the job does not have.
        let missing = try await run(source(), ["unit": "QQ-1"])
        XCTAssertTrue(missing.hasPrefix("Job 1007 has no unit matching \u{201C}QQ-1\u{201D}."), missing)
    }

    func testAnAboutThatMatchesNothingSaysSo() async throws {
        let answer = try await run(source(activeSerial: F.serial), ["about": "compressor"])
        XCTAssertTrue(answer.contains("None of its 3 visits on file mention \u{201C}compressor\u{201D}."), answer)
    }

    // MARK: - Warranty

    func testTheWarrantyIsAnsweredWithItsDateNoteAndAsOf() async throws {
        let answer = try await run(source(activeSerial: F.serial), ["about": "is it under warranty?"])
        XCTAssertEqual(answer, header + " Under warranty until \(OfficeBriefText.day("2027-03-01")). \(F.warrantyNote)")
        let noStatus = F.history(units: [.init(serial: F.serial)], flags: [])
        let none = try await run(source(history: noStatus, activeSerial: F.serial), ["about": "warranty"])
        XCTAssertTrue(none.hasSuffix("The office sent no warranty status for this unit."))
        let expired = F.history(units: [.init(serial: F.serial, warranty: .init(status: .expired, until: "2026-03-01", note: nil))],
                                flags: [])
        let gone = try await run(source(history: expired, activeSerial: F.serial), ["about": "warranty"])
        XCTAssertTrue(gone.hasSuffix("Warranty expired \(OfficeBriefText.day("2026-03-01"))."))
    }

    // MARK: - Gating

    func testItRefusesWithFieldAssistOff() async throws {
        UserDefaults.standard.set(false, forKey: "fieldAssistEnabled")
        let answer = try await run(source(), [:])
        XCTAssertEqual(answer, "Field Assist is disabled. Enable it in Settings → Field Assist.")
    }

    func testItReadsOnlyWhatItIsHanded() async throws {
        // The injected source is the whole of its input: with an empty one there is nothing to
        // say, however much any other part of the app might hold.
        var calls = 0
        let tool = ServiceHistoryTool(source: { calls += 1; return nil })
        let answer = try await tool.execute(args: ["about": "inducer"])
        XCTAssertEqual(answer, ServiceHistoryAnswer.noJobLine)
        XCTAssertEqual(calls, 1)
        // And the source file reaches for no network, process or model.
        let file = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("OpenGlasses/Sources/Services/NativeTools/ServiceHistoryTool.swift"),
                              encoding: .utf8)
        for forbidden in ["URLSession", "URLRequest", "LLMService", "BrainStore", "WebSocket"] {
            XCTAssertFalse(file.contains(forbidden), forbidden)
        }
    }

    func testTheLiveSourceReadsTheOpenJobThenTheNextJobAhead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SH-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["sessions", "store", "upcoming"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let sessions = FieldSessionService(sessionsRoot: root.appendingPathComponent("sessions"))
        let upcoming = UpcomingJobStore(directory: root.appendingPathComponent("upcoming"))
        let flow = GuidedJobFlow(sessions: sessions, store: ConversationStore(directory: root.appendingPathComponent("store")),
                                 seams: .init(speak: { _ in }, persistenceEnabled: { true }))
        flow.connectUpcoming(upcoming)
        let added = try XCTUnwrap(flow.addUpcomingJob(F.job()))

        let ahead = try XCTUnwrap(ServiceHistoryTool.liveSource(sessions: sessions, flow: flow))
        XCTAssertTrue(ahead.isJobAhead)
        XCTAssertEqual(ahead.history, F.history())
        XCTAssertEqual(ahead.systemName, F.systemName)

        _ = try flow.startUpcomingJob(id: added.id, vaultId: "refrigeration")
        let open = try XCTUnwrap(ServiceHistoryTool.liveSource(sessions: sessions, flow: flow))
        XCTAssertFalse(open.isJobAhead)
        XCTAssertEqual(open.jobTitle, "Job 1007")
        XCTAssertEqual(open.history, F.history())
        XCTAssertEqual(open.equipment, [KnownEquipment(model: "FX-90", serial: F.serial)],
                       "the job's machines ride beside the history so a model resolves")
        _ = try sessions.endSession()
        XCTAssertNil(sessions.history.first?.officeEquipment, "and go with it at close")
        XCTAssertNil(ServiceHistoryTool.liveSource(sessions: sessions, flow: flow))
    }

    func testItIsGatedClassifiedAndOfferedLikeEveryFieldTool() {
        XCTAssertTrue(FieldToolProfile.names.contains("service_history"), "offered during a job")
        XCTAssertEqual(OfflineToolPolicy.availability(of: "service_history"), .local, "works with no signal")
        XCTAssertEqual(ServiceHistoryTool().executionSemantics, .read(.notCancellable), "declared read-only")
        XCTAssertTrue(AIFeature.fieldAssist.record.toolNames.contains("service_history"),
                      "the Field Assist switch refuses it")
        XCTAssertTrue(LiveJobContract.jobToolNames.contains("service_history"), "live sessions get it")
        XCTAssertTrue(PromptInjectionPolicy.untrustedOutputTools.contains("service_history"),
                      "the office's records are framed as data")
    }

    func testTheDescriptionStandsAloneForThePrompt() {
        let description = ServiceHistoryTool().description
        for phrase in ["as of", "office's record", "never a diagnosis", "work order", "without signal"] {
            XCTAssertTrue(description.contains(phrase), phrase)
        }
    }
}
