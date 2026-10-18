import XCTest
@testable import OpenGlasses

/// Plan IW P2 — the Activity screen's model over a real `ActivityStore` in a scratch folder: a
/// day-grouped story, newest first, authorisation in plain words, filters, destinations, titles
/// only in HIPAA mode, and Clear. Invented titles only.
@MainActor
final class ActivityScreenModelTests: XCTestCase {

    private typealias Fx = GoalActivityFixture
    private var directory: URL!
    private var store: ActivityStore!
    private var titlesOnly = false
    private var goals: [Goal] = []
    private var threads: Set<String> = []

    override func setUp() {
        super.setUp()
        directory = Fx.workspace("ActivityScreen")
        store = ActivityStore(directory: directory, clock: { Fx.now }, hipaaMode: { false },
                              hipaaRetentionDays: { nil })
        titlesOnly = false
        goals = [Fx.goal([Fx.step(1, "Book the skip")])]
        threads = ["job-thread-1017"]
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func model() -> ActivityScreenModel {
        ActivityScreenModel(store: store,
                            goals: { [unowned self] in goals },
                            threadExists: { [unowned self] in threads.contains($0) },
                            titlesOnly: { [unowned self] in titlesOnly },
                            now: { Fx.now }, calendar: { Fx.calendar() })
    }

    private func seedMorning() {
        store.append(ActivityEntry(id: Fx.uuid(501), at: Fx.date(19, 8, 5), kind: .action,
                                   title: "Added an event to your calendar", detail: "You approved: Dentist",
                                   tool: "calendar", authorisation: .asked, origin: .wearer, outcome: .done))
        store.append(ActivityEntry(id: Fx.uuid(502), at: Fx.date(19, 8, 40), kind: .action,
                                   title: "Recorded a part on the job", tool: "record_part",
                                   authorisation: .asked, origin: .wearer, outcome: .uncertain,
                                   refs: [.operation("op-7"), .thread("job-thread-1017")]))
        store.append(ActivityFeed.goalCheckIn(goalID: Fx.uuid(1), spoken: true, at: Fx.date(19, 9)))
        store.append(ActivityEntry(id: Fx.uuid(504), at: Fx.date(19, 9, 30), kind: .held,
                                   title: "Your OK to use the send message tool", tool: "send_message",
                                   authorisation: .heldForYou, origin: .wearer, outcome: .waitingOnYou))
        store.append(ActivityEntry(id: Fx.uuid(505), at: Fx.date(18, 17), kind: .refused,
                                   title: "Didn't use the calendar tool: you said no", tool: "calendar",
                                   authorisation: .refused(reason: ActivityFeed.RefusalCode.declined),
                                   origin: .wearer, outcome: .failed))
        store.append(ActivityEntry(id: Fx.uuid(506), at: Fx.date(16, 12), kind: .scheduledRun,
                                   title: "Ran Upcoming Events", detail: "Nothing in the next half hour.",
                                   authorisation: .scheduled, origin: .scheduled, outcome: .done))
    }

    func testTheEmptyTrail() {
        let screen = model()
        XCTAssertTrue(screen.isEmpty)
        XCTAssertTrue(screen.sections.isEmpty)
    }

    func testAMorningReadsAsADayGroupedStoryNewestFirst() {
        seedMorning()
        let sections = model().sections
        XCTAssertEqual(sections.map(\.day), [.today, .yesterday, .earlier(Fx.calendar().startOfDay(for: Fx.date(16, 12)))])
        XCTAssertEqual(sections[0].rows.map(\.title), [
            "Your OK to use the send message tool",
            "Checked in on a goal",
            "Recorded a part on the job",
            "Added an event to your calendar",
        ])
        let rows = sections[0].rows
        XCTAssertEqual(rows.map(\.authorisation), ["Held for you", "Scheduled", "You approved it", "You approved it"])
        XCTAssertEqual(rows.map(\.outcome), [nil, nil, "May not have gone through", nil],
                       "a held row already says it is waiting")
        XCTAssertEqual(sections[1].rows.first?.authorisation, "Refused: you said no")
        XCTAssertNil(sections[1].rows.first?.outcome, "a refusal already says it did not run")
        XCTAssertEqual(sections[2].rows.first?.authorisation, "Scheduled")
    }

    func testRowsOpenTheGoalOrTheConversationTheyBelongTo() {
        seedMorning()
        let today = model().sections[0].rows
        let checkIn = today[1]
        XCTAssertEqual(checkIn.destination, .goal(Fx.uuid(1)))
        XCTAssertEqual(checkIn.goalTitle, "Clear the garage", "the goal is named by looking it up")
        XCTAssertEqual(today[2].destination, .thread("job-thread-1017"), "a job's action opens the job's thread")
        XCTAssertNil(today[3].destination)

        goals = []
        threads = []
        let gone = model().sections[0].rows
        XCTAssertNil(gone[1].destination, "a deleted goal is not a destination")
        XCTAssertNil(gone[1].goalTitle)
        XCTAssertNil(gone[2].destination, "nor a conversation that is no longer on the phone")
    }

    func testFilters() {
        seedMorning()
        let screen = model()
        func titles(_ filter: ActivityScreenModel.Filter) -> [String] {
            screen.filter = filter
            return screen.sections.flatMap(\.rows).map(\.title)
        }
        XCTAssertEqual(titles(.actions), ["Recorded a part on the job", "Added an event to your calendar"])
        XCTAssertEqual(titles(.held), ["Your OK to use the send message tool"])
        XCTAssertEqual(titles(.scheduled), ["Checked in on a goal", "Ran Upcoming Events"])
        XCTAssertEqual(titles(.refused), ["Didn't use the calendar tool: you said no"])
        XCTAssertEqual(titles(.all).count, 6)
    }

    func testHIPAAModeShowsTitlesOnly() {
        seedMorning()
        XCTAssertEqual(model().sections[0].rows.last?.detail, "You approved: Dentist")
        titlesOnly = true
        let screen = model()
        XCTAssertTrue(screen.showsTitlesOnly)
        XCTAssertTrue(screen.sections.flatMap(\.rows).allSatisfy { $0.detail == nil })
    }

    func testRefusalCodesInWords() {
        XCTAssertEqual(ActivityScreenModel.authorisationWords(.refused(reason: "blocked_by_safety")),
                       "Refused: a safety rule stopped it")
        XCTAssertEqual(ActivityScreenModel.authorisationWords(.refused(reason: ToolRefusalReason.featureDisabled.rawValue)),
                       "Refused: that feature is off")
        XCTAssertEqual(ActivityScreenModel.authorisationWords(.refused(reason: "something_new")),
                       "Refused: it wasn't allowed")
        XCTAssertEqual(ActivityScreenModel.authorisationWords(.standingGrant(scope: "jobs")),
                       "Under a permission you gave")
    }

    func testClearEmptiesTheTrail() {
        seedMorning()
        let screen = model()
        screen.clear()
        XCTAssertTrue(screen.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        let reopened = ActivityStore(directory: directory, clock: { Fx.now }, hipaaMode: { false },
                                     hipaaRetentionDays: { nil })
        XCTAssertTrue(reopened.entries.isEmpty, "Clear removes the file, not just the list on screen")
    }

    // MARK: - The support report's line

    func testTheSupportLineCountsAndNamesNothing() {
        seedMorning()
        let paused = Goal(id: Fx.uuid(2), title: "Paint the fence", createdAt: Fx.now, state: .paused,
                          steps: [], source: .wearer)
        let line = GoalActivityReportLine.line(goals: goals + [paused], entries: store.entries, now: Fx.now)
        XCTAssertEqual(line, "Goals: 1 active; activity entries (14 d): 6")
        XCTAssertFalse(line.contains("garage"))
        XCTAssertFalse(line.contains("calendar"))
        XCTAssertEqual(GoalActivityReportLine.line(goals: [], entries: [], now: Fx.now),
                       "Goals: 0 active; activity entries (14 d): 0")
    }
}
