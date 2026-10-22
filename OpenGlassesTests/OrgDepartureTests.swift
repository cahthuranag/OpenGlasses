import XCTest
@testable import OpenGlasses

/// Plan CT PR 4 — leaving the firm: the organisation's content goes at once; its session logs and
/// waiting reports go to it first and are erased once its endpoint has accepted them, or once the
/// window has passed; nothing is erased mid-job.
@MainActor
final class OrgDepartureTests: XCTestCase {

    private var now = Date(timeIntervalSince1970: 1_790_000_000)
    private var saved: OrgDeparture?
    private var sessions: [(id: String, startedAt: Date)] = []
    private var activeJob: String?
    private var erasedContentFor: [String?] = []
    private var erasedRecords: [[String]] = []
    private var endpoint = false
    private var outstandingCount = 0
    private var flushes = 0
    private var events: [String] = []
    private var closeFails = false
    private let enrolledAt = Date(timeIntervalSince1970: 1_789_000_000)

    override func setUp() {
        super.setUp()
        now = Date(timeIntervalSince1970: 1_790_000_000)
        saved = nil
        sessions = [("before", enrolledAt.addingTimeInterval(-60)),
                    ("job-1", enrolledAt.addingTimeInterval(3_600)),
                    ("job-2", enrolledAt.addingTimeInterval(7_200))]
        activeJob = nil
        erasedContentFor = []
        erasedRecords = []
        endpoint = false
        outstandingCount = 0
        flushes = 0
        events = []
        closeFails = false
    }

    private func makeService() -> OrgDepartureService {
        var seams = OrgDepartureService.Seams()
        seams.now = { [unowned self] in self.now }
        seams.load = { [unowned self] in self.saved }
        seams.save = { [unowned self] in self.saved = $0 }
        seams.sessionIds = { [unowned self] since in self.sessions.filter { $0.startedAt >= since }.map { $0.id } }
        seams.activeJobId = { [unowned self] in self.activeJob }
        seams.closeJobs = { [unowned self] ids, _ in
            if self.closeFails { throw URLError(.cannotWriteToFile) }
            if let active = self.activeJob, ids.contains(active) {
                self.events.append("close")
                self.activeJob = nil
            }
        }
        seams.eraseContent = { [unowned self] packId in
            self.events.append("erase-content")
            self.erasedContentFor.append(packId)
        }
        seams.hasEndpoint = { [unowned self] in self.endpoint }
        seams.flushEndpoint = { [unowned self] in
            self.events.append("flush")
            self.flushes += 1
        }
        seams.outstanding = { [unowned self] _ in self.outstandingCount }
        seams.eraseRecords = { [unowned self] ids in self.erasedRecords.append(ids) }
        let service = OrgDepartureService(seams: seams)
        service.loadAtLaunch()
        return service
    }

    private func leave(_ service: OrgDepartureService, reason: OrgDeparture.Reason = .revoked,
                       days: Int? = nil) async {
        await service.begin(reason, organizationName: "Northbridge Mechanical", enrolmentId: "e1",
                            enrolledAt: enrolledAt, packId: "hvac_rtu_pack", undeliveredEraseDays: days)
    }

    // MARK: - At once

    func testTheFirmsContentGoesAtOnceAndOnlyTheManagedPeriodsLogsAreOwed() async {
        let service = makeService()
        await leave(service)
        XCTAssertEqual(erasedContentFor, ["hvac_rtu_pack"], "the pack's vault, jobs ahead and staged exports")
        XCTAssertEqual(saved?.sessionIds, ["job-1", "job-2"], "a log from before enrolment is the wearer's own")
        XCTAssertEqual(saved?.eraseBy, now.addingTimeInterval(30 * 86_400), "30 days unless the profile says")
    }

    func testTheProfileSetsTheWindowWithinItsBounds() async {
        let service = makeService()
        await leave(service, days: 10)
        XCTAssertEqual(saved?.eraseBy, now.addingTimeInterval(10 * 86_400))

        saved = nil
        let other = makeService()
        await leave(other, days: 9_999)
        XCTAssertEqual(saved?.eraseBy, now.addingTimeInterval(365 * 86_400))
    }

    // MARK: - Delivered, then erased

    func testAcceptedByTheEndpointMeansDeliveredAndErased() async {
        endpoint = true
        let service = makeService()
        await leave(service)
        XCTAssertEqual(flushes, 1)
        XCTAssertEqual(erasedRecords, [["job-1", "job-2"]])
        XCTAssertEqual(saved?.deliveredToFirm, true)
        XCTAssertFalse(saved?.isPending ?? true)
    }

    func testUnacceptedRecordsWaitAndAreRetriedUntilTheEndpointTakesThem() async {
        endpoint = true
        outstandingCount = 2
        let service = makeService()
        await leave(service)
        XCTAssertEqual(erasedRecords, [], "not accepted yet — kept, and retried")
        XCTAssertTrue(saved?.isPending ?? false)

        outstandingCount = 0
        now = now.addingTimeInterval(86_400)
        await makeService().settle()
        XCTAssertEqual(erasedRecords.count, 1)
        XCTAssertEqual(saved?.deliveredToFirm, true)
    }

