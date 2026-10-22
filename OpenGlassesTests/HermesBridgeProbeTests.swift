import XCTest
@testable import OpenGlasses

/// Plan JP — the bridge's Test Connection. It used to report success when a ping was *sent*,
/// which URLSession allows before the socket is even open. Now it waits for the bridge's `welcome`
/// (or a `pong` on an open socket) and reads a failure from what the transport saw.
@MainActor
final class HermesBridgeProbeTests: XCTestCase {

    /// A socket whose behaviour is fixed up front: greet or not, answer pings or not, fail with a
    /// given error and leave given evidence behind.
    private final class ProbeSocket: HermesSocket, @unchecked Sendable {
        private let lock = NSLock()
        private var inbound: [String] = []
        private var waiters: [CheckedContinuation<HermesFrame, Error>] = []
        private var cancelled = false
        private var failure: Error?
        let evidence: HermesSocketDiagnostics
        let answersPing: Bool
        private var _sent: [String] = []
        var sent: [String] { lock.withLock { _sent } }

        init(greet: Bool, answersPing: Bool = true, failWith failure: Error? = nil,
             evidence: HermesSocketDiagnostics = HermesSocketDiagnostics()) {
            self.answersPing = answersPing
            self.failure = failure
            self.evidence = evidence
            if greet { inbound.append(#"{"type":"welcome"}"#) }
        }

        func diagnostics() -> HermesSocketDiagnostics { evidence }

        func send(_ text: String) async throws {
            lock.withLock { _sent.append(text) }
            if text.contains(#""ping""#), answersPing {
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 5_000_000)
                    self?.push(#"{"type":"pong"}"#)
                }
            }
        }

        private func push(_ text: String) {
            let waiter: CheckedContinuation<HermesFrame, Error>? = lock.withLock {
                if !waiters.isEmpty { return waiters.removeFirst() }
                inbound.append(text)
                return nil
            }
            waiter?.resume(returning: .text(text))
        }

        private enum Step {
            case frame(String)
            case fail(Error)
            case wait
        }

        func receive() async throws -> HermesFrame {
            let step: Step = lock.withLock {
                if cancelled { return .fail(CancellationError()) }
                if !inbound.isEmpty { return .frame(inbound.removeFirst()) }
                if let failure {
                    self.failure = nil
                    return .fail(failure)
                }
                return .wait
            }
            switch step {
            case .frame(let text): return .text(text)
            case .fail(let error): throw error
            case .wait:
                return try await withCheckedThrowingContinuation { continuation in
                    // Re-checked under the lock: a frame pushed since the first look must not be
                    // stranded in the queue with nobody waiting for it.
                    let ready: Step = lock.withLock {
                        if cancelled { return .fail(CancellationError()) }
                        if !inbound.isEmpty { return .frame(inbound.removeFirst()) }
                        waiters.append(continuation)
                        return .wait
                    }
                    switch ready {
                    case .frame(let text): continuation.resume(returning: .text(text))
                    case .fail(let error): continuation.resume(throwing: error)
                    case .wait: break
                    }
                }
            }
        }

        func cancel() {
            let pending: [CheckedContinuation<HermesFrame, Error>] = lock.withLock {
                cancelled = true
                defer { waiters.removeAll() }
                return waiters
            }
            pending.forEach { $0.resume(throwing: CancellationError()) }
        }
    }

    private var savedHost = ""
    private var savedPort = 0
    private var savedMode: (() -> MedicalEgressGuard.Mode)!

    override func setUp() {
        super.setUp()
        savedHost = Config.hermesBridgeHost
        savedPort = Config.hermesBridgePort
        savedMode = MedicalEgressGuard.currentMode
        MedicalEgressGuard.currentMode = { .off }
        Config.setHermesBridgeHost("192.168.1.9")
        Config.setHermesBridgePort(8765)
    }

    override func tearDown() {
        Config.setHermesBridgeHost(savedHost)
        Config.setHermesBridgePort(savedPort)
        MedicalEgressGuard.currentMode = savedMode
        super.tearDown()
    }

    func testAWelcomeIsSuccess() async {
        let bridge = HermesBridgeService(socketFactory: { _ in ProbeSocket(greet: true) })
        let diagnosis = await bridge.checkConnection(timeout: 2)
        XCTAssertEqual(diagnosis, .bridgeReady)
        XCTAssertEqual(bridge.status, .connected)
    }

