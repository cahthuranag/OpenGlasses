import XCTest
@testable import OpenGlasses

/// Plan DM P3 — the in-memory diagnostic ring and the consented export built from it.
///
/// Three properties are worth a test here, and they are the three the plan asks for: the ring is
/// bounded and ordered and safe to write to from any thread; the preview the wearer approves is
/// byte-for-byte the file that gets written; and a bundle lives in a protected session that is
/// deleted whichever way the share ends.
final class DiagnosticRingTests: XCTestCase {

    private func event(_ n: Int) -> PrivacyEvent {
        PrivacyEvent(.tools, .toolDispatch, [.init(.count, .count(n))])
    }

    func testRingKeepsTheMostRecentEventsInOrder() {
        let ring = DiagnosticRing(capacity: 5)
        for index in 1...12 {
            ring.record(event(index), line: "line-\(index)")
        }

        let lines = ring.entries.map(\.line)
        XCTAssertEqual(lines, ["line-8", "line-9", "line-10", "line-11", "line-12"],
                       "the ring must hold the newest `capacity` entries, oldest first")
        XCTAssertEqual(ring.count, 5)
    }

    func testRingBelowCapacityHoldsEverything() {
        let ring = DiagnosticRing(capacity: 500)
        for index in 1...10 { ring.record(event(index), line: "line-\(index)") }
        XCTAssertEqual(ring.count, 10)
        XCTAssertEqual(ring.entries.first?.line, "line-1")
        XCTAssertEqual(ring.entries.last?.line, "line-10")
    }

    func testEntriesCarryCategoryNameAndTimestamp() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let ring = DiagnosticRing(capacity: 4, clock: { fixed })
        ring.record(PrivacyLog.qrScanned(payload: .url, bytes: 42), line: "encoded")

