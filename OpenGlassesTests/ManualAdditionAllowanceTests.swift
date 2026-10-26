import XCTest
@testable import OpenGlasses

/// Plan JK §8 — the pure new-manual allowance. Fingerprints here are invented tokens.
final class ManualAdditionAllowanceTests: XCTestCase {
    private let limits = ManualLimits.personal
    private let day: TimeInterval = 86_400
    private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private func record(_ id: String, daysAgo: Double, spent: Bool = true, refunded: Bool = false, read: Bool = false) -> ManualAdditionRecord {
        .init(fingerprint: id, addedAt: now.addingTimeInterval(-daysAgo * day), spent: spent, refunded: refunded, read: read)
    }

    /// Five free fills, already done.
    private var filled: [ManualAdditionRecord] { (1...5).map { record("free-\($0)", daysAgo: 100, spent: false) } }

    private func decide(_ history: [ManualAdditionRecord]?, _ proposed: [String]) -> ManualAdditionAllowance.Decision {
        ManualAdditionAllowance.decide(limits: limits, history: history, proposed: proposed, now: now)
    }

    func testPersonalLimitsCarryTheDecidedAllowance() {
        let allowance = try! XCTUnwrap(ManualLimits.personal.additions)
        XCTAssertEqual(allowance.newPerWindow, 3)
        XCTAssertEqual(allowance.window, 30 * day)
        XCTAssertEqual(allowance.freeFirst, 5)
        XCTAssertEqual(allowance.undoWindow, day)
        XCTAssertNil(ManualLimits(manuals: 5, pagesPerManual: 100, totalPages: 300).additions)
    }

    func testNilLimitsMeanNoAllowanceEvenWithAnUnreadableHistory() {
        XCTAssertEqual(ManualAdditionAllowance.decide(limits: nil, history: nil, proposed: ["a"], now: now), .allowed(spending: []))
        let unlimited = ManualLimits(manuals: 5, pagesPerManual: nil, totalPages: nil)
        XCTAssertEqual(ManualAdditionAllowance.decide(limits: unlimited, history: nil, proposed: ["a"], now: now), .allowed(spending: []))
        XCTAssertNil(ManualAdditionAllowance.refund(limits: nil, history: [record("a", daysAgo: 0)], fingerprint: "a", now: now))
    }

    func testUnreadableHistoryRefusesAdditionsOnly() {
        XCTAssertEqual(decide(nil, ["a"]), .unavailable)
        XCTAssertEqual(decide([], [""]), .unavailable, "an empty fingerprint is not evidence of a manual")
        let message = try! XCTUnwrap(ManualAdditionAllowance.refusal(.unavailable, limits: limits))
        XCTAssertTrue(message.contains("remove"), message)
    }

    func testTheFirstFiveDistinctManualsAreFree() {
        guard case .allowed(let spending) = decide([], ["a", "b", "c", "d", "e"]) else { return XCTFail() }
        XCTAssertEqual(spending.count, 5)
        XCTAssertTrue(spending.allSatisfy { !$0.spent })
        guard case .allowed(let mixed) = decide(Array(filled.prefix(3)), ["a", "b", "c"]) else { return XCTFail() }
        XCTAssertEqual(mixed.map(\.spent), [false, false, true], "two free fills left, then the allowance")
        guard case .allowed(let duplicate) = decide([], ["a", "a"]) else { return XCTFail() }
        XCTAssertEqual(duplicate.count, 1, "the same bytes twice are one manual")
    }

    func testTheFourthNewManualInTheWindowIsRefusedWithTheDate() {
        let history = filled + [record("x", daysAgo: 10), record("y", daysAgo: 5), record("z", daysAgo: 1)]
        XCTAssertEqual(decide(history, ["new"]), .wouldExceed(remaining: 0, nextAvailable: now.addingTimeInterval(20 * day)))
        XCTAssertEqual(ManualAdditionAllowance.status(limits.additions!, history: history, now: now),
                       .init(freeRemaining: 0, remaining: 0, nextAvailable: now.addingTimeInterval(20 * day)))
    }

