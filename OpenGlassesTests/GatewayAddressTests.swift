import XCTest
@testable import OpenGlasses

/// Plan ID item 4: a gateway, Home Assistant or Hermes host typed without a scheme gets the one the
/// wearer most plausibly meant, and never a scheme error they did not cause.
final class GatewayAddressTests: XCTestCase {

    // MARK: - Normalise

    func testTypedHostsGetTheExpectedURL() {
        let cases: [(raw: String, port: Int?, expected: String, why: String)] = [
            ("nuc", nil, "http://nuc", "a dot-less name is on the local network"),
            ("hermes-box", 8765, "http://hermes-box:8765", "dot-less, with the caller's port"),
            ("192.168.1.20", nil, "http://192.168.1.20", "RFC 1918"),
            ("10.0.0.4:8123", nil, "http://10.0.0.4:8123", "RFC 1918, typed port kept"),
            ("172.20.1.1", nil, "http://172.20.1.1", "RFC 1918 172.16/12"),
            ("8.8.8.8", nil, "https://8.8.8.8", "a public IPv4 address"),
            ("[fd12:3456::5]:8123", nil, "http://[fd12:3456::5]:8123", "IPv6 unique-local, bracketed"),
            ("fd12:3456::5", nil, "http://[fd12:3456::5]", "IPv6 unique-local, bare"),
            ("[fe80::1]", nil, "http://[fe80::1]", "IPv6 link-local"),
            ("[2606:4700::1111]", nil, "https://[2606:4700::1111]", "a public IPv6 address"),
            ("100.101.102.103", nil, "http://100.101.102.103", "100.64/10, the Tailscale range"),
            ("169.254.10.10", nil, "http://169.254.10.10", "IPv4 link-local"),
            ("127.0.0.1:18789", nil, "http://127.0.0.1:18789", "loopback"),
            ("localhost", 8123, "http://localhost:8123", "localhost"),
            ("homeassistant.local:8123", nil, "http://homeassistant.local:8123", "mDNS name"),
            ("box.tailnet.ts.net", nil, "https://box.tailnet.ts.net", "tailscale serve answers https on 443"),
            ("box.tailnet.ts.net:18789", nil, "http://box.tailnet.ts.net:18789", "a port means the server itself"),
            ("box.tailnet.ts.net", 18789, "http://box.tailnet.ts.net:18789", "the caller's port counts too"),
            ("box.tailnet.ts.net:443", nil, "https://box.tailnet.ts.net:443", "443 is tailscale serve itself"),
            ("192.168.1.5:443", nil, "https://192.168.1.5:443", "443 is https wherever it is"),
            ("gateway.example.com", nil, "https://gateway.example.com", "a public name"),
            ("gateway.example.com:8443", nil, "https://gateway.example.com:8443", "a public name with a port"),
            ("https://192.168.1.20", nil, "https://192.168.1.20", "an explicit https is kept"),
            ("http://gateway.example.com", nil, "http://gateway.example.com", "an explicit http is kept"),
            ("HTTPS://Box.Example.com/", nil, "https://Box.Example.com", "scheme lower-cased, trailing slash gone"),
            ("http://192.168.1.20/", 18789, "http://192.168.1.20:18789", "trailing slash, caller's port added"),
            ("http://192.168.1.20:9000", 18789, "http://192.168.1.20:9000", "a typed port wins"),
            ("  nuc:8123  ", nil, "http://nuc:8123", "surrounding whitespace"),
            ("\tgateway.example.com/\n", nil, "https://gateway.example.com", "whitespace and slash together"),
            ("http://127.0.0.1:9/api/states", nil, "http://127.0.0.1:9/api/states", "a path is kept"),
            ("ha.example.com/api/", nil, "https://ha.example.com/api", "a path without a scheme"),
            ("wss://box.tailnet.ts.net/ws", nil, "wss://box.tailnet.ts.net/ws", "an explicit wss is kept"),
        ]
        for testCase in cases {
            XCTAssertEqual(GatewayAddress.normalise(testCase.raw, defaultPort: testCase.port), testCase.expected,
                           "\(testCase.raw): \(testCase.why)")
        }
    }

    func testGarbageIsNotAnAddress() {
        for raw in ["", "   ", "/", "http://", "https:///path", "my gateway", "nuc:", "nuc:port",
                    "nuc:99999", "[fd12::5", "[not-v6]:80", ".example.com", "exa..mple.com", "-nuc",
                    "://nuc", "1http://nuc"] {
            XCTAssertNil(GatewayAddress.normalise(raw), "'\(raw)' should not normalise")
        }
    }

