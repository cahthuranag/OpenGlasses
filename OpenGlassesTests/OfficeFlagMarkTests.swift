import XCTest
@testable import OpenGlasses

/// Plan HU, decided 2026-10-20 — a job ahead the office flagged as a warning carries a small mark
/// on the Jobs list row and the job-day card before it is opened, read by VoiceOver with the row.
@MainActor
final class OfficeFlagMarkTests: XCTestCase {

    private typealias F = OfficeHistoryFixtures

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func job(flags: [OfficeServiceHistory.Flag]) -> UpcomingJob {
        var job = F.job(history: F.history(flags: flags))
        job.scheduledFor = F.now.addingTimeInterval(3_600)
        return job
    }

    private let warning = OfficeServiceHistory.Flag(kind: .replacementPattern, unit: F.serial, text: F.flagText,
                                                    evidence: ["0871"], severity: .warning)
    private let info = OfficeServiceHistory.Flag(kind: .recallOrBulletin, unit: F.serial, text: "Bulletin FB-7.",
                                                 evidence: ["0871"], severity: .info)

    func testTheMarkCountsTheOfficesWarningFlagsOnly() {
        XCTAssertEqual(OfficeFlagMark.mark(for: job(flags: [warning, info])), OfficeFlagMark(warnings: 1))
        XCTAssertNil(OfficeFlagMark.mark(for: job(flags: [info])), "an info flag is not marked")
        XCTAssertNil(OfficeFlagMark.mark(for: F.job(history: nil)), "nor a job with no history")
        XCTAssertEqual(OfficeFlagMark(warnings: 1).label, "1 warning flag from the office")
        XCTAssertEqual(OfficeFlagMark(warnings: 2).label, "2 warning flags from the office")
    }

    func testTheJobsListRowCarriesTheMarkAndSaysIt() throws {
        let list = JobListComposer.compose(JobListInputs(now: F.now, calendar: calendar,
                                                         upcoming: [job(flags: [warning, warning])]))
        let row = try XCTUnwrap(list.scheduled.first)
        let badge = try XCTUnwrap(row.badges.first { $0.kind == .officeFlag })
        XCTAssertEqual(badge.label, "2 warning flags from the office")
        XCTAssertEqual(badge.symbol, OfficeFlagMark.symbol)
        XCTAssertTrue(badge.isWarning)
        XCTAssertTrue(row.spoken.contains("2 warning flags from the office"), "VoiceOver reads it with the row")

        let unflagged = JobListComposer.compose(JobListInputs(now: F.now, calendar: calendar,
                                                              upcoming: [job(flags: [info])]))
        XCTAssertFalse(unflagged.scheduled.first?.badges.contains { $0.kind == .officeFlag } ?? true)
    }

    func testTheJobDayCardCarriesTheMarkAndSaysIt() throws {
        let day = JobDayComposer.compose(JobDayInputs(now: F.now, calendar: calendar, upcoming: [job(flags: [warning])]))
        let row = try XCTUnwrap(day.jobs.first)
        XCTAssertEqual(row.officeFlag, OfficeFlagMark(warnings: 1))
        XCTAssertTrue(row.spoken.hasSuffix("1 warning flag from the office"), row.spoken)

        let plain = JobDayComposer.compose(JobDayInputs(now: F.now, calendar: calendar, upcoming: [job(flags: [info])]))
        XCTAssertNil(plain.jobs.first?.officeFlag)
        XCTAssertFalse(plain.jobs.first?.spoken.contains("flag") ?? true)
    }

    func testTheViewsGiveTheMarkItsAccessibilityLabel() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("OpenGlasses/Sources/App/Views/Job/JobDayViews.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains(".accessibilityLabel(mark.label)"), "the mark's own label")
        XCTAssertTrue(source.contains("mark?.label"), "and the full day's row says it")
        XCTAssertTrue(source.contains("mark: job.officeFlag"))
    }
}