    func testWindowEdgeAtExactlyThirtyDays() {
        let exactly = filled + [record("x", daysAgo: 30), record("y", daysAgo: 2), record("z", daysAgo: 1)]
        guard case .allowed(let spending) = decide(exactly, ["new"]) else { return XCTFail("a 30-day-old addition has come back") }
        XCTAssertEqual(spending.first?.spent, true)
        let justInside = filled + [record("x", daysAgo: 30 - 1 / day), record("y", daysAgo: 2), record("z", daysAgo: 1)]
        guard case .wouldExceed = decide(justInside, ["new"]) else { return XCTFail("one second short of 30 days still counts") }
    }

    func testUnusedAdditionsDoNotCarryOver() {
        // Nothing spent for months: still three, never six.
        let history = filled + [record("old-1", daysAgo: 90), record("old-2", daysAgo: 80)]
        guard case .allowed = decide(history, ["a", "b", "c"]) else { return XCTFail() }
        XCTAssertEqual(decide(history, ["a", "b", "c", "d"]), .wouldExceed(remaining: 3, nextAvailable: nil))
    }

    func testAReturningManualIsFreeEvenWhenTheAllowanceIsSpent() {
        let history = filled + [record("x", daysAgo: 3), record("y", daysAgo: 2), record("z", daysAgo: 1)]
        XCTAssertEqual(decide(history, ["free-2"]), .allowed(spending: []))
        XCTAssertEqual(decide(history, ["x"]), .allowed(spending: []))
    }

    func testAGivenBackManualIsNewAgain() {
        let history = filled + [record("x", daysAgo: 3, refunded: true)]
        guard case .allowed(let spending) = decide(history, ["x"]) else { return XCTFail() }
        XCTAssertEqual(spending.map(\.fingerprint), ["x"])
        XCTAssertEqual(spending.first?.spent, true)
        // A refunded free fill hands the free slot back.
        let refundedFree = Array(filled.prefix(4)) + [record("free-5", daysAgo: 0.1, spent: false, refunded: true)]
        XCTAssertEqual(ManualAdditionAllowance.status(limits.additions!, history: refundedFree, now: now).freeRemaining, 1)
    }

    func testUndoWithinADayRefundsOnlyAManualNothingWasReadFrom() {
        let unread = filled + [record("x", daysAgo: 0.5)]
        XCTAssertEqual(ManualAdditionAllowance.refund(limits: limits, history: unread, fingerprint: "x", now: now), unread.last!.key)
        let read = filled + [record("x", daysAgo: 0.5, read: true)]
        XCTAssertNil(ManualAdditionAllowance.refund(limits: limits, history: read, fingerprint: "x", now: now))
        let late = filled + [record("x", daysAgo: 1.01)]
        XCTAssertNil(ManualAdditionAllowance.refund(limits: limits, history: late, fingerprint: "x", now: now))
        XCTAssertNil(ManualAdditionAllowance.refund(limits: limits, history: filled, fingerprint: "unknown", now: now))
    }

    func testAReadMarksOnlyAdditionsStillInTheUndoWindow() {
        let history = filled + [record("x", daysAgo: 0.5), record("y", daysAgo: 2)]
        XCTAssertEqual(ManualAdditionAllowance.readMarks(limits: limits, history: history, fingerprint: "x", now: now), [history[5].key])
        XCTAssertEqual(ManualAdditionAllowance.readMarks(limits: limits, history: history, fingerprint: "y", now: now), [])
    }

    func testAFutureDatedRecordCountsInsideTheWindow() {
        // The clock was moved forward to add, then back: that addition spends the future window.
        let history = filled + [record("x", daysAgo: -40), record("y", daysAgo: 1), record("z", daysAgo: 1)]
        XCTAssertEqual(decide(history, ["new"]),
                       .wouldExceed(remaining: 0, nextAvailable: now.addingTimeInterval(29 * day)))
        XCTAssertEqual(ManualAdditionAllowance.inWindow(limits.additions!, history: history, now: now).count, 3)
    }

