import XCTest
@testable import OpenGlasses

/// Plan IW P0 — the trail keeps 14 days and at most 1000 entries, oldest dropped first.
final class ActivityRetentionTests: XCTestCase {
    private typealias F = GoalActivityFixture
    private let day: TimeInterval = 24 * 60 * 60

    func testTheHorizonIsFourteenDaysAndAThousandEntries() {
        XCTAssertEqual(ActivityRetention.horizonDays, 14)
        XCTAssertEqual(ActivityRetention.maximumEntries, 1000)
    }

    func testEntriesOlderThanTheHorizonAreDropped() {
        let now = F.now
        let kept = F.entry(1, at: now.addingTimeInterval(-14 * day), title: "On the boundary")
        let gone = F.entry(2, at: now.addingTimeInterval(-14 * day - 1), title: "Just past it")
        let recent = F.entry(3, at: now.addingTimeInterval(-60), title: "A minute ago")
        let future = F.entry(4, at: now.addingTimeInterval(3600), title: "Clock moved")
        let pruned = ActivityRetention.prune([recent, gone, future, kept], now: now)
        XCTAssertEqual(pruned.map(\.id), [kept.id, recent.id, future.id], "oldest first, the future kept")
    }

    func testTheOldestBeyondTheCapAreDropped() {
        let now = F.now
        let entries = (0..<1005).map { F.entry($0, at: now.addingTimeInterval(-Double($0) * 60), title: "Entry \($0)") }
        let pruned = ActivityRetention.prune(entries.shuffled(), now: now)
        XCTAssertEqual(pruned.count, 1000)
        XCTAssertEqual(pruned.first?.id, entries[999].id)
        XCTAssertEqual(pruned.last?.id, entries[0].id)
        XCTAssertFalse(pruned.contains { $0.id == entries[1000].id })
    }

    func testAShorterHIPAARetentionShortensTheTrailAndALongerOneDoesNot() {
        XCTAssertEqual(ActivityRetention.effectiveHorizonDays(), 14)
        XCTAssertEqual(ActivityRetention.effectiveHorizonDays(hipaaRetentionDays: 7), 7)
        XCTAssertEqual(ActivityRetention.effectiveHorizonDays(hipaaRetentionDays: 90), 14)
        XCTAssertEqual(ActivityRetention.effectiveHorizonDays(hipaaRetentionDays: 0), 14)

        let old = F.entry(1, at: F.now.addingTimeInterval(-8 * day), title: "Eight days ago")
        XCTAssertEqual(ActivityRetention.prune([old], now: F.now, horizonDays: 7), [])
        XCTAssertEqual(ActivityRetention.prune([old], now: F.now), [old])
    }

    func testPruningNothingIsNothing() {
        XCTAssertEqual(ActivityRetention.prune([], now: F.now), [])
    }
}
