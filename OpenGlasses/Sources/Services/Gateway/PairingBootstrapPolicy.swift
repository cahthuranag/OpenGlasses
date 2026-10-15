import Foundation

/// When a gateway-issued device token may be stored (Plan AR).
///
/// A stored device token outranks every other credential the next handshake could present
/// (`GatewayAuthSelector`), so whoever gets one stored decides which gateway this phone trusts.
/// Two frames can carry one, and they are not alike:
///
/// - **`device.paired` is unsolicited.** The gateway may send it at any moment — before the
///   handshake, after it, while nothing is pairing — and over a LAN `ws://` socket so may anyone on
///   the path. Its token is stored only inside a pairing bootstrap the wearer started from
///   Settings: for the gateway being paired, before the bootstrap's window closes, and once. The
///   first stored token ends the bootstrap, so a second one is turned away like any other
///   unsolicited token.
/// - **A token in the reply to our own connect request is the handshake itself** — a 2.0
///   `hello-ok` carries one whenever the gateway issues it — so it is not window-gated. The client
///   only asks about a reply whose `id` matches the connect it sent. When it lands mid-bootstrap
///   for that gateway, it completes the bootstrap.
///
/// Pure: the client feeds it events with their times and applies the transition it returns.
enum PairingBootstrapPolicy {

    /// How long a bootstrap waits for someone to approve the device on the gateway.
    static let window: TimeInterval = 10 * 60

    enum State: Equatable {
        case idle
        /// The wearer started pairing with `gatewayId`; the bootstrap ends at `deadline`.
        case bootstrapping(gatewayId: String, deadline: Date)
    }

    enum Event: Equatable {
        /// The wearer pressed Pair for this gateway. Replaces any bootstrap already running.
        case started(gatewayId: String, at: Date, window: TimeInterval = PairingBootstrapPolicy.window)
        /// The wearer cancelled, or the client was disconnected.
        case cancelled
        /// The bootstrap's timer fired. A timer older than the running bootstrap changes nothing.
        case timerFired(at: Date)
        /// A `device.paired` event carried a token, on the socket to `gatewayId` (nil: no
        /// gateway resolved for this socket).
        case pairedEventToken(gatewayId: String?, at: Date)
        /// The reply to our own outstanding connect request to `gatewayId` carried a token.
        case connectReplyToken(gatewayId: String, at: Date)
    }

    enum TokenVerdict: Equatable {
        case store
        case ignore(IgnoreReason)
    }

    enum IgnoreReason: String, Equatable {
        /// No wearer-started bootstrap is running: idle, already paired, cancelled, or a second
        /// token after the first one ended the bootstrap.
        case noBootstrap
        /// The bootstrap's window had closed.
        case bootstrapExpired
        /// The token came on a socket to a different gateway from the one being paired.
        case otherGateway
    }

    enum EndReason: String, Equatable {
        case paired, cancelled, timedOut
    }

    struct Transition: Equatable {
        let state: State
        /// Set only for the two token events.
        var token: TokenVerdict? = nil
        /// Set when this event ended a running bootstrap.
        var ended: EndReason? = nil
    }

    static func apply(_ event: Event, to state: State) -> Transition {
        switch (event, state) {
        case let (.started(gatewayId, at, window), _):
            return Transition(state: .bootstrapping(gatewayId: gatewayId,
                                                    deadline: at.addingTimeInterval(window)))

        case (.cancelled, .idle):
            return Transition(state: .idle)
        case (.cancelled, .bootstrapping):
            return Transition(state: .idle, ended: .cancelled)

        case (.timerFired, .idle):
            return Transition(state: .idle)
        case let (.timerFired(at), .bootstrapping(_, deadline)):
            guard at >= deadline else { return Transition(state: state) }
            return Transition(state: .idle, ended: .timedOut)

        case (.pairedEventToken, .idle):
            return Transition(state: .idle, token: .ignore(.noBootstrap))
        case let (.pairedEventToken(gatewayId, at), .bootstrapping(pairing, deadline)):
            if at > deadline {
                return Transition(state: .idle, token: .ignore(.bootstrapExpired), ended: .timedOut)
            }
            guard gatewayId == pairing else {
                return Transition(state: state, token: .ignore(.otherGateway))
            }
            return Transition(state: .idle, token: .store, ended: .paired)

        case (.connectReplyToken, .idle):
            return Transition(state: .idle, token: .store)
        case let (.connectReplyToken(gatewayId, _), .bootstrapping(pairing, _)):
            guard gatewayId == pairing else { return Transition(state: state, token: .store) }
            return Transition(state: .idle, token: .store, ended: .paired)
        }
    }
}
