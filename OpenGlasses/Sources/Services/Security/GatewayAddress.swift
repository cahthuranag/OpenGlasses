import Foundation
import Darwin

/// A gateway, Home Assistant or Hermes bridge address as the wearer typed it, made into the URL the
/// app will use (Plan ID item 4).
///
/// People type `nuc`, `192.168.1.20:8123` or `box.tailnet.ts.net` into a host field, not
/// `http://nuc`. Without a scheme `EndpointPolicy` refuses the string as `disallowedScheme`, an
/// error the wearer did not cause. This picks the scheme the wearer most plausibly meant:
///
/// - an explicit scheme is kept, whatever it is (an unusable one is still `EndpointPolicy`'s to
///   refuse, with its own words);
/// - `http` for a host on the wearer's own network as `URLFetchGuard.hostClass` reads it
///   (loopback, link-local, RFC 1918, 100.64/10, IPv6 unique-local, `*.local`), for a dot-less
///   single-label name (`nuc`, `hermes-box`), and for a `*.ts.net` name given with a port
///   (`tailscale serve` answers https on 443, so a port means the server itself);
/// - `https` for everything else, including `*.ts.net` without a port, and for port 443
///   anywhere.
///
/// The result still goes through `EndpointPolicy`. Choosing a scheme never widens what the policy
/// allows: a cleartext address it refuses in a release build stays refused. Pure.
enum GatewayAddress {

    /// An address split into its parts. `port` is the one that will be used (typed, else the
    /// default the caller passed); `typedPort` is only what the wearer typed.
    struct Components: Equatable, Sendable {
        var scheme: String
        var schemeWasTyped: Bool
        /// `user[:password]@`, kept so `EndpointPolicy` can refuse it rather than it vanishing.
        var userInfo: String?
        /// Without IPv6 brackets.
        var host: String
        var port: Int?
        var typedPort: Int?
        /// Path, query and fragment as typed (empty, or starting `/`, `?` or `#`), with trailing
        /// slashes removed.
        var tail: String

        /// The host as it is spelt inside a URL: an IPv6 literal goes in brackets.
        var urlHost: String { host.contains(":") ? "[\(host)]" : host }

        /// The whole URL, port included.
        var urlString: String {
            "\(scheme)://\(userInfo ?? "")\(urlHost)\(port.map { ":\($0)" } ?? "")\(tail)"
        }

        /// The URL without the port, for a settings field that has a port field beside it. The
        /// scheme stays, so a choice made because of the port survives the port moving out.
        var urlStringWithoutPort: String {
            "\(scheme)://\(userInfo ?? "")\(urlHost)\(tail)"
        }

        /// The websocket spelling of the scheme: `http` → `ws`, `https` → `wss`; anything else
        /// unchanged.
        var webSocketScheme: String {
            switch scheme {
            case "http": return "ws"
            case "https": return "wss"
            default: return scheme
            }
        }
    }

    /// The URL to use for `raw`, or nil when it is empty or not an address at all.
    /// `defaultPort` is added when none was typed (a typed port wins), and counts as a port for
    /// the `*.ts.net` rule.
    nonisolated static func normalise(_ raw: String, defaultPort: Int? = nil) -> String? {
        components(raw, defaultPort: defaultPort)?.urlString
    }

