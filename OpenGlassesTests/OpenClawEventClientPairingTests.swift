import XCTest
@testable import OpenGlasses

/// Plan AR: drives `OpenClawEventClient` over a scripted socket to prove a device token is stored
/// only inside a pairing the wearer started (for `device.paired`), or from the reply to our own
/// connect request — whatever else the server sends.
final class OpenClawEventClientPairingTests: XCTestCase {

    private var priorAgentMode = false
    private var priorGateways: [GatewayConfig] = []
    private var sink: PrivacyLineSink!
    private var tap: PrivacyLog.TapToken?

    override func setUp() {
        super.setUp()
        priorAgentMode = Config.agentModeEnabled
        priorGateways = Config.savedGateways
        Config.setAgentModeEnabled(true)
        Config.setSavedGateways([])
        sink = PrivacyLineSink()
        let sink = sink!
        tap = PrivacyLog.addTap { _, line in sink.record(line) }
    }

    override func tearDown() {
        if let tap { PrivacyLog.removeTap(tap) }
        Config.setAgentModeEnabled(priorAgentMode)
        Config.setSavedGateways(priorGateways)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func savedGateway(id: String, token: String = "", deviceToken: String? = nil,
                              priority: Int = 0) -> GatewayConfig {
        var gateway = GatewayConfig.newGateway(provider: .openclaw, priority: priority)
        gateway.id = id
        gateway.lanHost = "127.0.0.1"
        gateway.connectionMode = OpenClawConnectionMode.lan.rawValue
        gateway.token = token
        gateway.deviceToken = deviceToken
        return gateway
    }

    private func stored(_ id: String) -> GatewayConfig? {
        Config.savedGateways.first { $0.id == id }
    }

    private var setupCode: String {
        SetupCode.encode(SetupCodePayload(url: "http://127.0.0.1:18789", bootstrapToken: "boot-1"))
    }

    private func devicePaired(_ token: String) -> [String: Any] {
        ["type": "event", "event": "device.paired", "payload": ["token": token]]
    }

    /// A fresh scripted socket per connection, each opening with a challenge. `reply` answers the
    /// connect request (nil: withheld).
    private final class Sockets {
        private let lock = NSLock()
        private var made: [ScriptedGatewaySocket] = []
        var reply: ((String) -> [[String: Any]])?

        func make() -> ScriptedGatewaySocket {
            let socket = ScriptedGatewaySocket(initialFrames: [GatewayScript.challenge])
            socket.onRequest = { [weak self] frame in
                guard (frame["method"] as? String) == "connect", let id = frame["id"] as? String else { return [] }
                return self?.reply?(id) ?? []
            }
            lock.lock(); made.append(socket); lock.unlock()
            return socket
        }

        var last: ScriptedGatewaySocket? { lock.lock(); defer { lock.unlock() }; return made.last }
        var count: Int { lock.lock(); defer { lock.unlock() }; return made.count }
    }

    /// Statuses reported off the test's thread.
    private final class StatusLog {
        private let lock = NSLock()
        private var statuses: [PairingStatus] = []
        func record(_ status: PairingStatus) { lock.lock(); statuses.append(status); lock.unlock() }
        var seen: [PairingStatus] { lock.lock(); defer { lock.unlock() }; return statuses }
    }

    /// A clock the test moves by hand.
    private final class Clock {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 5,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "timed out waiting for \(description)")
    }

    private func ignoredCount() -> Int { sink.lines.filter { $0.contains("pairingTokenIgnored") }.count }

    // MARK: - Outside a pairing

    func testUnsolicitedDevicePairedWhileIdleIsIgnored() async throws {
        Config.setSavedGateways([savedGateway(id: "gw", token: "shared-token")])
        let sockets = Sockets()
        sockets.reply = { [GatewayScript.helloOk(replyTo: $0, methods: [])] }
        let client = OpenClawEventClient(socketFactory: { _ in sockets.make() })
        let paired = expectation(description: "connected")
        paired.assertForOverFulfill = false
        client.onPairingStatusChange = { if $0 == .paired { paired.fulfill() } }

        client.connect()
        await fulfillment(of: [paired], timeout: 2)

        sockets.last?.push(devicePaired("planted"))
        await waitUntil("the planted token to be turned away") { ignoredCount() == 1 }
        XCTAssertTrue(sink.contains("noBootstrap"))
        XCTAssertNil(stored("gw")?.deviceToken, "an unsolicited token must never be stored")
        XCTAssertFalse(sink.lines.joined().contains("planted"), "the token must never be logged")
        client.disconnect()
    }

