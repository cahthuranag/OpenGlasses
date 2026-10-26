import CryptoKit
import Foundation
import Security

/// The raw storage under the new-manual allowance (Plan JK §8): a per-subscription secret in the
/// iCloud Keychain, the history in iCloud key-value storage, and a local keychain copy that
/// survives a reinstall and works without iCloud. A seam, so tests never touch the live keychain
/// or key-value store: `InMemoryManualAdditionBackend` stands in for both.
protocol ManualAdditionHistoryBackend: AnyObject, Sendable {
    /// The fingerprint secret for one subscription, or nil when none was made yet. Throws when it
    /// cannot be read now (a locked phone): the caller refuses additions rather than make another.
    func secret(account: String) throws -> Data?
    /// Adds the secret; throws `ManualAdditionHistoryStore.Failure.duplicate` when another device
    /// already synced one in, so the caller re-reads instead of overwriting it.
    func addSecret(_ data: Data, account: String) throws
    /// The local copy (records and this device's holdings); nil when absent.
    func local() throws -> Data?
    func storeLocal(_ data: Data) throws
    /// The iCloud copy; nil when absent or iCloud is unavailable (never a reason to refuse).
    func cloud() -> Data?
    func storeCloud(_ data: Data)
    /// Deletes the secrets, both copies of the history and the holdings.
    func eraseAll() throws
}

/// Owns the keychain/iCloud pair and the merge. Every read unions the two copies by
/// `(fingerprint, addedAt)` and writes the union back to whichever copy was missing records, so a
/// smaller set never overwrites a larger one and a local-only history joins iCloud on sign-in.
final class ManualAdditionHistoryStore: @unchecked Sendable {
    enum Failure: Error, Equatable { case unavailable, duplicate }

    /// What this device holds that the allowance may still need: the fingerprint of each manual
    /// added here in the undo window, so a read or a removal can find its record without hashing
    /// the file again. Local only — never synced, and pruned once the undo window has passed.
    struct Holding: Codable, Equatable, Sendable {
        let fingerprint: String
        let addedAtMillis: Int64
        enum CodingKeys: String, CodingKey { case fingerprint = "f", addedAtMillis = "t" }
    }

    struct LocalCopy: Codable, Equatable, Sendable {
        var records: [String: [ManualAdditionRecord]] = [:]
        var holdings: [String: [String: Holding]] = [:]
    }

    /// The spend a successful install records. Built under the admission lock before the commit;
    /// a cancelled or failed install drops it unrecorded.
    struct Pending: Sendable {
        let subscription: String
        let records: [ManualAdditionRecord]
        let holdings: [String: Holding]
    }

    static let secretPrefix = "secret."

    private let backend: ManualAdditionHistoryBackend
    private let subscriptionKey: @Sendable () -> String
    private let lock = NSRecursiveLock()
    /// The last merged state. Kept so a write that failed (a locked phone) is retried on the next
    /// write and so this process never forgets a spend it made, and so a read mark is cheap.
    private var cached: LocalCopy?
    private var dirty = false

    /// False only for the unit-test host's default store, so suites that install manuals for
    /// other reasons are not limited by each other's additions. Allowance tests inject an
    /// enforcing in-memory store.
    let enforced: Bool

    init(backend: ManualAdditionHistoryBackend, enforced: Bool = true,
         subscriptionKey: @escaping @Sendable () -> String = { VerifiedStorePurchaseRecorder.shared.personalSubscriptionKey }) {
        self.backend = backend
        self.enforced = enforced
        self.subscriptionKey = subscriptionKey
    }

    var subscription: String { subscriptionKey() }

    // MARK: - Reading

    /// The merged history for the current subscription; nil when it cannot be read (fail closed).
    func history() -> [ManualAdditionRecord]? {
        lock.lock(); defer { lock.unlock() }
        return (try? load()).map { $0.records[subscription] ?? [] }
    }

    func status(limits: ManualLimits?, now: Date) -> ManualAdditionAllowance.Status? {
        guard let allowance = limits?.additions, let history = history() else { return nil }
        return ManualAdditionAllowance.status(allowance, history: history, now: now)
    }

