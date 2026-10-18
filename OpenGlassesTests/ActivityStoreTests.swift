import XCTest
@testable import OpenGlasses

/// Plan IW P1 — the trail's store: every append prunes, an operation is one row however often it
/// is delivered, the journal settles a row in place, HIPAA mode keeps the title only, and delete
/// all leaves nothing behind.
@MainActor
final class ActivityStoreTests: XCTestCase {
    private typealias F = GoalActivityFixture

    private var directory: URL!
    private var now = F.now

    override func setUp() {
        super.setUp()
        directory = F.workspace("ActivityStoreTests")
        now = F.now
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func store(hipaa: Bool = false, hipaaDays: Int? = nil) -> ActivityStore {
        ActivityStore(directory: directory, clock: { [unowned self] in self.now },
                      hipaaMode: { hipaa }, hipaaRetentionDays: { hipaaDays })
    }

    private func entry(_ n: Int, at: Date, detail: String? = nil, operation: String? = nil,
                       outcome: ActivityOutcome = .done) -> ActivityEntry {
        ActivityEntry(id: F.uuid(600 + n), at: at, kind: .action, title: "Saved a note for you",
                      detail: detail, tool: "save_note", authorisation: .asked, origin: .wearer,
                      outcome: outcome, refs: operation.map { [.operation($0)] } ?? [])
    }

    func testAnAppendSurvivesAReopen() {
        store().append(entry(1, at: F.date(19, 9), detail: "You approved: Save a note"))
        let reopened = store()
        XCTAssertEqual(reopened.entries.map(\.id), [F.uuid(601)])
        XCTAssertEqual(reopened.entries.first?.detail, "You approved: Save a note")
    }

    func testEveryAppendPrunesToTheFourteenDayHorizon() {
        let trail = store()
        trail.append(entry(1, at: F.date(1, 9)))      // eighteen days old
        trail.append(entry(2, at: F.date(10, 9)))     // nine days old
        trail.append(entry(3, at: F.date(19, 9)))
        XCTAssertEqual(trail.entries.map(\.id), [F.uuid(602), F.uuid(603)])
        XCTAssertEqual(store().entries.count, 2, "the pruned row is gone from disk too")
    }

    func testAppendsBeyondTheCapDropTheOldest() throws {
        struct Seed: Encodable { let version: Int; let entries: [ActivityEntry] }
        let seeded = (0..<(ActivityRetention.maximumEntries + 2)).map {
            entry($0, at: F.date(19, 8).addingTimeInterval(TimeInterval($0)))
        }
        try RecordJSONCodec.encoder().encode(Seed(version: 1, entries: seeded))
            .write(to: directory.appendingPathComponent("activity.json"))

        let trail = store()
        XCTAssertEqual(trail.entries.count, ActivityRetention.maximumEntries, "opening prunes too")
        trail.append(entry(5_000, at: F.date(19, 9)))
        XCTAssertEqual(trail.entries.count, ActivityRetention.maximumEntries)
        XCTAssertEqual(trail.entries.first?.id, F.uuid(603), "the three oldest are gone")
        XCTAssertEqual(trail.entries.last?.id, F.uuid(5_600))
    }

    func testAShorterHIPAARetentionShortensTheHorizon() {
        let trail = store(hipaaDays: 3)
        trail.append(entry(1, at: F.date(15, 9)))     // four days old
        trail.append(entry(2, at: F.date(18, 9)))
        XCTAssertEqual(trail.entries.map(\.id), [F.uuid(602)])
    }

    func testHIPAAModeKeepsTheTitleOnly() {
        let trail = store(hipaa: true)
        trail.append(entry(1, at: F.date(19, 9), detail: "You approved: Send a message to the clinic"))
        XCTAssertNil(trail.entries.first?.detail)
        XCTAssertEqual(trail.entries.first?.title, "Saved a note for you")
        XCTAssertFalse(String(decoding: (try? Data(contentsOf: directory.appendingPathComponent("activity.json"))) ?? Data(),
                              as: UTF8.self).contains("clinic"),
                       "the detail never reaches the disk")
    }

    func testARedeliveredOperationIsOneRow() {
        let trail = store()
        trail.append(entry(1, at: F.date(19, 9), operation: "op-1", outcome: .uncertain))
        trail.append(entry(2, at: F.date(19, 9, 1), operation: "op-1", outcome: .done))
        XCTAssertEqual(trail.entries.count, 1)
        XCTAssertEqual(trail.entries.first?.outcome, .done)
    }

    func testTheJournalSettlesTheRowForItsOperation() {
        let trail = store()
        trail.append(entry(1, at: F.date(19, 9), operation: "op-7"))
        trail.settle(operationID: "op-7", outcome: .uncertain)
        XCTAssertEqual(trail.entries.first?.outcome, .uncertain)
        trail.settle(operationID: "op-nobody", outcome: .failed)
        XCTAssertEqual(store().entries.first?.outcome, .uncertain, "an unknown operation changes nothing")
    }

    func testDeleteAllLeavesNothing() {
        let trail = store()
        trail.append(entry(1, at: F.date(19, 9)))
        trail.deleteAll()
        XCTAssertTrue(trail.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("activity.json").path))
        XCTAssertTrue(store().entries.isEmpty)
    }

    func testForgetRemovesOnlyRowsThatNameTheSubject() {
        let trail = store()
        trail.append(entry(1, at: F.date(19, 9), detail: "You approved: Send a message to Rangi"))
        trail.append(entry(2, at: F.date(19, 9, 5)))
        XCTAssertEqual(trail.forget(matching: "rangi"), 1)
        XCTAssertEqual(trail.entries.map(\.id), [F.uuid(602)])
        XCTAssertEqual(trail.forget(matching: "  "), 0)
    }

    func testADamagedFileReadsAsEmptyAndIsReplacedOnTheNextWrite() throws {
        try Data("not json".utf8).write(to: directory.appendingPathComponent("activity.json"))
        let trail = store()
        XCTAssertTrue(trail.entries.isEmpty)
        trail.append(entry(1, at: F.date(19, 9)))
        XCTAssertEqual(store().entries.count, 1)
    }
}
