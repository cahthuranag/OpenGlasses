import XCTest
@testable import OpenGlasses

/// Plan FG P1a — what a failed refresh means for the stored credential. Only the token endpoint
/// saying so in words makes a credential dead; a dropped connection, a timeout or a failing
/// service keeps it, and nobody is signed out.
final class OAuthRefreshFailureTests: XCTestCase {

    private func endpoint(_ status: Int, _ body: String = "") -> OAuthTokenEndpointError {
        OAuthTokenEndpointError(status: status, body: Data(body.utf8))
    }

    // MARK: - Dead: sign in again

    func testInvalidGrantIsDeadWhateverTheStatus() {
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(400, #"{"error":"invalid_grant"}"#)), .credentialDead)
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(401, #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#)), .credentialDead)
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(403, #"{"error":"invalid_grant"}"#)), .credentialDead)
    }

    func testExplicitRevocationCodesAreDead() {
        for code in ["token_revoked", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"] {
            XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(401, #"{"error":"\#(code)"}"#)), .credentialDead, code)
            // The same code nested in an error object, as some providers send it.
            XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(401, #"{"error":{"code":"\#(code)","message":"x"}}"#)), .credentialDead, code)
        }
    }

    // MARK: - Unreachable: keep the credential, try again

    func testTransportErrorsKeepTheCredential() {
        for code: URLError.Code in [.notConnectedToInternet, .timedOut, .networkConnectionLost,
                                     .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed] {
            XCTAssertEqual(OAuthRefreshFailure.classify(URLError(code)), .unreachable, "\(code)")
        }
        XCTAssertEqual(OAuthRefreshFailure.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)), .unreachable)
        XCTAssertEqual(OAuthRefreshFailure.classify(CancellationError()), .unreachable)
    }

    func testServerTroubleKeepsTheCredential() {
        for status in [500, 502, 503, 504, 429, 408] {
            XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(status)), .unreachable, "\(status)")
        }
        // A 5xx is unreachable even when its body is not JSON at all.
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(503, "<html>Service Unavailable</html>")), .unreachable)
        // A service that says it is temporarily unavailable, whatever status it picked.
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(400, #"{"error":"temporarily_unavailable"}"#)), .unreachable)
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(400, #"{"error":"server_error"}"#)), .unreachable)
    }

    // MARK: - Rejected: kept, but not a network fault

    func testOtherRefusalsAreNotProofTheCredentialIsDead() {
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(400, #"{"error":"invalid_request"}"#)), .rejected)
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(401, #"{"error":"invalid_client"}"#)), .rejected)
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(401)), .rejected)
        XCTAssertEqual(OAuthRefreshFailure.classify(endpoint(-1)), .rejected)
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "fixture"))
        XCTAssertEqual(OAuthRefreshFailure.classify(decoding), .rejected)
    }

    // MARK: - The code vocabulary

    func testUnknownAndUnreadableCodesReadAsNil() {
        XCTAssertNil(OAuthErrorCode.parse(Data(#"{"error":"something_new"}"#.utf8)))
        XCTAssertNil(OAuthErrorCode.parse(Data("not json".utf8)))
        XCTAssertNil(OAuthErrorCode.parse(Data()))
        XCTAssertEqual(OAuthErrorCode.parse(Data(#"{"code":"invalid_grant"}"#.utf8)), .invalidGrant)
    }

    // MARK: - What is said, and what is never kept

    func testMessagesSayWhetherTheWearerMustSignInAgain() {
        XCTAssertEqual(OAuthRefreshFailure.unreachable.message(provider: "ChatGPT"),
                       "Couldn't reach the ChatGPT sign-in service; I'll try again.")
        XCTAssertEqual(OAuthRefreshFailure.credentialDead.message(provider: "Claude"),
                       "Claude sign-in expired — please sign in again.")
        XCTAssertFalse(OAuthRefreshFailure.unreachable.message(provider: "Google").contains("sign in again"))
    }

    func testTheEndpointErrorKeepsNoBodyText() {
        let error = endpoint(400, #"{"error":"invalid_grant","error_description":"refresh-fixture-old is not valid"}"#)
        XCTAssertEqual(error.localizedDescription, "Token endpoint returned HTTP 400")
        XCTAssertFalse(String(describing: error).contains("refresh-fixture-old"))
        XCTAssertEqual(error.summary.description, "clientError(invalid_grant)#400")
        XCTAssertEqual(OAuthTokenEndpointError.summary(of: URLError(.timedOut)).category, .timedOut)
    }
}