    func testUnsolicitedDevicePairedWhenAlreadyPairedKeepsTheRealToken() async throws {
        Config.setSavedGateways([savedGateway(id: "gw", deviceToken: "real-token")])
        let sockets = Sockets()
        sockets.reply = { [GatewayScript.helloOk(replyTo: $0, methods: [])] }
        let client = OpenClawEventClient(socketFactory: { _ in sockets.make() })
        let paired = expectation(description: "connected")
        paired.assertForOverFulfill = false
        client.onPairingStatusChange = { if $0 == .paired { paired.fulfill() } }

        client.connect()
        await fulfillment(of: [paired], timeout: 2)
        let connect = try XCTUnwrap(sockets.last?.sentRequests(method: "connect").first)
        let auth = (connect["params"] as? [String: Any])?["auth"] as? [String: Any]
        XCTAssertEqual(auth?["token"] as? String, "real-token")

        sockets.last?.push(devicePaired("planted"))
        await waitUntil("the planted token to be turned away") { ignoredCount() == 1 }
        XCTAssertEqual(stored("gw")?.deviceToken, "real-token")
        client.disconnect()
    }

    func testResponseThatDoesNotAnswerOurConnectIsDropped() async throws {
        Config.setSavedGateways([savedGateway(id: "gw", token: "shared-token")])
        let sockets = Sockets()
        let client = OpenClawEventClient(socketFactory: { _ in sockets.make() })
        let statuses = StatusLog()
        client.onPairingStatusChange = { statuses.record($0) }

        client.connect()
        await waitUntil("the handshake to go out") { sockets.last?.sentRequests(method: "connect").isEmpty == false }
        sockets.last?.push(["type": "res", "id": "not-our-connect", "ok": true, "result": ["token": "planted"]])
        await waitUntil("the stray reply to be dropped") { sink.contains("responseUncorrelated") }
        XCTAssertNil(stored("gw")?.deviceToken)
        XCTAssertFalse(statuses.seen.contains(.paired),
                       "a stray reply must not authenticate the socket: \(statuses.seen)")

        let paired = expectation(description: "connected")
        client.onPairingStatusChange = { if $0 == .paired { paired.fulfill() } }
        let connectId = try XCTUnwrap(sockets.last?.sentRequests(method: "connect").first?["id"] as? String)
        sockets.last?.push(GatewayScript.helloOk(replyTo: connectId, methods: []))
        await fulfillment(of: [paired], timeout: 2)
        client.disconnect()
    }

    // MARK: - Inside a pairing the wearer started

    func testWearerStartedPairingStoresTheFirstTokenOnly() async throws {
        // A gateway being paired for the first time has no credential, so it is not "configured".
        Config.setSavedGateways([savedGateway(id: "new")])
        let sockets = Sockets()
        let client = OpenClawEventClient(socketFactory: { _ in sockets.make() })
        let paired = expectation(description: "paired")
        client.onPairingStatusChange = { if $0 == .paired { paired.fulfill() } }

        client.startPairing(gatewayId: "new", setupCode: setupCode)
        XCTAssertEqual(client.pairingGatewayId, "new")
        await waitUntil("the handshake to go out") { sockets.last?.sentRequests(method: "connect").isEmpty == false }
        let connect = try XCTUnwrap(sockets.last?.sentRequests(method: "connect").first)
        let auth = (connect["params"] as? [String: Any])?["auth"] as? [String: Any]
        XCTAssertEqual(auth?["token"] as? String, "boot-1", "the handshake presents the bootstrap token")

        sockets.last?.push(devicePaired("device-1"))
        await fulfillment(of: [paired], timeout: 2)
        XCTAssertEqual(stored("new")?.deviceToken, "device-1")
        XCTAssertNil(stored("new")?.setupCode, "the one-time code is dropped once a token lands")
        XCTAssertNil(client.pairingGatewayId)
        XCTAssertEqual(client.lastPairingEnd, .paired)

        sockets.last?.push(devicePaired("device-2"))
        await waitUntil("the second token to be turned away") { ignoredCount() == 1 }
        XCTAssertEqual(stored("new")?.deviceToken, "device-1")
        client.disconnect()
    }

