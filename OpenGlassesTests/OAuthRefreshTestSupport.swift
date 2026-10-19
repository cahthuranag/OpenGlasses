import Foundation
@testable import OpenGlasses

/// Shared fixtures for the Plan FG P1a refresh tests: a credential store that never touches the
/// keychain, a transport that is always offline, and token responses with invented values.
/// The model and token endpoints are stubbed with `RecordingQueueProtocol`.

/// Credentials held in memory, so a test never reads or wipes the item a real sign-in holds.
final class InMemoryCredentialStore {
    var data: Data?

    init() {}

    init<C: Encodable>(holding credentials: C) {
        data = try? JSONEncoder().encode(credentials)
    }

    /// Holds the holder strongly: a test may drop its own reference and keep only the service.
    var store: OAuthCredentialStore {
        OAuthCredentialStore(load: { self.data },
                             save: { self.data = $0 },
                             remove: { self.data = nil })
    }

    func decoded<C: Decodable>(_ type: C.Type) -> C? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// Every request fails before reaching a server, as on a phone with no signal. Counts attempts.
final class OfflineURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0

    static var attempts: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        count = 0
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

enum OAuthRefreshFixture {
    /// A token endpoint's success body. Values are invented.
    static func tokenBody(access: String, refresh: String? = "refresh-fixture-next",
                          expiresIn: Double = 3600) -> String {
        var fields = [#""access_token":"\#(access)""#, #""expires_in":\#(Int(expiresIn))"#]
        if let refresh { fields.append(#""refresh_token":"\#(refresh)""#) }
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// When credentials minted this long ago with a one-hour lifetime expired an hour ago.
    static let expiredIssue = Date().addingTimeInterval(-7200)
    /// Minted 58 minutes ago with a one-hour lifetime: inside the refresh leeway, not yet expired.
    static let nearExpiryIssue = Date().addingTimeInterval(-3480)

    static func decode<R: Decodable>(_ type: R.Type, _ body: String) throws -> R {
        try JSONDecoder().decode(type, from: Data(body.utf8))
    }

    /// A Claude reply that answers in text, for the buffered Messages route.
    static let anthropicReply = #"{"content":[{"type":"text","text":"It is sunny."}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":4}}"#
    static let anthropicUnauthorized = #"{"type":"error","error":{"type":"authentication_error","message":"invalid bearer token"}}"#

    /// A completed Responses turn, for the ChatGPT backend route.
    static let responsesReply = """
    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_fixture","output":[{"type":"message","content":[{"type":"output_text","text":"It is sunny."}]}],"usage":{"input_tokens":3,"output_tokens":4}}}

    """
    static let responsesUnauthorized = #"{"detail":"Unauthorized"}"#

    /// A Gemini reply that answers in text, and Vertex's refusal of a stale bearer token.
    static let geminiReply = #"{"candidates":[{"content":{"role":"model","parts":[{"text":"It is sunny."}]},"finishReason":"STOP"}]}"#
    static let vertexUnauthorized = #"{"error":{"code":401,"message":"Request had invalid authentication credentials.","status":"UNAUTHENTICATED"}}"#
}
