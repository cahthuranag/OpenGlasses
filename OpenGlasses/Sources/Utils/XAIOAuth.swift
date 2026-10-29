import Foundation

/// Pure core for the xAI account sign-in — a SuperGrok subscription used without an xAI API key
/// (no I/O, fully unit-testable). The network/persistence edge lives in `XAIOAuthService`.
///
/// Authorization code + PKCE in the browser, against xAI's CLI public client, the same arrangement
/// as the ChatGPT and Claude sign-ins. Unlike ChatGPT's token, which only opens a separate
/// subscription backend, this one carries the `api:access` scope and is accepted as a plain
/// `Bearer` on the public API (`api.x.ai/v1`): the existing xAI provider sends it in place of a
/// key, so there is no provider of its own. A key typed into the model always wins.
///
/// The registered redirect is a loopback URL, so the in-app sheet captures the code itself and
/// the paste route stays as the fallback.
enum XAIOAuth {

    // MARK: - Protocol constants
    //
    // Every endpoint and identifier lives here and nowhere else, so drift has a one-block blast
    // radius. A live sign-in on a device with a real subscription is the gate for these values.

    /// xAI's CLI public client (no secret — PKCE is the proof).
    static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    static let authorizeEndpoint = "https://auth.x.ai/oauth2/authorize"
    static let tokenEndpoint = "https://auth.x.ai/oauth2/token"
    /// OIDC discovery. It may move the two endpoints above, but only within xAI's own domain
    /// (`trustedEndpoint(_:)`); anything else, or no answer, keeps the static ones.
    static let discoveryURL = "https://auth.x.ai/.well-known/openid-configuration"
    /// Registered redirect for the public client — loopback, so `LoopbackCallbackServer` can
    /// answer it on the phone while the sign-in sheet is up.
    static let redirectURI = "http://127.0.0.1:56121/callback"
    /// `api:access` is what lets the token authenticate the public API.
    static let scopes = "openid profile email offline_access grok-cli:access api:access"
    /// The domain a discovered endpoint must stay inside.
    static let trustedDomain = "x.ai"

    // MARK: - Endpoints (static, or discovered and checked)

    struct Endpoints: Equatable, Sendable {
        let authorize: URL
        let token: URL

        static let standard = Endpoints(authorize: URL(string: XAIOAuth.authorizeEndpoint)!,
                                        token: URL(string: XAIOAuth.tokenEndpoint)!)
    }

    /// A discovered endpoint, accepted only when it is `https` on `x.ai` or a subdomain of it,
    /// with no credentials and no port of its own. Nil for anything else — the caller then keeps
    /// the static endpoint. The host test is exact or dot-suffix, so `x.ai.example.com`,
    /// `evilx.ai` and `example.com/x.ai` are all refused.
    static func trustedEndpoint(_ value: Any?) -> URL? {
        guard let text = value as? String,
              let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), !host.isEmpty,
              host == trustedDomain || host.hasSuffix("." + trustedDomain),
              let url = components.url else { return nil }
        return url
    }

    /// Read a discovery document: each endpoint it names is used if trusted, the static one if not.
    /// A missing, unreadable or hostile document gives the static pair.
    static func endpoints(fromDiscovery data: Data?) -> Endpoints {
        guard let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .standard
        }
        return Endpoints(
            authorize: trustedEndpoint(json["authorization_endpoint"]) ?? Endpoints.standard.authorize,
            token: trustedEndpoint(json["token_endpoint"]) ?? Endpoints.standard.token)
    }

    /// The discovery fetch: a short GET, so a slow answer falls back rather than holding a sign-in.
    static func discoveryRequest(timeout: TimeInterval = 5) -> URLRequest {
        var request = URLRequest(url: URL(string: discoveryURL)!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        return request
    }

    // MARK: - Authorize URL (browser flow)

    static func authorizeURL(verifier: String, state: String,
                             endpoints: Endpoints = .standard) -> URL? {
        var components = URLComponents(url: endpoints.authorize, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    /// Accepts a pasted callback URL, `code#state`, or a bare code (shared parser).
    static func parseAuthorizationInput(_ input: String) -> (code: String, state: String?)? {
        OAuthCodeInput.parse(input)
    }

    // MARK: - Token requests (form-encoded, standard OAuth; no client secret)

    static func tokenExchangeRequest(code: String, verifier: String,
                                     endpoints: Endpoints = .standard) -> URLRequest {
        formPOST(url: endpoints.token, fields: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    static func refreshRequest(refreshToken: String, endpoints: Endpoints = .standard) -> URLRequest {
        formPOST(url: endpoints.token, fields: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
    }

    // MARK: - Token response / credentials

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
        }
    }

    struct Credentials: Codable, Equatable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
        /// From the `id_token`, for the "Signed in as" row only. Kept with the tokens in the
        /// this-device-only keychain item; never logged.
        var email: String?
        var name: String?

        init(response: TokenResponse, now: Date = Date(), previous: Credentials? = nil) {
            accessToken = response.accessToken
            // A refresh response may omit fields — keep the previous values.
            refreshToken = response.refreshToken ?? previous?.refreshToken
            expiresAt = response.expiresIn.map { now.addingTimeInterval($0) }
            let identity = response.idToken.map(XAIOAuth.identity(fromIDToken:))
            email = identity?.email ?? previous?.email
            name = identity?.name ?? previous?.name
        }

        /// Refresh ahead of expiry so an in-flight request doesn't race the deadline.
        func needsRefresh(now: Date = Date(), leeway: TimeInterval = 300) -> Bool {
            guard let expiresAt else { return false }
            return now.addingTimeInterval(leeway) >= expiresAt
        }

        /// Who the row says is signed in: the email, else the name, else nil.
        var accountLabel: String? { email ?? name }
    }

    // MARK: - id_token claims

    /// The `email` and `name` claims of an `id_token`, decoded without verifying the signature:
    /// the token came straight from the token endpoint over TLS and is used for display only, as
    /// the ChatGPT sign-in reads its account id. Empty claims read as absent.
    static func identity(fromIDToken idToken: String) -> (email: String?, name: String?) {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2,
              let payload = ChatGPTOAuth.decodeBase64URL(String(segments[1])),
              let claims = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return (nil, nil)
        }
        func claim(_ key: String) -> String? {
            guard let value = (claims[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        return (claim("email"), claim("name"))
    }

    // MARK: - Model list

    /// Whether a `GET /v1/models` id is a chat model this app can talk to. xAI's list also carries
    /// image and video generators, voice models and build models, none of which answer Chat
    /// Completions. The rule is `ModelKindClassifier`'s; the pickers label those models rather than
    /// offer them as the assistant.
    static func isChatModel(_ id: String) -> Bool {
        ModelKindClassifier.kind(provider: .xai, id: id).isChat
    }

    // MARK: - Internals

    private static func formPOST(url: URL, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }   // deterministic body — testable byte-for-byte
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        request.timeoutInterval = 30
        return request
    }
}

/// Which credential an xAI request authenticates with. Pure apart from asking the sign-in for a
/// token; the token itself is refreshed in `XAIOAuthService`.
enum XAIAuth {

    /// A key typed into the model wins; otherwise the connected xAI account's (refreshed) access
    /// token; otherwise empty, which the send path reports as a missing credential.
    @MainActor
    static func resolveCredential(apiKey: String, account: XAIOAuthService) async -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return await account.validAccessToken() ?? ""
    }

    /// Whether `apiKey` leaves the request to the account sign-in — the only credential a 401
    /// may refresh (Plan FG P1a). A typed key never is.
    static func usesAccountSignIn(apiKey: String) -> Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