    /// An unusable scheme the wearer typed is kept, so `EndpointPolicy` refuses it in its own
    /// words rather than this layer guessing.
    func testATypedSchemeIsKeptEvenWhenThePolicyWillRefuseIt() {
        XCTAssertEqual(GatewayAddress.normalise("ftp://files.example.com"), "ftp://files.example.com")
        XCTAssertEqual(EndpointPolicy.validate("ftp://files.example.com", for: .homeAssistantCommand,
                                               build: .release),
                       .failure(.disallowedScheme("ftp")))
    }

    /// A user name in the address is kept, not silently dropped, so the endpoint rule refuses it.
    func testAUserNameIsKeptForThePolicyToRefuse() {
        let normalised = GatewayAddress.normalise("admin:pw@192.168.1.20:8123")
        XCTAssertEqual(normalised, "http://admin:pw@192.168.1.20:8123")
        XCTAssertEqual(EndpointPolicy.validate(normalised ?? "", for: .homeAssistantCommand, build: .release),
                       .failure(.credentialInURL))
    }

    /// The private-range half of the rule is `URLFetchGuard`'s table: a host the endpoint rule
    /// treats as public never defaults to cleartext unless it is a single label or a `*.ts.net`
    /// name with a port.
    func testThePrivateRangesComeFromTheFetchGuard() {
        for host in ["192.168.0.1", "10.1.2.3", "100.64.0.1", "fd00::1", "fe80::1", "printer.local", "localhost"] {
            XCTAssertTrue(URLFetchGuard.isBlockedHost(host), host)
            XCTAssertTrue(GatewayAddress.defaultsToCleartext(host: host, port: nil), host)
        }
        for host in ["example.com", "8.8.8.8", "box.tailnet.ts.net"] {
            XCTAssertFalse(URLFetchGuard.isBlockedHost(host), host)
            XCTAssertFalse(GatewayAddress.defaultsToCleartext(host: host, port: nil), host)
        }
        // Reserved but not the wearer's own network: no cleartext default.
        XCTAssertTrue(URLFetchGuard.isBlockedHost("192.0.2.10"))
        XCTAssertFalse(GatewayAddress.defaultsToCleartext(host: "192.0.2.10", port: 8080))
    }

    func testHostClassesKeepTheBlockedHostAnswer() {
        XCTAssertEqual(URLFetchGuard.hostClass("127.0.0.1"), .loopback)
        XCTAssertEqual(URLFetchGuard.hostClass("[::1]"), .loopback)
        XCTAssertEqual(URLFetchGuard.hostClass("app.localhost"), .loopback)
        XCTAssertEqual(URLFetchGuard.hostClass("169.254.169.254"), .linkLocal)
        XCTAssertEqual(URLFetchGuard.hostClass("172.31.255.1"), .privateNetwork)
        XCTAssertEqual(URLFetchGuard.hostClass("fc00::1"), .privateNetwork)
        XCTAssertEqual(URLFetchGuard.hostClass("100.127.0.1"), .sharedAddressSpace)
        XCTAssertEqual(URLFetchGuard.hostClass("::ffff:192.168.1.1"), .privateNetwork)
        XCTAssertEqual(URLFetchGuard.hostClass("mac.local"), .localName)
        XCTAssertEqual(URLFetchGuard.hostClass("metadata.internal"), .reserved)
        XCTAssertEqual(URLFetchGuard.hostClass("0x7f000001"), .reserved)
        XCTAssertEqual(URLFetchGuard.hostClass("224.0.0.1"), .reserved)
        XCTAssertEqual(URLFetchGuard.hostClass("100.128.0.1"), .publicHost)
        XCTAssertEqual(URLFetchGuard.hostClass("example.com"), .publicHost)
    }

    // MARK: - Components (the Hermes host and port split)

    func testComponentsSplitHostAndPort() {
        let bare = GatewayAddress.components("hermes-box", defaultPort: 8765)
        XCTAssertEqual(bare?.host, "hermes-box")
        XCTAssertEqual(bare?.port, 8765)
        XCTAssertNil(bare?.typedPort)
        XCTAssertEqual(bare?.scheme, "http")
        XCTAssertEqual(bare?.webSocketScheme, "ws")
        XCTAssertEqual(bare?.schemeWasTyped, false)

        let withPort = GatewayAddress.components("192.168.1.9:9000", defaultPort: 8765)
        XCTAssertEqual(withPort?.host, "192.168.1.9")
        XCTAssertEqual(withPort?.port, 9000, "a typed port wins over the field")
        XCTAssertEqual(withPort?.typedPort, 9000)

        let pasted = GatewayAddress.components("wss://box.tailnet.ts.net:443/", defaultPort: 8765)
        XCTAssertEqual(pasted?.host, "box.tailnet.ts.net")
        XCTAssertEqual(pasted?.port, 443)
        XCTAssertEqual(pasted?.scheme, "wss")
        XCTAssertEqual(pasted?.webSocketScheme, "wss")
        XCTAssertEqual(pasted?.schemeWasTyped, true)
        XCTAssertEqual(pasted?.tail, "")

        let v6 = GatewayAddress.components("[fd12::5]:9000")
        XCTAssertEqual(v6?.host, "fd12::5")
        XCTAssertEqual(v6?.urlHost, "[fd12::5]")
    }

