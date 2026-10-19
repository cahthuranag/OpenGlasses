import XCTest
@testable import OpenGlasses

/// Plan JH — `set_alarm` rings a real alarm through AlarmKit and never lets the model call it
/// something it is not. A tester was told his alarm would be in the Clock app; it never was.
@MainActor
final class AlarmToolTests: XCTestCase {

    /// A backend that remembers what it was asked and answers what the test set.
    final class FakeScheduler: AlarmScheduler, @unchecked Sendable {
        var authorization: AlarmAuthorization
        var scheduled: [AlarmPlan] = []
        var scheduleError: Error?
        var listed: [ScheduledAlarm] = []
        var cancelledCount = 0

        init(authorization: AlarmAuthorization) { self.authorization = authorization }

        func authorize() async -> AlarmAuthorization { authorization }
        func schedule(_ plan: AlarmPlan) async throws -> String {
            if let scheduleError { throw scheduleError }
            scheduled.append(plan)
            return "id-\(scheduled.count)"
        }
        func pending() async -> [ScheduledAlarm] { listed }
        func cancelAll() async -> Int { cancelledCount }
    }

    private struct Boom: Error {}

    /// A fixed "now": 2026-10-18 20:58 local, the tester's evening.
    private let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 18
        components.hour = 20; components.minute = 58
        return Calendar.current.date(from: components)!
    }()

    private func tool(real: FakeScheduler?, fallback: FakeScheduler) -> AlarmTool {
        AlarmTool(realAlarm: real, fallback: fallback, now: { self.now })
    }

    // MARK: - The real alarm

    func testAnAuthorizedRealAlarmIsScheduledAndDescribedAsOne() async throws {
        let real = FakeScheduler(authorization: .authorized)
        let fallback = FakeScheduler(authorization: .authorized)
        let result = try await tool(real: real, fallback: fallback)
            .execute(args: ["time": "7:00 AM", "label": "Wake up"])

        XCTAssertEqual(real.scheduled.count, 1)
        XCTAssertEqual(real.scheduled.first?.label, "Wake up")
        XCTAssertTrue(fallback.scheduled.isEmpty, "a real alarm needs no notification beside it")
        XCTAssertTrue(result.hasPrefix("Alarm set: Wake up at tomorrow at 7:00 AM"), result)
        XCTAssertTrue(result.contains("like a Clock alarm, even on silent"))
        XCTAssertTrue(result.contains(AlarmTool.Wording.notClockApp))
    }

    func testTheRealAlarmRingsAtTheResolvedMoment() async throws {
        let real = FakeScheduler(authorization: .authorized)
        _ = try await tool(real: real, fallback: FakeScheduler(authorization: .authorized))
            .execute(args: ["time": "7:00 AM"])
        let date = try XCTUnwrap(real.scheduled.first?.date)
        let parts = Calendar.current.dateComponents([.day, .hour, .minute], from: date)
        XCTAssertEqual(parts.day, 19, "7 AM has passed today, so tomorrow")
        XCTAssertEqual(parts.hour, 7)
        XCTAssertEqual(parts.minute, 0)
    }

    // MARK: - The fallback, and why

    func testARefusedPermissionFallsBackToTheNotificationAndSaysSo() async throws {
        let real = FakeScheduler(authorization: .denied)
        let fallback = FakeScheduler(authorization: .authorized)
        let result = try await tool(real: real, fallback: fallback).execute(args: ["time": "22:00"])

        XCTAssertTrue(real.scheduled.isEmpty)
        XCTAssertEqual(fallback.scheduled.count, 1)
        XCTAssertTrue(result.hasPrefix("Alarm set as a notification from this app"), result)
        XCTAssertTrue(result.contains("will not sound if the phone is on silent"))
        XCTAssertTrue(result.contains("the alarm permission for this app is off"))
        XCTAssertTrue(result.contains(AlarmTool.Wording.notClockApp))
    }

    func testADeviceWithoutARealAlarmFallsBackAndSaysSo() async throws {
        let fallback = FakeScheduler(authorization: .authorized)
        let result = try await tool(real: nil, fallback: fallback).execute(args: ["time": "22:00"])
        XCTAssertEqual(fallback.scheduled.count, 1)
        XCTAssertTrue(result.contains("cannot ring a real alarm"), result)
    }

    func testAnAlarmKitRefusalAfterAuthorizationFallsBack() async throws {
        let real = FakeScheduler(authorization: .authorized)
        real.scheduleError = Boom()
        let fallback = FakeScheduler(authorization: .authorized)
        let result = try await tool(real: real, fallback: fallback).execute(args: ["time": "22:00"])
        XCTAssertEqual(fallback.scheduled.count, 1)
        XCTAssertTrue(result.contains("could not be scheduled"), result)
    }

    func testNothingAllowedIsSaidPlainly() async throws {
        let result = try await tool(real: FakeScheduler(authorization: .denied),
                                    fallback: FakeScheduler(authorization: .denied))
            .execute(args: ["time": "22:00"])
        XCTAssertTrue(result.hasPrefix("Couldn't set the alarm"), result)
    }

    // MARK: - List and cancel

    func testListingNamesTheKindAndNeverTheClockApp() async throws {
        let real = FakeScheduler(authorization: .authorized)
        real.listed = [ScheduledAlarm(id: "a", label: "Wake up", date: now.addingTimeInterval(36_000))]
        let result = try await tool(real: real, fallback: FakeScheduler(authorization: .authorized))
            .execute(args: ["action": "list"])
        XCTAssertTrue(result.hasPrefix("1 alarm set in this app: Wake up:"), result)
        XCTAssertTrue(result.contains(AlarmTool.Wording.notClockApp))
    }

    func testListingFallsThroughToNotificationAlarms() async throws {
        let fallback = FakeScheduler(authorization: .authorized)
        fallback.listed = [ScheduledAlarm(id: "n", label: "Pills", date: now.addingTimeInterval(3_600))]
        let result = try await tool(real: FakeScheduler(authorization: .authorized), fallback: fallback)
            .execute(args: ["action": "list"])
        XCTAssertTrue(result.hasPrefix("1 notification alarm set in this app: Pills:"), result)
    }

    func testNothingSetIsSaidAsThisAppsAlarms() async throws {
        let result = try await tool(real: FakeScheduler(authorization: .authorized),
                                    fallback: FakeScheduler(authorization: .authorized))
            .execute(args: ["action": "list"])
        XCTAssertEqual(result, "No alarms set in this app.")
    }

    func testCancelAllCountsBothBackends() async throws {
        let real = FakeScheduler(authorization: .authorized)
        real.cancelledCount = 2
        let fallback = FakeScheduler(authorization: .authorized)
        fallback.cancelledCount = 1
        let result = try await tool(real: real, fallback: fallback).execute(args: ["action": "cancel_all"])
        XCTAssertEqual(result, "Cancelled 3 alarms.")
    }

    // MARK: - The words the model reads

    func testTheDescriptionNeverLetsTheModelPromiseTheClockApp() {
        let description = AlarmTool().description
        XCTAssertTrue(description.contains(AlarmTool.Wording.notClockApp))
        XCTAssertTrue(description.contains("never say it is in the Clock app"))
        XCTAssertTrue(description.contains("ask Siri"))
    }

    // MARK: - Resolving the moment

    func testResolveDateTakesTheNextOccurrenceAndTomorrow() {
        let calendar = Calendar.current
        if case .success(let date) = AlarmTool.resolveDate(time: "22:00", date: nil, now: now) {
            XCTAssertEqual(calendar.dateComponents([.day, .hour], from: date).day, 18, "still ahead today")
        } else { XCTFail() }
        if case .success(let date) = AlarmTool.resolveDate(time: "7:00 AM", date: "tomorrow", now: now) {
            XCTAssertEqual(calendar.dateComponents([.day, .hour], from: date).day, 19)
        } else { XCTFail() }
        XCTAssertEqual(AlarmTool.resolveDate(time: nil, date: nil, now: now), .failure(.noTime))
        XCTAssertEqual(AlarmTool.resolveDate(time: "sevenish", date: nil, now: now),
                       .failure(.unreadableTime("sevenish")))
    }

    // MARK: - The backend choice

    func testTheBackendChoiceFollowsAuthorization() {
        XCTAssertEqual(AlarmBackendChoice.decide(authorization: .authorized), .alarmKit)
        XCTAssertEqual(AlarmBackendChoice.decide(authorization: .denied), .notification(reason: .permissionDenied))
        XCTAssertEqual(AlarmBackendChoice.decide(authorization: .unavailable), .notification(reason: .unavailable))
    }

    // MARK: - The usage string AlarmKit requires

    func testTheCommittedInfoPlistCarriesTheAlarmKitUsageString() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("OpenGlasses/Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let usage = try XCTUnwrap(plist["NSAlarmKitUsageDescription"] as? String,
                                  "AlarmKit refuses to schedule without NSAlarmKitUsageDescription")
        XCTAssertFalse(usage.isEmpty)
    }
}
