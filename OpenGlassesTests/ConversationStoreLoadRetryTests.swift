import XCTest
@testable import OpenGlasses

/// Issue 427: a conversations file that could not be read at launch blocked saves for the rest of
/// the process.
///
/// The file is protected at rest (`.complete` then; first-unlock since a tester's locked-phone
/// saves failed), so an app that launches before the device's first unlock reads Cocoa 257 and
/// latches `saveBlocked`. `loadThreads()` only ever ran from
/// `init`, and `protectedDataDidBecomeAvailable()` rebuilt recall from memory without re-reading —
/// so nothing could ever clear the latch. Field trace: launched 07:19 locked, active at 07:51,
/// every single turn afterwards dropped with `saveSkipped detail=loadFailed`.
@MainActor
final class ConversationStoreLoadRetryTests: XCTestCase {

    private var tempDir: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationStoreLoadRetryTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("conversations.json")
    }

    override func tearDown() {
        // Always restore permissions or the directory cannot be removed.
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        try? FileManager.default.removeItem(at: tempDir)
        Config.setConversationEncryptionEnabled(false)
        super.tearDown()
    }

    private func writeThreads(_ threads: [ConversationThread]) throws {
        try JSONEncoder().encode(threads).write(to: fileURL, options: .atomic)
    }

    private func readThreadsFromDisk() throws -> [ConversationThread] {
        try JSONDecoder().decode([ConversationThread].self, from: Data(contentsOf: fileURL))
    }

    /// Makes the file unreadable and confirms the OS actually enforces it in this test process —
    /// a root test runner could read a 0o000 file and quietly invalidate the whole scenario.
    private func denyReadsOrSkip() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: fileURL.path)
        if (try? Data(contentsOf: fileURL)) != nil {
            throw XCTSkip("this process can read a 0o000 file (running as root?) — "
                          + "the unreadable-load path cannot be simulated here")
        }
    }

    func testLoadFailureBlocksSavesAndTheUnlockRetryRestoresThem() throws {
        let onDisk = ConversationThread(mode: "direct", title: "Written before the lock")
        try writeThreads([onDisk])

        try denyReadsOrSkip()

        // Launch with the file unreadable — exactly the locked-device case.
        let store = ConversationStore(directory: tempDir)
        XCTAssertTrue(store.saveBlocked, "an unreadable existing file must block saves")
        XCTAssertTrue(store.threads.isEmpty, "nothing was loaded")

        // A conversation happens anyway. It lives only in memory: the save is refused.
        let live = store.startThread(mode: "direct", personaId: nil)
        store.appendMessage(role: "user", content: "does this survive the unlock?")
        XCTAssertTrue(store.saveBlocked, "still blocked — nothing has re-read the file")

        // The device is unlocked: protected data becomes available.
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: fileURL.path)
        store.protectedDataDidBecomeAvailable()

        XCTAssertFalse(store.saveBlocked, "a successful re-read must lift the latch")
        let ids = Set(store.threads.map(\.id))
        XCTAssertEqual(ids, [onDisk.id, live.id],
                       "the on-disk thread is recovered and the unsaved live one is kept")

        // And the merged set is now actually on disk — the retry persists it.
        let persisted = try readThreadsFromDisk()
        XCTAssertEqual(Set(persisted.map(\.id)), [onDisk.id, live.id])
        XCTAssertEqual(persisted.first(where: { $0.id == live.id })?.messages.count, 1)

        // Saves work from here on.
        store.appendMessage(role: "assistant", content: "it did")
        XCTAssertFalse(store.saveBlocked)
        XCTAssertEqual(try readThreadsFromDisk().first(where: { $0.id == live.id })?.messages.count, 2)
    }

    /// A file that is still unreadable when the notification fires must leave the latch on —
    /// writing now would put an empty history over data that may be perfectly intact.
    func testRetryLeavesSavesBlockedWhileTheFileIsStillUnreadable() throws {
        let onDisk = ConversationThread(mode: "direct", title: "Untouched")
        try writeThreads([onDisk])
        try denyReadsOrSkip()

        let store = ConversationStore(directory: tempDir)
        XCTAssertTrue(store.saveBlocked)

        store.protectedDataDidBecomeAvailable()
        XCTAssertTrue(store.saveBlocked, "still unreadable — the store must stay closed for writes")

        // The original bytes are untouched.
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: fileURL.path)
        XCTAssertEqual(try readThreadsFromDisk().map(\.id), [onDisk.id])
    }

    /// The merge keeps the store's newest-first ordering rather than parking a brand-new
    /// conversation at the bottom of the list.
    func testMergedThreadsStayNewestFirst() throws {
        let old = ConversationThread(mode: "direct", title: "Older")
        try writeThreads([old])
        try denyReadsOrSkip()

        let store = ConversationStore(directory: tempDir)
        let live = store.startThread(mode: "direct", personaId: nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: fileURL.path)
        store.protectedDataDidBecomeAvailable()

        XCTAssertEqual(store.threads.first?.id, live.id,
                       "the thread started during the outage is the most recent one")
    }

    // MARK: - Encrypted stores

    /// The retry must never hand an encrypted file to the plaintext reader.
    ///
    /// `ConversationEncryptionService.isFileEncrypted(at:)` answers `false` for a file it cannot
    /// *read*, so a locked-device launch with encryption on latches `saveBlocked` down the same
    /// plaintext branch an unencrypted store takes. If the retry then re-read it as plaintext, the
    /// `OGENC1` bytes would decode as `.corrupt`, `StoreRecovery` would move the user's history
    /// aside, and `save()` would write an empty file over the top — a save outage turned into data
    /// loss for exactly the wearers who opted into more protection.
    ///
    /// The decrypt itself cannot succeed in a test process (no Keychain key, so `retrieveKey()`
    /// returns `errSecItemNotFound` without prompting — and any other Keychain outcome fails the
    /// same way on a payload that was never sealed with a real key). That is the point: whatever
    /// the decrypt does, the ciphertext on disk must come back byte-for-byte identical.
    func testEncryptedFileIsNotClobberedByTheRetry() throws {
        Config.setConversationEncryptionEnabled(true)

        // A plausible encrypted file: the magic header plus opaque bytes.
        var ciphertext = Data("OGENC1".utf8)
        ciphertext.append(Data(repeating: 0xAB, count: 256))
        try ciphertext.write(to: fileURL, options: .atomic)

        try denyReadsOrSkip()

        let store = ConversationStore(directory: tempDir)
        XCTAssertTrue(store.saveBlocked,
                      "an unreadable file latches the same way whether or not it is encrypted")

        // A conversation happens during the outage, as in the plaintext case.
        _ = store.startThread(mode: "direct", personaId: nil)
        store.appendMessage(role: "user", content: "written while saves were blocked")

        // Protected data becomes available.
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: fileURL.path)
        store.protectedDataDidBecomeAvailable()

        // Taking the decrypt branch is observable: only that branch closes the store while it runs.
        XCTAssertTrue(store.isLocked,
                      "an encrypted file must go through the decrypt path, not the plaintext reader")
        XCTAssertTrue(store.saveBlocked,
                      "the latch stays on until a decrypt actually succeeds")

        // The bytes are the whole point.
        XCTAssertEqual(try Data(contentsOf: fileURL), ciphertext,
                       "the encrypted history must be untouched by the retry")
    }

    /// The decrypt branch actually runs, actually fails here, and still leaves the file alone.
    ///
    /// The wait is observable rather than timed: a local `DiagnosticRing` taps the privacy log and
    /// the test blocks until the failure event appears, so this cannot pass by asserting before the
    /// task has run.
    func testFailedDecryptLeavesTheStoreClosedAndTheFileIntact() async throws {
        Config.setConversationEncryptionEnabled(true)

        var ciphertext = Data("OGENC1".utf8)
        ciphertext.append(Data(repeating: 0xCD, count: 128))
        try ciphertext.write(to: fileURL, options: .atomic)

        try denyReadsOrSkip()
        let store = ConversationStore(directory: tempDir)
        XCTAssertTrue(store.saveBlocked)

        let ring = DiagnosticRing(capacity: 200)
        ring.attach()
        defer { ring.detach() }

        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: fileURL.path)
        store.protectedDataDidBecomeAvailable()

        // Wait for the decrypt task to report its failure. The poll returns the moment the event
        // lands, so the budget only matters when the host is starved: two seconds was enough
        // alone and ran out on CI under the full suite (failed at 2.65 s), so it is fifteen.
        var reported = false
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if ring.entries.contains(where: { $0.line.contains("awaitingAuthentication") }) {
                reported = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(reported,
                      "the retry must have gone through the decrypt path and reported its failure")

        XCTAssertTrue(store.isLocked, "a store whose decrypt failed stays closed")
        XCTAssertTrue(store.saveBlocked, "and stays unwritable")
        XCTAssertEqual(try Data(contentsOf: fileURL), ciphertext,
                       "the ciphertext is untouched by a failed retry")
    }
}