        let entry = try? XCTUnwrap(ring.entries.first)
        XCTAssertEqual(entry?.category, .capture)
        XCTAssertEqual(entry?.name, .qrScanned)
        XCTAssertEqual(entry?.timestamp, fixed)
    }

    func testClearEmptiesTheRing() {
        let ring = DiagnosticRing(capacity: 4)
        ring.record(event(1), line: "a")
        ring.clear()
        XCTAssertTrue(ring.entries.isEmpty)
    }

    /// The ring is written from whichever thread logged, so concurrent writes must neither lose
    /// entries nor exceed the bound.
    func testConcurrentWritesStayBoundedAndComplete() {
        let ring = DiagnosticRing(capacity: 100)
        let queue = DispatchQueue(label: "canary.ring", attributes: .concurrent)
        let group = DispatchGroup()

        for index in 0..<500 {
            queue.async(group: group) { ring.record(self.event(index), line: "line-\(index)") }
        }
        group.wait()

        XCTAssertEqual(ring.count, 100, "the bound must hold under concurrency")
        XCTAssertEqual(Set(ring.entries.map(\.line)).count, 100, "no entry may be written twice")
    }

    func testPersistedTailSurvivesRelaunchWithoutMixingCurrentRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("breadcrumbs.json")
        let now = Date()
        let store = DiagnosticBreadcrumbStore(url: url)
        let entries = (0..<8).map {
            DiagnosticRing.Entry(timestamp: now, category: .lifecycle, name: .app, line: "event-\($0)")
        }
        store.schedule(entries)
        store.waitForPendingWrites()
        let relaunched = DiagnosticRing(capacity: 3, clock: { now }, persistenceURL: url)
        XCTAssertEqual(relaunched.previousEntries.map(\.line), ["event-5", "event-6", "event-7"])
        XCTAssertTrue(relaunched.entries.isEmpty)
        relaunched.record(event(1), line: "new-run")
        XCTAssertEqual(relaunched.entries.map(\.line), ["new-run"])
        XCTAssertEqual(relaunched.previousEntries.count, 3)
        relaunched.waitForPendingWrites()
    }

    func testPersistenceRejectsExpiredAndCorruptData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("breadcrumbs.json")
        let now = Date()
        let store = DiagnosticBreadcrumbStore(url: url)
        store.schedule([
            .init(timestamp: now.addingTimeInterval(-49 * 3600), category: .lifecycle, name: .app, line: "old"),
            .init(timestamp: now, category: .lifecycle, name: .app, line: "recent")
        ])
        store.waitForPendingWrites()
        XCTAssertEqual(store.read(capacity: 10, now: now).map(\.line), ["recent"])
        try Data("partial-json".utf8).write(to: url)
        XCTAssertTrue(store.read(capacity: 10, now: now).isEmpty)
    }

    func testPersistenceCoalescingKeepsNewestSnapshotAndCanClear() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticBreadcrumbStore(url: directory.appendingPathComponent("breadcrumbs.json"))
        let now = Date()
        for index in 0..<200 {
            store.schedule([.init(timestamp: now, category: .lifecycle, name: .app, line: "\(index)")])
        }
        store.waitForPendingWrites()
        XCTAssertEqual(store.read(capacity: 10, now: now).map(\.line), ["199"])
        store.schedule([])
        store.waitForPendingWrites()
        XCTAssertTrue(store.read(capacity: 10, now: now).isEmpty)
    }

    // MARK: - Retention across a long run and across relaunches

    private func temporaryFile() -> (directory: URL, url: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (directory, directory.appendingPathComponent("breadcrumbs.json"))
    }

    /// A tester's report held exactly the newest 500 lines of a long run: the launch was gone and
    /// nothing said so. The launch window is now kept, and the hole is counted.
    func testTheLaunchWindowSurvivesALongRunAndTheHoleIsCounted() {
        let ring = DiagnosticRing(capacity: 100, launchLimit: 10)
        XCTAssertEqual(ring.launchLimit, 10)
        for index in 0..<500 { ring.record(event(index), line: "line-\(index)") }

        let entries = ring.entries
        XCTAssertEqual(entries.count, 100, "the count bound still holds")
        XCTAssertEqual(entries.prefix(10).map(\.line), (0..<10).map { "line-\($0)" },
                       "the first events of the run are never evicted")
        XCTAssertEqual(entries[10].line, "line-410", "after them, the newest are kept")
        XCTAssertEqual(entries[10].gapBefore, 400, "and the first one kept counts what went")
        XCTAssertEqual(entries.last?.line, "line-499")
        XCTAssertEqual(entries.filter { $0.gapBefore != nil }.count, 1)
    }

    func testTheLaunchWindowIsATenthOfASmallRingAtMost() {
        XCTAssertEqual(DiagnosticRing(capacity: 5).launchLimit, 0)
        XCTAssertEqual(DiagnosticRing(capacity: 100).launchLimit, 10)
        XCTAssertEqual(DiagnosticRing().launchLimit, DiagnosticRing.defaultLaunchLimit)
        XCTAssertGreaterThan(DiagnosticRing.defaultCapacity, 500,
                             "the old 500-line ring is what lost a long run's launch")
    }

    func testEventsPastTheAgeBoundAreDroppedAndCounted() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let ring = DiagnosticRing(capacity: 1000, maxAge: 60, launchLimit: 0)
        ring.record(event(1), line: "old-1", at: start)
        ring.record(event(2), line: "old-2", at: start.addingTimeInterval(10))
        ring.record(event(3), line: "recent", at: start.addingTimeInterval(100))

        XCTAssertEqual(ring.entries.map(\.line), ["recent"])
        XCTAssertEqual(ring.entries.first?.gapBefore, 2)
    }

    /// An app update that renames or removes an event name used to make the whole saved file
    /// undecodable. Now it costs those entries, and they are counted.
    func testAnUndecodableEntryCostsOnlyItselfAndIsCounted() throws {
        let (directory, url) = temporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let valid = (0..<3).map {
            DiagnosticRing.Entry(timestamp: now, category: .lifecycle, name: .app, line: "kept-\($0)")
        }
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(valid)) as? [[String: Any]])
        var renamed = objects[0]
        renamed["name"] = "anEventNameThisBuildNeverHad"
        renamed["line"] = "gone"
        // [gone, kept-0, gone, kept-1, kept-2, gone]
        objects = [renamed, objects[0], renamed, objects[1], objects[2], renamed]
        try JSONSerialization.data(withJSONObject: objects).write(to: url)

        let load = DiagnosticBreadcrumbStore(url: url).load(capacity: 10, now: now)
        guard case .loaded(let entries, let trailing) = load else {
            return XCTFail("a file with some bad entries still loads, got \(load)")
        }
        XCTAssertEqual(entries.map(\.line), ["kept-0", "kept-1", "kept-2"])
        XCTAssertEqual(entries.map(\.gapBefore), [1, 1, nil])
        XCTAssertEqual(trailing, 1)

        // The trailing one is carried onto the new run's first entry.
        let ring = DiagnosticRing(capacity: 10, persistenceURL: url)
        ring.record(event(1), line: "new-run")
        XCTAssertEqual(ring.entries.first?.gapBefore, 1)
        ring.waitForPendingWrites()
    }

    /// The format before runs were told apart still reads: no `run`, no `gapBefore`.
    func testAFileWrittenByAnOlderBuildStillReads() throws {
        let (directory, url) = temporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let old: [[String: Any]] = [[
            "timestamp": now.timeIntervalSinceReferenceDate,
            "category": "lifecycle", "name": "app",
            "line": "[lifecycle] app event=loggingActive",
        ]]
        try JSONSerialization.data(withJSONObject: old).write(to: url)

        let ring = DiagnosticRing(capacity: 10, persistenceURL: url)
        XCTAssertEqual(ring.previousEntries.map(\.line), ["[lifecycle] app event=loggingActive"])
        XCTAssertNil(ring.previousEntries.first?.run)
    }

    /// Only the immediately previous run used to survive: the first event of a new run overwrote
    /// the file with that run alone. Earlier runs now accumulate within the bounds.
    func testEarlierRunsAccumulateAcrossRelaunches() {
        let (directory, url) = temporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = DiagnosticRing(capacity: 100, runID: "run-one", persistenceURL: url)
        for index in 0..<3 { first.record(event(index), line: "one-\(index)") }
        first.waitForPendingWrites()

        let second = DiagnosticRing(capacity: 100, runID: "run-two", persistenceURL: url)
        XCTAssertEqual(second.previousEntries.map(\.line), ["one-0", "one-1", "one-2"])
        for index in 0..<2 { second.record(event(index), line: "two-\(index)") }
        second.waitForPendingWrites()

        let third = DiagnosticRing(capacity: 100, runID: "run-three", persistenceURL: url)
        XCTAssertEqual(third.previousEntries.map(\.line), ["one-0", "one-1", "one-2", "two-0", "two-1"],
                       "the run before last is still there")
        XCTAssertEqual(third.previousEntries.map(\.run),
                       ["run-one", "run-one", "run-one", "run-two", "run-two"])
        third.record(event(9), line: "three-0")

        let lines = third.timeline.map(\.line)
        XCTAssertEqual(lines, [
            "── an earlier run of the app ──", "one-0", "one-1", "one-2",
            "── an earlier run of the app ──", "two-0", "two-1",
            "── this run of the app ──", "three-0",
        ])
        third.waitForPendingWrites()
    }

    func testTheTimelineMarksEveryHoleAndEveryRunBoundary() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        func entry(_ line: String, run: String?, gap: Int? = nil) -> DiagnosticRing.Entry {
            DiagnosticRing.Entry(timestamp: at, category: .lifecycle, name: .app, line: line,
                                 run: run, gapBefore: gap)
        }
        let lines = DiagnosticRing.timeline(
            history: [entry("legacy", run: nil, gap: 3), entry("a-1", run: "a")],
            current: [entry("launch", run: "me"), entry("later", run: "me", gap: 1)],
            historyProblem: nil, now: at).map(\.line)
        XCTAssertEqual(lines, [
            "… 3 earlier events not kept …", "── an earlier run of the app ──", "legacy",
            "── an earlier run of the app ──", "a-1",
            "── this run of the app ──", "launch",
            "… 1 earlier event not kept …", "later",
        ])
    }

    func testTheTimelineSaysWhenEarlierRunsCouldNotBeRead() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let current = [DiagnosticRing.Entry(timestamp: at, category: .lifecycle, name: .app,
                                            line: "now", run: "me")]
        let locked = DiagnosticRing.timeline(history: [], current: current,
                                             historyProblem: .unreadable, now: at)
        XCTAssertTrue(locked.first?.line.contains("could not be read yet") ?? false)
        XCTAssertEqual(locked.first?.at, at, "dated with the events it sits beside, so a window keeps it")
        let corrupt = DiagnosticRing.timeline(history: [], current: current,
                                              historyProblem: .corrupt, now: at)
        XCTAssertTrue(corrupt.first?.line.contains("could not be read") ?? false)
    }

    /// A launch before the phone's first unlock cannot read the saved history. Writing then would
    /// replace every earlier run with this one, so writes wait for the retry on unlock.
    func testAnUnreadableHistoryIsNotOverwrittenAndIsReadOnUnlock() throws {
        let (directory, url) = temporaryFile()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let earlier = DiagnosticRing(capacity: 100, runID: "earlier", persistenceURL: url)
        earlier.record(event(1), line: "from-before")
        earlier.waitForPendingWrites()

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        if (try? Data(contentsOf: url)) != nil {
            throw XCTSkip("this process can read a 0o000 file (running as root?)")
        }

        let ring = DiagnosticRing(capacity: 100, runID: "now", persistenceURL: url)
        XCTAssertTrue(ring.previousEntries.isEmpty)
        ring.record(event(2), line: "while-locked")
        ring.waitForPendingWrites()
        XCTAssertTrue(ring.timeline.first?.line.contains("could not be read yet") ?? false)

        // Unlocked: the history is read, and only then is the file written — with both runs.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        ring.protectedDataDidBecomeAvailable()
        XCTAssertEqual(ring.previousEntries.map(\.line), ["from-before"])
        ring.waitForPendingWrites()
        XCTAssertEqual(DiagnosticBreadcrumbStore(url: url).read(capacity: 100, now: Date()).map(\.line),
                       ["from-before", "while-locked"])
    }

    func testClearForgetsEarlierRunsToo() {
        let (directory, url) = temporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let earlier = DiagnosticRing(capacity: 100, persistenceURL: url)
        earlier.record(event(1), line: "from-before")
        earlier.waitForPendingWrites()

        let ring = DiagnosticRing(capacity: 100, persistenceURL: url)
        XCTAssertFalse(ring.previousEntries.isEmpty)
        ring.clear()
        ring.waitForPendingWrites()
        XCTAssertTrue(ring.previousEntries.isEmpty)
        XCTAssertTrue(ring.timeline.isEmpty)
        XCTAssertTrue(DiagnosticBreadcrumbStore(url: url).read(capacity: 100, now: Date()).isEmpty)
    }

    /// Attaching subscribes to the real facade; detaching actually stops it.
    func testAttachRecordsRealEventsAndDetachStops() {
        let ring = DiagnosticRing(capacity: 50)
        ring.attach()
        defer { ring.detach() }
        XCTAssertTrue(ring.isAttached)

        PrivacyLog.toolDispatch(.native, tool: "probe_tool")
        XCTAssertEqual(ring.count, 1)
        XCTAssertTrue(ring.entries.first?.line.contains("probe_tool") == true)

        ring.attach()  // idempotent — must not double-record
        PrivacyLog.toolDispatch(.native, tool: "probe_tool")
        XCTAssertEqual(ring.count, 2)

        ring.detach()
        PrivacyLog.toolDispatch(.native, tool: "probe_tool")
        XCTAssertEqual(ring.count, 2)
        XCTAssertFalse(ring.isAttached)
    }
}

