import XCTest
@testable import OpenGlasses

/// Tests for the calendar tool's date resolution, headless with an injected `now` and `Calendar`.
///
/// A month/day without a year must resolve to its next occurrence on or after today in the
/// wearer's calendar and time zone, so a January hold asked for in December lands in the coming
/// year. An explicit year is kept as given.
final class CalendarToolTests: XCTestCase {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        return cal
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func resolve(_ str: String, now: Date) -> Date? {
        CalendarTool.resolveDate(str, now: now, calendar: calendar)
    }

    // MARK: - Month/day without a year

    func testDateLaterThisYearStaysInThisYear() {
        let now = date(2026, 3, 10, hour: 14)
        XCTAssertEqual(resolve("Jun 5", now: now), date(2026, 6, 5))
        XCTAssertEqual(resolve("June 5", now: now), date(2026, 6, 5))
    }

    func testDateAlreadyPassedThisYearRollsToNextYear() {
        // A January hold asked for in December is next year's January, not the one just gone.
        let now = date(2026, 12, 18, hour: 9)
        XCTAssertEqual(resolve("Jan 15", now: now), date(2027, 1, 15))
        XCTAssertEqual(resolve("January 15", now: now), date(2027, 1, 15))
    }

    func testTodaysMonthDayResolvesToTodayNotNextYear() {
        // "On or after today": late in the day the same month/day is still today.
        let now = date(2026, 10, 19, hour: 23, minute: 30)
        XCTAssertEqual(resolve("Oct 19", now: now), date(2026, 10, 19))
    }

    func testYesterdaysMonthDayRollsToNextYear() {
        let now = date(2026, 10, 19, hour: 0, minute: 5)
        XCTAssertEqual(resolve("Oct 18", now: now), date(2027, 10, 18))
    }

    func testResolvesInTheWearersTimeZoneNotUTC() {
        // 00:30 on 19 Oct in Auckland is still 18 Oct in UTC; "Oct 19" must be today, not next year.
        let now = date(2026, 10, 19, hour: 0, minute: 30)
        XCTAssertEqual(resolve("Oct 19", now: now), date(2026, 10, 19))
    }

    // MARK: - 29 February

    func testFebruary29InALeapYearBeforeTheDateStaysInThatYear() {
        let now = date(2028, 1, 10)
        XCTAssertEqual(resolve("Feb 29", now: now), date(2028, 2, 29))
    }

    func testFebruary29InANonLeapYearResolvesToTheNextLeapYear() {
        // 2026 and 2027 have no 29 February; the next real one is in 2028.
        let now = date(2026, 1, 10)
        XCTAssertEqual(resolve("Feb 29", now: now), date(2028, 2, 29))
    }

    func testFebruary29AfterItHasPassedInALeapYearResolvesToTheNextLeapYear() {
        let now = date(2028, 3, 1)
        XCTAssertEqual(resolve("Feb 29", now: now), date(2032, 2, 29))
    }

    // MARK: - Explicit year

    func testExplicitYearIsKeptAsGiven() {
        let now = date(2026, 12, 18)
        XCTAssertEqual(resolve("2025-03-18", now: now), date(2025, 3, 18))
        XCTAssertEqual(resolve("2027-01-15", now: now), date(2027, 1, 15))
        XCTAssertEqual(resolve("01/15/2027", now: now), date(2027, 1, 15))
        XCTAssertEqual(resolve("01-15-2027", now: now), date(2027, 1, 15))
    }

    func testExplicitYearIsStartOfDayInTheWearersTimeZone() {
        let resolved = resolve("2027-01-15", now: date(2026, 6, 1))
        XCTAssertEqual(resolved, calendar.startOfDay(for: resolved!))
    }

    // MARK: - Unparseable

    func testUnrecognisedStringReturnsNil() {
        XCTAssertNil(resolve("someday", now: date(2026, 6, 1)))
        XCTAssertNil(resolve("", now: date(2026, 6, 1)))
    }
}