/// A save that fails is retried without waiting for another turn.
///
/// Field trace: app backgrounded, phone locked in a pocket, and every glasses turn logged
/// `saveFailed error=storage(NSError)#513` — the file was `.complete`-protected. The threads lived
/// on in memory, but nothing marked them unsaved, so a process death before the next successful
/// turn lost them. The class is now first-unlock, and a failed save leaves the store dirty until
/// protected data returns or the app comes to the front.
@MainActor
final class ConversationStoreSaveRetryTests: XCTestCase {

    /// Counts writes so a test can tell a flush that wrote from one that did nothing.
    private final class WriteCounter: @unchecked Sendable {
        var count = 0
    }

    private var tempDir: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        Config.setConversationEncryptionEnabled(false)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationStoreSaveRetryTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("conversations.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Throws what a write against a `.complete` file on a locked phone throws (Cocoa 513).
    private static let failingWriter: @Sendable (Data, URL, Data.WritingOptions) throws -> Void = { _, _, _ in
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    }

    private func readThreadsFromDisk() throws -> [ConversationThread] {
        try JSONDecoder().decode([ConversationThread].self, from: Data(contentsOf: fileURL))
    }

    func testTheFileIsWrittenWithTheFirstUnlockClass() {
        XCTAssertEqual(ConversationStore.fileProtection, .completeUntilFirstUserAuthentication,
                       "glasses turns save with the phone locked; .complete refuses them")
        XCTAssertTrue(ConversationStore.writeOptions.contains(.completeFileProtectionUntilFirstUserAuthentication))
        XCTAssertTrue(ConversationStore.writeOptions.contains(.atomic))
        XCTAssertFalse(ConversationStore.writeOptions.contains(.completeFileProtection))
        XCTAssertEqual(SensitiveStore.conversationThreads.record.protection,
                       .completeUntilFirstUserAuthentication,
                       "the registry describes the class the store actually writes")
    }

    func testTheWriteCarriesTheFirstUnlockOptions() {
        let store = ConversationStore(directory: tempDir)
        let seen = OptionsBox()
        store.writeData = { data, url, options in
            seen.options = options
            try data.write(to: url, options: options)
        }
        store.startThread(mode: "direct")
        XCTAssertEqual(seen.options, ConversationStore.writeOptions)
    }

    private final class OptionsBox: @unchecked Sendable {
        var options: Data.WritingOptions?
    }

    func testAFailedSaveMarksTheStoreDirtyAndKeepsTheTurnInMemory() throws {
        let store = ConversationStore(directory: tempDir)
        store.writeData = Self.failingWriter

        let thread = store.startThread(mode: "direct")
        store.appendMessage(role: "user", content: "said with the phone in a pocket")

        XCTAssertTrue(store.needsSave, "a failed save must be remembered, not just logged")
        XCTAssertFalse(store.saveBlocked, "a write failure is not a read failure — no latch")
        XCTAssertEqual(store.threads.first?.id, thread.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testUnlockFlushesWhatTheLockedSavesMissed() throws {
        let store = ConversationStore(directory: tempDir)
        store.writeData = Self.failingWriter
        let thread = store.startThread(mode: "direct")
        store.appendMessage(role: "user", content: "first locked turn")
        store.appendMessage(role: "assistant", content: "second locked turn")
        XCTAssertTrue(store.needsSave)

        // The phone is unlocked: writes work again, and nothing else happens — no new turn.
        store.writeData = { data, url, options in try data.write(to: url, options: options) }
        store.protectedDataDidBecomeAvailable()

        XCTAssertFalse(store.needsSave)
        let persisted = try readThreadsFromDisk()
        XCTAssertEqual(persisted.map(\.id), [thread.id])
        XCTAssertEqual(persisted.first?.messages.count, 2, "both locked turns reached the file")
    }

    func testComingToTheFrontFlushesToo() throws {
        let store = ConversationStore(directory: tempDir)
        store.writeData = Self.failingWriter
        let thread = store.startThread(mode: "direct")
        XCTAssertTrue(store.needsSave)

        store.writeData = { data, url, options in try data.write(to: url, options: options) }
        store.flushPendingSave()

        XCTAssertFalse(store.needsSave)
        XCTAssertEqual(try readThreadsFromDisk().map(\.id), [thread.id])
    }

    func testAFlushWithNothingPendingDoesNotWrite() {
        let store = ConversationStore(directory: tempDir)
        store.startThread(mode: "direct")
        XCTAssertFalse(store.needsSave)

        let counter = WriteCounter()
        store.writeData = { data, url, options in
            counter.count += 1
            try data.write(to: url, options: options)
        }
        store.flushPendingSave()
        store.protectedDataDidBecomeAvailable()
        XCTAssertEqual(counter.count, 0, "a clean store has nothing to flush")
    }

    func testTheNextSuccessfulTurnAlsoClearsTheFlag() throws {
        let store = ConversationStore(directory: tempDir)
        store.writeData = Self.failingWriter
        store.startThread(mode: "direct")
        store.appendMessage(role: "user", content: "lost to the lock")
        XCTAssertTrue(store.needsSave)

        store.writeData = { data, url, options in try data.write(to: url, options: options) }
        store.appendMessage(role: "assistant", content: "written once unlocked")

        XCTAssertFalse(store.needsSave, "every save writes the whole list, so one success covers all")
        XCTAssertEqual(try readThreadsFromDisk().first?.messages.count, 2)
    }

    func testAFlushThatFailsAgainStaysDirty() {
        let store = ConversationStore(directory: tempDir)
        store.writeData = Self.failingWriter
        store.startThread(mode: "direct")

        store.flushPendingSave()
        XCTAssertTrue(store.needsSave, "still locked — keep it for the next chance")
    }
}