// MARK: - The document

final class DiagnosticExportBuilderTests: XCTestCase {

    private let environment = DiagnosticExportEnvironment(
        appVersion: "2026.9", buildNumber: "354",
        systemName: "iOS", systemVersion: "26.0", deviceModel: "iPhone17,1")

    private func entries(_ count: Int) -> [DiagnosticRing.Entry] {
        (0..<count).map { index in
            DiagnosticRing.Entry(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                                 category: .tools, name: .toolRun,
                                 line: "[tools] toolRun event=succeeded tool=web_search elapsed=1.5s")
        }
    }

    func testPreviewIsExactlyWhatGetsWritten() throws {
        let document = DiagnosticExportBuilder.build(entries: entries(3), environment: environment)
        // Every event line appears in the body, and the body is the single representation.
        for line in document.eventLines {
            XCTAssertTrue(document.body.contains(line))
        }
        for line in document.headerLines where !line.isEmpty {
            XCTAssertTrue(document.body.contains(line))
        }
        XCTAssertEqual(document.eventCount, 3)
    }

    func testEventLinesCarryATimestampAndTheEncodedEvent() throws {
        let document = DiagnosticExportBuilder.build(entries: entries(1), environment: environment,
                                                     timeZone: TimeZone(identifier: "UTC")!)
        let line = try XCTUnwrap(document.eventLines.first)
        XCTAssertTrue(line.hasPrefix("22:13:20.000"), "got \(line)")
        XCTAssertTrue(line.contains("[tools] toolRun event=succeeded"))
    }

