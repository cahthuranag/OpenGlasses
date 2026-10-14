import XCTest
@testable import OpenGlasses

/// The Home Screen widget's glasses line: the words for every state, battery only for a live
/// connected reading, and the stale rule that keeps a killed app from leaving "Connected" up.
final class WidgetGlassesPresentationTests: XCTestCase {

    private let written = Date(timeIntervalSince1970: 1_800_000_000)
    private var fresh: Date { written.addingTimeInterval(60) }
    private var aged: Date { written.addingTimeInterval(WidgetGlassesPresentation.staleAfter) }

    private func render(_ snapshot: WidgetGlassesSnapshot?, at now: Date? = nil,
                        everAdded: Bool = false) -> WidgetGlassesLine {
        WidgetGlassesPresentation.render(snapshot: snapshot, now: now ?? fresh, glassesEverAdded: everAdded)
    }

    private func snapshot(_ phase: WidgetGlassesSnapshot.Phase, stoodDown: Bool = false,
                          battery: Int? = nil, charging: Bool = false,
                          name: String? = "Ray-Ban Meta") -> WidgetGlassesSnapshot {
        WidgetGlassesSnapshot(phase: phase, stoodDown: stoodDown, deviceName: name, battery: battery,
                              charging: charging, writtenAt: written)
    }

    // MARK: - Every phase × stood-down × battery × charging

    func testEveryCombination() {
        for phase in WidgetGlassesSnapshot.Phase.allCases {
            for stoodDown in [false, true] {
                for battery in [nil, 72] as [Int?] {
                    for charging in [false, true] {
                        let line = render(snapshot(phase, stoodDown: stoodDown, battery: battery,
                                                   charging: charging))
                        let context = "\(phase) stoodDown=\(stoodDown) battery=\(String(describing: battery)) charging=\(charging)"
                        let liveConnected = phase == .connected && !stoodDown
                        XCTAssertEqual(line.text, Self.expectedText(phase, stoodDown: stoodDown), context)
                        XCTAssertEqual(line.tone, liveConnected ? .connected : .neutral, context)
                        XCTAssertEqual(line.glassesUsable, liveConnected, context)
                        XCTAssertEqual(line.batteryText, liveConnected ? battery.map { "\($0)%" } : nil,
                                       "battery is shown only for a live connected reading — \(context)")
                        XCTAssertEqual(line.charging, liveConnected && charging, context)
                        XCTAssertEqual(line.deviceName, phase.claimsLiveLink ? "Ray-Ban Meta" : nil, context)
                        XCTAssertFalse(line.accessibilityLabel.isEmpty, context)
                    }
                }
            }
        }
    }

    private static func expectedText(_ phase: WidgetGlassesSnapshot.Phase, stoodDown: Bool) -> String {
        switch phase {
        case .noGlassesAdded: return "No glasses added"
        case .addedDisconnected: return "Glasses not connected"
        case .connecting: return "Connecting…"
        case .connected: return stoodDown ? "Glasses paused" : "Connected"
        }
    }

    func testConnectedSaysBatteryAndChargingToVoiceOver() {
        let line = render(snapshot(.connected, battery: 72, charging: true))
        XCTAssertEqual(line.batteryText, "72%")
        XCTAssertTrue(line.charging)
        XCTAssertEqual(line.accessibilityLabel, "Glasses connected, battery 72%, charging")
        XCTAssertEqual(render(snapshot(.connected)).accessibilityLabel, "Glasses connected")
    }

    func testPausedGlassesShowNoBattery() {
        let line = render(snapshot(.connected, stoodDown: true, battery: 40, charging: true))
        XCTAssertEqual(line.text, "Glasses paused")
        XCTAssertNil(line.batteryText)
        XCTAssertFalse(line.charging)
        XCTAssertEqual(line.symbol, "pause.circle")
    }

    // MARK: - Never written

    func testNothingWrittenFollowsWhetherGlassesWereEverAdded() {
        XCTAssertEqual(render(nil, everAdded: false).text, "No glasses added")
        XCTAssertEqual(render(nil, everAdded: true).text, "Glasses not connected")
        for everAdded in [false, true] {
            let line = render(nil, everAdded: everAdded)
            XCTAssertEqual(line.tone, .neutral)
            XCTAssertNil(line.batteryText)
            XCTAssertNil(line.deviceName)
        }
        XCTAssertEqual(WidgetGlassesPresentation.entryDates(for: nil, now: fresh), [fresh])
    }

    // MARK: - Staleness

    func testAConnectedSnapshotGoesStale() {
        let stale = render(snapshot(.connected, battery: 72, charging: true), at: aged)
        let time = written.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(stale.text, "Last seen connected \(time)")
        XCTAssertNil(stale.batteryText, "a stale snapshot never shows a battery")
        XCTAssertFalse(stale.charging)
        XCTAssertNil(stale.deviceName)
        XCTAssertEqual(stale.tone, .neutral)
        XCTAssertFalse(stale.glassesUsable)

        let justBefore = render(snapshot(.connected, battery: 72),
                                at: aged.addingTimeInterval(-1))
        XCTAssertEqual(justBefore.text, "Connected")
    }

    func testPausedAndConnectingSnapshotsGoStaleToo() {
        for snap in [snapshot(.connecting), snapshot(.connected, stoodDown: true)] {
            XCTAssertTrue(render(snap, at: aged).text.hasPrefix("Last seen connected"), "\(snap.phase)")
        }
    }

