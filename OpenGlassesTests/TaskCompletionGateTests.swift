import XCTest
@testable import OpenGlasses

/// A tester's Lennox job (build 497): a measurement closed a repair, the repair was then recorded
/// twice, and the test run that proved it never reached the report.
///
/// Headless: the technician's words are injected, so each case replays the tester's own sentence.
@MainActor
final class TaskCompletionGateTests: XCTestCase {

    private var tempRoot: URL!
    private var previousEntitlement: FieldAssistEntitlementProvider!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskCompletionGateTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousEntitlement = EntitlementTestScope.grant()
        VaultRegistry.shared.resetCache()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled")
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    private func liveSession() throws -> FieldSessionService {
        let service = FieldSessionService(sessionsRoot: tempRoot.appendingPathComponent("sessions"))
        _ = try service.startSession(vaultId: "refrigeration", assetId: nil, jobReference: "1027")
        return service
    }

    private let replace = "Replace the open hot-surface ignitor"

    // MARK: - The words

    func testAMeasurementIsNotARepair() {
        XCTAssertFalse(TaskCompletionStatement.states(
            "Measured the igniter and it shows me an open circuit", completing: replace))
        XCTAssertFalse(TaskCompletionStatement.states(
            "Igniter measurement shows me open circuit", completing: replace))
    }

    func testTheTestersRepairSentencesCloseIt() {
        XCTAssertTrue(TaskCompletionStatement.states("To test it out replaced", completing: replace))
        XCTAssertTrue(TaskCompletionStatement.states(
            "Igniter replaced what's the procedure to test it out", completing: replace))
        XCTAssertTrue(TaskCompletionStatement.states("swapped it for the new one", completing: replace))
        XCTAssertTrue(TaskCompletionStatement.states("put a new one in", completing: replace))
        XCTAssertTrue(TaskCompletionStatement.states("that's done", completing: replace))
        XCTAssertTrue(TaskCompletionStatement.states("checked it, all good",
                                                     completing: "Check the pressure switch tubing"))
    }

    func testDeniedOrFutureWorkDoesNotCloseIt() {
        XCTAssertFalse(TaskCompletionStatement.states("I haven't replaced it yet", completing: replace))
        XCTAssertFalse(TaskCompletionStatement.states("it needs to be replaced", completing: replace))
        XCTAssertFalse(TaskCompletionStatement.states("not done", completing: replace))
        XCTAssertFalse(TaskCompletionStatement.states("should I replace it", completing: replace))
    }

    func testPastFormsOfTitleVerbs() {
        XCTAssertTrue(TaskCompletionStatement.pastForms(of: "replace").contains("replaced"))
        XCTAssertTrue(TaskCompletionStatement.pastForms(of: "check").contains("checked"))
        XCTAssertTrue(TaskCompletionStatement.pastForms(of: "plug").contains("plugged"))
        XCTAssertTrue(TaskCompletionStatement.pastForms(of: "tidy").contains("tidied"))
        XCTAssertTrue(TaskCompletionStatement.pastForms(of: "tighten").contains("tightened"))
    }

    func testAPassedCheckNeedsAPass() {
        let said = "OK the test run bus just fine the furnace is working so prepare the report and close the job"
        XCTAssertTrue(TaskCompletionStatement.statesPassedCheck(said))
        XCTAssertTrue(TaskCompletionStatement.mentionsCheck(said))
        XCTAssertFalse(TaskCompletionStatement.statesPassedCheck("it's still not working"))
        XCTAssertFalse(TaskCompletionStatement.mentionsCheck("the customer is fine with the quote"))
    }

    func testTheTwoReplacementTitlesAreTheSameWork() {
        XCTAssertTrue(TaskTitleMatch.isSameWork(replace, "Replace hot-surface ignitor"))
        XCTAssertTrue(TaskTitleMatch.isSameWork("Replace the igniter", "Replaced ignitor"))
        XCTAssertFalse(TaskTitleMatch.isSameWork(replace, "Check the hot-surface ignitor"))
        XCTAssertFalse(TaskTitleMatch.isSameWork(replace, "Replace the flame sensor"))
    }

    // MARK: - The task tool

    func testAReadingDoesNotCloseTheRepairButTheRepairDoes() async throws {
        let service = try liveSession()
        var said = "Measured the igniter and it shows me an open circuit"
        let tool = TaskTool(sessionService: service, currentUtterance: { said })
        _ = try await ProposeTaskTool(sessionService: service).execute(args: [
            "title": replace, "citation": "SLP99UHVK Service Manual, page 20"])
        _ = try await tool.execute(args: ["verb": "accept"])

        let refused = try await tool.execute(args: ["verb": "done",
                                                    "completion_note": "Replaced hot-surface ignitor"])
        XCTAssertTrue(refused.hasPrefix("Not closed"), refused)
        XCTAssertEqual(service.activeSession?.tasks.first?.status, .inProgress)
        XCTAssertNil(service.activeSession?.tasks.first?.completionNote)

        said = "To test it out replaced"
        let closed = try await tool.execute(args: ["verb": "done", "completion_note": "Replaced"])
        XCTAssertTrue(closed.hasPrefix("Closed"), closed)
        XCTAssertEqual(service.activeSession?.tasks.first?.status, .done)
    }

