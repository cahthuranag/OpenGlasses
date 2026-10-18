import XCTest
@testable import OpenGlasses

/// Plan AR: the address a setup code carries — checked by the gateway endpoint rule and used
/// only to fill an empty gateway, never to replace a saved address unasked.
final class SetupCodeAddressTests: XCTestCase {

    private func parse(_ raw: String, build: EndpointPolicy.BuildFlavor = .release)
        -> Result<SetupCodeAddress, SetupCodeAddress.Rejection> {
        SetupCodeAddress.parse(raw, defaultPort: 18789, build: build)
    }

    private func gateway(lanHost: String = "", port: Int = 18789, tunnelHost: String = "",
                         mode: OpenClawConnectionMode = .auto) -> GatewayConfig {
        var config = GatewayConfig.newGateway(provider: .openclaw)
        config.lanHost = lanHost
        config.port = port
        config.tunnelHost = tunnelHost
        config.connectionMode = mode.rawValue
        return config
    }

    // MARK: - Parse

    func testLANAddressKeepsHostAndPort() {
        XCTAssertEqual(try parse("http://192.168.1.20:18800").get().leg, .lan(host: "192.168.1.20", port: 18800))
        XCTAssertEqual(try parse("ws://192.168.1.20/ws").get().leg, .lan(host: "192.168.1.20", port: 18789))
    }

    func testTLSAddressBecomesAnHTTPSBase() {
        XCTAssertEqual(try parse("wss://gw.example.ts.net/ws").get().leg,
                       .tunnel(baseURL: "https://gw.example.ts.net"))
        XCTAssertEqual(try parse("https://gw.example.ts.net:8443/openclaw/").get().leg,
                       .tunnel(baseURL: "https://gw.example.ts.net:8443/openclaw"))
    }

    func testOtherSchemesAreRefused() {
        XCTAssertEqual(parse("ftp://gw.example.com"), .failure(.endpoint(.disallowedScheme("ftp"))))
        XCTAssertEqual(parse("javascript:alert(1)"), .failure(.endpoint(.disallowedScheme("javascript"))))
    }

    func testCredentialInTheAddressIsRefused() {
        XCTAssertEqual(parse("https://user:pass@gw.example.com"), .failure(.endpoint(.credentialInURL)))
    }

    func testQueryOrFragmentIsRefused() {
        XCTAssertEqual(parse("https://gw.example.com/?token=abc"), .failure(.queryOrFragment))
        XCTAssertEqual(parse("https://gw.example.com/#x"), .failure(.queryOrFragment))
    }

    func testCleartextToAPublicHostIsRefusedInRelease() {
        guard case .failure(.endpoint(.cleartextHTTPNotPermitted)) = parse("http://gw.example.com:18789") else {
            return XCTFail("a public cleartext address must not pass the gateway endpoint rule")
        }
    }

    func testGarbageIsRefused() {
        if case .success = parse("not a url") { XCTFail("garbage must not parse") }
        if case .success = parse("") { XCTFail("an empty address must not parse") }
        if case .success = parse("https://") { XCTFail("an address with no host must not parse") }
    }

    // MARK: - Apply

    func testEmptyGatewayIsFilledAndThePinnedModeMatchesTheLeg() throws {
        let lan = try parse("http://192.168.1.20:18800").get()
        guard case let .filled(updated) = lan.apply(to: gateway()) else { return XCTFail("expected filled") }
        XCTAssertEqual(updated.lanHost, "192.168.1.20")
        XCTAssertEqual(updated.port, 18800)
        XCTAssertEqual(updated.connectionModeEnum, .lan)

        let tunnel = try parse("https://gw.example.ts.net").get()
        guard case let .filled(viaTunnel) = tunnel.apply(to: gateway()) else { return XCTFail("expected filled") }
        XCTAssertEqual(viaTunnel.tunnelHost, "https://gw.example.ts.net")
        XCTAssertEqual(viaTunnel.connectionModeEnum, .tunnel)
    }

    func testSameAddressMatches() throws {
        let lan = try parse("http://192.168.1.20:18800").get()
        XCTAssertEqual(lan.apply(to: gateway(lanHost: "http://192.168.1.20/", port: 18800)), .matches)
        let tunnel = try parse("wss://gw.example.ts.net/ws").get()
        XCTAssertEqual(tunnel.apply(to: gateway(tunnelHost: "https://gw.example.ts.net/", mode: .tunnel)), .matches)
    }

    func testDifferentSavedAddressIsNeverReplacedSilently() throws {
        let code = try parse("https://elsewhere.example.com").get()
        let saved = gateway(lanHost: "192.168.1.20")
        XCTAssertEqual(code.apply(to: saved), .differs)

        let otherPort = try parse("http://192.168.1.20:9999").get()
        XCTAssertEqual(otherPort.apply(to: saved), .differs)

        // A LAN match on a gateway pinned to its tunnel would not be where the code points.
        let lan = try parse("http://192.168.1.20").get()
        XCTAssertEqual(lan.apply(to: gateway(lanHost: "192.168.1.20", tunnelHost: "https://t.example.ts.net",
                                             mode: .tunnel)), .differs)
    }

    func testReplacingKeepsEverythingElse() throws {
        var saved = gateway(lanHost: "192.168.1.20")
        saved.name = "Studio"
        saved.token = "shared"
        let replaced = try parse("https://gw.example.ts.net").get().replacing(in: saved)
        XCTAssertEqual(replaced.tunnelHost, "https://gw.example.ts.net")
        XCTAssertEqual(replaced.connectionModeEnum, .tunnel)
        XCTAssertEqual(replaced.name, "Studio")
        XCTAssertEqual(replaced.token, "shared")
        XCTAssertEqual(replaced.id, saved.id)
    }
}