    func testHeaderStatesWhatTheFileIsAndIsNot() {
        let document = DiagnosticExportBuilder.build(entries: entries(2), environment: environment)
        let header = document.headerLines.joined(separator: " ")
        XCTAssertTrue(header.contains("2026.9"))
        XCTAssertTrue(header.contains("iPhone17,1"))
        XCTAssertTrue(header.contains("no conversation content"))
        XCTAssertTrue(header.contains("2 events from this session"))
        // P3.4: the honest note about `.private` log fields must travel with the file.
        XCTAssertTrue(header.lowercased().contains("does not make the value safe to send"))
    }

    func testAFullRingSaysSoRatherThanImplyingNothingElseHappened() {
        let full = DiagnosticExportBuilder.build(entries: entries(10), environment: environment,
                                                 capacity: 10)
        XCTAssertTrue(full.ringWasFull)
        XCTAssertTrue(full.body.contains("the oldest were dropped"))

        let partial = DiagnosticExportBuilder.build(entries: entries(3), environment: environment,
                                                    capacity: 10)
        XCTAssertFalse(partial.ringWasFull)
        XCTAssertFalse(partial.body.contains("the oldest were dropped"))
    }

    func testEmptyRingProducesAnHonestDocument() {
        let document = DiagnosticExportBuilder.build(entries: [], environment: environment)
        XCTAssertTrue(document.body.contains("(no events recorded yet)"))
        XCTAssertEqual(document.eventCount, 0)
    }

