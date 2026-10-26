import XCTest
@testable import OpenGlasses

/// Plan IW P1 — the feeders. Each existing hook turns what it already knows into at most one trail
/// entry: the router for what it ran, confirmed, refused or held; the journal for how an uncertain
/// call settled; the scheduler for each run; the plan executor for each step; the notification
/// queue for what it said straight away. Reads make nothing, and nothing carries the wearer's words.
@MainActor
final class ActivityFeederTests: XCTestCase {
    private typealias F = GoalActivityFixture

    private var journalDirectory: URL!
    private var savedAgentMode = false

    override func setUp() {
        super.setUp()
        journalDirectory = F.workspace("ActivityFeederTests")
        savedAgentMode = Config.agentModeEnabled
        Config.setAgentModeEnabled(false)
    }

    override func tearDown() {
        Config.setAgentModeEnabled(savedAgentMode)
        try? FileManager.default.removeItem(at: journalDirectory)
        super.tearDown()
    }

    // MARK: - Fixtures

    private final class FakeTool: NativeTool {
        let name: String
        let description = "activity feeder fixture"
        var parametersSchema: [String: Any] { ["type": "object"] }
        let executionSemantics: ToolExecutionSemantics
        let delay: UInt64
        private(set) var runs = 0

        init(_ name: String, _ semantics: ToolExecutionSemantics, delay: UInt64 = 0) {
            self.name = name
            self.executionSemantics = semantics
            self.delay = delay
        }

        func execute(args: [String: Any]) async throws -> String {
            runs += 1
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            return "done"
        }
    }

    private func router(_ tools: [FakeTool]) -> (NativeToolRouter, FakeActivityRecorder) {
        let registry = NativeToolRegistry(locationService: LocationService())
        tools.forEach(registry.register)
        let router = NativeToolRouter(registry: registry)
        router.operationJournal = ProtectedOperationJournal(directory: journalDirectory)
        let recorder = FakeActivityRecorder()
        router.activityRecorder = recorder
        return (router, recorder)
    }

