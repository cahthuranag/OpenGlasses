import XCTest
@testable import OpenGlasses

/// Plan IW P0 — "what have you done today?" and "what's next?", spoken. Windows are the wearer's
/// own day, the answer fits the My Day ceiling, and what is waiting on the wearer is said last,
/// every time.
final class ActivityPhraserTests: XCTestCase {
    private typealias F = GoalActivityFixture

    private let dentist = F.entry(1, at: F.date(19, 8, 10), title: "Added the dentist to your calendar", tool: "calendar")
    private let skips = F.entry(2, at: F.date(19, 9), title: "Searched for skip hire and saved two options")
    private let parts = F.entry(3, at: F.date(19, 9, 30), title: "Recorded four parts on job 1017",
                                tool: "van_stock", authorisation: .standingGrant(scope: "van-stock"))
    private let lateLastNight = F.entry(4, at: F.date(18, 23, 30), title: "Set a reminder for you", tool: "reminder")
    private let approval = F.entry(5, at: F.date(19, 7), title: "Approve the parts order for job 1017",
                                   kind: .held, outcome: .waitingOnYou, authorisation: .heldForYou)

    private var auckland: ActivityPhraser { ActivityPhraser(now: F.now, timeZone: F.auckland) }

    // MARK: - The plan's example

    func testTodayCountsThenNamesThenSaysNothingIsWaiting() {
        XCTAssertEqual(auckland.summary(of: [dentist, skips, parts, lateLastNight], window: .today),
                       "Today I did three things. Added the dentist to your calendar. "
                           + "Searched for skip hire and saved two options. Recorded four parts on job 1017. "
                           + "Nothing is waiting on you.")
    }

    // MARK: - Windows

