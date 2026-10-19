import Foundation
import os

/// One token refresh at a time per credential (Plan FG P1a).
///
/// The subscription sign-ins rotate their refresh token: each refresh spends the old one and
/// hands back a new one. Two callers that both found the access token near expiry used to refresh
/// independently, so the second spent a refresh token the first had already used, got
/// `invalid_grant`, and the wearer was signed out by their own app. Here the first caller for a
/// key starts the refresh and every caller that arrives while it runs awaits that same task.
///
/// **Ownership.** A refresh's outcome is committed only while its task still owns the slot. A
/// sign-out or a new sign-in calls `invalidate(_:)`, synchronously on the main actor, and from
/// then on the refresh that was running is stale: its result is dropped rather than written over
/// the credential that replaced it (or over the absence of one). The check and the commit run in
/// one main-actor turn, so nothing can sign out between them.
///
/// **Release.** The slot is released when the task ends, success or failure, after the commit and
/// before any caller sees the result, so the next caller after a failed refresh starts a fresh
/// attempt instead of inheriting the failure, and no caller can start a second refresh with a
/// refresh token the first has just spent but not yet replaced.
///
/// Plan FG P1 reuses this actor for its enterprise connections, keyed by issuer, account, client
/// and resource as well as provider.
actor SingleFlightRefresher {
    static let shared = SingleFlightRefresher()

    /// Which credential a refresh belongs to. The subscription sign-ins key by provider alone;
    /// FG P1's connections add the rest, so two connections to one provider never share a slot.
    struct Key: Hashable, Sendable {
        let provider: String
        var issuer: String?
        var account: String?
        var client: String?
        var resource: String?

        init(provider: String, issuer: String? = nil, account: String? = nil,
             client: String? = nil, resource: String? = nil) {
            self.provider = provider
            self.issuer = issuer
            self.account = account
            self.client = client
            self.resource = resource
        }
    }

    private struct Slot {
        let ticket: UInt64
        /// The key's epoch when this refresh started. A later `invalidate` moves the key past it.
        let epoch: UInt64
        let task: Task<Bool, Never>
        /// Callers waiting on this refresh, the one that started it included.
        var callers: Int
    }

    private var slots: [Key: Slot] = [:]
    private var nextTicket: UInt64 = 0

    /// Per-key epochs, behind a lock rather than the actor so `invalidate` can be synchronous: a
    /// sign-out must take effect before its own line returns, not at the actor's next turn.
    private nonisolated let epochs = OSAllocatedUnfairLock<[Key: UInt64]>(initialState: [:])

    init() {}

    /// End every refresh running for `key`: its outcome will not be committed, and the next
    /// caller starts a new one. Call it on sign-out and before storing a new sign-in.
    nonisolated func invalidate(_ key: Key) {
        epochs.withLock { $0[key, default: 0] &+= 1 }
    }

    private nonisolated func epoch(of key: Key) -> UInt64 {
        epochs.withLock { $0[key, default: 0] }
    }

    /// Refresh `key`'s credential, or wait for the refresh already running for it.
    ///
    /// The caller that starts the refresh supplies `fetch` (the token request) and `commit` (what
    /// to do with the outcome, success or failure, on the main actor). A caller that joins a
    /// running refresh has its own closures ignored: it gets the same outcome as the first.
    ///
    /// Returns whether the outcome was committed — `false` when the slot was lost to a sign-out or
    /// a newer sign-in while the request was in flight. A failure is delivered to `commit`, not
    /// thrown: the owner of the credential decides what a failure means for it.
    @discardableResult
    func refresh<Value: Sendable>(_ key: Key,
                                  fetch: @escaping @Sendable () async throws -> Value,
                                  commit: @escaping @MainActor @Sendable (Result<Value, Error>) -> Void) async -> Bool {
        let current = epoch(of: key)
        if var slot = slots[key], slot.epoch == current {
            slot.callers += 1
            slots[key] = slot
            return await slot.task.value
        }

        nextTicket &+= 1
        let ticket = nextTicket
        let task = Task<Bool, Never> {
            let outcome: Result<Value, Error>
            do {
                outcome = .success(try await fetch())
            } catch {
                outcome = .failure(error)
            }
            let committed = await MainActor.run { () -> Bool in
                guard self.epoch(of: key) == current else { return false }
                commit(outcome)
                return true
            }
            self.release(key, ticket: ticket)
            return committed
        }
        slots[key] = Slot(ticket: ticket, epoch: current, task: task, callers: 1)
        return await task.value
    }

    /// Drop the slot if it is still this task's — a refresh started after an `invalidate` may
    /// have replaced it already, and that one is not ours to release.
    private func release(_ key: Key, ticket: UInt64) {
        if slots[key]?.ticket == ticket { slots[key] = nil }
    }

    /// How many callers are waiting on `key`'s refresh, 0 when none is running. Read by the tests
    /// to know every concurrent caller has joined before the token request is allowed to finish.
    func callers(for key: Key) -> Int {
        slots[key]?.callers ?? 0
    }
}
