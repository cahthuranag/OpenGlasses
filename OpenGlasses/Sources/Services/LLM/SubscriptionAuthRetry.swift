import Foundation

/// One forced refresh on a 401 for the account-sign-in routes (Plan FG P1a).
///
/// A stored expiry is the app's guess at when an access token stops working; the model endpoint
/// is the authority. A token revoked early, or a clock that disagrees, used to fail the turn with
/// an auth error the wearer could do nothing about until the stored expiry came round. Now a 401
/// from the model endpoint forces a refresh through `SingleFlightRefresher`, whatever the stored
/// expiry says, and the request goes once more with the new token. A second 401 surfaces as it
/// always did, so a credential that really is refused still reaches the fallback chain.
///
/// Only a credential that came from a sign-in rides this: a pasted API key has nothing to refresh.
enum SubscriptionAuthRetry {

    /// The token a turn is sent with. A reference, so a token refreshed in one round of a tool
    /// loop is the one every later round sends.
    final class Credential {
        var token: String
        init(_ token: String) { self.token = token }
    }

    static func isUnauthorized(_ error: Error) -> Bool {
        if case LLMError.apiError(_, 401, _, _) = error { return true }
        return false
    }

    static func isUnauthorized(_ response: URLResponse) -> Bool {
        (response as? HTTPURLResponse)?.statusCode == 401
    }

    /// Send `request` through `attempt`. When it is refused with a 401 — thrown as
    /// `LLMError.apiError`, or returned and recognised by `refused` — and `credential` is set,
    /// `refresh` is asked for a token to replace the refused one; the request is signed with it by
    /// `sign` and sent once more. With no credential, or no replacement, the first outcome stands.
    ///
    /// The request is signed with `credential`'s token before it is first sent, so a request built
    /// before an earlier round's refresh goes with the token that replaced the refused one.
    static func send<T>(_ request: URLRequest, credential: Credential?, provider: String,
                        refresh: (String) async -> String?,
                        sign: (String, inout URLRequest) -> Void,
                        refused: (T) -> Bool = { _ in false },
                        attempt: (URLRequest) async throws -> T) async throws -> T {
        var request = request
        if let credential { sign(credential.token, &request) }

        let first: Result<T, Error>
        do {
            first = .success(try await attempt(request))
        } catch {
            first = .failure(error)
        }

        let unauthorized: Bool
        switch first {
        case .success(let value): unauthorized = refused(value)
        case .failure(let error): unauthorized = isUnauthorized(error)
        }
        guard unauthorized, let credential else { return try first.get() }

        guard let fresh = await refresh(credential.token) else {
            PrivacyLog.model(.authRefreshRetry, provider: PrivacyToken(provider), success: false)
            return try first.get()
        }
        PrivacyLog.model(.authRefreshRetry, provider: PrivacyToken(provider), success: true)
        credential.token = fresh
        var retried = request
        sign(fresh, &retried)
        return try await attempt(retried)
    }
}
