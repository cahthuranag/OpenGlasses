import XCTest
@testable import OpenGlasses

/// Plan IH P2 — what the Van Stock screen shows is worked out from the log and nothing else.
final class VanStockRowsTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private var log: VanStockLog {
        var log = VanStockLog()
        log.addItem(id: "sensor", number: "62-23543-01", description: "Flame sensor", minimum: 2,
                    bin: "left shelf 2", codes: ["0123456789012"], verified: true, batch: "b0")
        log.addItem(id: "cable", description: "thermostat cable", unit: .m, batch: "b0")
        log.addItem(id: "igniter", number: "14T56", description: "Igniter", batch: "b0")
        log.addItem(id: "fuse", description: "Fuse", batch: "b0")
        log.record(.counted, itemID: "sensor", quantity: 2, at: start, batch: "b0", source: .typed)
        log.record(.loaded, itemID: "cable", quantity: 30, at: start, batch: "b0", source: .spoken)
        log.record(.counted, itemID: "fuse", quantity: 0, at: start, batch: "b0", source: .typed)
        return log
    }

    func testRowsAreInNameOrderWhateverTheCase() {
        XCTAssertEqual(VanStockRows.rows(log).map(\.id), ["sensor", "fuse", "igniter", "cable"])
    }

    func testQuantityIsNeverANumberForALineNothingWasRecordedAgainst() {
        let rows = Dictionary(uniqueKeysWithValues: VanStockRows.rows(log).map { ($0.id, $0) })
        XCTAssertEqual(rows["sensor"]?.quantity, "2")
        XCTAssertEqual(rows["cable"]?.quantity, "30 m")
        XCTAssertEqual(rows["fuse"]?.quantity, "0")
        XCTAssertNil(rows["igniter"]?.quantity)
    }

    func testMarks() {
        let rows = Dictionary(uniqueKeysWithValues: VanStockRows.rows(log).map { ($0.id, $0) })
        XCTAssertEqual(rows["sensor"]?.isLow, true, "at its minimum")
        XCTAssertEqual(rows["fuse"]?.isLow, true, "recorded at zero with no minimum")
        XCTAssertEqual(rows["cable"]?.isLow, false)
        XCTAssertEqual(rows["igniter"]?.isLow, false, "never recorded is not the same as run out")
        XCTAssertEqual(rows["igniter"]?.isUnverified, true)
        XCTAssertEqual(rows["sensor"]?.isUnverified, false)
        XCTAssertEqual(rows["fuse"]?.isUnverified, false, "a line with no number has nothing to verify")
    }

    func testSearchMatchesDescriptionNumberBinAndCode() {
        XCTAssertEqual(VanStockRows.rows(log, query: "flame").map(\.id), ["sensor"])
        XCTAssertEqual(VanStockRows.rows(log, query: "14t").map(\.id), ["igniter"])
        XCTAssertEqual(VanStockRows.rows(log, query: "SHELF left").map(\.id), ["sensor"])
        XCTAssertEqual(VanStockRows.rows(log, query: "0123456789012").map(\.id), ["sensor"])
        XCTAssertEqual(VanStockRows.rows(log, query: "flame igniter"), [])
        XCTAssertEqual(VanStockRows.rows(log, query: "   ").count, 4)
    }

    func testHistoryIsNewestFirstAndAnUndoMarksWhatItTookBack() {
        var log = self.log
        log.record(.used, itemID: "sensor", quantity: 1, at: start.addingTimeInterval(60), batch: "b1", source: .spoken)
        log.undoLastBatch(at: start.addingTimeInterval(120), batch: "u1", source: .typed)
        let history = VanStockRows.history(log, itemID: "sensor")
        XCTAssertEqual(history.map(\.movement.kind), [.used, .counted])
        XCTAssertEqual(history.map(\.takenBack), [true, false])
        XCTAssertEqual(VanStockRows.history(log, itemID: "nobody"), [])
    }
}
