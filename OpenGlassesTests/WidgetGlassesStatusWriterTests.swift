import XCTest
@testable import OpenGlasses

/// The app side of the widget's glasses line: the reading it writes (battery only while
/// connected), no write without a change, one write and one reload per burst, and the re-stamp
/// that keeps a quiet but running app from being shown as gone.
@MainActor
final class WidgetGlassesStatusWriterTests: XCTestCase {

    private final class FakeStore: WidgetGlassesSnapshotStoring {
        var writes: [WidgetGlassesSnapshot] = []
        func write(_ snapshot: WidgetGlassesSnapshot) { writes.append(snapshot) }
    }

    private final class FakeReloader: WidgetTimelineReloading {
        var reloads = 0
        func reloadHomeWidget() { reloads += 1 }
    }

    private var store: FakeStore!
    private var reloader: FakeReloader!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var pendingFlushes: [@MainActor () -> Void] = []
    private var link: GlassesConnectionPhase = .connected
    private var stoodDown = false
    private var battery: Int? = 72
    private var charging = false
    private var writer: WidgetGlassesStatusWriter!

    override func setUp() async throws {
        store = FakeStore()
        reloader = FakeReloader()
        pendingFlushes = []
        writer = WidgetGlassesStatusWriter(
            store: store, reloader: reloader,
            now: { [unowned self] in self.clock },
            schedule: { [unowned self] _, work in self.pendingFlushes.append(work) }
        ) { [unowned self] date in
            WidgetGlassesSnapshot.reading(link: self.link, stoodDown: self.stoodDown, glassesAdded: true,
                                          deviceName: "Ray-Ban Meta", battery: self.battery,
                                          charging: self.charging, at: date)
        }
    }

    /// The end of the coalescing window.
    private func runWindow() {
        let flushes = pendingFlushes
        pendingFlushes = []
        flushes.forEach { $0() }
    }

    // MARK: - Coalescing and change detection

    func testTheFirstReadingIsAlwaysWritten() {
        writer.setNeedsWrite()
        XCTAssertTrue(store.writes.isEmpty, "nothing is written before the window closes")
        runWindow()
        XCTAssertEqual(store.writes.count, 1)
        XCTAssertEqual(store.writes.first?.writtenAt, clock)
        XCTAssertEqual(reloader.reloads, 1)
    }

    func testNoWriteWhenNothingChanged() {
        writer.setNeedsWrite(); runWindow()
        clock += 60
        writer.setNeedsWrite(); runWindow()
        writer.setNeedsWrite(); runWindow()
        XCTAssertEqual(store.writes.count, 1)
        XCTAssertEqual(reloader.reloads, 1)
    }

    func testABurstIsOneWriteAndOneReload() {
        writer.setNeedsWrite(); runWindow()
        for level in [71, 70, 69, 68, 67, 66] {
            battery = level
            writer.setNeedsWrite()
        }
        charging = true
        writer.setNeedsWrite()
        XCTAssertEqual(pendingFlushes.count, 1, "a burst opens one window")
        runWindow()
        XCTAssertEqual(store.writes.count, 2)
        XCTAssertEqual(store.writes.last?.battery, 66, "the reading is taken at the end of the window")
        XCTAssertEqual(reloader.reloads, 2)
    }

    // MARK: - Battery steps

    /// Writes the first reading at `from`, then moves to `to` and reports whether that wrote.
    private func batteryMoveWrites(from: Int?, to: Int?) -> Bool {
        battery = from
        writer = WidgetGlassesStatusWriter(
            store: store, reloader: reloader,
            now: { [unowned self] in self.clock },
            schedule: { [unowned self] _, work in self.pendingFlushes.append(work) }
        ) { [unowned self] date in
            WidgetGlassesSnapshot.reading(link: self.link, stoodDown: self.stoodDown, glassesAdded: true,
                                          deviceName: "Ray-Ban Meta", battery: self.battery,
                                          charging: self.charging, at: date)
        }
        writer.setNeedsWrite(); runWindow()
        let before = store.writes.count
        battery = to
        writer.setNeedsWrite(); runWindow()
        return store.writes.count > before
    }

    func testTheBatteryWritesOnlyInStepsOrAcrossAThreshold() {
        XCTAssertFalse(batteryMoveWrites(from: 72, to: 69))
        XCTAssertTrue(batteryMoveWrites(from: 72, to: 67))
        XCTAssertTrue(batteryMoveWrites(from: 22, to: 19))
        XCTAssertTrue(batteryMoveWrites(from: 11, to: 9))
        XCTAssertTrue(batteryMoveWrites(from: nil, to: 72))
        XCTAssertTrue(batteryMoveWrites(from: 72, to: nil))
    }

    func testASlowDrainWritesWhenItAddsUpToAStep() {
        writer.setNeedsWrite(); runWindow()
        for level in [71, 70, 69, 68] {
            battery = level
            writer.setNeedsWrite(); runWindow()
        }
        XCTAssertEqual(store.writes.count, 1, "each point alone is under a step")
        battery = 67
        writer.setNeedsWrite(); runWindow()
        XCTAssertEqual(store.writes.count, 2, "five points from the last write is a step")
        XCTAssertEqual(store.writes.last?.battery, 67)
    }