    func testASetThatDoesNotFitIsRefusedWhole() {
        let history = filled + [record("x", daysAgo: 10)]
        XCTAssertEqual(decide(history, ["a", "b", "c"]), .wouldExceed(remaining: 2, nextAvailable: now.addingTimeInterval(20 * day)))
        XCTAssertEqual(decide(history, ["a", "b", "c", "d"]), .wouldExceed(remaining: 2, nextAvailable: nil),
                       "four new manuals never fit three a window")
        guard case .allowed(let spending) = decide(history, ["a", "free-1", "b"]) else { return XCTFail() }
        XCTAssertEqual(spending.map(\.fingerprint), ["a", "b"], "a set spends one addition per manual new to you")
    }

    func testAnOfflineOverspendDelaysTheNextAddition() {
        let history = filled + [record("w", daysAgo: 20), record("x", daysAgo: 10), record("y", daysAgo: 5), record("z", daysAgo: 1)]
        // Four in a window of three: two must come back before one more fits.
        XCTAssertEqual(decide(history, ["new"]), .wouldExceed(remaining: 0, nextAvailable: now.addingTimeInterval(20 * day)))
    }

    func testRefusalCopyNamesTheCountAndTheDateWithoutAnUpsell() throws {
        var components = DateComponents(); components.year = 2026; components.month = 11; components.day = 12; components.hour = 12
        let date = try XCTUnwrap(Calendar.current.date(from: components))
        let message = try XCTUnwrap(ManualAdditionAllowance.refusal(.wouldExceed(remaining: 0, nextAvailable: date), limits: limits,
                                                                    locale: Locale(identifier: "en_NZ")))
        XCTAssertEqual(message, "You've added 3 new manuals in the last 30 days. Your next new manual can be added on 12 November. Manuals you've had before can come back any time.")
        let set = try XCTUnwrap(ManualAdditionAllowance.refusal(.wouldExceed(remaining: 2, nextAvailable: nil), limits: limits))
        XCTAssertTrue(set.contains("nothing was added"), set)
        for line in [message, set] {
            for needle in ["Field Assist", "upgrade", "subscribe", "$", "a month", "Plan "] {
                XCTAssertFalse(line.contains(needle), "\"\(line)\" contains \"\(needle)\"")
            }
        }
    }

    func testUploadNoticeShowsOnlyWhenOneOrNoneIsLeft() {
        XCTAssertNil(ManualAdditionAllowance.uploadNotice(nil))
        XCTAssertNil(ManualAdditionAllowance.uploadNotice(.init(freeRemaining: 2, remaining: 0, nextAvailable: now)))
        XCTAssertNil(ManualAdditionAllowance.uploadNotice(.init(freeRemaining: 0, remaining: 2, nextAvailable: now)))
        XCTAssertEqual(ManualAdditionAllowance.uploadNotice(.init(freeRemaining: 0, remaining: 1, nextAvailable: now)),
                       "1 new manual left for now. Manuals you've had before don't count.")
        let none = ManualAdditionAllowance.uploadNotice(.init(freeRemaining: 0, remaining: 0, nextAvailable: now), locale: Locale(identifier: "en_NZ"))
        XCTAssertTrue(none?.hasPrefix("No new manuals left until ") == true, none ?? "")
    }

    func testPlanLimitsAndDisclosureDescribeTheAllowance() {
        let details = MyManualsPaywallCopy.limitDetails(.personal)
        XCTAssertTrue(details.contains("Up to 3 new manuals in any 30 days"), details)
        XCTAssertFalse(details.contains("a month"))
        XCTAssertFalse(MyManualsPaywallCopy.limitDetails(ManualLimits(manuals: 5, pagesPerManual: nil, totalPages: nil)).contains("new manuals"))
        XCTAssertTrue(MyManualsPaywallCopy.disclosure.contains("fingerprints and dates, never the manual"))
        XCTAssertTrue(MyManualsPaywallCopy.disclosure.contains("iCloud"))
    }

    func testRecordsRoundTripThroughJSONToTheSameKey() throws {
        let original = ManualAdditionRecord(fingerprint: "a", addedAt: Date(timeIntervalSince1970: 1_800_000_000.123_456), spent: true)
        let decoded = try JSONDecoder().decode(ManualAdditionRecord.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.key, original.key)
        let text = String(decoding: try JSONEncoder().encode(original), as: UTF8.self)
        XCTAssertFalse(text.contains("title"))
    }
}
