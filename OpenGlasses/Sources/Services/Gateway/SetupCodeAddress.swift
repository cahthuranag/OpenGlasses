import Foundation

/// The gateway address a setup code carries (`SetupCodePayload.url`), checked and mapped onto a
/// `GatewayConfig`'s connection fields (Plan AR).
///
/// A setup code is pasted or scanned, so its address is untrusted input. It passes the same
/// endpoint rule as the event-stream socket it will configure (`EndpointPolicy` for
/// `.openClawEventStream`: no credential in the URL, and in a release build cleartext only to a
/// private-network host), and it may not carry a query or fragment.
///
/// **The rule for using it:** a setup code fills in a gateway that has no address yet (one-scan
/// gateway creation). It never replaces an address the wearer already saved without asking —
/// `apply(to:)` reports `.differs`, and only `replacing(in:)`, which the settings call after the
/// wearer confirms, overwrites it. Pairing against the saved address instead is not offered: it
/// would hand the code's bootstrap token to a server the code was not issued for.
struct SetupCodeAddress: Equatable {

    enum Leg: Equatable {
        /// `http`/`ws`: a LAN host and port (`GatewayConfig.lanHost` / `.port`).
        case lan(host: String, port: Int)
        /// `https`/`wss`: a TLS base URL (`GatewayConfig.tunnelHost`), always spelt `https://`.
        case tunnel(baseURL: String)
    }

    let leg: Leg

    enum Rejection: Error, Equatable {
        case endpoint(EndpointPolicy.Rejection)
        case queryOrFragment
    }

    enum ApplyResult: Equatable {
        /// The gateway had no address; this is it with the code's address filled in.
        case filled(GatewayConfig)
        /// The gateway already points where the code does.
        case matches
        /// The gateway points somewhere else. Ask before `replacing(in:)`.
        case differs
    }

    static func parse(_ raw: String, defaultPort: Int,
                      build: EndpointPolicy.BuildFlavor = .current) -> Result<SetupCodeAddress, Rejection> {
        let url: URL
        switch EndpointPolicy.validate(raw, for: .openClawEventStream, build: build) {
        case .success(let valid): url = valid
        case .failure(let rejection): return .failure(.endpoint(rejection))
        }
        guard url.query == nil, url.fragment == nil else { return .failure(.queryOrFragment) }
        // `validate` has already required a host and one of these four schemes.
        let host = url.host ?? ""
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "http" || scheme == "ws" {
            return .success(SetupCodeAddress(leg: .lan(host: host, port: url.port ?? defaultPort)))
        }
        // The client appends `/ws` to a tunnel base, so a code that already names it drops it.
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix("/ws") { path.removeLast(3) }
        while path.hasSuffix("/") { path.removeLast() }
        let port = url.port.map { ":\($0)" } ?? ""
        return .success(SetupCodeAddress(leg: .tunnel(baseURL: "https://\(host)\(port)\(path)")))
    }

    /// The rule above, as a decision. Pure.
    func apply(to gateway: GatewayConfig) -> ApplyResult {
        let lan = Self.bareHost(gateway.lanHost)
        let tunnel = gateway.tunnelURL
        if lan.isEmpty && tunnel.isEmpty { return .filled(replacing(in: gateway)) }
        switch leg {
        case let .lan(host, port):
            let sameLAN = lan.caseInsensitiveCompare(host) == .orderedSame && gateway.port == port
            return sameLAN && gateway.connectionModeEnum != .tunnel ? .matches : .differs
        case let .tunnel(baseURL):
            let sameTunnel = tunnel.caseInsensitiveCompare(baseURL) == .orderedSame
            return sameTunnel && gateway.connectionModeEnum != .lan ? .matches : .differs
        }
    }

    /// The gateway pointed at this address, with the connection mode pinned to its leg.
    func replacing(in gateway: GatewayConfig) -> GatewayConfig {
        var updated = gateway
        switch leg {
        case let .lan(host, port):
            updated.lanHost = host
            updated.port = port
            updated.connectionMode = OpenClawConnectionMode.lan.rawValue
        case let .tunnel(baseURL):
            updated.tunnelHost = baseURL
            updated.connectionMode = OpenClawConnectionMode.tunnel.rawValue
        }
        return updated
    }

    /// A saved LAN host without the scheme or slashes the settings field tolerates.
    private static func bareHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["http://", "https://"] where host.lowercased().hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