    func testABurstThatEndsWhereItBeganWritesNothing() {
        writer.setNeedsWrite(); runWindow()
        battery = 71; writer.setNeedsWrite()
        battery = 72; writer.setNeedsWrite()
        runWindow()
        XCTAssertEqual(store.writes.count, 1)
        XCTAssertEqual(reloader.reloads, 1)
    }

    func testEachChangeOfStateIsWritten() {
        writer.setNeedsWrite(); runWindow()
        stoodDown = true; writer.setNeedsWrite(); runWindow()
        charging = true; stoodDown = false; writer.setNeedsWrite(); runWindow()
        link = .addedDisconnected; writer.setNeedsWrite(); runWindow()
        XCTAssertEqual(store.writes.map(\.phase), [.connected, .connected, .connected, .addedDisconnected])
        XCTAssertEqual(reloader.reloads, 4)
    }

    // MARK: - Re-stamp

    func testALiveSnapshotIsRestampedOnceDue() {
        writer.setNeedsWrite(); runWindow()
        clock += WidgetGlassesPresentation.restampAfter - 1
        writer.setNeedsWrite(); runWindow()
        XCTAssertEqual(store.writes.count, 1, "not yet due")
        clock += 1
        writer.setNeedsWrite(); runWindow()
        XCTAssertEqual(store.writes.count, 2)
        XCTAssertEqual(store.writes.last?.writtenAt, clock)
    }

    /// Driven the way the app drives it — a check every `restampCheckInterval` and nothing else —
    /// a connected snapshot never reaches `staleAfter`, and costs at most two reloads an hour.
    func testTheCheckLoopKeepsALiveSnapshotFresh() {
        let start = clock
        writer.setNeedsWrite(); runWindow()
        var oldest: TimeInterval = 0
        while clock < start.addingTimeInterval(6 * 3600) {
            clock += WidgetGlassesPresentation.restampCheckInterval
            if let last = store.writes.last {
                oldest = max(oldest, clock.timeIntervalSince(last.writtenAt))
            }
            writer.setNeedsWrite(); runWindow()
        }
        XCTAssertLessThan(oldest, WidgetGlassesPresentation.staleAfter)
        XCTAssertLessThanOrEqual(reloader.reloads, 1 + 6 * 2, "at most two re-stamps an hour")
    }

    func testADisconnectedSnapshotIsNeverRestamped() {
        link = .addedDisconnected
        writer.setNeedsWrite(); runWindow()
        clock += WidgetGlassesPresentation.staleAfter * 10
        writer.setNeedsWrite(); runWindow()
        XCTAssertEqual(store.writes.count, 1)
    }

    // MARK: - The reading

    func testBatteryAndChargingOnlyWhileConnected() {
        for phase in [GlassesConnectionPhase.noGlassesAdded, .addedDisconnected, .connecting] {
            let reading = WidgetGlassesSnapshot.reading(link: phase, stoodDown: true, glassesAdded: true,
                                                        deviceName: "Ray-Ban Meta", battery: 55,
                                                        charging: true, at: clock)
            XCTAssertNil(reading.battery, "\(phase)")
            XCTAssertFalse(reading.charging, "\(phase)")
            XCTAssertFalse(reading.stoodDown, "\(phase)")
        }
        let connected = WidgetGlassesSnapshot.reading(link: .connected, stoodDown: false, glassesAdded: true,
                                                      deviceName: "Ray-Ban Meta", battery: 55,
                                                      charging: true, at: clock)
        XCTAssertEqual(connected.battery, 55)
        XCTAssertTrue(connected.charging)
        XCTAssertEqual(connected.deviceName, "Ray-Ban Meta")
    }

    func testTheNameOnlyWhileConnectedOrConnecting() {
        let away = WidgetGlassesSnapshot.reading(link: .addedDisconnected, stoodDown: false, glassesAdded: true,
                                                 deviceName: "Ray-Ban Meta", battery: nil,
                                                 charging: false, at: clock)
        XCTAssertNil(away.deviceName)
        let coming = WidgetGlassesSnapshot.reading(link: .connecting, stoodDown: false, glassesAdded: true,
                                                   deviceName: "Ray-Ban Meta", battery: nil,
                                                   charging: false, at: clock)
        XCTAssertEqual(coming.deviceName, "Ray-Ban Meta")
    }

    func testNeverAddedFollowsTheAppsOwnRecord() {
        let added = WidgetGlassesSnapshot.reading(link: .noGlassesAdded, stoodDown: false, glassesAdded: true,
                                                  deviceName: nil, battery: nil, charging: false, at: clock)
        XCTAssertEqual(added.phase, .addedDisconnected)
        let never = WidgetGlassesSnapshot.reading(link: .noGlassesAdded, stoodDown: false, glassesAdded: false,
                                                  deviceName: nil, battery: nil, charging: false, at: clock)
        XCTAssertEqual(never.phase, .noGlassesAdded)
    }
}
