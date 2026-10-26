import XCTest
@testable import OpenGlasses

/// Plan JK §8 — the history store's keychain/iCloud pair and its merge, on in-memory backends only.
/// Nothing here touches the live keychain or the iCloud key-value store.
final class ManualAdditionHistoryMergeTests: XCTestCase {
    private let limits = ManualLimits.personal
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("JK-additions-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func store(_ backend: InMemoryManualAdditionBackend, subscription: String = "store-1") -> ManualAdditionHistoryStore {
        ManualAdditionHistoryStore(backend: backend, subscriptionKey: { subscription })
    }

    private func file(_ text: String) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + ".pdf")
        try Data(text.utf8).write(to: url)
        return url
    }

    private func record(_ id: String, daysAgo: Double, spent: Bool = true) -> ManualAdditionRecord {
        .init(fingerprint: id, addedAt: now.addingTimeInterval(-daysAgo * day), spent: spent)
    }

    private func encodeCloud(_ records: [String: [ManualAdditionRecord]]) throws -> Data { try JSONEncoder().encode(records) }

    /// Add `count` new manuals through the store, as an install would.
    @discardableResult
    private func add(_ store: ManualAdditionHistoryStore, _ texts: [String], at date: Date) throws -> ManualAdditionHistoryStore.Pending? {
        let documents = try texts.map { (identity: "my-manuals/" + UUID().uuidString, original: try file($0)) }
        let pending = try store.prepare(documents: documents, limits: limits, now: date)
        if let pending { store.commit(pending, undoWindow: day, now: date) }
        return pending
    }

    func testMergeIsAUnionByFingerprintAndDateAndFlagsOnlyTurnOn() {
        let a = record("a", daysAgo: 3), b = record("b", daysAgo: 2)
        var aRead = a; aRead.read = true
        var bRefunded = b; bRefunded.refunded = true
        let merged = ManualAdditionAllowance.merge([a, b], [aRead], [bRefunded, record("c", daysAgo: 1)])
        XCTAssertEqual(merged.map(\.fingerprint), ["a", "b", "c"])
        XCTAssertTrue(merged[0].read)
        XCTAssertTrue(merged[1].refunded)
        // The same manual added on two dates is two records.
        XCTAssertEqual(ManualAdditionAllowance.merge([a], [record("a", daysAgo: 1)]).count, 2)
    }

    func testASmallerCopyNeverOverwritesALargerOne() throws {
        let backend = InMemoryManualAdditionBackend()
        let local = ManualAdditionHistoryStore.LocalCopy(records: ["store-1": [record("a", daysAgo: 3), record("b", daysAgo: 2), record("c", daysAgo: 1)]])
        backend.localData = try JSONEncoder().encode(local)
        backend.cloudData = try encodeCloud(["store-1": [record("a", daysAgo: 3)]])
        let history = try XCTUnwrap(store(backend).history())
        XCTAssertEqual(history.map(\.fingerprint), ["a", "b", "c"])
        let cloud = try JSONDecoder().decode([String: [ManualAdditionRecord]].self, from: try XCTUnwrap(backend.cloudData))
        XCTAssertEqual(cloud["store-1"]?.count, 3, "the union is written back to the copy that lacked it")
    }

    func testAKeychainOnlyHistoryJoinsICloudOnSignIn() throws {
        let backend = InMemoryManualAdditionBackend()
        backend.cloudAvailable = false
        let offline = store(backend)
        try add(offline, (1...6).map { "manual \($0)" }, at: now)
        XCTAssertNil(backend.cloudData)
        XCTAssertEqual(offline.history()?.count, 6)

        // Later the person signs in to iCloud, where another device already recorded one addition.
        backend.cloudAvailable = true
        backend.cloudData = try encodeCloud(["store-1": [record("from-ipad", daysAgo: 1)]])
        let reopened = store(backend)
        XCTAssertEqual(reopened.history()?.count, 7)
        let cloud = try JSONDecoder().decode([String: [ManualAdditionRecord]].self, from: try XCTUnwrap(backend.cloudData))
        XCTAssertEqual(cloud["store-1"]?.count, 7)
        let local = try JSONDecoder().decode(ManualAdditionHistoryStore.LocalCopy.self, from: try XCTUnwrap(backend.localData))
        XCTAssertEqual(local.records["store-1"]?.count, 7, "and the keychain copy keeps what iCloud brought")
        XCTAssertFalse(String(decoding: try XCTUnwrap(backend.cloudData), as: UTF8.self).contains("my-manuals/"),
                       "holdings never leave the phone")
    }

    func testTwoDevicesAddingOfflineOverspendByWhatTheyAddedAndThenStop() throws {
        // One person, one subscription, one iCloud Keychain secret; two devices, offline.
        let phone = InMemoryManualAdditionBackend(), pad = InMemoryManualAdditionBackend()
        let base = (1...5).map { record("free-\($0)", daysAgo: 60, spent: false) } + [record("x", daysAgo: 2)]
        for backend in [phone, pad] {
            backend.localData = try JSONEncoder().encode(ManualAdditionHistoryStore.LocalCopy(records: ["store-1": base]))
            backend.cloudAvailable = false
            backend.secrets[ManualAdditionHistoryStore.secretPrefix + "store-1"] = Data(repeating: 7, count: 32)
        }
        try add(store(phone), ["phone A", "phone B"], at: now)
        try add(store(pad), ["pad A", "pad B"], at: now)

        // Back online: both copies meet in iCloud.
        phone.cloudAvailable = true; pad.cloudAvailable = true
        _ = store(phone).history()
        pad.cloudData = phone.cloudData
        let merged = try XCTUnwrap(store(pad).history())
        XCTAssertEqual(ManualAdditionAllowance.inWindow(limits.additions!, history: merged, now: now).count, 5, "overspent by two; accepted")
        XCTAssertThrowsError(try add(store(pad), ["one more"], at: now)) {
            XCTAssertTrue($0.localizedDescription.contains("can be added on"), $0.localizedDescription)
        }
    }

    func testFingerprintsFollowTheBytesAndTheSubscriptionSecret() throws {
        let backend = InMemoryManualAdditionBackend()
        let first = store(backend)
        let same = try first.fingerprint(of: try file("the same manual"))
        XCTAssertEqual(try first.fingerprint(of: try file("the same manual")), same)
        XCTAssertNotEqual(try first.fingerprint(of: try file("a re-saved manual")), same)
        XCTAssertEqual(same.count, 64)
        XCTAssertNotEqual(try store(backend, subscription: "store-2").fingerprint(of: try file("the same manual")), same,
                          "another subscription derives other fingerprints")
        // A second device that finds the synced secret uses it.
        let other = InMemoryManualAdditionBackend()
        other.secrets = backend.secrets
        XCTAssertEqual(try store(other).fingerprint(of: try file("the same manual")), same)
    }

    func testAReturningManualCostsNothingAndRemovalWithoutAReadGivesTheAdditionBack() throws {
        let backend = InMemoryManualAdditionBackend()
        let store = store(backend)
        try add(store, (1...5).map { "fill \($0)" }, at: now)
        let identity = "my-manuals/new.pdf"
        let url = try file("the job's manual")
        let pending = try XCTUnwrap(try store.prepare(documents: [(identity, url)], limits: limits, now: now))
        XCTAssertEqual(pending.records.map(\.spent), [true])
        store.commit(pending, undoWindow: day, now: now)
        XCTAssertEqual(store.status(limits: limits, now: now)?.remaining, 2)

        XCTAssertTrue(store.noteRemoved(identity: identity, limits: limits, now: now.addingTimeInterval(3600)))
        XCTAssertEqual(store.status(limits: limits, now: now)?.remaining, 3, "the wrong file is given back")

        // Re-added, read, removed: nothing comes back.
        let later = now.addingTimeInterval(7200)
        let again = try XCTUnwrap(try store.prepare(documents: [(identity, url)], limits: limits, now: later))
        store.commit(again, undoWindow: day, now: later)
        store.noteRead(identities: [identity], limits: limits, now: later.addingTimeInterval(60))
        XCTAssertFalse(store.noteRemoved(identity: identity, limits: limits, now: later.addingTimeInterval(120)))
        XCTAssertEqual(store.status(limits: limits, now: now)?.remaining, 2)
        // And it is now a manual you've had before: free from here on.
        XCTAssertNil(try store.prepare(documents: [("my-manuals/back.pdf", url)], limits: limits, now: now)?.records.first)
    }

    func testTheSameFileStillOnTheShelfIsNotGivenBack() throws {
        let store = store(InMemoryManualAdditionBackend())
        try add(store, (1...5).map { "fill \($0)" }, at: now)
        let url = try file("duplicate")
        let pending = try XCTUnwrap(try store.prepare(documents: [("my-manuals/one.pdf", url)], limits: limits, now: now))
        store.commit(pending, undoWindow: day, now: now)
        let copy = try XCTUnwrap(try store.prepare(documents: [("my-manuals/two.pdf", url)], limits: limits, now: now))
        XCTAssertTrue(copy.records.isEmpty, "a second copy of a held manual is a returning manual")
        store.commit(copy, undoWindow: day, now: now)
        XCTAssertFalse(store.noteRemoved(identity: "my-manuals/one.pdf", limits: limits, now: now))
    }

    func testAnUnreadableHistoryRefusesAdditionsButNeverRemovalOrReading() throws {
        let backend = InMemoryManualAdditionBackend()
        let store = store(backend)
        try add(store, ["fill"], at: now)
        backend.localReadable = false
        let locked = self.store(backend)
        XCTAssertNil(locked.history())
        XCTAssertThrowsError(try locked.prepare(documents: [("my-manuals/x.pdf", try file("x"))], limits: limits, now: now)) {
            XCTAssertTrue($0.localizedDescription.contains("could not be checked"), $0.localizedDescription)
        }
        XCTAssertThrowsError(try locked.checkNewManual(limits: limits, now: now))
        XCTAssertFalse(locked.noteRemoved(identity: "my-manuals/x.pdf", limits: limits, now: now))
        locked.noteRead(identities: ["my-manuals/x.pdf"], limits: limits, now: now)

        let corrupt = InMemoryManualAdditionBackend()
        corrupt.localData = Data("not json".utf8)
        XCTAssertNil(self.store(corrupt).history(), "a damaged copy is unreadable, never an empty allowance")
        XCTAssertNoThrow(try self.store(InMemoryManualAdditionBackend()).checkNewManual(limits: nil, now: now))
    }

    func testAWriteThatCannotLandIsKeptAndRetried() throws {
        let backend = InMemoryManualAdditionBackend()
        let store = store(backend)
        try add(store, ["fill"], at: now)
        let pending = try XCTUnwrap(try store.prepare(documents: [("my-manuals/y.pdf", try file("y"))], limits: limits, now: now))
        backend.localReadable = false
        store.commit(pending, undoWindow: day, now: now)
        backend.localReadable = true
        XCTAssertEqual(store.history()?.count, 2, "this process never forgets a spend it made")
        let local = try JSONDecoder().decode(ManualAdditionHistoryStore.LocalCopy.self, from: try XCTUnwrap(backend.localData))
        XCTAssertEqual(local.records["store-1"]?.count, 2, "and the next read writes it through")
    }

    func testErasureDeletesTheSecretAndTheFingerprints() throws {
        let backend = InMemoryManualAdditionBackend()
        let store = store(backend)
        try add(store, ["fill"], at: now)
        XCTAssertFalse(backend.secrets.isEmpty)
        try store.eraseAll()
        XCTAssertTrue(backend.secrets.isEmpty)
        XCTAssertNil(backend.localData)
        XCTAssertNil(backend.cloudData)
        XCTAssertEqual(store.history(), [])
    }

    func testTheUnitTestHostNeverUsesTheLiveStore() {
        XCTAssertFalse(ManualLibraryAdmission.additions.enforced,
                       "the test host's default store must be in memory and not limit unrelated suites")
    }

    func testTheKeyValueEntitlementIsInTheSpecAndThePersonalExample() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for path in ["OpenGlasses/OpenGlasses.entitlements", "Config/Entitlements/Personal/OpenGlasses.entitlements.example"] {
            let data = try Data(contentsOf: repo.appendingPathComponent(path))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(plist["com.apple.developer.ubiquity-kvstore-identifier"] as? String,
                           "$(TeamIdentifierPrefix)$(CFBundleIdentifier)", path)
        }
        let spec = try String(contentsOf: repo.appendingPathComponent("project.base.yml"), encoding: .utf8)
        XCTAssertTrue(spec.contains("com.apple.developer.ubiquity-kvstore-identifier"))
    }
}