    func testAnOpenSocketMustAnswerAPing() async {
        let socket = ProbeSocket(greet: true)
        let bridge = HermesBridgeService(socketFactory: { _ in socket })
        _ = await bridge.checkConnection(timeout: 2)
        let again = await bridge.checkConnection(timeout: 2)
        XCTAssertEqual(again, .bridgeReady)
        XCTAssertTrue(socket.sent.contains { $0.contains("ping") })
    }

    func testAnUnansweredPingIsNotSuccess() async {
        let socket = ProbeSocket(greet: true, answersPing: false)
        let bridge = HermesBridgeService(socketFactory: { _ in socket })
        _ = await bridge.checkConnection(timeout: 1)
        let again = await bridge.checkConnection(timeout: 0.3)
        XCTAssertEqual(again, .bridgeSilent)
    }

    /// The regression: a socket that never greets used to pass because the ping was queued.
    func testSilenceAfterTheUpgradeIsNoWelcome() async {
        let bridge = HermesBridgeService(socketFactory: { _ in
            ProbeSocket(greet: false, evidence: HermesSocketDiagnostics(httpStatus: 101))
        })
        let diagnosis = await bridge.checkConnection(timeout: 0.3)
        XCTAssertEqual(diagnosis, .noWelcome)
        XCTAssertFalse(diagnosis.isSuccess)
        XCTAssertEqual(bridge.status, .disconnected, "a failed probe leaves no half-open socket")
    }

    func testAPlainHTTPAnswerPointsAtTheAPIServer() async {
        let bridge = HermesBridgeService(socketFactory: { _ in
            ProbeSocket(greet: false, failWith: URLError(.badServerResponse),
                        evidence: HermesSocketDiagnostics(httpStatus: 404))
        })
        let diagnosis = await bridge.checkConnection(timeout: 2)
        XCTAssertEqual(diagnosis, .looksLikeAPIServer)
        XCTAssertEqual(diagnosis.suggestedKind, .apiServer)
    }

    func testCloseCode4401IsARefusedToken() async {
        let bridge = HermesBridgeService(socketFactory: { _ in
            ProbeSocket(greet: false, failWith: URLError(.networkConnectionLost),
                        evidence: HermesSocketDiagnostics(httpStatus: 101, closeCode: 4401))
        })
        let diagnosis = await bridge.checkConnection(timeout: 2)
        XCTAssertEqual(diagnosis, .bridgeRefusedToken)
    }

    func testARefusedConnectionIsUnreachable() async {
        let bridge = HermesBridgeService(socketFactory: { _ in
            ProbeSocket(greet: false, failWith: URLError(.cannotConnectToHost))
        })
        let diagnosis = await bridge.checkConnection(timeout: 2)
        XCTAssertEqual(diagnosis, .unreachable(.bridgeScript))
    }

    func testNoHostIsSaidBeforeDialling() async {
        Config.setHermesBridgeHost("")
        var dialled = false
        let bridge = HermesBridgeService(socketFactory: { _ in dialled = true; return ProbeSocket(greet: true) })
        let diagnosis = await bridge.checkConnection(timeout: 0.3)
        XCTAssertEqual(diagnosis, .noHost)
        XCTAssertFalse(dialled)
    }

    // MARK: - Token redaction (fold-in)

    func testTheConnectingDebugLineNeverCarriesTheToken() {
        let url = HermesBridgeProtocol.endpointURL(host: "192.168.1.9", port: 8765, token: "s3cret-token")!
        let shown = HermesBridgeProtocol.redactedForLog(url)
        XCTAssertFalse(shown.contains("s3cret-token"))
        XCTAssertEqual(shown, "ws://192.168.1.9:8765/?token=<redacted>")
        let plain = HermesBridgeProtocol.endpointURL(host: "192.168.1.9", port: 8765, token: nil)!
        XCTAssertEqual(HermesBridgeProtocol.redactedForLog(plain), "ws://192.168.1.9:8765/")
    }

    func testConnectLogsTheRedactedAddress() {
        let savedToken = Config.hermesBridgeToken
        Config.setHermesBridgeToken("s3cret-token")
        defer { Config.setHermesBridgeToken(savedToken) }
        let bridge = HermesBridgeService(socketFactory: { _ in ProbeSocket(greet: false) })
        var events: [String] = []
        bridge.onDebugEvent = { events.append($0) }
        bridge.connect()
        bridge.disconnect()
        XCTAssertTrue(events.contains { $0.contains("connecting to") })
        XCTAssertFalse(events.contains { $0.contains("s3cret-token") })
    }
}
