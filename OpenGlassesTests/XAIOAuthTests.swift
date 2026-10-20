import XCTest
@testable import OpenGlasses

/// Pure-logic coverage for the xAI account sign-in core: authorize-URL construction, pasted-input
/// parsing, form-encoded token requests, the discovery trust rule, id_token claim extraction,
/// credential refresh carry-over, the chat-model filter and the credential precedence. No network,
/// no keychain. Values are invented.
final class XAIOAuthTests: XCTestCase {

    // MARK: - Authorize URL

    func testAuthorizeURLCarriesPKCEAndIdentity() throws {
        let url = try XCTUnwrap(XAIOAuth.authorizeURL(verifier: "test-verifier", state: "test-state"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "auth.x.ai")
        XCTAssertEqual(components.path, "/oauth2/authorize")
        XCTAssertEqual(params["client_id"], "b1a00492-073a-47ea-816f-4c329264a828")
        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["redirect_uri"], "http://127.0.0.1:56121/callback")
        XCTAssertEqual(params["scope"], "openid profile email offline_access grok-cli:access api:access")
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertEqual(params["code_challenge"], PKCE.challenge(for: "test-verifier"))
        XCTAssertEqual(params["state"], "test-state")
        XCTAssertNil(params["client_secret"])
    }

    func testAuthorizeURLFollowsADiscoveredEndpoint() throws {
        let endpoints = XAIOAuth.Endpoints(authorize: URL(string: "https://accounts.x.ai/authorize")!,
                                           token: XAIOAuth.Endpoints.standard.token)
        let url = try XCTUnwrap(XAIOAuth.authorizeURL(verifier: "v", state: "s", endpoints: endpoints))
        XCTAssertEqual(url.host, "accounts.x.ai")
        XCTAssertEqual(url.path, "/authorize")
    }

    func testRedirectIsTheLoopbackTheSheetCanServe() throws {
        let redirect = try XCTUnwrap(OAuthRedirect(XAIOAuth.redirectURI))
        XCTAssertTrue(redirect.isLoopback)
        XCTAssertEqual(redirect.host, "127.0.0.1")
        XCTAssertEqual(redirect.port, 56121)
        XCTAssertEqual(redirect.path, "/callback")
    }

    // MARK: - Pasted input

    func testParsePastedLoopbackCallbackURL() throws {
        let parsed = try XCTUnwrap(XAIOAuth.parseAuthorizationInput(
            "http://127.0.0.1:56121/callback?code=code-fixture&state=state-fixture"))
        XCTAssertEqual(parsed.code, "code-fixture")
        XCTAssertEqual(parsed.state, "state-fixture")
    }

    func testParseCodeHashState() throws {
        let parsed = try XCTUnwrap(XAIOAuth.parseAuthorizationInput("code-fixture#state-fixture"))
        XCTAssertEqual(parsed.code, "code-fixture")
        XCTAssertEqual(parsed.state, "state-fixture")
    }

    func testParseBareCode() throws {
        let parsed = try XCTUnwrap(XAIOAuth.parseAuthorizationInput("  code-fixture \n"))
        XCTAssertEqual(parsed.code, "code-fixture")
        XCTAssertNil(parsed.state)
        XCTAssertNil(XAIOAuth.parseAuthorizationInput("   "))
    }

    // MARK: - Token requests