    /// The defence-in-depth pass P0.5 kept `LogRedaction` for. Nothing that reaches the builder
    /// should contain a token — the ring holds encoded events, and no field of one can be a URL —
    /// so this is the belt to the type system's braces, and it has to actually run.
    func testFinalRedactionPassMasksATokenThatSomehowSurvived() {
        let planted = DiagnosticRing.Entry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            category: .capture, name: .qrFetchLoaded,
            line: #"[capture] qrFetchLoaded host=https://x.example.test/a?token=CANARY-7f3a-SECRET"#)
        let document = DiagnosticExportBuilder.build(entries: [planted], environment: environment)

        XCTAssertFalse(document.body.contains("CANARY-7f3a-SECRET"),
                       "the final redaction pass must mask a token value")
        XCTAssertTrue(document.body.contains("token=***"))
    }

    func testPreviousRunIsLabeledDatedAndRedactedInExport() {
        let previous = DiagnosticRing.Entry(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            category: .capture, name: .qrFetchLoaded, line: "url=https://example.test/?token=CANARY-SECRET")
        let document = DiagnosticExportBuilder.build(entries: entries(1), environment: environment,
            previousEntries: [previous], timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(document.eventCount, 2)
        XCTAssertTrue(document.body.contains("Previous run (may be a different app build; exit reason unknown)"))
        XCTAssertTrue(document.body.contains("2023-11-14"))
        XCTAssertFalse(document.body.contains("CANARY-SECRET"))
        XCTAssertTrue(document.body.contains("Nothing is sent automatically"))
    }

    func testDisplayNameIsADateAndNothingElse() {
        let name = DiagnosticExportBuilder.displayName(now: Date(timeIntervalSince1970: 1_700_000_000),
                                                       timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "avenkin-diagnostics-2023-11-14-2213.txt")
    }
}

// MARK: - The protected session

@MainActor
final class DiagnosticExportCoordinatorTests: XCTestCase {