    /// Union both copies, write back what either lacks, and cache the result.
    @discardableResult
    func load() throws -> LocalCopy {
        lock.lock(); defer { lock.unlock() }
        let localData: Data?
        do { localData = try backend.local() } catch { throw Failure.unavailable }
        var local = LocalCopy()
        if let localData {
            // An unreadable local copy is an unreadable history: additions refuse, never reset it.
            guard let decoded = try? JSONDecoder().decode(LocalCopy.self, from: localData) else { throw Failure.unavailable }
            local = decoded
        }
        // iCloud is advisory: a missing or damaged copy there never refuses and never shrinks.
        let cloud = backend.cloud().flatMap { try? JSONDecoder().decode([String: [ManualAdditionRecord]].self, from: $0) } ?? [:]
        var merged = local
        if let cached {
            for (sub, records) in cached.records { merged.records[sub] = ManualAdditionAllowance.merge(merged.records[sub] ?? [], records) }
            for (sub, holdings) in cached.holdings { merged.holdings[sub, default: [:]].merge(holdings) { old, _ in old } }
        }
        for (sub, records) in cloud { merged.records[sub] = ManualAdditionAllowance.merge(merged.records[sub] ?? [], records) }
        let cloudLacks = merged.records.contains { sub, records in Set(cloud[sub] ?? []) != Set(records) }
        cached = merged
        if merged != local || dirty { persistLocal(merged) }
        if cloudLacks { persistCloud(merged) }
        return merged
    }

    // MARK: - Fingerprints

    /// HMAC-SHA256 of the file's bytes under the subscription's secret, streamed in 1 MiB pieces.
    func fingerprint(of url: URL) throws -> String {
        let key = try secretKey(create: true)
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.unavailable }
        defer { try? handle.close() }
        var hmac = HMAC<SHA256>(key: key)
        while true {
            let chunk: Data
            do { chunk = try handle.read(upToCount: 1 << 20) ?? Data() } catch { throw Failure.unavailable }
            if chunk.isEmpty { break }
            hmac.update(data: chunk)
        }
        return Data(hmac.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    private func secretKey(create: Bool) throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        let account = Self.secretPrefix + subscription
        let existing: Data?
        do { existing = try backend.secret(account: account) } catch { throw Failure.unavailable }
        if let existing, existing.count == 32 { return SymmetricKey(data: existing) }
        guard existing == nil, create else { throw Failure.unavailable }
        let fresh = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        do { try backend.addSecret(fresh, account: account) }
        catch Failure.duplicate {
            // Another device's secret arrived first; use it so both derive the same fingerprints.
            guard let synced = try? backend.secret(account: account), synced.count == 32 else { throw Failure.unavailable }
            return SymmetricKey(data: synced)
        } catch { throw Failure.unavailable }
        return SymmetricKey(data: fresh)
    }

    // MARK: - Writing

    /// Decide an install's additions. `documents` are the documents new to the shelf by identity,
    /// with the original file each is fingerprinted from. Throws the refusal copy when it does not
    /// fit; returns the spend to record once the install commits.
    func prepare(documents: [(identity: String, original: URL)], limits: ManualLimits?, now: Date) throws -> Pending? {
        guard enforced, limits?.additions != nil, !documents.isEmpty else { return nil }
        // Hashed outside this store's lock, so a read mark on the main actor never waits on a
        // large file. The admission lock (held by the caller) still serialises additions.
        let fingerprints: [String]
        do { fingerprints = try documents.map { try fingerprint(of: $0.original) } }
        catch { throw ManualLibraryAdmission.Failure.refused(ManualAdditionAllowance.refusal(.unavailable, limits: limits)!) }
        lock.lock(); defer { lock.unlock() }
        let decision = ManualAdditionAllowance.decide(limits: limits, history: history(), proposed: fingerprints, now: now)
        guard let records = decision.spending else {
            throw ManualLibraryAdmission.Failure.refused(ManualAdditionAllowance.refusal(decision, limits: limits)!)
        }
        let millis = ManualAdditionRecord(fingerprint: "-", addedAt: now, spent: false).addedAtMillis
        var holdings: [String: Holding] = [:]
        for (document, print) in zip(documents, fingerprints) { holdings[document.identity] = .init(fingerprint: print, addedAtMillis: millis) }
        return Pending(subscription: subscription, records: records, holdings: holdings)
    }

    /// The capture doors: a photographed manual is new by construction, so check room for one.
    func checkNewManual(limits: ManualLimits?, now: Date) throws {
        guard enforced, limits?.additions != nil else { return }
        let decision = ManualAdditionAllowance.decide(limits: limits, history: history(),
                                                      proposed: ["pending:" + UUID().uuidString], now: now)
        if let refusal = ManualAdditionAllowance.refusal(decision, limits: limits) {
            throw ManualLibraryAdmission.Failure.refused(refusal)
        }
    }

