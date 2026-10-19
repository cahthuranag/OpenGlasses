import XCTest
@testable import OpenGlasses

/// Plan HY P2 — the rolling call budget: window roll-off, the exact boundary, the injected clock,
/// and the rule that safety loops never take one.
final class CallBudgetTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testDefaultIsTwoHundredAndFortyAnHour() {
        let budget = CallBudget()
        XCTAssertEqual(budget.limit, 240)
        XCTAssertEqual(budget.window, 3600)
        XCTAssertEqual(budget.remaining(now: t0), 240)
    }

    func testAdmitsUpToTheLimitThenRefuses() {
        var budget = CallBudget(limit: 3, window: 60)
        XCTAssertTrue(budget.admit(now: at(0)))
        XCTAssertTrue(budget.admit(now: at(1)))
        XCTAssertEqual(budget.remaining(now: at(2)), 1)
        XCTAssertTrue(budget.admit(now: at(2)))
        XCTAssertEqual(budget.remaining(now: at(3)), 0)
        XCTAssertFalse(budget.admit(now: at(3)))
        XCTAssertEqual(budget.remaining(now: at(3)), 0, "a refused call is not charged")
    }

    func testCallsRollOffOneByOne() {
        var budget = CallBudget(limit: 2, window: 60)
        _ = budget.admit(now: at(0))
        _ = budget.admit(now: at(10))
        XCTAssertFalse(budget.admit(now: at(30)))
        XCTAssertEqual(budget.remaining(now: at(61)), 1, "the first call has rolled off")
        XCTAssertTrue(budget.admit(now: at(61)))
        XCTAssertFalse(budget.admit(now: at(65)))
        XCTAssertEqual(budget.remaining(now: at(71)), 1, "then the second")
    }

    /// A call is counted for less than one window: at exactly one window it has rolled off.
    func testTheExactBoundary() {
        var budget = CallBudget(limit: 1, window: 60)
        XCTAssertTrue(budget.admit(now: at(0)))
        XCTAssertEqual(budget.remaining(now: at(59.999)), 0)
        XCTAssertFalse(budget.admit(now: at(59.999)))
        XCTAssertEqual(budget.remaining(now: at(60)), 1)
        XCTAssertTrue(budget.admit(now: at(60)))
    }

    func testNextAvailableIsWhenTheOldestRollsOff() {
        var budget = CallBudget(limit: 2, window: 60)
        XCTAssertEqual(budget.nextAvailable(now: at(0)), at(0), "room now means now")
        _ = budget.admit(now: at(5))
        _ = budget.admit(now: at(20))
        XCTAssertEqual(budget.nextAvailable(now: at(30)), at(65))
        XCTAssertEqual(budget.nextAvailable(now: at(66)), at(66))
    }

    /// Time comes only from the caller: the same calls at the same stamps give the same answers,
    /// whatever the wall clock says.
    func testTheClockIsInjected() {
        var a = CallBudget(limit: 1, window: 3600)
        var b = CallBudget(limit: 1, window: 3600)
        let far = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(a.admit(now: far), b.admit(now: far))
        XCTAssertFalse(a.admit(now: far.addingTimeInterval(3599)))
        XCTAssertTrue(b.admit(now: far.addingTimeInterval(3600)))
    }

    func testANegativeOrZeroLimitAdmitsNothing() {
        var budget = CallBudget(limit: -5, window: 60)
        XCTAssertEqual(budget.limit, 0)
        XCTAssertFalse(budget.admit(now: t0))
    }

    // MARK: - Safety loops are never budgeted

    private func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OpenGlasses/Sources")
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Navigation's hazard loop and first aid are safety work. A call budget there would trade a
    /// callout for a cloud call, so neither loop may reference one.
    func testNavigationAndFirstAidNeverTakeACallBudget() throws {
        for file in ["Services/Accessibility/NavigationAssistService.swift",
                     "Services/NativeTools/NavigationAssistTool.swift",
                     "Services/FirstAid/FirstAidAssistService.swift",
                     "Services/FirstAid/FirstAidProtocol.swift",
                     "Services/NativeTools/FirstAidTool.swift"] {
            let text = try source(file)
            XCTAssertFalse(text.contains("CallBudget"), "\(file) must never be budgeted")
            XCTAssertFalse(text.contains("LiveCoachPacer"), "\(file) must never be budgeted")
        }
    }
}