    /// Records what the protector was asked to protect, and can be made to fail either half.
    private final class RecordingProtector: ProtectedExportProtecting {
        enum Failure { case directory, file }
        var failure: Failure?
        private(set) var protected: [URL] = []

        func protect(_ url: URL) throws {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if failure == .directory && isDirectory { throw ProtectedExportFault.setupFailed }
            if failure == .file && !isDirectory { throw ProtectedExportFault.setupFailed }
            protected.append(url)
            try FileProtectionApplier().protect(url)
        }
    }

    private var root: URL!
    private var protector: RecordingProtector!
    private var coordinator: DiagnosticExportCoordinator!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticExportTests_\(UUID().uuidString)")
        protector = RecordingProtector()
        coordinator = DiagnosticExportCoordinator(
            store: ProtectedExportFileStore(rootDirectoryName: "DiagnosticExports",
                                            root: root, protector: protector))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func document(_ text: String = "diagnostics") -> DiagnosticExportDocument {
        DiagnosticExportBuilder.build(
            entries: [DiagnosticRing.Entry(timestamp: Date(), category: .tools, name: .toolRun,
                                           line: "[tools] toolRun event=succeeded \(text)")],
            environment: .unknown)
    }

    func testTheFileHoldsExactlyThePreviewedBytes() throws {
        let previewed = document()
        let lease = try coordinator.makeLease(document: previewed)
        defer { coordinator.release(lease) }

        let written = try String(contentsOf: lease.fileURL, encoding: .utf8)
        XCTAssertEqual(written, previewed.body,
                       "the file must be the preview — nothing appended after consent")
    }

    func testTheBundleIsProtectedAndBackupExcludedUnderTheRoot() throws {
        let lease = try coordinator.makeLease(document: document())
        defer { coordinator.release(lease) }

        XCTAssertTrue(ProtectedExportFileStore.isContained(lease.fileURL, within: root))
        XCTAssertTrue(protector.protected.contains { $0.path == lease.sessionDirectory.path })
        XCTAssertTrue(protector.protected.contains { $0.path == lease.fileURL.path })
        XCTAssertLessThan(protector.protected.firstIndex { $0.path == lease.sessionDirectory.path }!,
                          protector.protected.firstIndex { $0.path == lease.fileURL.path }!,
                          "the directory is protected before it can hold anything")

        for url in [lease.sessionDirectory, lease.fileURL] {
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            XCTAssertEqual(values.isExcludedFromBackup, true)
        }
        if let protection = try FileManager.default.attributesOfItem(atPath: lease.fileURL.path)[.protectionKey]
            as? FileProtectionType {
            XCTAssertEqual(protection, .complete)
        }
    }

    func testOnDiskNameIsAUUIDNotTheDisplayName() throws {
        let lease = try coordinator.makeLease(document: document(),
                                              displayName: "my-diagnostics-2026.txt")
        defer { coordinator.release(lease) }
        let stem = lease.fileURL.deletingPathExtension().lastPathComponent
        XCTAssertNotNil(UUID(uuidString: stem), "on-disk name must be a bare UUID, got \(stem)")
        XCTAssertEqual(lease.displayName, "my-diagnostics-2026.txt")
    }

    func testTraversalDisplayNamesCannotEscapeTheRoot() throws {
        for hostile in ["../../etc/passwd", "/etc/passwd", "../"] {
            let lease = try coordinator.makeLease(document: document(), displayName: hostile)
            XCTAssertTrue(ProtectedExportFileStore.isContained(lease.fileURL, within: root))
            XCTAssertFalse(lease.displayName.contains("/"))
            XCTAssertFalse(lease.displayName.contains(".."))
            coordinator.release(lease)
        }
    }

    func testEverySharedOutcomeRemovesTheFile() throws {
        for outcome in [DiagnosticExportCoordinator.ShareOutcome.completed, .cancelled, .failed] {
            let lease = try coordinator.makeLease(document: document())
            coordinator.beginShare(lease)
            coordinator.finishShare(lease, outcome: outcome)
            XCTAssertFalse(FileManager.default.fileExists(atPath: lease.sessionDirectory.path),
                           "\(outcome) must delete the bundle")
            XCTAssertEqual(coordinator.activeLeaseCount, 0)
        }
    }