    /// Record a committed install's spend. Never throws: the manual is already installed, and a
    /// write that cannot land now stays in this process's cache and is retried on the next write.
    func commit(_ pending: Pending, undoWindow: TimeInterval, now: Date) {
        lock.lock(); defer { lock.unlock() }
        var copy = (try? load()) ?? cached ?? LocalCopy()
        copy.records[pending.subscription] = ManualAdditionAllowance.merge(copy.records[pending.subscription] ?? [], pending.records)
        copy.holdings[pending.subscription, default: [:]].merge(pending.holdings) { _, new in new }
        prune(&copy, undoWindow: undoWindow, now: now)
        save(copy)
    }

    /// A read from one of these manuals ends its undo. Cheap when nothing is in the undo window.
    func noteRead(identities: [String], limits: ManualLimits?, now: Date) {
        guard limits?.additions != nil, !identities.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let sub = subscription
        guard let snapshot = cached ?? (try? load()),
              let held = snapshot.holdings[sub], identities.contains(where: { held[$0] != nil }) else { return }
        var copy = snapshot
        var records = copy.records[sub] ?? []
        var changed = false
        for identity in identities {
            guard let holding = held[identity] else { continue }
            let marks = Set(ManualAdditionAllowance.readMarks(limits: limits, history: records, fingerprint: holding.fingerprint, now: now))
            guard !marks.isEmpty else { continue }
            records = records.map { record in
                var record = record
                if marks.contains(record.key) { record.read = true }
                return record
            }
            changed = true
        }
        guard changed else { return }
        copy.records[sub] = records
        save(copy)
    }

    /// A removal: give the addition back when the undo rule allows it. Never blocks the removal.
    @discardableResult
    func noteRemoved(identity: String, limits: ManualLimits?, now: Date) -> Bool {
        guard let allowance = limits?.additions else { return false }
        lock.lock(); defer { lock.unlock() }
        let sub = subscription
        guard var copy = (try? load()) ?? cached, let holding = copy.holdings[sub]?[identity] else { return false }
        copy.holdings[sub]?[identity] = nil
        var refunded = false
        // The same file still on this shelf under another identity is still held: nothing to give back.
        let stillHeld = copy.holdings[sub]?.values.contains { $0.fingerprint == holding.fingerprint } == true
        if !stillHeld, let key = ManualAdditionAllowance.refund(limits: limits, history: copy.records[sub] ?? [],
                                                                fingerprint: holding.fingerprint, now: now) {
            copy.records[sub] = (copy.records[sub] ?? []).map { record in
                var record = record
                if record.key == key { record.refunded = true }
                return record
            }
            refunded = true
        }
        prune(&copy, undoWindow: allowance.undoWindow, now: now)
        save(copy)
        return refunded
    }

    /// Plan JK §8 erasure, pending the privacy review: deletes the secrets, the fingerprints and
    /// the dates in both copies. TODO(privacy review): whether in-window dates (no content,
    /// self-expiring after 30 days) may be kept until they expire, so that an erasure does not
    /// also reset the allowance, is an open owner decision. Today everything goes.
    func eraseAll() throws {
        lock.lock(); defer { lock.unlock() }
        cached = nil
        dirty = false
        do { try backend.eraseAll() } catch { throw Failure.unavailable }
    }

    // MARK: - Internals

    private func prune(_ copy: inout LocalCopy, undoWindow: TimeInterval, now: Date) {
        let cutoff = Int64((now.timeIntervalSince1970 - undoWindow) * 1000)
        for sub in copy.holdings.keys {
            copy.holdings[sub] = copy.holdings[sub]?.filter { $0.value.addedAtMillis > cutoff }
        }
    }

    private func save(_ copy: LocalCopy) {
        cached = copy
        persistLocal(copy)
        persistCloud(copy)
    }

    private func persistLocal(_ copy: LocalCopy) {
        guard let data = try? JSONEncoder().encode(copy) else { dirty = true; return }
        do { try backend.storeLocal(data); dirty = false } catch { dirty = true }
    }

    private func persistCloud(_ copy: LocalCopy) {
        // Holdings never leave the phone: only fingerprints, dates and flags sync.
        guard let data = try? JSONEncoder().encode(copy.records) else { return }
        backend.storeCloud(data)
    }
}

// MARK: - Backends

