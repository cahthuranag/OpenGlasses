import XCTest
@testable import OpenGlasses

@MainActor
final class PilotReportPromptPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        return c
    }
    private func date(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: .init(year: 2026, month: 9, day: day, hour: hour))!
    }
    private func offer(sent: Set<String> = [], last: String? = nil, enabled: Bool = true,
                       job: Bool = false, live: Bool = false, car: Bool = false) -> [Date] {
        PilotReportPromptPolicy.daysToOffer(now: date(29),
            activityDays: [date(29), date(30), date(28), date(28), date(27), date(22), date(21)],
            sentDays: sent, lastPromptDay: last, enabled: enabled, jobOpen: job, live: live,
            carPlay: car, calendar: calendar)
    }
    func testUnsentDaysInCalendarWindowNewestFirstAcrossDST() {
        XCTAssertEqual(offer(), [28, 27, 22].map { calendar.startOfDay(for: date($0)) })
        XCTAssertEqual(offer(sent: [PilotReportPromptPolicy.dayKey(date(28), calendar: calendar)]),
                       [27, 22].map { calendar.startOfDay(for: date($0)) })
    }
    func testBusyOrOffDoesNotPromptOrConsumeTheDay() {
        XCTAssertEqual(offer(enabled: false), [])
        XCTAssertEqual(offer(job: true), [])
        XCTAssertEqual(offer(live: true), [])
        XCTAssertEqual(offer(car: true), [])
        XCTAssertEqual(offer(last: PilotReportPromptPolicy.dayKey(date(29), calendar: calendar)), [])
        XCTAssertFalse(offer(last: PilotReportPromptPolicy.dayKey(date(28), calendar: calendar)).isEmpty)
    }
    func testCancellationDismissalSuccessfulSendAndDeparture() throws {
        let name = "PilotReportTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PilotReportStore(defaults: defaults)
        defaults.set(true, forKey: "pilotReportsEnabled")
        defaults.set(["pilot@example.com"], forKey: "pilotReportRecipients")
        store.prompted(at: date(28), calendar: calendar)
        // Cancel and Not now do not write a sent day, so yesterday is eligible tomorrow.
        XCTAssertTrue(store.sentDays.isEmpty)
        XCTAssertFalse(offer(sent: store.sentDays, last: store.lastPromptDay).isEmpty)
        store.sent(day: date(28), now: date(29), calendar: calendar)
        XCTAssertFalse(offer(sent: store.sentDays).contains(calendar.startOfDay(for: date(28))))
        store.sent(day: date(1), now: date(29), calendar: calendar)
        XCTAssertFalse(store.sentDays.contains(PilotReportPromptPolicy.dayKey(date(1), calendar: calendar)),
                       "a review left open for weeks cannot grow the bounded marker set")
        store.clear()
        XCTAssertFalse(store.enabled)
        XCTAssertNil(store.recipients)
        XCTAssertTrue(store.sentDays.isEmpty)
        XCTAssertNil(store.lastPromptDay)
    }
    func testRecipientsRejectWholeInvalidListAndLimitToThree() {
        XCTAssertNil(PilotReportRecipients.validated([]))
        XCTAssertNil(PilotReportRecipients.validated(["a@example.com", "bad"]))
        XCTAssertNil(PilotReportRecipients.validated(Array(repeating: "a@example.com", count: 4)))
        XCTAssertEqual(PilotReportRecipients.validated([" a@example.com ", "b@example.com", "A@example.com"]),
                       ["a@example.com", "b@example.com"])
    }
    func testAllActivityDaysIncludeConversationsAndTraceAndTrailOnlyDays() {
        let days = JobTranscriptExport.activityDays(sessions: [],
            conversations: [[date(28), date(28, hour: 11)], [date(28), date(27)]],
            traces: [date(26), date(30)], activity: [date(25), date(16), date(15)],
            now: date(29), calendar: calendar)
        XCTAssertEqual(days.map(\.day), [28, 27, 26, 25, 16].map { calendar.startOfDay(for: date($0)) })
        XCTAssertEqual(days[0].conversationCount, 2)
        XCTAssertEqual(days[2].traceCount, 1)
        XCTAssertEqual(days[3].activityCount, 1)
    }
    func testPersistedHistoryKeepsSevenDaysAndPrunesByMeasuredCapacity() {
        let now = date(29)
        let entries = (0...8).map { offset in
            DiagnosticRing.Entry(timestamp: calendar.date(byAdding: .day, value: -offset, to: now)!,
                                  category: .lifecycle, name: .app, line: "event-\(offset)")
        }.reversed()
        let retained = DiagnosticBreadcrumbStore.retained(Array(entries).map { Optional($0) },
            capacity: DiagnosticRing.defaultCapacity, maxAge: DiagnosticRing.defaultMaxAge, now: now)
        XCTAssertEqual(retained.entries.map(\.line), (0...7).reversed().map { "event-\($0)" })
        let bounded = DiagnosticBreadcrumbStore.retained(retained.entries.map { Optional($0) },
            capacity: 3, maxAge: DiagnosticRing.defaultMaxAge, now: now)
        XCTAssertEqual(bounded.entries.map(\.line), ["event-2", "event-1", "event-0"])
        XCTAssertEqual(bounded.entries.first?.gapBefore, 5)
    }

    func testDiagnosticAgePolicyIsSevenDaysWithBoundedCapacity() {
        XCTAssertEqual(DiagnosticRing.defaultMaxAge, 7 * 24 * 60 * 60)
        XCTAssertEqual(DiagnosticRing.defaultCapacity, 14_000)
        XCTAssertEqual(DiagnosticBreadcrumbStore.maxFileSize, 16_000_000)
        XCTAssertTrue(DiagnosticExportBuilder.explanation.joined().contains("7 days"))
        XCTAssertTrue(SensitiveStore.diagnosticBreadcrumbs.record.retention.rendered.contains("7 days"))
    }
}