    func testHelloOkTokenCompletesAWearerStartedPairing() async throws {
        Config.setSavedGateways([savedGateway(id: "new")])
        let sockets = Sockets()
        sockets.reply = { [GatewayScript.helloOk(replyTo: $0, methods: [], deviceToken: "from-hello")] }
        let client = OpenClawEventClient(socketFactory: { _ in sockets.make() })
        let paired = expectation(description: "paired")
        client.onPairingStatusChange = { if $0 == .paired { paired.fulfill() } }

        client.startPairing(gatewayId: "new", setupCode: setupCode)
        await fulfillment(of: [paired], timeout: 2)
        XCTAssertEqual(stored("new")?.deviceToken, "from-hello")
        XCTAssertEqual(client.lastPairingEnd, .paired)
        XCTAssertNil(client.pairingGatewayId)
        client.disconnect()
    }

    func testTokenAfterThePairingTimedOutIsIgnored() async throws {
        Config.setSavedGateways([savedGateway(id: "new")])
        let sockets = Sockets()
        let clock = Clock()
        let client = OpenClawEventClient(socketFactory: { _ in sockets.make() },
                                         clock: { clock.now }, bootstrapWindow: 60)

        client.startPairing(gatewayId: "new", setupCode: setupCode)
        await waitUntil("the handshake to go out") { sockets.last?.sentRequests(method: "connect").isEmpty == false }
        clock.advance(61)

        sockets.last?.push(devicePaired("late"))
        await waitUntil("the late token to be turned away") { ignoredCount() == 1 }
        XCTAssertTrue(sink.contains("bootstrapExpired"))
        XCTAssertNil(stored("new")?.deviceToken)
        XCTAssertNil(stored("new")?.setupCode, "a pairing that timed out stops presenting its code")
        XCTAssertEqual(client.lastPairingEnd, .timedOut)
        XCTAssertNil(client.pairingGatewayId)
        client.disconnect()
    }

    func testTokenAfterThePairingWasCancelledIsIgnored() async throws {
        Config.setSavedGateways([savedGateway(id: "home", token: "shared-token", priority: 0),
                                 savedGateway(id: "new", priority: 1)])
        let sockets = Sockets()
        // The pairing socket's connect is left unanswered; the configured gateway's is answered.
        sockets.reply = { id in sockets.count >= 2 ? [GatewayScript.helloOk(replyTo: id, methods: [])] : [] }
        let client = OpenClawEventClient(socketFactory: { _ in sockets.make() })

        client.startPairing(gatewayId: "new", setupCode: setupCode)
        // The handshake persists this gateway's device id; let that land before cancelling.
        await waitUntil("the pairing handshake to go out") {
            sockets.count == 1 && sockets.last?.sentRequests(method: "connect").isEmpty == false
        }
        XCTAssertEqual(client.connectionGatewayId, "new")

        let reconnected = expectation(description: "back on the configured gateway")
        reconnected.assertForOverFulfill = false
        client.onPairingStatusChange = { if $0 == .paired { reconnected.fulfill() } }
        client.cancelPairing()
        XCTAssertEqual(client.lastPairingEnd, .cancelled)
        XCTAssertNil(client.pairingGatewayId)
        XCTAssertNil(stored("new")?.setupCode, "a cancelled pairing stops presenting its code")
        await fulfillment(of: [reconnected], timeout: 2)
        XCTAssertEqual(client.connectionGatewayId, "home")

        sockets.last?.push(devicePaired("after-cancel"))
        await waitUntil("the token to be turned away") { ignoredCount() == 1 }
        XCTAssertNil(stored("new")?.deviceToken)
        XCTAssertNil(stored("home")?.deviceToken)
        client.disconnect()
    }

    func testPairingNeedsAgentMode() {
        Config.setSavedGateways([savedGateway(id: "new")])
        Config.setAgentModeEnabled(false)
        var made = 0
        let client = OpenClawEventClient(socketFactory: { _ in made += 1; return ScriptedGatewaySocket() })
        var last: PairingStatus?
        client.onPairingStatusChange = { last = $0 }

        client.startPairing(gatewayId: "new", setupCode: setupCode)
        XCTAssertEqual(made, 0, "no socket opens while Agent Mode is off")
        XCTAssertNil(client.pairingGatewayId)
        XCTAssertNil(stored("new")?.setupCode)
        if case .error? = last {} else { XCTFail("expected an error status, got \(String(describing: last))") }
    }

    func testPairingRefusesAnInvalidSetupCode() {
        Config.setSavedGateways([savedGateway(id: "new")])
        var made = 0
        let client = OpenClawEventClient(socketFactory: { _ in made += 1; return ScriptedGatewaySocket() })
        client.startPairing(gatewayId: "new", setupCode: "not-a-setup-code")
        XCTAssertEqual(made, 0)
        XCTAssertNil(client.pairingGatewayId)
    }
}