    func testWithoutAnEndpointNothingCountsAsDeliveredAndTheWindowDecides() async {
        let service = makeService()
        await leave(service)
        XCTAssertEqual(flushes, 0, "no endpoint: the local sink would mark records done without sending")
        XCTAssertEqual(erasedRecords, [])

        now = now.addingTimeInterval(29 * 86_400)
        await service.settle()
        XCTAssertEqual(erasedRecords, [])

        now = now.addingTimeInterval(86_400)
        await service.settle()
        XCTAssertEqual(erasedRecords, [["job-1", "job-2"]])
        XCTAssertEqual(saved?.deliveredToFirm, false, "the erasure records that it never reached the firm")
    }

    func testALapseClosesItsExistingJobAndDeliversTheRecord() async {
        endpoint = true
        activeJob = "job-2"
        let service = makeService()
        await leave(service, reason: .lapsed)
        now = now.addingTimeInterval(40 * 86_400)
        await service.settle()
        XCTAssertNil(activeJob)
        XCTAssertEqual(erasedRecords.count, 1)
    }

    func testRevocationAndRemovalCloseTheManagedJobBeforeCleanupAndDelivery() async {
        for reason: OrgDeparture.Reason in [.revoked, .removed] {
            saved = nil
            events = []
            endpoint = true
            activeJob = "job-2"
            let service = makeService()
            await leave(service, reason: reason)
            XCTAssertNil(activeJob)
            XCTAssertEqual(events, ["close", "erase-content", "flush"])
            XCTAssertEqual(service.departure?.deliveredToFirm, true)
        }
    }

    func testFailedClosureRemainsLockedAndRetriesAfterRestart() async {
        activeJob = "job-2"
        closeFails = true
        let service = makeService()
        await leave(service)
        XCTAssertTrue(saved?.isPending == true)
        XCTAssertEqual(erasedContentFor.count, 0)
        XCTAssertEqual(flushes, 0)

        closeFails = false
        await makeService().settle()
        XCTAssertNil(activeJob)
        XCTAssertEqual(erasedContentFor, ["hvac_rtu_pack"])
    }

    func testAPersonalJobDoesNotDelayDeliveryOfTheFormerOrganisationsRecords() async {
        activeJob = "personal-job"
        endpoint = true
        await leave(makeService())
        XCTAssertEqual(activeJob, "personal-job")
        XCTAssertEqual(flushes, 1)
        XCTAssertEqual(saved?.deliveredToFirm, true)
    }

    func testRevocationUpgradesAPendingLapseAndCannotBeUndoneByRenewal() async {
        activeJob = "job-2"
        let service = makeService()
        await leave(service, reason: .lapsed)
        await leave(service, reason: .revoked)
        XCTAssertNil(activeJob)
        XCTAssertEqual(saved?.reason, .revoked)
        service.cancelLapse(enrolmentId: "e1")
        XCTAssertEqual(saved?.reason, .revoked)
    }

    func testLocalFallbackCannotMarkAnOrganisationsRecordAsSent() async {
        let local = LocalSyncSink()
        let sink = UndeliveredHandoverSink(fallback: local, ownedIDs: { ["job-1"] })
        let owned = QueuedOp(kind: .workRecord, sessionId: "job-1")
        let result = await sink.deliver(owned)
        guard case .waiting = result else { return XCTFail("Local storage is not delivery to the firm") }
        XCTAssertTrue(local.delivered.isEmpty)
    }

    func testLocalFallbackHoldsAnExpiredSubscribersHandoverWithoutChangingOrdinarySync() async {
        let local = LocalSyncSink()
        let sink = UndeliveredHandoverSink(fallback: local, ownedIDs: { [] })
        let handover = QueuedOp.make(kind: .workRecord, sessionId: "personal-job",
            json: ["access_closure": ["outcome": "deferred", "reason": "Subscription expired"]])
        let result = await sink.deliver(handover)
        guard case .waiting = result else { return XCTFail("An expiry handover needs real delivery too") }
        XCTAssertTrue(local.delivered.isEmpty)
        let ordinary = QueuedOp(kind: .logEntry, sessionId: "personal-job")
        let ordinaryResult = await sink.deliver(ordinary)
        XCTAssertEqual(ordinaryResult, .done)
        XCTAssertEqual(local.delivered, [ordinary.id])
    }

    func testLeavingTwiceForTheSameEnrolmentChangesNothing() async {
        outstandingCount = 1
        endpoint = true
        let service = makeService()
        await leave(service, reason: .revoked)
        let first = saved
        now = now.addingTimeInterval(3_600)
        await leave(service, reason: .removed)
        XCTAssertEqual(saved, first, "a revoked phone its owner then removes keeps the first window")
        XCTAssertEqual(erasedContentFor.count, 1)
    }

    // MARK: - Which logs are the firm's

    func testOnlyLogsFromTheManagedPeriodAreTheFirms() {
        func session(_ id: String, _ offset: TimeInterval) -> FieldSession {
            FieldSession(id: id, vaultId: "v", assetId: nil, mode: .aiOnly,
                         startedAt: enrolledAt.addingTimeInterval(offset), outcome: .resolved,
                         escalations: [], billableSeconds: 0)
        }
        let history = [session("mine", -60), session("theirs", 0), session("theirs-too", 3_600)]
        XCTAssertEqual(OrgDepartureService.managedSessionIds(history, since: enrolledAt),
                       ["theirs", "theirs-too"],
                       "the removal prompt and the departure agree on what is owed")
    }
}