    /// 11:30 PM yesterday in Auckland is 10:30 AM "today" in UTC. The wearer's zone decides.
    func testTodayIsTheWearersDayNotUTC() {
        let entries = [dentist, skips, parts, lateLastNight]
        let utc = ActivityPhraser(now: F.now, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(auckland.entries(entries, in: .today).map(\.id), [dentist.id, skips.id, parts.id])
        XCTAssertEqual(utc.entries(entries, in: .today).map(\.id),
                       [lateLastNight.id, dentist.id, skips.id, parts.id])
        XCTAssertTrue(utc.summary(of: entries, window: .today).hasPrefix("Today I did four things."))
    }

    func testThisMorningEndsAtNoon() {
        let afternoon = ActivityPhraser(now: F.date(19, 14), timeZone: F.auckland)
        let lunch = F.entry(6, at: F.date(19, 12, 30), title: "Started a timer for you", tool: "set_timer")
        XCTAssertEqual(afternoon.summary(of: [parts, lunch], window: .thisMorning),
                       "This morning I did one thing. Recorded four parts on job 1017. Nothing is waiting on you.")
        // Before noon, the morning so far.
        XCTAssertEqual(auckland.interval(for: .thisMorning),
                       DateInterval(start: F.date(19, 0), end: F.now))
    }

    func testSinceATimeNamesThatTime() {
        XCTAssertEqual(auckland.summary(of: [dentist, skips, parts], window: .since(F.date(19, 9, 15))),
                       "Since 9:15 AM, I did one thing. Recorded four parts on job 1017. Nothing is waiting on you.")
        XCTAssertEqual(auckland.interval(for: .since(F.date(19, 11))), DateInterval(start: F.now, end: F.now),
                       "a start in the future is an empty window, not a crash")
    }

    func testNothingDoneSaysSoAndStillSaysWhatIsWaiting() {
        XCTAssertEqual(auckland.summary(of: [lateLastNight], window: .today),
                       "I haven't done anything today, and nothing is waiting on you.")
        XCTAssertEqual(auckland.summary(of: [approval], window: .today),
                       "I haven't done anything else today. One thing is waiting on you: "
                           + "approve the parts order for job 1017.")
    }

    // MARK: - Counts by kind, outcomes, waiting last

    func testCountsByKindInAFixedOrder() {
        let entries = [
            F.entry(10, at: F.date(19, 6), title: "Ran your morning check", kind: .scheduledRun, authorisation: .scheduled),
            F.entry(11, at: F.date(19, 7), title: "Told you the parcel arrived", kind: .toldYou),
            F.entry(12, at: F.date(19, 8), title: "Told you the rain is coming", kind: .toldYou),
            dentist, skips,
        ]
        XCTAssertTrue(auckland.summary(of: entries, window: .today)
            .hasPrefix("Today I did two things, ran one scheduled task, and passed on two updates."))
    }

    func testWaitingOnYouIsLastEvenWhenItCameFirst() {
        let text = auckland.summary(of: [approval, dentist, skips], window: .today)
        XCTAssertEqual(text, "Today I did two things. Added the dentist to your calendar. "
                           + "Searched for skip hire and saved two options. "
                           + "One thing is waiting on you: approve the parts order for job 1017.")
    }

    func testSeveralThingsWaiting() {
        let second = F.entry(7, at: F.date(19, 8), title: "A message to the office", kind: .held,
                             outcome: .waitingOnYou, authorisation: .heldForYou)
        let third = F.entry(8, at: F.date(19, 9), title: "Confirm the van stock count", kind: .held,
                            outcome: .waitingOnYou, authorisation: .heldForYou)
        XCTAssertEqual(auckland.waitingSentence([second, approval]),
                       "Two things are waiting on you: approve the parts order for job 1017 and a message to the office.")
        XCTAssertEqual(auckland.waitingSentence([third, second, approval]),
                       "Three things are waiting on you, starting with approve the parts order for job 1017 "
                           + "and a message to the office.")
    }

    func testFailedAndUncertainEntriesSaySo() {
        let failed = F.entry(20, at: F.date(19, 8), title: "Sent the report to the office", outcome: .failed)
        let unsure = F.entry(21, at: F.date(19, 9), title: "Sent a message for you", outcome: .uncertain)
        XCTAssertEqual(auckland.summary(of: [failed, unsure], window: .today),
                       "Today I did two things. Sent the report to the office, but it didn't work. "
                           + "Sent a message for you, but I couldn't confirm it went through. Nothing is waiting on you.")
    }

    /// Something that went wrong is told even when quieter entries crowd the list.
    func testProblemsAreAmongTheEntriesRead() {
        var entries = (0..<7).map { F.entry(30 + $0, at: F.date(19, 8, $0), title: "Saved note \($0)") }
        let failed = F.entry(40, at: F.date(19, 6), title: "Sent the report to the office", outcome: .failed)
        entries.append(failed)
        let text = auckland.summary(of: entries, window: .today)
        XCTAssertTrue(text.contains("Sent the report to the office, but it didn't work."), text)
        XCTAssertTrue(text.contains("And three more things."), text)
    }

    // MARK: - The 35-second ceiling

    func testALongDayFitsTheCeilingAndKeepsTheWaitingLine() {
        let long = "recorded a long list of parts used from your van at the far end of the valley road"
        let entries = (0..<12).map { F.entry(50 + $0, at: F.date(19, 6, $0 * 4), title: "Job \(100 + $0): \(long)") } + [approval]
        let text = auckland.summary(of: entries, window: .today)
        XCTAssertLessThanOrEqual(MyDaySpeechPolicy.estimatedDuration(for: text), MyDaySpeechPolicy.maximumDuration)
        XCTAssertTrue(text.hasPrefix("Today I did twelve things."), text)
        XCTAssertTrue(text.hasSuffix("One thing is waiting on you: approve the parts order for job 1017."), text)
        let spoken = entries.filter { text.contains($0.title) && $0.outcome != .waitingOnYou }.count
        XCTAssertLessThan(spoken, ActivityPhraser.maximumSpokenEntries, "the ceiling must have cost entries")
        XCTAssertGreaterThan(spoken, 0)
        XCTAssertTrue(text.contains("And \(SpokenPhrasing.number(12 - spoken)) more things."), text)
    }

    func testSpokenEntriesAreInTimeOrder() {
        let text = auckland.summary(of: [parts, dentist, skips], window: .today)
        let positions = [dentist, skips, parts].compactMap { text.range(of: $0.title)?.lowerBound }
        XCTAssertEqual(positions, positions.sorted())
        XCTAssertEqual(positions.count, 3)
    }

    // MARK: - What's next

    func testWhatsNextMergesGoalsScheduledTasksAndWaiting() {
        let garage = F.goal([F.step(1, "Book the skip", state: .done),
                             F.step(2, "List the bike for sale", dueAt: F.date(24, 12))])
        let lounge = F.goal([F.step(1, "Order the rug")], title: "Sort the lounge")
        let paused = F.goal([F.step(1, "Paint the fence")], state: .paused, title: "Fence")
        let scheduled = [
            UpcomingScheduledTask(name: "Morning check", dueAt: F.date(19, 16)),
            UpcomingScheduledTask(name: "Weekly review", dueAt: F.date(21, 9)),
            UpcomingScheduledTask(name: "Already run", dueAt: F.date(19, 9)),
        ]
        XCTAssertEqual(auckland.whatsNext(goals: [garage, lounge, paused], scheduled: scheduled,
                                          entries: [dentist, approval]),
                       "Here's what's next. I'll run Morning check today at 4 PM. "
                           + "Clear the garage: list the bike for sale, due Saturday. Sort the lounge: order the rug. "
                           + "One thing is waiting on you: approve the parts order for job 1017.")
    }

    func testWhatsNextWhenThereIsNothing() {
        XCTAssertEqual(auckland.whatsNext(goals: [], scheduled: [], entries: [dentist]),
                       "Nothing's coming up, and nothing is waiting on you.")
        XCTAssertEqual(auckland.whatsNext(goals: [], scheduled: [], entries: [approval]),
                       "Nothing else is coming up. One thing is waiting on you: approve the parts order for job 1017.")
    }

    func testWhatsNextNamesAtMostFourThings() {
        let goals = (1...6).map { F.goal([F.step(1, "Step")], dueAt: F.date(19 + $0, 9), title: "Goal \($0)") }
        let text = auckland.whatsNext(goals: goals, scheduled: [], entries: [])
        XCTAssertEqual(text, "Here's what's next. Goal 1: step, due tomorrow. Goal 2: step, due Wednesday. "
                           + "Goal 3: step, due Thursday. Goal 4: step, due Friday. And two more things.")
    }
}