    private func formFields(_ request: URLRequest) throws -> [String: String] {
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        return Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair -> (String, String) in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return (kv[0], kv.count > 1 ? kv[1].removingPercentEncoding ?? kv[1] : "")
        })
    }

    func testTokenExchangeRequestIsFormEncodedWithVerifierAndNoSecret() throws {
        let request = XAIOAuth.tokenExchangeRequest(code: "code-fixture", verifier: "verifier-fixture")
        XCTAssertEqual(request.url?.absoluteString, "https://auth.x.ai/oauth2/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        let fields = try formFields(request)
        XCTAssertEqual(fields["grant_type"], "authorization_code")
        XCTAssertEqual(fields["code"], "code-fixture")
        XCTAssertEqual(fields["code_verifier"], "verifier-fixture")
        XCTAssertEqual(fields["client_id"], XAIOAuth.clientID)
        XCTAssertEqual(fields["redirect_uri"], XAIOAuth.redirectURI)
        XCTAssertNil(fields["client_secret"])
    }

    func testRefreshRequestBody() throws {
        let request = XAIOAuth.refreshRequest(refreshToken: "refresh-fixture")
        XCTAssertEqual(request.url?.absoluteString, "https://auth.x.ai/oauth2/token")
        let fields = try formFields(request)
        XCTAssertEqual(fields["grant_type"], "refresh_token")
        XCTAssertEqual(fields["refresh_token"], "refresh-fixture")
        XCTAssertEqual(fields["client_id"], XAIOAuth.clientID)
        XCTAssertNil(fields["client_secret"])
    }

    func testTokenRequestsFollowADiscoveredTokenEndpoint() {
        let endpoints = XAIOAuth.Endpoints(authorize: XAIOAuth.Endpoints.standard.authorize,
                                           token: URL(string: "https://auth.x.ai/oauth2/v2/token")!)
        XCTAssertEqual(XAIOAuth.refreshRequest(refreshToken: "r", endpoints: endpoints).url?.path,
                       "/oauth2/v2/token")
        XCTAssertEqual(XAIOAuth.tokenExchangeRequest(code: "c", verifier: "v", endpoints: endpoints).url?.path,
                       "/oauth2/v2/token")
    }

    // MARK: - Discovery trust rule

    func testDiscoveredEndpointTrustTable() {
        let accepted = [
            "https://x.ai/oauth2/token",
            "https://auth.x.ai/oauth2/token",
            "https://AUTH.X.AI/oauth2/authorize",
            "https://accounts.auth.x.ai/token",
            "https://auth.x.ai:443/oauth2/token",
        ]
        for value in accepted {
            XCTAssertNotNil(XAIOAuth.trustedEndpoint(value), value)
        }
        let refused: [Any?] = [
            "http://auth.x.ai/oauth2/token",          // cleartext
            "https://x.ai.evil.com/oauth2/token",     // x.ai as a label of another domain
            "https://evil.com/x.ai",                   // x.ai only in the path
            "https://evilx.ai/oauth2/token",           // suffix without the dot
            "https://user:pw@auth.x.ai/oauth2/token",  // credentials in the URL
            "https://auth.x.ai:8443/oauth2/token",     // a port of its own
            "wss://auth.x.ai/token",
            "auth.x.ai/oauth2/token",
            "",
            42,
            nil,
        ]
        for value in refused {
            XCTAssertNil(XAIOAuth.trustedEndpoint(value), "\(String(describing: value))")
        }
    }

    func testDiscoveryDocumentUsesTrustedEndpointsAndFallsBackPerEndpoint() throws {
        let trusted = Data(#"{"issuer":"https://auth.x.ai","authorization_endpoint":"https://auth.x.ai/oauth2/v2/authorize","token_endpoint":"https://auth.x.ai/oauth2/v2/token"}"#.utf8)
        let both = XAIOAuth.endpoints(fromDiscovery: trusted)
        XCTAssertEqual(both.authorize.absoluteString, "https://auth.x.ai/oauth2/v2/authorize")
        XCTAssertEqual(both.token.absoluteString, "https://auth.x.ai/oauth2/v2/token")

        let hostile = Data(#"{"authorization_endpoint":"https://x.ai.evil.com/authorize","token_endpoint":"http://auth.x.ai/token"}"#.utf8)
        XCTAssertEqual(XAIOAuth.endpoints(fromDiscovery: hostile), .standard)

        let mixed = Data(#"{"authorization_endpoint":"https://evil.com/x.ai","token_endpoint":"https://auth.x.ai/oauth2/v2/token"}"#.utf8)
        let half = XAIOAuth.endpoints(fromDiscovery: mixed)
        XCTAssertEqual(half.authorize, XAIOAuth.Endpoints.standard.authorize)
        XCTAssertEqual(half.token.absoluteString, "https://auth.x.ai/oauth2/v2/token")

        XCTAssertEqual(XAIOAuth.endpoints(fromDiscovery: nil), .standard)
        XCTAssertEqual(XAIOAuth.endpoints(fromDiscovery: Data("not json".utf8)), .standard)
        XCTAssertEqual(XAIOAuth.endpoints(fromDiscovery: Data("{}".utf8)), .standard)
    }

    func testDiscoveryRequestIsAShortGet() {
        let request = XAIOAuth.discoveryRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://auth.x.ai/.well-known/openid-configuration")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertLessThanOrEqual(request.timeoutInterval, 5)
        XCTAssertNil(request.httpBody)
    }

    // MARK: - id_token claims and credentials

    static func idToken(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        return "eyJhbGciOiJub25lIn0." + PKCE.base64URL(payload) + ".sig"
    }

    func testIdentityClaims() {
        let both = XAIOAuth.identity(fromIDToken: Self.idToken(["email": "wearer@example.com", "name": "A Wearer"]))
        XCTAssertEqual(both.email, "wearer@example.com")
        XCTAssertEqual(both.name, "A Wearer")

        let nameOnly = XAIOAuth.identity(fromIDToken: Self.idToken(["name": "A Wearer", "email": " "]))
        XCTAssertNil(nameOnly.email)
        XCTAssertEqual(nameOnly.name, "A Wearer")

        let none = XAIOAuth.identity(fromIDToken: "not-a-jwt")
        XCTAssertNil(none.email)
        XCTAssertNil(none.name)
    }

    func testCredentialsCarryExpiryAndIdentityAndKeepThemAcrossARefresh() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let signIn = try JSONDecoder().decode(XAIOAuth.TokenResponse.self, from: Data("""
        {"access_token":"access-fixture","refresh_token":"refresh-fixture","expires_in":3600,
         "id_token":"\(Self.idToken(["email": "wearer@example.com"]))"}
        """.utf8))
        let first = XAIOAuth.Credentials(response: signIn, now: now)
        XCTAssertEqual(first.accessToken, "access-fixture")
        XCTAssertEqual(first.expiresAt, now.addingTimeInterval(3600))
        XCTAssertEqual(first.accountLabel, "wearer@example.com")
        XCTAssertFalse(first.needsRefresh(now: now))
        XCTAssertTrue(first.needsRefresh(now: now.addingTimeInterval(3400)))

        let refresh = try JSONDecoder().decode(XAIOAuth.TokenResponse.self,
                                               from: Data(#"{"access_token":"access-fixture-2","expires_in":3600}"#.utf8))
        let second = XAIOAuth.Credentials(response: refresh, now: now, previous: first)
        XCTAssertEqual(second.accessToken, "access-fixture-2")
        XCTAssertEqual(second.refreshToken, "refresh-fixture")
        XCTAssertEqual(second.email, "wearer@example.com")
    }

    func testAccountLabelFallsBackToNameThenNothing() throws {
        let named = try JSONDecoder().decode(XAIOAuth.TokenResponse.self, from: Data("""
        {"access_token":"a","id_token":"\(Self.idToken(["name": "A Wearer"]))"}
        """.utf8))
        XCTAssertEqual(XAIOAuth.Credentials(response: named).accountLabel, "A Wearer")
        let bare = try JSONDecoder().decode(XAIOAuth.TokenResponse.self, from: Data(#"{"access_token":"a"}"#.utf8))
        XCTAssertNil(XAIOAuth.Credentials(response: bare).accountLabel)
    }

    // MARK: - Model list filter

    func testChatModelFilter() {
        for id in ["grok-4.7", "grok-4-fast", "grok-3-mini", "grok-code-fast-1"] {
            XCTAssertTrue(XAIOAuth.isChatModel(id), id)
        }
        for id in ["grok-2-image", "grok-imagine-image", "grok-imagine-video", "grok-voice",
                   "grok-build", "grok-tts-1", "grok-embedding"] {
            XCTAssertFalse(XAIOAuth.isChatModel(id), id)
        }
    }

    // MARK: - Credential precedence and form rules

    func testOnlyAnEmptyKeyLeavesTheRequestToTheSignIn() {
        XCTAssertTrue(XAIAuth.usesAccountSignIn(apiKey: ""))
        XCTAssertTrue(XAIAuth.usesAccountSignIn(apiKey: " \n"))
        XCTAssertFalse(XAIAuth.usesAccountSignIn(apiKey: "xai-key-fixture"))
    }

    func testFormAcceptsAnXAIModelWithAKeyOrTheSignIn() {
        func ready(key: String = "", xai: Bool = false, others: Bool = false) -> Bool {
            ModelFormValidation.credentialsReady(provider: .xai, apiKey: key, claudeConnected: others,
                                                 chatgptConnected: others, googleConnected: others,
                                                 xaiConnected: xai)
        }
        XCTAssertFalse(ready())
        XCTAssertTrue(ready(key: "key"))
        XCTAssertTrue(ready(xai: true))
        XCTAssertFalse(ready(others: true), "another provider's sign-in is not an xAI credential")
        // The xAI sign-in reaches no other provider.
        XCTAssertFalse(ModelFormValidation.credentialsReady(
            provider: .openai, apiKey: "", claudeConnected: false, chatgptConnected: false,
            googleConnected: false, xaiConnected: true))
    }

    @MainActor
    func testModelRowBadgeForXAI() {
        func badge(key: Bool = false, xai: Bool = false) -> AIPersonalitySettingsScreen.ModelAuthBadge {
            AIPersonalitySettingsScreen.modelAuthBadge(provider: .xai, hasKey: key, claudeConnected: true,
                                                       chatgptConnected: true, googleConnected: true,
                                                       xaiConnected: xai)
        }
        XCTAssertEqual(badge(key: true, xai: true), .init(label: "Key set", isReady: true))
        XCTAssertEqual(badge(xai: true), .init(label: "xAI account connected", isReady: true))
        XCTAssertEqual(badge(), .init(label: "No account or key", isReady: false))
    }

    func testMissingCredentialCopyOffersTheSignIn() {
        XCTAssertTrue(LLMProvider.xai.missingCredentialMessage.contains("sign in with xAI"))
    }
}