    func testDisconnectedAndNotAddedAreNotAged() {
        let longAfter = written.addingTimeInterval(7 * 24 * 3600)
        XCTAssertEqual(render(snapshot(.addedDisconnected), at: longAfter).text, "Glasses not connected")
        XCTAssertEqual(render(snapshot(.noGlassesAdded), at: longAfter).text, "No glasses added")
        for phase in [WidgetGlassesSnapshot.Phase.addedDisconnected, .noGlassesAdded] {
            XCTAssertEqual(WidgetGlassesPresentation.entryDates(for: snapshot(phase), now: fresh), [fresh],
                           "\(phase) claims nothing live, so it has no stale entry")
        }
    }

    func testALiveSnapshotHasAStaleEntry() {
        for phase in [WidgetGlassesSnapshot.Phase.connected, .connecting] {
            let dates = WidgetGlassesPresentation.entryDates(for: snapshot(phase), now: fresh)
            XCTAssertEqual(dates, [fresh, aged], "\(phase)")
            let lines = dates.map { render(snapshot(phase, battery: 50), at: $0) }
            XCTAssertFalse(lines[0].text.hasPrefix("Last seen"))
            XCTAssertTrue(lines[1].text.hasPrefix("Last seen connected"))
        }
        // Already stale when the timeline is asked for: one entry, the stale one.
        let late = aged.addingTimeInterval(60)
        XCTAssertEqual(WidgetGlassesPresentation.entryDates(for: snapshot(.connected), now: late), [late])
    }

    func testTheRestampComesStrictlyInsideTheStaleWindow() {
        typealias P = WidgetGlassesPresentation
        XCTAssertEqual(P.staleAfter, 45 * 60)
        XCTAssertEqual(P.restampAfter, 30 * 60)
        XCTAssertEqual(P.restampCheckInterval, 10 * 60)
        // The app checks every restampCheckInterval and the writer's window adds a moment, so the
        // oldest a running app's live snapshot gets is restampAfter + the check + the window.
        let worstCase = P.restampAfter + P.restampCheckInterval + WidgetGlassesStatusWriter.coalesceSeconds
        XCTAssertLessThan(worstCase, P.staleAfter)
        // At most two re-stamps an hour.
        XCTAssertGreaterThanOrEqual(P.restampAfter, 30 * 60)
    }

    // MARK: - Battery steps

    func testBatteryStepsThatReload() {
        let matters = WidgetGlassesPresentation.batteryStepMatters
        XCTAssertFalse(matters(72, 69), "three points is not worth a reload")
        XCTAssertFalse(matters(72, 72))
        XCTAssertTrue(matters(72, 67), "five points is")
        XCTAssertTrue(matters(67, 72), "in either direction")
        XCTAssertTrue(matters(22, 19), "crossing 20%")
        XCTAssertTrue(matters(19, 21), "crossing 20% upwards")
        XCTAssertFalse(matters(21, 20), "20% itself is not below the threshold")
        XCTAssertTrue(matters(11, 9), "crossing 10%")
        XCTAssertTrue(matters(9, 11), "crossing 10% upwards")
        XCTAssertFalse(matters(9, 6), "below every threshold, under a step")
        XCTAssertTrue(matters(nil, 72), "a battery appearing")
        XCTAssertTrue(matters(72, nil), "a battery going away")
        XCTAssertFalse(matters(nil, nil))
    }

    func testOnlyTheBatteryIsDamped() {
        let base = snapshot(.connected, battery: 72)
        var smallDrop = base; smallDrop.battery = 70
        XCTAssertFalse(smallDrop.differsForWidget(from: base))
        var restamped = base; restamped.writtenAt = written.addingTimeInterval(600)
        XCTAssertFalse(restamped.differsForWidget(from: base), "when it was written never counts")
        var charging = base; charging.charging = true
        var paused = base; paused.stoodDown = true
        var renamed = base; renamed.deviceName = "Oakley Meta"
        var away = base; away.phase = .addedDisconnected
        for changed in [charging, paused, renamed, away] {
            XCTAssertTrue(changed.differsForWidget(from: base))
        }
    }

    // MARK: - Codable

    func testRoundTripsThroughTheAppGroup() throws {
        let suite = "WidgetGlassesPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(WidgetGlassesSnapshot.load(from: defaults))
        let original = snapshot(.connected, stoodDown: true, battery: 64, charging: true)
        original.save(to: defaults)
        XCTAssertNotNil(defaults.data(forKey: WidgetGlassesSnapshot.storageKey))
        XCTAssertEqual(WidgetGlassesSnapshot.load(from: defaults), original)

        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(WidgetGlassesSnapshot.self, from: data), original)
    }

    func testAnUnknownPhaseDecodesAsNotConnected() throws {
        let json = #"{"phase":"somethingNewer","stoodDown":false,"battery":80,"charging":true,"writtenAt":0}"#
        let decoded = try JSONDecoder().decode(WidgetGlassesSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.phase, .addedDisconnected)
        let line = render(decoded, at: Date(timeIntervalSinceReferenceDate: 60))
        XCTAssertEqual(line.text, "Glasses not connected")
        XCTAssertNil(line.batteryText)
    }

    func testMissingOptionalFieldsStillDecode() throws {
        let json = #"{"phase":"connected","writtenAt":0}"#
        let decoded = try JSONDecoder().decode(WidgetGlassesSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, WidgetGlassesSnapshot(phase: .connected,
                                                      writtenAt: Date(timeIntervalSinceReferenceDate: 0)))
    }

    func testGarbageIsNoSnapshotRatherThanACrash() throws {
        let suite = "WidgetGlassesPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: WidgetGlassesSnapshot.storageKey)
        XCTAssertNil(WidgetGlassesSnapshot.load(from: defaults))
    }
}