    func testNoWordsLeavesTheGateOutOfTheWay() async throws {
        let service = try liveSession()
        let tool = TaskTool(sessionService: service, currentUtterance: { nil })
        _ = try await tool.execute(args: ["verb": "add", "title": "Cleaned the condensate trap"])
        let closed = try await tool.execute(args: ["verb": "done"])
        XCTAssertTrue(closed.hasPrefix("Closed"), closed)
    }

    func testTheSameRepairIsNotAddedTwice() async throws {
        let service = try liveSession()
        let tool = TaskTool(sessionService: service, currentUtterance: { "Igniter replaced" })
        _ = try await tool.execute(args: ["verb": "add", "title": replace])
        _ = try await tool.execute(args: ["verb": "done"])

        let reply = try await tool.execute(args: ["verb": "add", "title": "Replace hot-surface ignitor"])
        XCTAssertTrue(reply.contains("already on this job as done"), reply)
        XCTAssertEqual(service.activeSession?.tasks.count, 1)
    }

    func testAddingWorkAlreadyRecommendedStartsTheRecommendation() async throws {
        let service = try liveSession()
        _ = try await ProposeTaskTool(sessionService: service).execute(args: [
            "title": replace, "citation": "SLP99UHVK Service Manual, page 20"])
        let reply = try await TaskTool(sessionService: service, currentUtterance: { nil })
            .execute(args: ["verb": "add", "title": "Replace hot-surface ignitor"])
        XCTAssertTrue(reply.contains("started rather than added again"), reply)
        XCTAssertEqual(service.activeSession?.tasks.count, 1)
        XCTAssertEqual(service.activeSession?.tasks.first?.status, .inProgress)
    }

    func testTheSameRecommendationIsNotMadeTwice() async throws {
        let service = try liveSession()
        let propose = ProposeTaskTool(sessionService: service)
        _ = try await propose.execute(args: ["title": replace, "citation": "SLP99UHVK Service Manual, page 20"])
        let reply = try await propose.execute(args: ["title": "Replace hot-surface ignitor",
                                                     "citation": "SLP99UHVK Service Manual, page 20"])
        XCTAssertTrue(reply.contains("not recommended again"), reply)
        XCTAssertEqual(service.activeSession?.tasks.count, 1)
    }

    // MARK: - The final check

    func testThePassedTestRunGoesOnTheJobAsItCloses() async throws {
        let service = try liveSession()
        let said = "OK the test run bus just fine the furnace is working so prepare the report and close the job"
        let task = TaskTool(sessionService: service, currentUtterance: { "Igniter replaced" })
        _ = try await task.execute(args: ["verb": "add", "title": replace])
        _ = try await task.execute(args: ["verb": "done"])

        let tool = FieldSessionTool(service: service, currentUtterance: { said })
        _ = try await tool.execute(args: ["action": "end", "outcome": "resolved"])

        let ended = try XCTUnwrap(service.history.first)
        let check = try XCTUnwrap(ended.tasks.first { $0.title == FieldSessionService.finalCheckTitle })
        XCTAssertEqual(check.status, .done)
        XCTAssertEqual(check.completionNote, said)
        XCTAssertEqual(check.verification?.isVerified, true)
        XCTAssertTrue(WorkRecord.line(for: check).contains("operational test"))
    }

    func testNoTestMentionedRecordsNoCheck() async throws {
        let service = try liveSession()
        let task = TaskTool(sessionService: service, currentUtterance: { "Igniter replaced" })
        _ = try await task.execute(args: ["verb": "add", "title": replace])
        _ = try await task.execute(args: ["verb": "done"])

        let tool = FieldSessionTool(service: service, currentUtterance: { "the customer is fine, close the job" })
        _ = try await tool.execute(args: ["action": "end"])
        XCTAssertFalse(try XCTUnwrap(service.history.first).tasks.contains { $0.isVerificationTask })
    }

    func testTheModelsTestResultIsUsedWhenTheWordsSayNothing() {
        XCTAssertEqual(FieldSessionTool.passedTest(stated: "heat cycle passed", said: "close the job"),
                       "heat cycle passed")
        XCTAssertNil(FieldSessionTool.passedTest(stated: "test failed", said: "close the job"))
    }
}