/// Tests and the unit-test host. Holds everything in memory; `cloudAvailable` and `localReadable`
/// model a device without iCloud and a locked phone.
final class InMemoryManualAdditionBackend: ManualAdditionHistoryBackend, @unchecked Sendable {
    private let lock = NSLock()
    var secrets: [String: Data] = [:]
    var localData: Data?
    var cloudData: Data?
    var cloudAvailable = true
    var localReadable = true

    init() {}

    func secret(account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard localReadable else { throw ManualAdditionHistoryStore.Failure.unavailable }
        return secrets[account]
    }
    func addSecret(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard localReadable else { throw ManualAdditionHistoryStore.Failure.unavailable }
        guard secrets[account] == nil else { throw ManualAdditionHistoryStore.Failure.duplicate }
        secrets[account] = data
    }
    func local() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard localReadable else { throw ManualAdditionHistoryStore.Failure.unavailable }
        return localData
    }
    func storeLocal(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard localReadable else { throw ManualAdditionHistoryStore.Failure.unavailable }
        localData = data
    }
    func cloud() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return cloudAvailable ? cloudData : nil
    }
    func storeCloud(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if cloudAvailable { cloudData = data }
    }
    func eraseAll() throws {
        lock.lock(); defer { lock.unlock() }
        secrets = [:]; localData = nil; cloudData = nil
    }
}

/// The device: the secret is a synchronizable keychain item (iCloud Keychain, end-to-end
/// encrypted), the local copy a this-device-only keychain item (survives a reinstall), and the
/// shared copy an `NSUbiquitousKeyValueStore` value. Without the key-value entitlement or an iCloud
/// account the store is local-only and the keychain copy carries the history alone.
final class LiveManualAdditionBackend: ManualAdditionHistoryBackend, @unchecked Sendable {
    /// Storage keys, not product names. Never change them: the history is found by them.
    static let keychainService = "OpenGlasses.MyManualsAdditions"
    static let localAccount = "history"
    static let cloudKey = "myManuals.additions"

    private var observer: NSObjectProtocol?
    private let lock = NSLock()
    private var externalChange: (@Sendable () -> Void)?

    /// Runs when another device's history arrives through iCloud; the store merges it in.
    var onExternalChange: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return externalChange }
        set { lock.lock(); externalChange = newValue; lock.unlock() }
    }

    init() {
        let store = NSUbiquitousKeyValueStore.default
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: nil) { [weak self] _ in
            self?.onExternalChange?()
        }
        store.synchronize()
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func base(_ account: String, synchronizable: Bool) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.keychainService,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: synchronizable]
    }

    private func read(_ account: String, synchronizable: Bool) throws -> Data? {
        var query = base(account, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default:
            PrivacyLog.keychainFailed(.read, status: Int(status))
            throw ManualAdditionHistoryStore.Failure.unavailable
        }
    }

    func secret(account: String) throws -> Data? { try read(account, synchronizable: true) }

    func addSecret(_ data: Data, account: String) throws {
        var query = base(account, synchronizable: true)
        query[kSecValueData as String] = data
        // Synchronizable items cannot be this-device-only; readable after the first unlock so a
        // locked-phone answer path never needs it (only additions do).
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem { throw ManualAdditionHistoryStore.Failure.duplicate }
        guard status == errSecSuccess else {
            PrivacyLog.keychainFailed(.write, status: Int(status))
            throw ManualAdditionHistoryStore.Failure.unavailable
        }
    }

    func local() throws -> Data? { try read(Self.localAccount, synchronizable: false) }

    func storeLocal(_ data: Data) throws {
        let lookup = base(Self.localAccount, synchronizable: false)
        let changes: [String: Any] = [kSecValueData as String: data,
                                      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(lookup as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(lookup.merging(changes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            PrivacyLog.keychainFailed(.write, status: Int(status))
            throw ManualAdditionHistoryStore.Failure.unavailable
        }
    }

    func cloud() -> Data? { NSUbiquitousKeyValueStore.default.data(forKey: Self.cloudKey) }

    func storeCloud(_ data: Data) {
        NSUbiquitousKeyValueStore.default.set(data, forKey: Self.cloudKey)
    }

    func eraseAll() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.keychainService,
                                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
        let status = SecItemDelete(query as CFDictionary)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: Self.cloudKey)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            PrivacyLog.keychainFailed(.write, status: Int(status))
            throw ManualAdditionHistoryStore.Failure.unavailable
        }
    }
}
