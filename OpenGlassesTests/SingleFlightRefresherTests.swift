import XCTest
@testable import OpenGlasses

/// Plan FG P1a — one token refresh at a time per credential. The token request is a closure here,
/// held at a gate until every caller under test has arrived, so "concurrent" is a fact the test
/// establishes rather than a timing it hopes for.
@MainActor
final class SingleFlightRefresherTests: XCTestCase {

    private let key = SingleFlightRefresher.Key(provider: "fixture")

    /// Holds the token request open until the test lets it finish.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    /// What reached `commit`, in order.
    private final class Commits {
        var outcomes: [Result<String, Error>] = []
        var values: [String] { outcomes.compactMap { try? $0.get() } }
        var failures: Int { outcomes.filter { if case .failure = $0 { return true } else { return false } }.count }
    }

    private struct FixtureFailure: Error {}

    /// Wait until `count` callers are queued on `key`, failing rather than hanging.
    private func waitForCallers(_ refresher: SingleFlightRefresher, _ count: Int,
                                key: SingleFlightRefresher.Key? = nil,
                                file: StaticString = #filePath, line: UInt = #line) async {
        let key = key ?? self.key
        for _ in 0..<500 {
            if await refresher.callers(for: key) >= count { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("only \(await refresher.callers(for: key)) of \(count) callers arrived", file: file, line: line)
    }

    func testTenConcurrentCallersCauseOneTokenRequest() async {
        let refresher = SingleFlightRefresher()
        let gate = Gate()
        let requests = Counter()
        let commits = Commits()

        let callers = (0..<10).map { _ in
            Task { () -> Bool in
                await refresher.refresh(
                    self.key,
                    fetch: { () async throws -> String in
                        await requests.increment()
                        await gate.wait()
                        return "fresh-token"
                    },
                    commit: { commits.outcomes.append($0) })
            }
        }
        await waitForCallers(refresher, 10)
        await gate.open()

        var results: [Bool] = []
        for caller in callers { results.append(await caller.value) }

        let tokenRequests = await requests.value
        XCTAssertEqual(tokenRequests, 1, "ten callers spent the refresh token more than once")
        XCTAssertEqual(results, Array(repeating: true, count: 10), "every caller sees the one outcome")
        XCTAssertEqual(commits.values, ["fresh-token"], "the outcome is committed once, not per caller")
        let waiting = await refresher.callers(for: key)
        XCTAssertEqual(waiting, 0, "the slot is released once the refresh ends")
    }

    func testASlotLostToSignOutDoesNotCommit() async {
        let refresher = SingleFlightRefresher()
        let gate = Gate()
        let commits = Commits()

        let refresh = Task {
            await refresher.refresh(
                self.key,
                fetch: { () async throws -> String in
                    await gate.wait()
                    return "token-for-the-old-account"
                },
                commit: { commits.outcomes.append($0) })
        }
        await waitForCallers(refresher, 1)
        refresher.invalidate(key)   // the wearer signs out while the request is in flight
        await gate.open()

        let committed = await refresh.value
        XCTAssertFalse(committed)
        XCTAssertTrue(commits.outcomes.isEmpty, "a stale refresh wrote over a sign-out")
    }

    func testAFailureAfterSignOutIsNotCommittedEither() async {
        let refresher = SingleFlightRefresher()
        let gate = Gate()
        let commits = Commits()

        let refresh = Task {
            await refresher.refresh(
                self.key,
                fetch: { () async throws -> String in
                    await gate.wait()
                    throw FixtureFailure()
                },
                commit: { commits.outcomes.append($0) })
        }
        await waitForCallers(refresher, 1)
        refresher.invalidate(key)   // a new sign-in replaced the account; its failure is not ours
        await gate.open()

        let committed = await refresh.value
        XCTAssertFalse(committed)
        XCTAssertTrue(commits.outcomes.isEmpty, "a stale failure could discard the new sign-in")
    }

    func testAFailedRefreshReleasesTheSlot() async {
        let refresher = SingleFlightRefresher()
        let requests = Counter()
        let commits = Commits()

        let first = await refresher.refresh(
            key,
            fetch: { () async throws -> String in
                await requests.increment()
                throw FixtureFailure()
            },
            commit: { commits.outcomes.append($0) })
        XCTAssertTrue(first, "a failure is committed so its owner can classify it")
        XCTAssertEqual(commits.failures, 1)
        let waiting = await refresher.callers(for: key)
        XCTAssertEqual(waiting, 0)

        let second = await refresher.refresh(
            key,
            fetch: { () async throws -> String in
                await requests.increment()
                return "fresh-token"
            },
            commit: { commits.outcomes.append($0) })
        XCTAssertTrue(second)
        let tokenRequests = await requests.value
        XCTAssertEqual(tokenRequests, 2, "the next caller after a failure starts its own attempt")
        XCTAssertEqual(commits.values, ["fresh-token"])
    }

    func testACallerAfterInvalidationStartsAFreshRefresh() async {
        let refresher = SingleFlightRefresher()
        let oldGate = Gate()
        let requests = Counter()
        let commits = Commits()

        let stale = Task {
            await refresher.refresh(
                self.key,
                fetch: { () async throws -> String in
                    await requests.increment()
                    await oldGate.wait()
                    return "stale-token"
                },
                commit: { commits.outcomes.append($0) })
        }
        await waitForCallers(refresher, 1)
        refresher.invalidate(key)

        // A caller for the new sign-in does not join the stale request.
        let fresh = await refresher.refresh(
            key,
            fetch: { () async throws -> String in
                await requests.increment()
                return "new-account-token"
            },
            commit: { commits.outcomes.append($0) })
        await oldGate.open()
        let staleCommitted = await stale.value

        XCTAssertTrue(fresh)
        XCTAssertFalse(staleCommitted)
        let tokenRequests = await requests.value
        XCTAssertEqual(tokenRequests, 2)
        XCTAssertEqual(commits.values, ["new-account-token"])
    }

    func testDifferentKeysDoNotShareASlot() async {
        let refresher = SingleFlightRefresher()
        let gate = Gate()
        let requests = Counter()
        // Plan FG P1 keys by account too: two accounts at one provider refresh independently.
        let first = SingleFlightRefresher.Key(provider: "fixture", account: "account-a")
        let second = SingleFlightRefresher.Key(provider: "fixture", account: "account-b")

        let tasks = [first, second].map { key in
            Task {
                await refresher.refresh(
                    key,
                    fetch: { () async throws -> String in
                        await requests.increment()
                        await gate.wait()
                        return "token"
                    },
                    commit: { _ in })
            }
        }
        await waitForCallers(refresher, 1, key: first)
        await waitForCallers(refresher, 1, key: second)
        await gate.open()
        for task in tasks { _ = await task.value }

        let tokenRequests = await requests.value
        XCTAssertEqual(tokenRequests, 2)
    }
}
