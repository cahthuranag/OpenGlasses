import Foundation
import Darwin

/// Blocks server-side-request-forgery-shaped fetches (docs/plans/BC-unconditional-safety-gate.md).
///
/// Tools that fetch a URL supplied by untrusted input — a scanned QR code, an LLM tool argument —
/// must not be pointed at the user's private network or a cloud metadata endpoint. Without this,
/// a malicious QR could aim a fetch at `http://192.168.1.1/…` or `169.254.169.254` and exfiltrate
/// the response back through the model. Pure and headless-testable.
enum URLFetchGuard {

    enum Rejection: Error, Equatable, CustomStringConvertible {
        case invalidURL
        case disallowedScheme(String)
        case privateOrReservedHost(String)
        case missingHost

        var description: String {
            switch self {
            case .invalidURL: return "not a valid URL"
            case .disallowedScheme(let s): return "scheme '\(s)' is not allowed (only http/https)"
            case .privateOrReservedHost(let h): return "host '\(h)' is on a private or reserved network"
            case .missingHost: return "URL has no host"
            }
        }
    }

    /// Validate a URL string for outbound fetch. Returns the parsed `URL` or a `Rejection`.
    static func validate(_ urlString: String) -> Result<URL, Rejection> {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failure(.invalidURL)
        }
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else {
            return .failure(.disallowedScheme(scheme.isEmpty ? "(none)" : scheme))
        }
        guard let host = url.host, !host.isEmpty else {
            return .failure(.missingHost)
        }
        guard url.user == nil, url.password == nil, url.fragment == nil else {
            return .failure(.invalidURL)
        }
        if isBlockedHost(host) {
            return .failure(.privateOrReservedHost(host))
        }
        return .success(url)
    }

    /// True for loopback, link-local, private, and other reserved hosts that a public fetch must
    /// never target. Covers literal IPv4/IPv6 and obvious hostname forms (`localhost`, `*.local`).
    /// DNS names that *resolve* to private space are not caught here (that needs resolution); the
    /// literal + suffix checks stop the direct-address SSRF a QR/LLM arg realistically uses.
    nonisolated static func isBlockedHost(_ rawHost: String) -> Bool {
        hostClass(rawHost) != .publicHost
    }

    /// Where a host sits, as far as its spelling can tell. `isBlockedHost` is "anything but
    /// `publicHost`"; `GatewayAddress` reads the finer classes to choose `http` for a host on the
    /// wearer's own network. One table of ranges, so the two can never disagree about what is
    /// private.
    enum HostClass: Equatable, Sendable {
        /// `localhost`, `*.localhost`, 127/8, `::1`.
        case loopback
        /// 169.254/16, fe80::/10.
        case linkLocal
        /// RFC 1918 IPv4 and IPv6 unique-local (fc00::/7).
        case privateNetwork
        /// 100.64.0.0/10, the shared address space carrier-grade NAT and Tailscale use.
        case sharedAddressSpace
        /// An mDNS / Bonjour `*.local` name.
        case localName
        /// Everything else a public fetch must not target: unspecified, multicast, documentation
        /// and benchmarking ranges, `*.internal`, and numeric spellings other stacks may read as
        /// an address.
        case reserved
        /// None of the above.
        case publicHost
    }

    nonisolated static func hostClass(_ rawHost: String) -> HostClass {
        var host = rawHost.lowercased()
        // Strip IPv6 brackets.
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }

        if host == "localhost" || host.hasSuffix(".localhost") { return .loopback }
        if host.hasSuffix(".local") { return .localName }     // mDNS / Bonjour
        if host.hasSuffix(".internal") { return .reserved }   // common metadata alias

        if let v4 = IPv4(host) { return v4.hostClass }
        if let v6 = IPv6(host) { return v6.hostClass }
        // Refuse legacy numeric spellings that different URL/network stacks may reinterpret as an
        // IP address (single-integer, octal-like or hexadecimal). Only canonical dotted IPv4 and
        // inet_pton-accepted IPv6 reach the network policy.
        let numericAlphabet = CharacterSet(charactersIn: "0123456789abcdefx.")
        if !host.isEmpty, host.unicodeScalars.allSatisfy(numericAlphabet.contains),
           host.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains) {
            return .reserved
        }
        return .publicHost
    }

    // MARK: - IPv4

    private struct IPv4 {
        let octets: [UInt8]
        init?(_ s: String) {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            var out: [UInt8] = []
            for p in parts {
                guard p.count == 1 || p.first != "0" else { return nil }
                guard let n = UInt8(p) else { return nil }
                out.append(n)
            }
            octets = out
        }

        var hostClass: HostClass {
            let (a, b) = (octets[0], octets[1])
            switch a {
            case 0: return .reserved               // 0.0.0.0/8 "this network"
            case 10: return .privateNetwork        // 10.0.0.0/8 private
            case 127: return .loopback             // loopback
            case 169 where b == 254: return .linkLocal   // link-local (incl. 169.254.169.254 metadata)
            case 172 where (16...31).contains(b): return .privateNetwork  // 172.16.0.0/12 private
            case 192 where b == 0: return .reserved      // IETF protocol assignments
            case 192 where b == 2: return .reserved      // TEST-NET-1
            case 192 where b == 168: return .privateNetwork   // 192.168.0.0/16 private
            case 198 where b == 18 || b == 19: return .reserved // benchmarking
            case 198 where b == 51 && octets[2] == 100: return .reserved // TEST-NET-2
            case 203 where b == 0 && octets[2] == 113: return .reserved // TEST-NET-3
            case 100 where (64...127).contains(b): return .sharedAddressSpace // 100.64.0.0/10 CGNAT
            case 255 where octets == [255, 255, 255, 255]: return .reserved
            default: return a >= 224 ? .reserved : .publicHost   // multicast + reserved (224+)
            }
        }
    }

    // MARK: - IPv6

    private struct IPv6 {
        let bytes: [UInt8]

        init?(_ value: String) {
            let address = value.split(separator: "%", maxSplits: 1).first.map(String.init) ?? value
            var parsed = in6_addr()
            guard address.withCString({ inet_pton(AF_INET6, $0, &parsed) }) == 1 else { return nil }
            bytes = withUnsafeBytes(of: parsed) { Array($0) }
        }

        var hostClass: HostClass {
            guard bytes.count == 16 else { return .reserved }
            if bytes.allSatisfy({ $0 == 0 }) { return .reserved }                // unspecified
            if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return .loopback } // loopback
            if bytes[0] & 0xFE == 0xFC { return .privateNetwork }                // ULA fc00::/7
            if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return .linkLocal }    // link-local fe80::/10
            if bytes[0] == 0xFF { return .reserved }                             // multicast
            if Array(bytes[0...11]) == Array(repeating: 0, count: 10) + [0xFF, 0xFF] {
                return IPv4(bytes[12...15].map(String.init).joined(separator: "."))?.hostClass ?? .reserved
            }
            if Array(bytes[0...3]) == [0x20, 0x01, 0x0D, 0xB8] { return .reserved } // documentation
            if Array(bytes[0...7]) == [0x01, 0x00, 0, 0, 0, 0, 0, 0] { return .reserved } // discard-only
            return .publicHost
        }
    }
}
