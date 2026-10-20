import Foundation

/// What the gateway settings show about the event client: the last status it reported, the
/// gateway its socket is for, and the running or most recent pairing (Plan AR).
struct GatewayPairingSnapshot: Equatable {
    var status: PairingStatus? = nil
    var connectionGatewayId: String? = nil
    var pairingGatewayId: String? = nil
    var lastPairingGatewayId: String? = nil
    var lastPairingEnd: PairingBootstrapPolicy.EndReason? = nil
}

/// WebSocket client for receiving proactive notifications from OpenClaw.
/// Connects to the OpenClaw gateway's WebSocket endpoint, authenticates,
/// and listens for heartbeat/cron events to speak through TTS.
///
/// Plan EH P1: the handshake is the shared `OpenClawConnectParams` (challenge-timestamped device
/// signature, closed-schema params) and the reply is read through `PairingResponseInterpreter`,
/// which understands the 2.0 `hello-ok` and its pairing-required details.
///
/// Plan AR: a device token is stored only as `PairingBootstrapPolicy` allows — an unsolicited
/// `device.paired` only inside a pairing the wearer started, and a `res` only when it answers the
/// connect request this socket sent.
class OpenClawEventClient {
    var onNotification: ((String) -> Void)?
    /// Surfaces live pairing/connection state to the gateway settings UI.
    var onPairingStatusChange: ((PairingStatus) -> Void)?
    /// Remote invoke (Plan BH): an unsolicited server→client request frame arrived. The handler
    /// produces exactly one reply frame and passes it to the completion for sending.
    var onRemoteRequest: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)?

    private let socketFactory: GatewaySocketFactory
    private var socket: GatewaySocket?
    private var isConnected = false
    private var shouldReconnect = false
    private var reconnectDelay: TimeInterval = 2
    private let maxReconnectDelay: TimeInterval = 30
    /// The gateway resolved for the current connection — its credential drives the handshake.
    private var currentGateway: GatewayConfig?
    /// The gateway's `connect.challenge` — signed into the device-identity block so remote
    /// gateways grant real scopes (token-only connects can be granted zero scopes).
    private var challenge: GatewayChallenge?
    /// The gateway's hello-ok for this socket (role, scopes, catalog).
    private(set) var gatewayHello: GatewayHello?
    /// The `id` of the connect request this socket is waiting on. Only the `res` carrying it is
    /// read as the handshake's answer; any other `res` is dropped.
    private var pendingConnectId: String?

    /// Plan AR: the wearer-started pairing, if one is running, and when it gives up.
    private var bootstrap: PairingBootstrapPolicy.State = .idle
    private var bootstrapTimer: DispatchWorkItem?
    /// How the most recent pairing ended, and which gateway it was for.
    private(set) var lastPairingEnd: PairingBootstrapPolicy.EndReason?
    private(set) var lastPairingGatewayId: String?
    private let clock: () -> Date
    private let bootstrapWindow: TimeInterval

    /// The gateway the running pairing is for, if any.
    var pairingGatewayId: String? {
        if case let .bootstrapping(gatewayId, _) = bootstrap { return gatewayId }
        return nil
    }

    /// The gateway this client's socket is for (or was last for).
    var connectionGatewayId: String? { currentGateway?.id }

    /// Everything the gateway settings show, read together with the status it accompanies.
    func pairingSnapshot(status: PairingStatus) -> GatewayPairingSnapshot {
        GatewayPairingSnapshot(status: status,
                               connectionGatewayId: connectionGatewayId,
                               pairingGatewayId: pairingGatewayId,
                               lastPairingGatewayId: lastPairingGatewayId,
                               lastPairingEnd: lastPairingEnd)
    }

    /// Has this socket completed the connect handshake? `isConnected` is set only by a `.paired`
    /// hello-ok, so it is exactly "the peer proved it is our gateway" — the predicate names that
    /// intent for the inbound gate below. In LAN mode the socket is cleartext `ws://`, so without
    /// this an on-path attacker could inject a request frame instead of the gateway's hello-ok.
    private var isAuthenticated: Bool { isConnected }

    init(socketFactory: @escaping GatewaySocketFactory = URLSessionGatewaySocket.make,
         clock: @escaping () -> Date = { Date() },
         bootstrapWindow: TimeInterval = PairingBootstrapPolicy.window) {
        self.socketFactory = socketFactory
        self.clock = clock
        self.bootstrapWindow = bootstrapWindow
    }

    func connect() {
        // BK P0: listening for inbound gateway events and feeding them to the triage LLM is itself
        // an autonomous background action on untrusted content — gate the whole loop on Agent Mode,
        // not just the outbound `delegateTask` leg it can reach.
        guard Config.isOpenClawAgentActive else {
            PrivacyLog.gatewayConnection(.inactive)
            return
        }
        shouldReconnect = true
        reconnectDelay = 2
        establishConnection()
    }

    func disconnect() {
        sendDeviceEvent(type: "connection", payload: ["status": "disconnected"])
        // A pairing does not outlive its socket: a teardown is a cancel.
        applyBootstrap(.cancelled)
        shouldReconnect = false
        isConnected = false
        challenge = nil
        gatewayHello = nil
        pendingConnectId = nil
        socket?.cancel()
        socket = nil
        onPairingStatusChange?(.disconnected)
        PrivacyLog.gatewayConnection(.disconnected)
    }

    /// Begin device pairing with a setup code, from the wearer's own press in the gateway
    /// settings: store the code on that gateway and reconnect to it, so the handshake presents the
    /// bootstrap token. This opens the only window in which an unsolicited `device.paired` token
    /// is stored (`PairingBootstrapPolicy`); it closes on the first stored token, a cancel, a
    /// disconnect, or after `bootstrapWindow`.
    ///
    /// The gateway is named rather than resolved: a gateway being paired for the first time has
    /// no credential yet, so it is not one of `Config.enabledGateways`.
    func startPairing(gatewayId: String, setupCode: String) {
        guard Config.agentModeEnabled else {
            PrivacyLog.gatewayConnection(.inactive)
            onPairingStatusChange?(.error("Agent Mode is off"))
            return
        }
        guard SetupCode.decode(setupCode) != nil,
              let gateway = Self.pairableGateway(gatewayId) else {
            onPairingStatusChange?(.error("No gateway to pair"))
            return
        }
        // Close whatever was running first: a pairing it cancels drops its own setup code.
        disconnect()
        Config.setGatewaySetupCode(gatewayId: gateway.id, setupCode: setupCode)
        lastPairingEnd = nil
        lastPairingGatewayId = gateway.id
        applyBootstrap(.started(gatewayId: gateway.id, at: clock(), window: bootstrapWindow))
        PrivacyLog.gatewayConnection(.pairingStarted, peer: PrivateIdentifier(gateway.id))
        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.pairingGatewayId != nil else { return }
            self.applyBootstrap(.timerFired(at: self.clock()))
            // Nobody approved in time: close the pairing socket and carry on as at launch.
            if self.pairingGatewayId == nil, self.lastPairingEnd == .timedOut {
                self.disconnect()
                self.connect()
            }
        }
        bootstrapTimer?.cancel()
        bootstrapTimer = timer
        // A second past the deadline, so the wall clock agrees the window has closed.
        DispatchQueue.main.asyncAfter(deadline: .now() + bootstrapWindow + 1, execute: timer)
        shouldReconnect = true
        reconnectDelay = 2
        establishConnection()
    }

    /// The wearer abandoned the pairing they started. The socket closes; if another gateway is
    /// set up and Agent Mode is on, the client reconnects to it as it would at launch.
    func cancelPairing() {
        guard pairingGatewayId != nil else { return }
        disconnect()
        connect()
    }

    // MARK: - Private

    private func establishConnection() {
        // A running pairing pins its gateway; otherwise the multi-gateway config, falling back
        // to legacy if needed.
        let pairing = pairingGatewayId.flatMap(Self.pairableGateway)
        guard let gateway = pairing ?? Self.activeGateway() else {
            PrivacyLog.gatewayConnection(.notConfigured)
            return
        }
        currentGateway = gateway
        // A new socket starts unauthenticated: a reconnect must never inherit the previous
        // socket's handshake, or the inbound gate would open on a peer that never proved itself.
        isConnected = false
        gatewayHello = nil
        pendingConnectId = nil
        onPairingStatusChange?(.connecting)

        let wsURL = Self.webSocketURL(for: gateway)
        guard let url = try? EndpointPolicy.requireOpenable(wsURL, for: .openClawEventStream) else {
            PrivacyLog.gatewayConnection(.endpointMalformed, peer: PrivateIdentifier(gateway.id))
            onPairingStatusChange?(.error("Gateway address not allowed"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue(OpenClawBridge.messageChannel, forHTTPHeaderField: "x-openclaw-message-channel")
        let socket = socketFactory(request)
        self.socket = socket

        PrivacyLog.gatewayConnection(.connecting, transport: Self.transport(for: gateway),
                                     peer: PrivateIdentifier(gateway.id))
        startReceiving(on: socket)
    }

    /// The saved gateway a pairing targets: enabled, speaking the OpenClaw protocol, and with an
    /// address — its credential is what the pairing is about to get.
    private static func pairableGateway(_ gatewayId: String) -> GatewayConfig? {
        Config.savedGateways.first {
            $0.id == gatewayId && $0.enabled && $0.gatewayProvider.usesOpenClawProtocol
                && (!$0.lanHost.isEmpty || !$0.tunnelHost.isEmpty)
        }
    }

    /// Find the first enabled gateway that uses the OpenClaw WebSocket protocol.
    private static func activeGateway() -> GatewayConfig? {
        let gateways = Config.enabledGateways
        if let gw = gateways.first(where: { $0.gatewayProvider.usesOpenClawProtocol && $0.isConfigured }) {
            return gw
        }
        // Fall back to legacy single-gateway config
        if Config.openClawEnabled && !Config.openClawGatewayToken.isEmpty {
            return GatewayConfig(
                id: "legacy",
                name: "Legacy OpenClaw",
                provider: GatewayProvider.openclaw.rawValue,
                lanHost: Config.openClawLanHost,
                port: Config.openClawPort,
                tunnelHost: Config.openClawTunnelHost,
                token: Config.openClawGatewayToken,
                connectionMode: Config.openClawConnectionMode.rawValue,
                enabled: true,
                priority: 0
            )
        }
        return nil
    }

    /// Build a WebSocket URL from a gateway config.
    private static func webSocketURL(for gateway: GatewayConfig) -> String {
        let mode = gateway.connectionModeEnum
        switch mode {
        case .tunnel:
            return tunnelWebSocketURL(for: gateway)
        case .lan:
            return lanWebSocketURL(for: gateway)
        case .auto:
            if !gateway.tunnelHost.isEmpty {
                return tunnelWebSocketURL(for: gateway)
            }
            return lanWebSocketURL(for: gateway)
        }
    }

    /// Which leg `webSocketURL(for:)` will pick — mirrors its branch, for logging only.
    private static func transport(for gateway: GatewayConfig) -> PrivacyLog.GatewayTransport {
        switch gateway.connectionModeEnum {
        case .tunnel: return .tunnel
        case .lan: return .lan
        case .auto: return gateway.tunnelHost.isEmpty ? .lan : .tunnel
        }
    }

    // The gateway token is presented in the `connect` handshake (see `sendConnectHandshake`),
    // never in the URL — keeping it out of the query string prevents it leaking into device,
    // proxy, and server access logs.
    private static func tunnelWebSocketURL(for gateway: GatewayConfig) -> String {
        // `tunnelURL` carries the scheme even when the wearer typed a bare name.
        let base = gateway.tunnelURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return "\(base)/ws"
    }

    private static func lanWebSocketURL(for gateway: GatewayConfig) -> String {
        let host = gateway.lanHost
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        return "ws://\(host):\(gateway.port)/ws"
    }

    private func startReceiving(on socket: GatewaySocket) {
        Task { [weak self] in
            while let self, self.socket === socket {
                do {
                    let text = try await socket.receive()
                    self.handleMessage(text)
                } catch {
                    guard self.socket === socket else { return }
                    PrivacyLog.gatewayFailed(.receive, SafeErrorSummary(error))
                    self.isConnected = false
                    self.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        if type == "event" {
            handleEvent(json)
        } else if type == "res" {
            handleConnectResponse(json)
        } else if type == "req" {
            handleRequestFrame(json)
        }
    }

    /// Remote invoke (Plan BH): an unsolicited server→client request. The wired handler owns
    /// parse/policy/execute and always produces exactly one reply frame; with no handler wired
    /// we still answer (unsupported) rather than leave the gateway hanging.
    /// (The 2.0 gateway delivers node commands as `node.invoke.request` events answered by the
    /// `node.invoke.result` RPC — that mapping lands with the node role in Plan EH P3.)
    private func handleRequestFrame(_ json: [String: Any]) {
        // Deny-by-default before the handshake: drop the frame with no reply of any kind. Even an
        // error reply would confirm a listening client to an on-path attacker on the LAN's
        // cleartext socket, so nothing goes back on the wire and the handler is never reached.
        guard isAuthenticated else {
            PrivacyLog.gatewayConnection(.requestDroppedPreAuth)
            return
        }
        guard let handler = onRemoteRequest else {
            if let request = RemoteCommandParser.parse(json) {
                sendFrame(RemoteInvokeReply.unsupported(id: request.id, action: "remote_invoke"))
            }
            return
        }
        handler(json) { [weak self] reply in
            self?.sendFrame(reply)
        }
    }

    private func sendFrame(_ frame: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: frame),
              let string = String(data: data, encoding: .utf8) else { return }
        Task {
            do { try await socket.send(string) } catch {
                PrivacyLog.gatewayFailed(.send, SafeErrorSummary(error))
            }
        }
    }

    /// Fire-and-forget device event (Plan BH follow-up): tell the gateway-side agent something
    /// changed on the device without being asked — connection state, glasses attach/detach,
    /// battery. On the wire this is the `node.event` RPC, which the gateway accepts only from a
    /// socket admitted as a node; until this socket connects with the node role (Plan EH P3) the
    /// event is not sent, rather than sending a frame the gateway will refuse.
    func sendDeviceEvent(type: String, payload: [String: Any]) {
        guard isConnected, gatewayHello?.role == GatewayWire.Role.node.rawValue else { return }
        var body: [String: Any] = [
            "type": type,
            "timestamp": Int(Date().timeIntervalSince1970),
        ]
        if !payload.isEmpty { body["data"] = payload }
        let request = GatewayRequestCatalog.nodeEvent("device.event", payload: body)
        sendFrame([
            "type": "req",
            "id": UUID().uuidString,
            "method": request.method,
            "params": request.params,
        ])
        PrivacyLog.gatewayConnection(.deviceEventSent, detail: PrivacyToken(type))
    }

    /// Map a connect `res` to a pairing outcome: persist a freshly-issued device token, update
    /// connection state, and surface the status. Pure interpretation lives in
    /// `PairingResponseInterpreter`; this applies its side effects.
    private func handleConnectResponse(_ json: [String: Any]) {
        // Only the answer to the connect this socket sent is the handshake. Any other `res` —
        // the reply to a device event, or one planted on a cleartext LAN socket — carries no
        // connection state and no credential.
        guard let id = json["id"] as? String, let expected = pendingConnectId, id == expected else {
            PrivacyLog.gatewayConnection(.responseUncorrelated)
            return
        }
        pendingConnectId = nil
        let outcome = PairingResponseInterpreter.interpretResponse(json)

        if let token = outcome.deviceToken, let gatewayId = currentGateway?.id {
            storeDeviceToken(token, gatewayId: gatewayId,
                             offer: .connectReplyToken(gatewayId: gatewayId, at: clock()))
        }

        switch outcome.status {
        case .paired:
            isConnected = true
            reconnectDelay = 2
            gatewayHello = outcome.hello
            if let hello = outcome.hello {
                PrivacyLog.gatewayConnection(.helloReceived, count: hello.events.count,
                                             detail: PrivacyToken(hello.role))
            }
            PrivacyLog.gatewayConnection(.connected)
            sendDeviceEvent(type: "connection", payload: ["status": "connected"])
        case .waitingApproval:
            // The gateway closes the socket on a pending approval; the reconnect loop presents
            // the same identity again and the approved device gets its token in hello-ok.
            PrivacyLog.gatewayConnection(.pairingPending)
            if outcome.pauseReconnect { reconnectDelay = maxReconnectDelay }
        case .error:
            // The interpreter's message and the raw frame are both the gateway's own prose —
            // the frame additionally echoes the credential we just presented.
            PrivacyLog.gatewayConnection(.authRejected)
        case .disconnected, .connecting:
            break
        }
        onPairingStatusChange?(outcome.status)
    }

    private func handleEvent(_ json: [String: Any]) {
        guard let event = json["event"] as? String else { return }
        let payload = json["payload"] as? [String: Any] ?? [:]

        switch event {
        case "connect.challenge":
            // Ungated: the challenge *is* the handshake — gating it would prevent connecting.
            challenge = GatewayChallenge.parse(event: json)
            sendConnectHandshake()
        case "device.paired":
            // Not gated on the handshake — the approval can arrive before it succeeds — but gated
            // on the wearer's own pairing: outside it, whatever the server sends, nothing is stored.
            guard let outcome = PairingResponseInterpreter.interpretPairedEvent(payload),
                  let token = outcome.deviceToken else { return }
            let gatewayId = currentGateway?.id
            if storeDeviceToken(token, gatewayId: gatewayId,
                                offer: .pairedEventToken(gatewayId: gatewayId, at: clock())) {
                onPairingStatusChange?(.paired)
            }
        case "heartbeat", "cron":
            // These are spoken to the wearer, so they are actuation too: an unauthenticated peer
            // does not get to put words in the glasses' mouth.
            guard isAuthenticated else {
                PrivacyLog.gatewayConnection(.eventDroppedPreAuth, detail: PrivacyToken(event))
                return
            }
            if event == "heartbeat" {
                handleHeartbeatEvent(payload)
            } else {
                handleCronEvent(payload)
            }
        default:
            break
        }
    }

    // MARK: - Pairing bootstrap (Plan AR)

    /// Ask the policy about a device token and store it only on `.store`. Returns whether it was
    /// stored. Nothing from the token or the frame is logged.
    @discardableResult
    private func storeDeviceToken(_ token: String, gatewayId: String?,
                                  offer: PairingBootstrapPolicy.Event) -> Bool {
        let verdict = applyBootstrap(offer)
        guard verdict == .store, let gatewayId else {
            if case let .ignore(reason)? = verdict {
                PrivacyLog.gatewayConnection(.pairingTokenIgnored, detail: PrivacyToken(reason.rawValue))
            }
            return false
        }
        Config.setDeviceCredentials(gatewayId: gatewayId, deviceToken: token)
        PrivacyLog.gatewayConnection(.devicePaired, peer: PrivateIdentifier(gatewayId))
        return true
    }

    /// Run an event through the policy and apply what it says. A bootstrap that ends without a
    /// token drops the setup code — its bootstrap token is one-time — and says so to the settings.
    @discardableResult
    private func applyBootstrap(_ event: PairingBootstrapPolicy.Event) -> PairingBootstrapPolicy.TokenVerdict? {
        let pairing = pairingGatewayId
        let transition = PairingBootstrapPolicy.apply(event, to: bootstrap)
        bootstrap = transition.state
        if let ended = transition.ended {
            bootstrapTimer?.cancel()
            bootstrapTimer = nil
            lastPairingEnd = ended
            PrivacyLog.gatewayConnection(.pairingEnded, detail: PrivacyToken(ended.rawValue))
            if ended != .paired, let pairing {
                Config.clearGatewaySetupCode(gatewayId: pairing)
            }
            if ended == .timedOut {
                onPairingStatusChange?(.error("Pairing timed out"))
            }
        }
        return transition.token
    }

    private func sendConnectHandshake() {
        // Present the ACTIVE gateway's credential (device token > bootstrap > shared token),
        // not the legacy global token — this both fixes wrong-credential sends on multi-gateway
        // setups and enables device pairing. Falls back to the global token if no gateway was
        // resolved, so the default path is unchanged.
        let token: String
        var deviceId = ""
        if let gateway = currentGateway {
            token = GatewayAuthSelector.credential(
                deviceToken: gateway.deviceToken,
                setupCode: gateway.setupCode,
                sharedToken: gateway.token
            )
            deviceId = Config.deviceId(forGateway: gateway.id)
        } else {
            token = Config.openClawGatewayToken
        }

        // Shared builder: role/scopes, closed-schema client block, and — when the gateway issued
        // a challenge — the Ed25519 device-identity block signed at the challenge's timestamp.
        let connectId = UUID().uuidString
        pendingConnectId = connectId
        let connectMsg: [String: Any] = [
            "type": "req",
            "id": connectId,
            "method": "connect",
            "params": OpenClawConnectParams.build(
                displayName: "Avenkin",
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                token: token,
                role: .operator,
                challenge: challenge,
                pairedDeviceId: deviceId.isEmpty ? nil : deviceId
            )
        ]

        PrivacyLog.gatewayConnection(.handshakeSent)
        sendFrame(connectMsg)
    }

    private func handleHeartbeatEvent(_ payload: [String: Any]) {
        let status = payload["status"] as? String ?? ""
        guard status == "sent",
              let preview = payload["preview"] as? String, !preview.isEmpty else { return }

        let silent = payload["silent"] as? Bool ?? false
        guard !silent else { return }

        // The preview is spoken to the wearer; it is the notification's content, not metadata.
        PrivacyLog.gatewayNotification(.heartbeat, characters: preview.count)
        onNotification?(preview)
    }

    private func handleCronEvent(_ payload: [String: Any]) {
        let action = payload["action"] as? String ?? ""
        guard action == "finished" else { return }

        let summary = payload["summary"] as? String
            ?? payload["result"] as? String
            ?? ""
        guard !summary.isEmpty else { return }

        PrivacyLog.gatewayNotification(.cronResult, characters: summary.count)
        onNotification?(summary)
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        // Jitter (±20%) so a fleet of clients doesn't stampede a recovering gateway in lockstep.
        // The socket is load-bearing for inbound remote invoke (Plan BH), so we keep retrying
        // forever — but connection state is surfaced via `onPairingStatusChange`, never silent.
        let delay = reconnectDelay * Double.random(in: 0.8...1.2)
        PrivacyLog.gatewayReconnectScheduled(delaySeconds: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.shouldReconnect else { return }
            self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
            self.establishConnection()
        }
    }
}