    func testDoubleReleaseIsHarmless() throws {
        let lease = try coordinator.makeLease(document: document())
        coordinator.release(lease)
        coordinator.release(lease)
        XCTAssertEqual(coordinator.activeLeaseCount, 0)
    }

    func testBackgroundingReleasesWhatNoShareHolds() throws {
        let shared = try coordinator.makeLease(document: document())
        let abandoned = try coordinator.makeLease(document: document())
        coordinator.beginShare(shared)

        coordinator.handleBackground()

        XCTAssertTrue(FileManager.default.fileExists(atPath: shared.fileURL.path),
                      "a bundle held by an onscreen share survives backgrounding")
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.sessionDirectory.path))
        coordinator.finishShare(shared, outcome: .completed)
    }

    func testScavengeRemovesACrashAbandonedBundlePastTTL() throws {
        let store = ProtectedExportFileStore(rootDirectoryName: "DiagnosticExports",
                                             root: root, protector: protector)
        let session = try store.createSession(fileExtension: "txt") { url in
            try Data("stale".utf8).write(to: url)
        }
        // A different store instance is what a later launch has: it owns nothing here.
        let nextLaunch = DiagnosticExportCoordinator(
            store: ProtectedExportFileStore(rootDirectoryName: "DiagnosticExports",
                                            root: root, protector: RecordingProtector()),
            clock: { Date().addingTimeInterval(7200) })
        nextLaunch.scavenge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.directory.path))
    }

    func testScavengeSparesABundleInsideTheRecoveryWindow() throws {
        let lease = try coordinator.makeLease(document: document())
        coordinator.scavenge()
        XCTAssertTrue(FileManager.default.fileExists(atPath: lease.fileURL.path))
        coordinator.release(lease)
    }

    func testAProtectionFailureLeavesNothingBehind() {
        protector.failure = .file
        XCTAssertThrowsError(try coordinator.makeLease(document: document()))
        let remaining = (try? FileManager.default.contentsOfDirectory(at: root,
                                                                     includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(remaining.isEmpty, "a bundle that could not be protected must not survive")
    }

    /// The end-to-end privacy claim: drive real subsystems with the canary corpus, export the ring
    /// that recorded them, and read the file back off disk.
    func testACanaryDrivenThroughTheAppNeverReachesAnExportFile() async throws {
        let ring = DiagnosticRing(capacity: 500)
        ring.attach()
        defer { ring.detach() }

        // Real subsystems, canary-bearing input — the same corpus `PrivacyCanaryTests` drives.
        let registry = NativeToolRegistry(locationService: LocationService())
        registry.register(ExportProbeTool())
        let router = NativeToolRouter(registry: registry)
        router.toolTimeoutSeconds = 5
        _ = await router.handleToolCall(name: "export_probe",
                                        args: ["payload": PrivacyCanary.toolArguments])
        AmbientCaptionService().insertVisualNote(PrivacyCanary.transcript)
        PrivacyLog.qrFetchBlocked(.refused(URLFetchGuard.Rejection
            .privateOrReservedHost(PrivacyCanary.url)))

        XCTAssertFalse(ring.entries.isEmpty, "the ring recorded nothing — the probe is vacuous")

        let document = DiagnosticExportBuilder.build(entries: ring.entries, environment: .unknown,
                                                     capacity: ring.capacity)
        let lease = try coordinator.makeLease(document: document)
        defer { coordinator.release(lease) }

        let written = try String(contentsOf: lease.fileURL, encoding: .utf8)
        XCTAssertFalse(written.uppercased().contains(PrivacyCanary.stem),
                       "a canary reached the export file:\n\(written)")
        for canary in PrivacyCanary.all {
            XCTAssertFalse(written.contains(canary))
        }
        XCTAssertTrue(written.contains("export_probe"),
                      "the export must still describe what happened")
    }
}

/// Returns a canary-bearing result through the real tool router.
private struct ExportProbeTool: NativeTool {
    let name = "export_probe"
    let description = "test fixture"
    let parametersSchema: [String: Any] = ["type": "object", "properties": [:] as [String: Any]]

    func execute(args: [String: Any]) async throws -> String {
        PrivacyCanary.toolResult
    }
}