    func testTypedSchemesMapOntoWebSocketSchemes() {
        XCTAssertEqual(GatewayAddress.components("https://bridge.example.com")?.webSocketScheme, "wss")
        XCTAssertEqual(GatewayAddress.components("http://bridge.example.com")?.webSocketScheme, "ws")
        XCTAssertEqual(GatewayAddress.components("ws://bridge.example.com")?.webSocketScheme, "ws")
        XCTAssertEqual(GatewayAddress.components("wss://192.168.1.9")?.webSocketScheme, "wss")
        XCTAssertEqual(GatewayAddress.components("bridge.example.com")?.webSocketScheme, "wss")
    }

    // MARK: - Settings fields

    func testFieldValuesShowTheSchemeAndMoveATypedPort() {
        XCTAssertEqual(GatewayAddress.fieldValues(host: "nuc:9000", port: 18789),
                       .init(host: "http://nuc", port: 9000))
        XCTAssertEqual(GatewayAddress.fieldValues(host: "box.tailnet.ts.net", port: 18789),
                       .init(host: "http://box.tailnet.ts.net", port: 18789),
                       "the scheme chosen because of the port stays once the port moves out")
        XCTAssertEqual(GatewayAddress.fieldValues(host: "https://gw.example.com:8443/", port: 18789),
                       .init(host: "https://gw.example.com", port: 8443))
        XCTAssertEqual(GatewayAddress.fieldValues(host: "box.tailnet.ts.net:8765", port: 8765, webSocket: true),
                       .init(host: "ws://box.tailnet.ts.net", port: 8765))
        XCTAssertEqual(GatewayAddress.fieldValues(host: "box.tailnet.ts.net:443", port: 8765, webSocket: true),
                       .init(host: "wss://box.tailnet.ts.net", port: 443))
        XCTAssertEqual(GatewayAddress.fieldValues(host: "https://bridge.example.com/x", port: 8765, webSocket: true),
                       .init(host: "wss://bridge.example.com", port: 8765))
        XCTAssertNil(GatewayAddress.fieldValues(host: "", port: 18789))
        XCTAssertNil(GatewayAddress.fieldValues(host: "not a host", port: 18789))
        XCTAssertNil(GatewayAddress.fieldValues(host: "me@nuc", port: 18789))
    }

    // MARK: - Where it is applied

    func testGatewayURLsCarryAScheme() {
        var gateway = GatewayConfig.newGateway(provider: .openclaw)
        gateway.lanHost = "nuc"
        gateway.tunnelHost = "box.tailnet.ts.net"
        XCTAssertEqual(gateway.lanURL, "http://nuc:18789")
        XCTAssertEqual(gateway.tunnelURL, "https://box.tailnet.ts.net")

        gateway.lanHost = "http://192.168.1.20/"
        gateway.tunnelHost = "https://gw.example.ts.net/"
        XCTAssertEqual(gateway.lanURL, "http://192.168.1.20:18789", "an already-complete host is unchanged")
        XCTAssertEqual(gateway.tunnelURL, "https://gw.example.ts.net")

        gateway.lanHost = ""
        gateway.tunnelHost = ""
        XCTAssertEqual(gateway.lanURL, "")
        XCTAssertEqual(gateway.tunnelURL, "")
    }

    func testHomeAssistantURLIsNormalisedOnSaveAndRead() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "homeAssistantURL")
        defer { defaults.set(previous, forKey: "homeAssistantURL") }

        Config.setHomeAssistantURL("homeassistant.local:8123/")
        XCTAssertEqual(defaults.string(forKey: "homeAssistantURL"), "http://homeassistant.local:8123")
        XCTAssertEqual(Config.homeAssistantURL, "http://homeassistant.local:8123")

        // A value saved before normalisation existed is read with a scheme too.
        defaults.set("192.168.1.100:8123", forKey: "homeAssistantURL")
        XCTAssertEqual(Config.homeAssistantURL, "http://192.168.1.100:8123")

        Config.setHomeAssistantURL("")
        XCTAssertEqual(Config.homeAssistantURL, "")
    }
}