    private func answer(_ coordinator: ToolConfirmationCoordinator, approve: Bool) async {
        for _ in 0..<200 {
            if coordinator.pending != nil {
                coordinator.resolve(approve)
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("confirmation never became pending")
    }

    // MARK: - The router

    func testACalendarCreateTheWearerAskedForMakesOneAskedEntry() async {
        let (router, recorder) = router([FakeTool("calendar", .local())])
        let outcome = await router.executeRoot(name: "calendar",
                                               args: ["action": "create", "title": "Dentist"],
                                               invocationID: "call-1")
        XCTAssertEqual(outcome, .completed("done"))
        XCTAssertEqual(recorder.entries.count, 1)
        let entry = recorder.entries[0]
        XCTAssertEqual(entry.title, "Added an event to your calendar")
        XCTAssertEqual(entry.kind, .action)
        XCTAssertEqual(entry.authorisation, .asked)
        XCTAssertEqual(entry.origin, .wearer)
        XCTAssertEqual(entry.outcome, .done)
        XCTAssertEqual(entry.refs, [.operation("call-1")])
        XCTAssertNil(entry.detail, "nothing the wearer said is copied into the trail")
    }

    func testAConfirmedCallIsAskedAndCarriesTheApprovalLineWithoutTheBody() async {
        let (router, recorder) = router([FakeTool("send_message", .external(.bestEffort))])
        let coordinator = ToolConfirmationCoordinator()
        router.confirmationCoordinator = coordinator

        async let outcome = router.executeRoot(name: "send_message",
                                               args: ["to": "Mere", "body": "running late"])
        await answer(coordinator, approve: true)
        let result = await outcome
        XCTAssertEqual(result, .completed("done"))

        XCTAssertEqual(recorder.entries.count, 1)
        let entry = recorder.entries[0]
        XCTAssertEqual(entry.authorisation, .asked)
        XCTAssertEqual(entry.title, "Sent a message for you")
        XCTAssertEqual(entry.detail, "You approved: Send a message to Mere")
        XCTAssertFalse((entry.detail ?? "").contains("running late"))
    }

    func testAReadMakesNoEntry() async {
        let (router, recorder) = router([FakeTool("calendar", .local()), FakeTool("get_weather", .read())])
        _ = await router.executeRoot(name: "calendar", args: ["action": "today"])
        _ = await router.executeRoot(name: "get_weather", args: [:])
        XCTAssertTrue(recorder.entries.isEmpty)
    }

    func testADeclinedCallIsRecordedAsRefused() async {
        let tool = FakeTool("send_message", .external(.bestEffort))
        let (router, recorder) = router([tool])
        let coordinator = ToolConfirmationCoordinator()
        router.confirmationCoordinator = coordinator

        async let outcome = router.executeRoot(name: "send_message", args: ["to": "Mere"])
        await answer(coordinator, approve: false)
        guard case .rejected = await outcome else { return XCTFail("a declined call must not run") }

        XCTAssertEqual(tool.runs, 0)
        XCTAssertEqual(recorder.entries.count, 1)
        XCTAssertEqual(recorder.entries[0].kind, .refused)
        XCTAssertEqual(recorder.entries[0].authorisation, .refused(reason: "declined"))
        XCTAssertEqual(recorder.entries[0].title, "Didn't use the send message tool: you said no")
    }

    func testAFloorRefusalIsRecordedWithItsReason() async {
        let (router, recorder) = router([])
        let parent = ResolvedToolCall.root(name: "pack_tidy", origin: .model)
        let child = parent.child(name: SkillPackToolWrapper.namePrefix + "other",
                                 arguments: ToolArguments(), composerID: "tidy")
        guard case .rejected = await router.execute(child) else { return XCTFail("chaining is refused") }
        XCTAssertEqual(recorder.entries.map(\.authorisation),
                       [.refused(reason: ToolRefusalReason.packChaining.rawValue)])
        XCTAssertEqual(recorder.entries.first?.outcome, .failed)
    }

    func testANoCoordinatorRefusalIsRecorded() async {
        let (router, recorder) = router([FakeTool("send_message", .external(.bestEffort))])
        router.confirmationCoordinator = nil
        _ = await router.executeRoot(name: "send_message", args: ["to": "Mere"])
        XCTAssertEqual(recorder.entries.map(\.authorisation), [.refused(reason: "no_confirmation")])
    }

    func testAHeldActionIsWaitingOnTheWearer() async {
        Config.setAgentModeEnabled(true)
        let (router, recorder) = router([FakeTool("send_message", .external(.bestEffort))])
        router.safetyContextProvider = {
            SafetyContext(now: Date(), location: nil, homeRegion: nil, enabledRules: [],
                          quietHoursStart: 22, quietHoursEnd: 7, autonomy: .paused)
        }
        var held: [String] = []
        router.onActionHeld = { held.append($0) }
        _ = await router.executeRoot(name: "send_message", args: ["to": "Mere", "body": "hi"])

        XCTAssertEqual(held.count, 1, "the held-recommendation hook still fires")
        XCTAssertEqual(recorder.entries.count, 1, "and the trail gets one entry for it, not two")
        let entry = recorder.entries[0]
        XCTAssertEqual(entry.kind, .held)
        XCTAssertEqual(entry.authorisation, .heldForYou)
        XCTAssertEqual(entry.outcome, .waitingOnYou)
        XCTAssertNil(entry.detail)
    }

    func testAJobsActionLinksToTheJobsThread() async {
        let previousEntitlement = EntitlementTestScope.grant(tier: .team)
        let previousEnabled = UserDefaults.standard.object(forKey: "fieldAssistEnabled")
        defer {
            EntitlementTestScope.restore(previousEntitlement)
            UserDefaults.standard.set(previousEnabled, forKey: "fieldAssistEnabled")
        }
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        let (router, recorder) = router([FakeTool("van_stock", .local())])
        router.activityJobThread = { "thread-1017" }
        _ = await router.executeRoot(name: "van_stock", args: ["action": "use"], invocationID: "call-2")
        XCTAssertEqual(recorder.entries.first?.refs, [.operation("call-2"), .thread("thread-1017")])
        XCTAssertEqual(recorder.entries.first?.title, "Recorded a part used from your van")
    }

    func testNoRecorderMeansNoEntryAndNoChangeToTheCall() async {
        let (router, _) = router([FakeTool("calendar", .local())])
        router.activityRecorder = nil
        let result = await router.executeRoot(name: "calendar", args: ["action": "create"])
        XCTAssertEqual(result, .completed("done"))
    }

    // MARK: - The journal

    func testATimedOutWriteIsUncertainAndSettlesWhenTheAnswerArrives() async throws {
        let (router, recorder) = router([FakeTool("calendar", .local(), delay: 400_000_000)])
        router.toolTimeoutSeconds = 0.05
        let outcome = await router.executeRoot(name: "calendar", args: ["action": "create"],
                                               invocationID: "call-3")
        guard case .outcomeUnknown = outcome else { return XCTFail("expected an unknown outcome, got \(outcome)") }
        XCTAssertEqual(recorder.entries.first?.outcome, .uncertain, "a journal .unknown marks the row uncertain")

        for _ in 0..<100 where recorder.entries.first?.outcome == .uncertain {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(recorder.entries.first?.outcome, .done, "the late answer settles the same row")
        XCTAssertTrue(recorder.settled.contains { $0.operationID == "call-3" && $0.outcome == .done })
        XCTAssertEqual(recorder.entries.count, 1)
    }

    func testJournalStatesMapOntoOutcomes() {
        XCTAssertEqual(ActivityFeed.outcome(of: OperationState.unknown), .uncertain)
        XCTAssertEqual(ActivityFeed.outcome(of: OperationState.completed), .done)
        XCTAssertEqual(ActivityFeed.outcome(of: OperationState.failed), .failed)
        XCTAssertNil(ActivityFeed.outcome(of: OperationState.started))
    }

    // MARK: - Scheduled runs

    func testAScheduledRunIsRecordedWithSpeakResultOff() {
        let recorder = FakeActivityRecorder()
        let task = AgentScheduler.ScheduledTask(id: "t1", name: "Tool shed check", prompt: "p",
                                                intervalMinutes: 60, enabled: true, speakResult: false)
        AgentScheduler.recordRun(of: task, result: .reported("Two tools are overdue.\nThe drill and the saw."),
                                 recorder: recorder, at: F.now)
        XCTAssertEqual(recorder.entries.count, 1)
        let entry = recorder.entries[0]
        XCTAssertEqual(entry.kind, .scheduledRun)
        XCTAssertEqual(entry.title, "Ran Tool shed check")
        XCTAssertEqual(entry.detail, "Two tools are overdue. The drill and the saw.")
        XCTAssertEqual(entry.origin, .scheduled)
        XCTAssertEqual(entry.authorisation, .scheduled)
        XCTAssertEqual(entry.outcome, .done)
    }

    func testAScheduledRunWithNothingToReportOrAFailure() {
        let nothing = ActivityFeed.scheduledRun(taskName: "Upcoming Events", result: .nothingToReport, at: F.now)
        XCTAssertNil(nothing.detail)
        XCTAssertEqual(nothing.outcome, .done)
        XCTAssertEqual(ActivityFeed.scheduledRun(taskName: "Upcoming Events", result: .failed, at: F.now).outcome,
                       .failed)
        let long = ActivityFeed.scheduledRun(taskName: "Digest", result: .reported(String(repeating: "a", count: 400)),
                                             at: F.now)
        XCTAssertEqual(long.detail?.count, ActivityEntry.detailLength)
    }

    func testACallInsideAScheduledRunIsScheduled() async {
        let (router, recorder) = router([FakeTool("reminder", .local())])
        _ = await ActivityScope.$scheduledTask.withValue("Morning check") {
            await router.executeRoot(name: "reminder", args: ["action": "create"])
        }
        XCTAssertEqual(recorder.entries.first?.authorisation, .scheduled)
        XCTAssertEqual(recorder.entries.first?.origin, .scheduled)
    }

    // MARK: - Plan steps

    func testEachSideEffectingPlanStepIsAPlannedStepWithThePlansGoal() async {
        let (router, recorder) = router([FakeTool("calendar", .local()), FakeTool("get_weather", .read())])
        let plan = AgentPlan(goal: "Get ready for the trip", steps: [
            AgentStep(tool: "get_weather", rationale: "check the forecast"),
            AgentStep(tool: "calendar", args: ["action": "create", "title": "Pack"], rationale: "hold time"),
        ])
        let result = await PlanExecutor(router: router).execute(plan)
        XCTAssertFalse(result.aborted)
        XCTAssertEqual(recorder.entries.count, 1, "the read step makes no entry")
        let entry = recorder.entries[0]
        XCTAssertEqual(entry.kind, .plannedStep)
        XCTAssertEqual(entry.detail, "Get ready for the trip")
        XCTAssertEqual(entry.origin, .agent)
        XCTAssertFalse(entry.title.contains("Pack"))
    }

    // MARK: - Told you straight away

    func testAnImmediateDeliveryRecordsToldYou() {
        let queue = AgentNotificationQueue()
        let recorder = FakeActivityRecorder()
        queue.activityRecorder = recorder
        queue.noteToldYou(message: "Your 3 pm moved to 4.", source: "Agent Task", at: F.now)
        XCTAssertEqual(recorder.entries.count, 1)
        let entry = recorder.entries[0]
        XCTAssertEqual(entry.kind, .toldYou)
        XCTAssertEqual(entry.title, "Passed on an update")
        XCTAssertEqual(entry.detail, "Your 3 pm moved to 4.")
        XCTAssertEqual(entry.origin, .scheduled)
    }

    func testNotificationSourcesMapOntoOrigins() {
        XCTAssertEqual(ActivityFeed.notificationOrigin("Agent Task"), .scheduled)
        XCTAssertEqual(ActivityFeed.notificationOrigin("OpenClaw fix"), .remote(source: "openclaw"))
        XCTAssertEqual(ActivityFeed.notificationOrigin("summary"), .agent)
    }

    // MARK: - HIPAA

    func testHIPAAModeKeepsTheTitleOnlyThroughTheProductionRecorder() {
        let directory = F.workspace("ActivityFeederHIPAA")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActivityStore(directory: directory, hipaaMode: { true }, hipaaRetentionDays: { nil })
        let recorder = ActivityRecorder(store: store)
        recorder.record(ActivityFeed.toldYou(message: "Your appointment with the clinic is at 2.",
                                             source: "Agent Task", at: Date()))
        XCTAssertEqual(store.entries.first?.title, "Passed on an update")
        XCTAssertNil(store.entries.first?.detail)
    }
}