    /// `raw` split into scheme, host, port and the rest, with the scheme chosen as described on
    /// the type. Accepts `scheme://host:port/path`, `host:port`, a bare host, a bracketed or bare
    /// IPv6 literal, and surrounding whitespace and trailing slashes.
    nonisolated static func components(_ raw: String, defaultPort: Int? = nil) -> Components? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }

        // Scheme: only `name://` before any path counts. `nuc:8080` is a host and a port, not
        // the scheme `nuc`, and a `://` inside a path or query is not a scheme at all.
        var typedScheme: String?
        var rest = Substring(text)
        if let separator = text.range(of: "://") {
            let prefix = text[..<separator.lowerBound]
            if !prefix.contains(where: { "/?#".contains($0) }) {
                let scheme = prefix.lowercased()
                guard isSchemeName(scheme) else { return nil }
                typedScheme = scheme
                rest = text[separator.upperBound...]
            }
        }

        // Authority ends at the first `/`, `?` or `#`; everything after is kept as typed.
        let authorityEnd = rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex
        var authority = rest[..<authorityEnd]
        let tail = String(rest[authorityEnd...])

        var userInfo: String?
        if let at = authority.lastIndex(of: "@") {
            userInfo = String(authority[...at])
            authority = authority[authority.index(after: at)...]
        }

        guard let split = splitHostPort(authority) else { return nil }
        let host = split.host
        let typedPort = split.port

        let port = typedPort ?? defaultPort
        if let port, !(1...65_535).contains(port) { return nil }
        let scheme = typedScheme ?? (defaultsToCleartext(host: host, port: port) ? "http" : "https")
        let result = Components(scheme: scheme, schemeWasTyped: typedScheme != nil, userInfo: userInfo,
                                host: host, port: port, typedPort: typedPort, tail: tail)
        // Last word on "is this an address at all" goes to Foundation's own parser.
        guard let url = URL(string: result.urlString), url.host?.isEmpty == false else { return nil }
        return result
    }

    /// What a host field with a port field beside it should show once the wearer has finished
    /// editing it: the host with its scheme (so they see what will be used), and a port typed in
    /// the host moved into the port field. `webSocket` spells the scheme `ws`/`wss` and drops any
    /// path, for the Hermes bridge, which is a socket on `/`. Nil leaves the fields as typed:
    /// empty, not an address, or carrying a user name the endpoint rule will refuse.
    struct FieldValues: Equatable, Sendable {
        var host: String
        var port: Int
    }

    nonisolated static func fieldValues(host: String, port: Int, webSocket: Bool = false) -> FieldValues? {
        guard let address = components(host, defaultPort: port), address.userInfo == nil,
              let resolvedPort = address.port else { return nil }
        let shown = webSocket ? "\(address.webSocketScheme)://\(address.urlHost)" : address.urlStringWithoutPort
        return FieldValues(host: shown, port: resolvedPort)
    }

    /// True when a host given without a scheme should be reached over `http`. The private-range
    /// half is `URLFetchGuard`'s table, so this can never call a host private that the endpoint
    /// rule does not. Port 443 is https wherever it is.
    nonisolated static func defaultsToCleartext(host: String, port: Int?) -> Bool {
        if port == 443 { return false }
        switch URLFetchGuard.hostClass(host) {
        case .loopback, .linkLocal, .privateNetwork, .sharedAddressSpace, .localName:
            return true
        case .reserved, .publicHost:
            break
        }
        let name = host.lowercased()
        // A single label (`nuc`) only resolves through the local network's own DNS or mDNS search.
        if !name.contains("."), !name.contains(":") { return true }
        if name.hasSuffix(".ts.net") { return port != nil }
        return false
    }

    // MARK: - Parsing

    private nonisolated static func isSchemeName(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, CharacterSet.letters.contains(first) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789+-.")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// `host`, `host:port`, `[v6]`, `[v6]:port` or a bare IPv6 literal. Nil when the host is
    /// empty or malformed, or the port is not a number.
    private nonisolated static func splitHostPort(_ authority: Substring) -> (host: String, port: Int?)? {
        let host: Substring
        var portText: Substring?
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            host = authority[authority.index(after: authority.startIndex)..<close]
            let after = authority[authority.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":") else { return nil }
                portText = after.dropFirst()
            }
            guard isIPv6Literal(host) else { return nil }
        } else if authority.filter({ $0 == ":" }).count >= 2 {
            // A bare IPv6 literal cannot carry a port; brackets are how one is written with a port.
            host = authority
            guard isIPv6Literal(host) else { return nil }
        } else {
            if let colon = authority.firstIndex(of: ":") {
                host = authority[..<colon]
                portText = authority[authority.index(after: colon)...]
            } else {
                host = authority
            }
            guard isHostName(host) else { return nil }
        }
        var port: Int?
        if let portText {
            guard !portText.isEmpty, portText.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(portText) else { return nil }
            port = value
        }
        return (host: String(host), port: port)
    }

    private nonisolated static func isHostName(_ value: Substring) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("."), !value.hasPrefix("-"), !value.contains("..") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        return value.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

    private nonisolated static func isIPv6Literal(_ value: Substring) -> Bool {
        let address = value.split(separator: "%", maxSplits: 1).first.map(String.init) ?? String(value)
        var parsed = in6_addr()
        return address.withCString { inet_pton(AF_INET6, $0, &parsed) } == 1
    }
}
